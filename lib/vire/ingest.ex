defmodule Vire.Ingest do
  @moduledoc """
  Files arriving from providers and uploads, and their parsing into
  activities. Every file is kept byte for byte, once per user: a file whose
  SHA-256 the user already has is not stored again.

  Activities and their files also arrive from Garmin, through a sync per user
  bounded by the user's seasons. Each sync is recorded as a run from the moment
  it is queued, and every change to a run or to a file's status is published
  through `Vire.Events`.

  Every function but `reparse_outdated/0`, `enqueue_scheduled_syncs/0` and
  `fetch_signed_file/3`, which takes its user from a signed URL, takes a scope
  first and touches only its user's files.
  """

  import Ecto.Query

  alias Plug.Crypto.KeyGenerator
  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Activities
  alias Vire.Activities.Activity
  alias Vire.Events
  alias Vire.Ingest.Decoder
  alias Vire.Ingest.FitActivity
  alias Vire.Ingest.ParseWorker
  alias Vire.Ingest.SourceFile
  alias Vire.Ingest.SyncRun
  alias Vire.Ingest.SyncWorker
  alias Vire.Repo
  alias Vire.Training
  alias Vire.Training.Period

  @file_url_seconds 15 * 60

  @doc """
  Stores `content` for the scope's user as a file of `kind` from `origin`.

  Returns `{:stored, file}` for a new file, and `{:existing, file}` with the
  stored file as it stands when the user already has one with the same
  SHA-256.
  """
  def store_file(%Scope{user: user}, content, kind, origin) when is_binary(content) do
    sha256 = :crypto.hash(:sha256, content)

    case file_by_hash(user.id, sha256) do
      nil -> insert_file(user.id, content, sha256, kind, origin)
      file -> {:existing, file}
    end
  end

  @doc """
  Stores `content` as the scope's `.fit` file from `origin` and enqueues its
  parse, both in one transaction.

  Answers as `store_file/4` does; a file the user already has is not queued.
  """
  def store_fit_file(%Scope{} = scope, content, origin) do
    result =
      Repo.transact(fn ->
        with {:stored, file} <- store_file(scope, content, :fit, origin),
             {:ok, _job} <- enqueue_parse(scope, file) do
          {:ok, {:stored, file}}
        else
          {:existing, file} -> {:ok, {:existing, file}}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, stored} -> stored
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The scope's file with `id`, without its content, or `nil`."
  def get_file(%Scope{user: user}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> SourceFile |> where(user_id: ^user.id) |> Repo.get(uuid)
      :error -> nil
    end
  end

  @doc """
  A URL that downloads the scope's `file` with no session or token, and the
  time it expires, fifteen minutes after `now`. The URL carries the user, the
  expiry and an HMAC over the file id, the user id and the expiry, keyed from
  the endpoint's secret key base.
  """
  def signed_file_url(
        %Scope{user: %{id: user_id}},
        %SourceFile{user_id: user_id} = file,
        now \\ DateTime.utc_now()
      ) do
    expires_at = now |> DateTime.add(@file_url_seconds) |> DateTime.truncate(:second)
    expires = DateTime.to_unix(expires_at)

    query =
      URI.encode_query(%{
        "user" => user_id,
        "expires" => expires,
        "signature" => file_signature(file.id, user_id, expires)
      })

    {VireWeb.Endpoint.url() <> "/files/#{file.id}?" <> query, expires_at}
  end

  @doc """
  The file with `id`, with its content, that a URL from `signed_file_url/3`
  names in `params`, or `nil` when the signature does not match, the URL has
  expired or the file is not the user's.
  """
  def fetch_signed_file(id, params, now \\ DateTime.utc_now())

  def fetch_signed_file(
        id,
        %{"user" => user_id, "expires" => expires, "signature" => signature},
        now
      )
      when is_binary(id) and is_binary(user_id) and is_binary(expires) and is_binary(signature) do
    with {expires, ""} <- Integer.parse(expires),
         true <- expires > DateTime.to_unix(now),
         true <- Plug.Crypto.secure_compare(signature, file_signature(id, user_id, expires)),
         {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      file_with_content(user_id, id)
    else
      _invalid -> nil
    end
  end

  def fetch_signed_file(_id, _params, _now), do: nil

  defp file_signature(id, user_id, expires) do
    key =
      KeyGenerator.generate(
        VireWeb.Endpoint.config(:secret_key_base),
        "source file url",
        cache: Plug.Keys
      )

    :hmac
    |> :crypto.mac(:sha256, key, Enum.join([id, user_id, expires], "|"))
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Enqueues the job that parses the scope's `.fit` file into its activity,
  counting the file on the sync run with `run_id` once it is parsed or given
  up on, when one is given. While a job for the file waits or runs, the
  existing job is returned.
  """
  def enqueue_parse(scope, file, run_id \\ nil)

  def enqueue_parse(
        %Scope{user: %{id: user_id}},
        %SourceFile{user_id: user_id, kind: :fit} = file,
        run_id
      ),
      do: Oban.insert(parse_job(file, run_id))

  def enqueue_parse(%Scope{}, %SourceFile{}, _run_id), do: {:error, :not_parseable}

  @doc """
  Enqueues a parse of every processed `.fit` file, of every user, that an
  older processor version read. Returns the number of files enqueued.
  """
  def reparse_outdated do
    version = ParseWorker.processor_version()

    SourceFile
    |> where(kind: :fit, status: :processed)
    |> where([f], f.processor_version < ^version)
    |> Repo.all()
    |> Enum.map(&Oban.insert!(parse_job(&1, nil)))
    |> length()
  end

  @doc """
  Enqueues a Garmin sync of the user's seasons, of the dates in `period` only
  when one is given, for a user with an unpaused Garmin connection, and
  answers its run. `trigger` records what asked for it: `:manual`, `:plan` or
  `:scheduled`.

  While a sync of the user waits, enqueuing another widens the waiting one to
  cover both and answers its run, which a manual request makes manual.
  """
  @spec enqueue_sync(Scope.t(), Period.t() | nil, :manual | :plan | :scheduled) ::
          {:ok, SyncRun.t()} | {:error, :not_connected | :paused | term()}
  def enqueue_sync(%Scope{} = scope, period \\ nil, trigger \\ :manual) do
    case Accounts.get_provider_connection(scope, :garmin) do
      nil -> {:error, :not_connected}
      %{paused_at: %DateTime{}} -> {:error, :paused}
      _connection -> insert_sync(scope, period, trigger)
    end
  end

  @doc "Enqueues a Garmin sync of every season of the scope's user, and answers its run."
  def sync_now(%Scope{} = scope), do: enqueue_sync(scope, nil, :manual)

  @doc """
  Enqueues a sync for every user with an unpaused Garmin connection. Returns
  the number of syncs enqueued.
  """
  def enqueue_scheduled_syncs do
    :garmin
    |> Accounts.list_unpaused_provider_connections()
    |> Enum.count(&match?({:ok, _run}, insert_sync(Scope.for_user(&1.user), nil, :scheduled)))
  end

  @doc """
  The state of the scope's Garmin sync: whether a connection is `:active`,
  `:paused` or there is `:none`, when it last synced, and `run`, by default
  the scope's latest run, with the activities it found that Vire did not hold
  yet, each with the session it is matched to or `nil`.
  """
  def sync_status(%Scope{} = scope, run \\ :latest) do
    connection = Accounts.get_provider_connection(scope, :garmin)
    run = if run == :latest, do: latest_sync_run(scope), else: run

    %{
      connection: connection_state(connection),
      last_synced_at: connection && connection.last_synced_at,
      run: run,
      activities: run_activities(scope, run)
    }
  end

  @doc "The scope's sync run with `id`, or `nil`."
  def get_sync_run(%Scope{user: user}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> SyncRun |> where(user_id: ^user.id) |> Repo.get(uuid)
      :error -> nil
    end
  end

  @doc "The scope's most recently queued sync run, or `nil`."
  def latest_sync_run(%Scope{user: user}) do
    SyncRun
    |> where(user_id: ^user.id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  defp connection_state(nil), do: :none
  defp connection_state(%{paused_at: %DateTime{}}), do: :paused
  defp connection_state(_connection), do: :active

  defp run_activities(_scope, nil), do: []

  defp run_activities(scope, %SyncRun{user_id: user_id, new_activity_ids: ids})
       when user_id == scope.user.id do
    activities = Activities.list_activities_by_id(scope, ids)
    sessions = Training.list_matched_sessions(scope, Enum.map(activities, & &1.id))

    activities
    |> Enum.sort_by(& &1.started_at, DateTime)
    |> Enum.map(&%{activity: &1, session: Map.get(sessions, &1.id)})
  end

  @doc """
  Matches the activities on the local date of the scope's activity, just
  stored from a parsed file or a provider summary, to that day's sessions.
  """
  def activity_recorded(%Scope{} = scope, %Activity{local_date: date}),
    do: Training.match_activities(scope, date)

  defp insert_sync(%Scope{user: user}, period, trigger) do
    run_id = Ecto.UUID.generate()
    args = Map.put(sync_args(user, period), "run_id", run_id)

    with {:ok, run} <- Repo.transact(fn -> queue_run(args, run_id, user, trigger) end) do
      Events.publish(run.user_id, {:sync_run, run})
      {:ok, run}
    end
  end

  defp queue_run(args, run_id, user, trigger) do
    with {:ok, job} <- insert_or_widen(args), do: run_of(job, run_id, user, trigger)
  end

  defp insert_or_widen(args) do
    case Oban.insert(SyncWorker.new(args)) do
      {:ok, %Oban.Job{conflict?: true, id: id} = job} when not is_nil(id) -> widen(job, args)
      other -> other
    end
  end

  # A job that kept its args belongs to a run queued before this one.
  defp run_of(%Oban.Job{args: %{"run_id" => run_id}}, run_id, user, trigger),
    do: Repo.insert(%SyncRun{id: run_id, user_id: user.id, trigger: trigger})

  defp run_of(%Oban.Job{args: %{"run_id" => waiting_id}}, _run_id, _user, trigger) do
    run = Repo.get!(SyncRun, waiting_id)

    if trigger == :manual and run.trigger != :manual,
      do: run |> Ecto.Changeset.change(trigger: :manual) |> Repo.update(),
      else: {:ok, run}
  end

  defp sync_args(user, nil), do: %{"user_id" => user.id, "first" => nil, "last" => nil}

  defp sync_args(user, %Period{first: first, last: last}),
    do: %{
      "user_id" => user.id,
      "first" => Date.to_iso8601(first),
      "last" => Date.to_iso8601(last)
    }

  defp widen(%Oban.Job{args: waiting} = job, args) do
    widened = Map.merge(waiting, widened_range(waiting, args))

    if widened == waiting do
      {:ok, job}
    else
      replace_waiting_args(job, widened, args)
    end
  end

  defp widened_range(%{"first" => nil}, _args), do: %{"first" => nil, "last" => nil}
  defp widened_range(_waiting, %{"first" => nil}), do: %{"first" => nil, "last" => nil}

  defp widened_range(waiting, args),
    do: %{
      "first" => min(waiting["first"], args["first"]),
      "last" => max(waiting["last"], args["last"])
    }

  # The waiting job may start between the conflict and this update; it then
  # runs with its old args, and a new job covers the requested range.
  defp replace_waiting_args(%Oban.Job{id: id} = job, widened, args) do
    {updated, _jobs} =
      Oban.Job
      |> where(id: ^id)
      |> where([j], j.state in ["available", "scheduled", "retryable"])
      |> Repo.update_all(set: [args: widened])

    case updated do
      1 -> {:ok, %{job | args: widened}}
      0 -> Oban.insert(SyncWorker.new(args))
    end
  end

  @doc """
  Decodes the scope's file with `id` and stores its activity, laps, lengths
  and streams, marking the file processed in the same transaction.

  A file the decoder or the parser rejects, or whose parse raises, is marked
  failed with the error and kept, and the answer is `{:cancel, error}`. A decoder that fails to answer
  marks the file failed too, and the answer is `{:error, reason}` so the job
  is tried again.
  """
  def parse_file(%Scope{} = scope, id) do
    case get_file_with_content(scope, id) do
      nil -> {:cancel, "the source file no longer exists"}
      file -> parse(scope, file)
    end
  end

  defp parse(scope, file) do
    with {:ok, decoded} <- decode(file),
         {:ok, parsed} <- FitActivity.from_decoded(decoded),
         {:ok, {activity, processed}} <- store_parsed(scope, file, parsed) do
      result = activity_recorded(scope, activity)
      publish_file(processed)
      result
    else
      {:error, {:decoder, reason}} ->
        mark_failed(file, "the decoder did not answer: #{inspect(reason)}")
        {:error, reason}

      {:error, %Ecto.Changeset{} = changeset} ->
        reject(file, "the parsed activity is invalid: #{inspect(changeset.errors)}")

      {:error, message} ->
        reject(file, message)
    end
  rescue
    exception -> reject(file, "parsing failed: #{Exception.message(exception)}")
  end

  defp decode(file) do
    case Decoder.decode(file.content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, {:decoder, reason}}
    end
  end

  defp store_parsed(scope, file, parsed) do
    Repo.transact(fn ->
      with {:ok, activity} <- Activities.replace_from_file(scope, file, parsed),
           {:ok, processed} <-
             set_status(file, %{
               status: :processed,
               processor_version: ParseWorker.processor_version(),
               error: nil
             }) do
        {:ok, {activity, processed}}
      end
    end)
  end

  defp reject(file, message) do
    mark_failed(file, message)
    {:cancel, message}
  end

  defp mark_failed(file, message) do
    with {:ok, failed} <-
           set_status(file, %{
             status: :failed,
             processor_version: ParseWorker.processor_version(),
             error: message
           }) do
      publish_file(failed)
      {:ok, failed}
    end
  end

  defp publish_file(%SourceFile{} = file), do: Events.publish(file.user_id, {:source_file, file})

  defp set_status(file, attrs),
    do: %{file | content: nil} |> SourceFile.status_changeset(attrs) |> Repo.update()

  defp get_file_with_content(%Scope{user: user}, id), do: file_with_content(user.id, id)

  defp file_with_content(user_id, id) do
    SourceFile
    |> where(user_id: ^user_id, id: ^id)
    |> select_merge([f], %{content: f.content})
    |> Repo.one()
  end

  defp parse_job(file, nil),
    do: ParseWorker.new(%{source_file_id: file.id, user_id: file.user_id})

  defp parse_job(file, run_id),
    do: ParseWorker.new(%{source_file_id: file.id, user_id: file.user_id, run_id: run_id})

  defp insert_file(user_id, content, sha256, kind, origin) do
    changeset =
      SourceFile.create_changeset(%SourceFile{user_id: user_id}, %{
        kind: kind,
        origin: origin,
        sha256: sha256,
        byte_size: byte_size(content),
        content: content
      })

    # A concurrent store of the same file wins the unique index; this one then
    # returns that file.
    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:user_id, :sha256]) do
      {:ok, %SourceFile{id: nil}} -> {:existing, file_by_hash(user_id, sha256)}
      {:ok, file} -> {:stored, file}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp file_by_hash(user_id, sha256),
    do: SourceFile |> where(user_id: ^user_id, sha256: ^sha256) |> Repo.one()
end
