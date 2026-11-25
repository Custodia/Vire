defmodule Vire.Mcp.PlanTools do
  @moduledoc """
  MCP tools that read and write the training plan, from season to session,
  match sessions by hand, and run and follow a Garmin sync. Every write takes a
  change log entry and lands in the change log under the calling client.
  """

  @behaviour Vire.Mcp.ToolGroup

  import Vire.Mcp.Arguments

  alias Vire.Events
  alias Vire.Ingest
  alias Vire.Ingest.SyncRun
  alias Vire.Mcp.PlanRead
  alias Vire.Mcp.PlanWrite
  alias Vire.Mcp.Render
  alias Vire.Mcp.Tool
  alias Vire.Training

  @max_wait 120

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
          "Starts a Garmin sync of every season, or joins the one waiting, and answers its " <>
            "run when the run finishes or wait_seconds pass, whichever is first, as it stands " <>
            "then. A run goes queued, then searching while Garmin is asked and each new " <>
            "activity is stored and matched, then fetching while the .fit files are " <>
            "downloaded and parsed, five seconds apart, and ends finished or failed. From " <>
            "fetching on, every activity says which session it matched or could be; " <>
            "get_sync follows the run.",
        input_schema:
          object(%{
            wait_seconds: %{
              type: "integer",
              minimum: 0,
              maximum: @max_wait,
              description: "The longest to wait for the run to finish, 0 by default"
            }
          }),
        function: &sync_now/2
      },
      %Tool{
        name: "get_sync",
        description:
          "Reads a Garmin sync run as sync_now answers it, the latest when run_id is left out.",
        input_schema: object(%{run_id: id("The run")}),
        function: &get_sync/2
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

  defp sync_now(scope, args) do
    wait = Map.get(args, "wait_seconds", 0)
    if wait > 0, do: Events.subscribe(scope)

    try do
      case Ingest.sync_now(scope) do
        {:ok, run} -> {:ok, synced(scope, awaited(scope, run, wait))}
        {:error, :not_connected} -> {:error, "The athlete has no Garmin connection"}
        {:error, :paused} -> {:error, "The athlete's Garmin connection is paused"}
        {:error, reason} -> {:error, reason}
      end
    after
      if wait > 0, do: forget_events(scope)
    end
  end

  defp awaited(_scope, run, 0), do: run

  defp awaited(scope, run, wait) do
    deadline = System.monotonic_time(:millisecond) + wait * 1000
    run |> await(deadline) |> then(&(Ingest.get_sync_run(scope, &1.id) || &1))
  end

  defp await(%SyncRun{state: state} = run, _deadline) when state in [:finished, :failed], do: run

  defp await(%SyncRun{id: id} = run, deadline) do
    receive do
      {:sync_run, %SyncRun{id: ^id} = changed} -> await(changed, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> run
    end
  end

  defp forget_events(scope) do
    Events.unsubscribe(scope)

    receive do
      {:sync_run, _run} -> forget_events(scope)
      {:source_file, _file} -> forget_events(scope)
    after
      0 -> :ok
    end
  end

  defp get_sync(scope, args) do
    run =
      case args["run_id"] do
        nil -> Ingest.latest_sync_run(scope)
        id -> Ingest.get_sync_run(scope, id)
      end

    if run, do: {:ok, synced(scope, run)}, else: {:error, :not_found}
  end

  defp synced(scope, run) do
    %{activities: activities} = Ingest.sync_status(scope, run)
    unmatched = for %{activity: activity, session: nil} <- activities, do: activity
    Render.sync_run(run, activities, Training.list_candidate_sessions(scope, unmatched))
  end
end
