defmodule Vire.Activities do
  @moduledoc """
  Recorded activities with their laps, pool lengths and per-second streams.

  Every function takes a scope first and touches only its user's activities.
  Another user's activity reads as `nil` or is left out of a list.
  """

  import Ecto.Query

  alias Vire.Accounts.Scope
  alias Vire.Activities.Activity
  alias Vire.Activities.ActivityStream
  alias Vire.Activities.Lap
  alias Vire.Activities.Length
  alias Vire.Ingest.SourceFile
  alias Vire.Repo

  @position_channels ["position_lat", "position_long"]
  @insert_chunk 1_000
  @lock_space 1_098_215_013

  @doc """
  The scope's activities with a local date in `dates`, newest first, without
  their laps, lengths or streams. `discipline:` narrows them to one discipline.
  """
  def list_activities(%Scope{} = scope, %Date.Range{} = dates, opts \\ []) do
    {first, last} = Enum.min_max_by([dates.first, dates.last], & &1, Date)

    Activity
    |> for_user(scope)
    |> where([a], a.local_date >= ^first and a.local_date <= ^last)
    |> with_discipline(Keyword.get(opts, :discipline))
    |> order_by(desc: :started_at)
    |> Repo.all()
  end

  @doc "The scope's activity with `id`, with its laps and lengths in order, or `nil`."
  def get_activity(%Scope{} = scope, id) do
    case fetch(scope, id) do
      nil ->
        nil

      activity ->
        Repo.preload(activity,
          laps: from(l in Lap, order_by: l.lap_index),
          lengths: from(l in Length, order_by: l.length_index)
        )
    end
  end

  @doc "The scope's activity parsed from the source file with `source_file_id`, or `nil`."
  def get_activity_by_source_file(%Scope{} = scope, source_file_id) do
    case Ecto.UUID.cast(source_file_id) do
      {:ok, uuid} -> Activity |> for_user(scope) |> Repo.get_by(source_file_id: uuid)
      :error -> nil
    end
  end

  @doc """
  The streams of the scope's activity with `id` for `channels`, a list of
  channel names or `:all`, as a map from channel to its unit and samples, or
  `nil` when there is no such activity. A channel the activity did not record
  is left out.

  Each sample covers `seconds_per_sample` seconds: the mean of the window's
  recorded values, or for position channels the first recorded value, and
  `nil` where the window holds none.
  """
  def get_activity_streams(%Scope{} = scope, id, channels, seconds_per_sample)
      when is_integer(seconds_per_sample) and seconds_per_sample > 0 do
    case fetch(scope, id) do
      nil ->
        nil

      activity ->
        ActivityStream
        |> where(activity_id: ^activity.id)
        |> with_channels(channels)
        |> Repo.all()
        |> Map.new(fn stream ->
          {stream.channel,
           %{
             unit: stream.unit,
             samples: downsample(stream.samples, seconds_per_sample, stream.channel)
           }}
        end)
    end
  end

  @doc """
  Stores what was parsed from the scope's source file as its activity, laps,
  lengths and streams, in one transaction. Parsing a file again updates its
  activity and replaces the children.

  A file no activity holds yet goes to the scope's provider activity without a
  file that started within a minute of it, keeping the provider's fields, and
  otherwise makes a new activity.
  """
  def replace_from_file(
        %Scope{user: %{id: user_id}} = scope,
        %SourceFile{user_id: user_id} = file,
        parsed
      ) do
    Repo.transact(fn ->
      lock_activities(user_id)

      activity =
        Activity |> for_user(scope) |> Repo.get_by(source_file_id: file.id) ||
          scope |> started_near(parsed.activity.started_at) |> provider_only() |> Repo.one() ||
          %Activity{user_id: user_id}

      changeset =
        activity
        |> Activity.file_changeset(parsed.activity)
        |> Ecto.Changeset.put_change(:source_file_id, file.id)

      with {:ok, activity} <- Repo.insert_or_update(changeset) do
        replace_children(activity, parsed)
        {:ok, activity}
      end
    end)
  end

  @doc """
  Stores a provider's summary of one of the scope's activities: `attrs` with
  the provider, its external id, the start, UTC offset and local date, the
  discipline, duration, distance, training load and the summary itself.

  The summary updates the activity with its provider and external id. Without
  one it goes to the scope's activity from a file that has no provider and
  started within a minute of it, and otherwise makes a new activity.
  """
  def upsert_provider_activity(
        %Scope{user: %{id: user_id}} = scope,
        %{provider: provider, external_id: external_id, started_at: started_at} = attrs
      ) do
    Repo.transact(fn ->
      lock_activities(user_id)

      activity =
        Activity |> for_user(scope) |> Repo.get_by(provider: provider, external_id: external_id) ||
          scope |> started_near(started_at) |> where([a], is_nil(a.provider)) |> Repo.one() ||
          %Activity{user_id: user_id}

      activity
      |> Activity.provider_changeset(attrs)
      |> Repo.insert_or_update()
    end)
  end

  @doc """
  Attaches the scope's source file to the scope's activity that has none.

  When an activity without a provider already holds the file, the activity's
  provider fields move to that one and the activity is deleted; the answer is
  the activity that holds the file.
  """
  def attach_source_file(
        %Scope{user: %{id: user_id}} = scope,
        %Activity{user_id: user_id, id: id},
        %SourceFile{user_id: user_id} = file
      ) do
    Repo.transact(fn ->
      lock_activities(user_id)
      holder = Activity |> for_user(scope) |> Repo.get_by(source_file_id: file.id)

      case Activity |> for_user(scope) |> Repo.get(id) do
        nil -> {:error, :not_found}
        %Activity{source_file_id: nil} = activity -> attach(activity, holder, file)
        %Activity{} = activity -> {:ok, activity}
      end
    end)
  end

  defp attach(activity, nil, file),
    do: activity |> Activity.source_file_changeset(file.id) |> Repo.update()

  defp attach(activity, %Activity{provider: nil} = holder, _file) do
    Repo.delete!(activity)

    holder
    |> Activity.provider_changeset(Map.take(activity, Activity.from_provider_fields()))
    |> Repo.update()
  end

  defp attach(_activity, %Activity{}, _file), do: {:error, :file_held_by_another_activity}

  defp started_near(scope, started_at) do
    Activity
    |> for_user(scope)
    |> where(
      [a],
      a.started_at >= ^DateTime.add(started_at, -60) and
        a.started_at <= ^DateTime.add(started_at, 60)
    )
    |> order_by(
      [a],
      fragment(
        "abs(extract(epoch from ? - ?))",
        a.started_at,
        type(^started_at, :utc_datetime_usec)
      )
    )
    |> limit(1)
  end

  defp provider_only(query),
    do: where(query, [a], is_nil(a.source_file_id) and not is_nil(a.provider))

  # A parse and a provider summary of the same activity can arrive at once;
  # the lock keeps them from both inserting it.
  defp lock_activities(user_id),
    do: Repo.query!("select pg_advisory_xact_lock(#{@lock_space}, hashtext($1))", [user_id])

  defp replace_children(activity, parsed) do
    for schema <- [Lap, Length, ActivityStream] do
      Repo.delete_all(where(schema, activity_id: ^activity.id))
    end

    insert_children(Lap, activity, parsed.laps)
    insert_children(Length, activity, parsed.lengths)
    insert_children(ActivityStream, activity, parsed.streams)
  end

  defp insert_children(schema, activity, rows) do
    rows
    |> Enum.map(&Map.put(&1, :activity_id, activity.id))
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end

  defp downsample(samples, 1, _channel), do: samples

  defp downsample(samples, seconds, channel) do
    window = if channel in @position_channels, do: &first_recorded/1, else: &mean/1

    samples
    |> Enum.chunk_every(seconds)
    |> Enum.map(window)
  end

  defp first_recorded(window), do: Enum.find(window, &(not is_nil(&1)))

  defp mean(window) do
    case Enum.reject(window, &is_nil/1) do
      [] -> nil
      values -> Enum.sum(values) / length(values)
    end
  end

  defp with_discipline(query, nil), do: query
  defp with_discipline(query, discipline), do: where(query, discipline: ^discipline)

  defp with_channels(query, :all), do: query
  defp with_channels(query, channels), do: where(query, [s], s.channel in ^channels)

  defp fetch(scope, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Activity |> for_user(scope) |> Repo.get(uuid)
      :error -> nil
    end
  end

  defp for_user(query, %Scope{user: user}), do: where(query, user_id: ^user.id)
end
