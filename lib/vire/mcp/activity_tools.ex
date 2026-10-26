defmodule Vire.Mcp.ActivityTools do
  @moduledoc """
  MCP tools that read recorded activities: summaries over a range of dates,
  one activity with its laps and lengths, its streams downsampled, and signed
  URLs for original files. Each activity names the session it is matched to.
  """

  @behaviour Vire.Mcp.ToolGroup

  import Vire.Mcp.Arguments

  alias Vire.Activities
  alias Vire.Ingest
  alias Vire.Mcp.Render
  alias Vire.Mcp.Tool
  alias Vire.Mcp.When
  alias Vire.Training

  @max_files 50

  @impl true
  def tools do
    [
      %Tool{
        name: "list_activities",
        description:
          "Lists the activities recorded on the local dates when names, newest first, as " <>
            "summaries without laps, lengths or streams, each with the id of the session " <>
            "it is matched to or null.",
        input_schema:
          object(
            %{
              when: When.schema("The local dates to list"),
              discipline: enum(disciplines(), "Only activities of this discipline"),
              unmatched: %{
                type: "boolean",
                description: "With true, only activities no session is matched to"
              }
            },
            ["when"]
          ),
        function: &list_activities/2
      },
      %Tool{
        name: "get_activity",
        description:
          "Reads one activity: its summary with its matched session's id, its laps, its " <>
            "pool lengths, and the provider's own summary as the provider sent it.",
        input_schema: object(%{id: id("The activity")}, ["id"]),
        function: &get_activity/2
      },
      %Tool{
        name: "get_activity_streams",
        description:
          "Reads an activity's recorded channels, one sample per seconds_per_sample " <>
            "seconds from the start, each the mean of its window or the first recorded " <>
            "value for position, and null where nothing was recorded, so a pause reads " <>
            "as nulls. Channels are named after the recorded fields, such as heart_rate, " <>
            "power, cadence, speed, altitude, distance, position_lat and position_long; " <>
            "a channel the activity did not record is left out.",
        input_schema:
          object(
            %{
              id: id("The activity"),
              channels: %{
                type: "array",
                items: %{type: "string"},
                description: "The channels to read; every recorded channel when left out"
              },
              seconds_per_sample: integer("The seconds each sample covers", 1)
            },
            ["id", "seconds_per_sample"]
          ),
        function: &get_activity_streams/2
      },
      %Tool{
        name: "get_activity_files",
        description:
          "Answers, for each activity, a URL that downloads its original .fit file with " <>
            "no credentials until it expires, fifteen minutes after the call, with the " <>
            "file's size in bytes and its SHA-256 in hex, and lists under missing the " <>
            "activities it has no file for, with the reason. Fetch and decode the files " <>
            "outside this conversation.",
        input_schema:
          object(
            %{
              ids: %{
                type: "array",
                minItems: 1,
                maxItems: @max_files,
                items: id("An activity"),
                description: "The activities, up to #{@max_files}"
              }
            },
            ["ids"]
          ),
        function: &get_activity_files/2
      }
    ]
  end

  defp list_activities(scope, args) do
    with {:ok, period} <- resolve(scope, args["when"]) do
      discipline = args["discipline"] && String.to_existing_atom(args["discipline"])

      activities =
        scope
        |> Activities.list_activities(Date.range(period.first, period.last),
          discipline: discipline
        )
        |> with_sessions(scope)
        |> Enum.reject(&(args["unmatched"] == true and &1.session_id))

      {:ok, %{period: Map.from_struct(period), activities: activities}}
    end
  end

  defp resolve(scope, value) do
    case When.resolve(scope, value) do
      {:ok, period} -> {:ok, period}
      {:error, error} -> {:error, {:invalid, [error]}}
    end
  end

  defp with_sessions(activities, scope) do
    sessions = Training.list_matched_sessions(scope, Enum.map(activities, & &1.id))
    Enum.map(activities, &Map.put(Render.activity(&1), :session_id, session_id(sessions, &1)))
  end

  defp session_id(sessions, activity) do
    case Map.get(sessions, activity.id) do
      nil -> nil
      session -> session.id
    end
  end

  defp get_activity(scope, args) do
    case Activities.get_activity(scope, args["id"]) do
      nil ->
        {:error, :not_found}

      activity ->
        sessions = Training.list_matched_sessions(scope, [activity.id])

        {:ok,
         Map.put(Render.activity_detail(activity), :session_id, session_id(sessions, activity))}
    end
  end

  defp get_activity_streams(scope, %{"id" => id, "seconds_per_sample" => seconds} = args) do
    case Activities.get_activity_streams(scope, id, Map.get(args, "channels", :all), seconds) do
      nil -> {:error, :not_found}
      streams -> {:ok, %{activity_id: id, seconds_per_sample: seconds, streams: streams}}
    end
  end

  defp get_activity_files(scope, %{"ids" => ids}) do
    ids = Enum.uniq(ids)
    activities = scope |> Activities.list_activities_by_id(ids) |> Map.new(&{&1.id, &1})

    {files, missing} =
      ids
      |> Enum.map(&file_link(scope, &1, activities[&1]))
      |> Enum.split_with(&match?({:ok, _link}, &1))

    {:ok,
     %{
       files: Enum.map(files, &elem(&1, 1)),
       missing: Enum.map(missing, fn {:missing, id, reason} -> %{id: id, reason: reason} end)
     }}
  end

  defp file_link(_scope, id, nil), do: {:missing, id, "Not found"}
  defp file_link(_scope, id, %{source_file_id: nil}), do: {:missing, id, "No recorded file yet"}

  defp file_link(scope, id, activity) do
    file = Ingest.get_file(scope, activity.source_file_id)
    {url, expires_at} = Ingest.signed_file_url(scope, file)

    {:ok,
     %{
       activity_id: id,
       file_id: file.id,
       url: url,
       expires_at: expires_at,
       byte_size: file.byte_size,
       sha256: Base.encode16(file.sha256, case: :lower)
     }}
  end
end
