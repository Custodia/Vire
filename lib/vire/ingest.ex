defmodule Vire.Ingest do
  @moduledoc """
  Files arriving from providers and uploads, and their parsing into
  activities. Every file is kept byte for byte, once per user: a file whose
  SHA-256 the user already has is not stored again.

  Every function but `reparse_outdated/0` takes a scope first and touches only
  its user's files.
  """

  import Ecto.Query

  alias Vire.Accounts.Scope
  alias Vire.Activities
  alias Vire.Ingest.Decoder
  alias Vire.Ingest.FitActivity
  alias Vire.Ingest.ParseWorker
  alias Vire.Ingest.SourceFile
  alias Vire.Repo

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

  @doc "The scope's file with `id`, without its content, or `nil`."
  def get_file(%Scope{user: user}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> SourceFile |> where(user_id: ^user.id) |> Repo.get(uuid)
      :error -> nil
    end
  end

  @doc """
  Enqueues the job that parses the scope's `.fit` file into its activity.
  While a job for the file waits or runs, the existing job is returned.
  """
  def enqueue_parse(
        %Scope{user: %{id: user_id}},
        %SourceFile{user_id: user_id, kind: :fit} = file
      ),
      do: Oban.insert(parse_job(file))

  def enqueue_parse(%Scope{}, %SourceFile{}), do: {:error, :not_parseable}

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
    |> Enum.map(&Oban.insert!(parse_job(&1)))
    |> length()
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
         {:ok, _activity} <- store_parsed(scope, file, parsed) do
      :ok
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
           {:ok, _file} <-
             set_status(file, %{
               status: :processed,
               processor_version: ParseWorker.processor_version(),
               error: nil
             }) do
        {:ok, activity}
      end
    end)
  end

  defp reject(file, message) do
    mark_failed(file, message)
    {:cancel, message}
  end

  defp mark_failed(file, message) do
    set_status(file, %{
      status: :failed,
      processor_version: ParseWorker.processor_version(),
      error: message
    })
  end

  defp set_status(file, attrs),
    do: %{file | content: nil} |> SourceFile.status_changeset(attrs) |> Repo.update()

  defp get_file_with_content(%Scope{user: user}, id) do
    SourceFile
    |> where(user_id: ^user.id, id: ^id)
    |> select_merge([f], %{content: f.content})
    |> Repo.one()
  end

  defp parse_job(file),
    do: ParseWorker.new(%{source_file_id: file.id, user_id: file.user_id})

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
