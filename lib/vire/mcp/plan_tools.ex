defmodule Vire.Mcp.PlanTools do
  @moduledoc """
  MCP tools that read and write the training plan, from season to session,
  match sessions by hand, and request a Garmin sync. Every write takes a
  change log entry and lands in the change log under the calling client.
  """

  @behaviour Vire.Mcp.ToolGroup

  import Vire.Mcp.Arguments

  alias Vire.Ingest
  alias Vire.Mcp.PlanRead
  alias Vire.Mcp.PlanWrite
  alias Vire.Mcp.Render
  alias Vire.Mcp.Tool
  alias Vire.Training

  @impl true
  def tools do
    [
      %Tool{
        name: "read_plan",
        description:
          "Reads the plan as rows of one level, from season through phase, block, cycle " <>
            "and day to session, each row with its rationale. from is the level listed and " <>
            "to how far down each row goes; a row below a season carries its chain of the " <>
            "rows above it. when keeps the rows overlapping its dates at every level, " <>
            "season_id one season, and filter the sessions it matches with the rows above " <>
            "them. A session without an activity carries its candidates when it has any: " <>
            "activities on its date that may be it, with a confidence from 0 to 1 and why. " <>
            "Activities themselves come from list_activities.",
        input_schema: PlanRead.schema(),
        function: &PlanRead.read/2
      },
      %Tool{
        name: "write_plan",
        description: PlanWrite.description(),
        input_schema: PlanWrite.schema(),
        function: &PlanWrite.write/2
      },
      %Tool{
        name: "match_session",
        description:
          "Clears a session's match with a null activity_id, which makes it planned, or " <>
            "matches it to an activity recorded on its date, which makes it done. " <>
            "Automatic matching leaves a session matched or cleared by hand alone. " <>
            "Answers the session with any candidates left.",
        input_schema:
          object(
            %{
              session_id: id("The session"),
              activity_id: %{
                type: ["string", "null"],
                format: "uuid",
                description: "The activity, or null to clear the match"
              },
              change_log:
                Map.put(string("Why the match is set, kept in the change log"), :minLength, 1)
            },
            ["session_id", "activity_id", "change_log"]
          ),
        function: &match_session/2
      },
      %Tool{
        name: "sync_now",
        description:
          "Enqueues a Garmin sync of every season and answers the job's id. Activities " <>
            "arrive and are matched to sessions as the job runs.",
        input_schema: object(%{}),
        function: &sync_now/2
      }
    ]
  end

  defp match_session(scope, args) do
    %{"session_id" => id, "activity_id" => activity_id, "change_log" => change_log} = args

    case Training.match_session(scope, id, activity_id, change_log) do
      {:ok, session} -> {:ok, with_candidates(scope, session)}
      {:error, :different_date} -> {:error, "The activity was recorded on another date"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_candidates(scope, session) do
    case Training.list_candidates(scope, [session]) do
      %{} = none when map_size(none) == 0 -> Render.session(session)
      %{} = found -> Map.put(Render.session(session), :candidates, found[session.id])
    end
  end

  defp sync_now(scope, _args) do
    case Ingest.sync_now(scope) do
      {:ok, job} -> {:ok, %{job_id: job.id}}
      {:error, :not_connected} -> {:error, "The athlete has no Garmin connection"}
      {:error, :paused} -> {:error, "The athlete's Garmin connection is paused"}
      {:error, reason} -> {:error, reason}
    end
  end
end
