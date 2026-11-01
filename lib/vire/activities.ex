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
  """
  def replace_from_file(
        %Scope{user: %{id: user_id}},
        %SourceFile{user_id: user_id} = file,
        parsed
      ) do
    changeset =
      Activity.file_changeset(
        %Activity{user_id: user_id, source_file_id: file.id},
        parsed.activity
      )

    Repo.transact(fn ->
      with {:ok, activity} <-
             Repo.insert(changeset,
               on_conflict: {:replace, [:updated_at | Activity.from_file_fields()]},
               conflict_target: :source_file_id,
               returning: true
             ) do
        replace_children(activity, parsed)
        {:ok, activity}
      end
    end)
  end

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
