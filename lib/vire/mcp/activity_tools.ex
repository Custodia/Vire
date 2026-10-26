defmodule Vire.Mcp.ActivityTools do
  @moduledoc """
  MCP tools that read recorded activities: summaries over a range of dates,
  one activity with its laps and lengths, its streams downsampled, and a
  signed URL for its original file.
  """

  @behaviour Vire.Mcp.ToolGroup

  import Vire.Mcp.Arguments

  alias Vire.Activities
  alias Vire.Ingest
  alias Vire.Mcp.Render
  alias Vire.Mcp.Tool

  @disciplines ["swim", "bike", "run", "strength", "other"]

  @impl true
  def tools do
    [
      %Tool{
        name: "list_activities",
        description:
          "Lists the activities recorded on local dates within a period, newest first, " <>
            "as summaries without laps, lengths or streams.",
        input_schema:
          object(
            %{
              period: period("The local dates to list"),
              discipline: enum(@disciplines, "Only activities of this discipline")
            },
            ["period"]
          ),
        function: &list_activities/2
      },
      %Tool{
        name: "get_activity",
        description:
          "Reads one activity: its summary, its laps, its pool lengths, and the " <>
            "provider's own summary as the provider sent it.",
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
        name: "get_activity_file",
        description:
          "Answers a URL that downloads the activity's original .fit file with no " <>
            "credentials until it expires, fifteen minutes after the call, with the " <>
            "file's size in bytes and its SHA-256 in hex. Fetch and decode the file " <>
            "outside this conversation.",
        input_schema: object(%{id: id("The activity")}, ["id"]),
        function: &get_activity_file/2
      }
    ]
  end

  defp list_activities(scope, args) do
    with {:ok, period} <- read_period(args, "period"),
         {:ok, discipline} <- read_discipline(args["discipline"]) do
      activities =
        Activities.list_activities(scope, Date.range(period.first, period.last),
          discipline: discipline
        )

      {:ok, %{activities: Enum.map(activities, &Render.activity/1)}}
    end
  end

  defp get_activity(scope, args) do
    case Activities.get_activity(scope, args["id"]) do
      nil -> {:error, :not_found}
      activity -> {:ok, Render.activity_detail(activity)}
    end
  end

  defp get_activity_streams(scope, args) do
    with {:ok, channels} <- read_channels(args["channels"]),
         {:ok, seconds} <- read_seconds(args["seconds_per_sample"]),
         streams when is_map(streams) <-
           Activities.get_activity_streams(scope, args["id"], channels, seconds) do
      {:ok, %{activity_id: args["id"], seconds_per_sample: seconds, streams: streams}}
    else
      nil -> {:error, :not_found}
      {:error, message} -> {:error, message}
    end
  end

  defp get_activity_file(scope, args) do
    with %{source_file_id: file_id} = activity when is_binary(file_id) <-
           Activities.get_activity(scope, args["id"]) || {:error, :not_found},
         %Ingest.SourceFile{} = file <- Ingest.get_file(scope, file_id) do
      {url, expires_at} = Ingest.signed_file_url(scope, file)

      {:ok,
       %{
         activity_id: activity.id,
         file_id: file.id,
         url: url,
         expires_at: expires_at,
         byte_size: file.byte_size,
         sha256: Base.encode16(file.sha256, case: :lower)
       }}
    else
      %{source_file_id: nil} -> {:error, "The activity has no recorded file yet"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_discipline(nil), do: {:ok, nil}

  defp read_discipline(discipline) when discipline in @disciplines,
    do: {:ok, String.to_existing_atom(discipline)}

  defp read_discipline(_discipline),
    do: {:error, "discipline must be one of " <> Enum.join(@disciplines, ", ")}

  defp read_channels(nil), do: {:ok, :all}

  defp read_channels(channels) when is_list(channels) do
    if Enum.all?(channels, &is_binary/1),
      do: {:ok, channels},
      else: {:error, "channels must be a list of channel names"}
  end

  defp read_channels(_channels), do: {:error, "channels must be a list of channel names"}

  defp read_seconds(seconds) when is_integer(seconds) and seconds > 0, do: {:ok, seconds}
  defp read_seconds(_seconds), do: {:error, "seconds_per_sample must be a whole number from 1"}
end
