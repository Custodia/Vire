defmodule Vire.Mcp.PlanTools do
  @moduledoc """
  MCP tools that read and write the training plan, from season to session,
  and request a Garmin sync. Every write takes a rationale and lands in the
  change log under the calling client.
  """

  @behaviour Vire.Mcp.ToolGroup

  import Vire.Mcp.Arguments

  alias Vire.Activities
  alias Vire.Ingest
  alias Vire.Mcp.Render
  alias Vire.Mcp.Tool
  alias Vire.Training

  @disciplines ["swim", "bike", "run", "strength", "other"]

  @impl true
  def tools do
    [
      %Tool{
        name: "list_seasons",
        description: "Lists the athlete's seasons with their periods, earliest first.",
        input_schema: object(%{}),
        function: &list_seasons/2
      },
      %Tool{
        name: "get_plan",
        description:
          "Reads the plan as a tree from season to phases, blocks, cycles, days and " <>
            "sessions, each row with its rationale. Give either season_id, for that whole " <>
            "season, or period, for the seasons overlapping it with only the rows " <>
            "beneath them that overlap it too.",
        input_schema:
          object(%{
            season_id: id("The season to read"),
            period: period("The dates to read")
          }),
        function: &get_plan/2
      },
      %Tool{
        name: "get_day",
        description:
          "Reads one date: its day in the plan with the season, phase, block and cycle " <>
            "above it and its sessions with their status and matched activity, and every " <>
            "activity recorded on that local date. The day is null for a date outside " <>
            "every cycle.",
        input_schema: object(%{date: date("The date")}, ["date"]),
        function: &get_day/2
      },
      %Tool{
        name: "create_season",
        description:
          "Creates a season. Seasons do not overlap. Garmin activities inside it are " <>
            "synced.",
        input_schema:
          object(
            %{
              name: string("The season's name"),
              period: period("The season's dates"),
              rationale: string("Why the season exists, kept with it")
            },
            ["name", "period", "rationale"]
          ),
        function: &create_season/2
      },
      %Tool{
        name: "update_season",
        description:
          "Changes a season's name or period. A period that gains dates syncs Garmin " <>
            "activities on them; a period must still contain the season's phases.",
        input_schema:
          update_schema(%{
            name: string("The new name"),
            period: period("The new dates")
          }),
        function: &update(&1, &2, :update_season, ["name", "period"])
      },
      %Tool{
        name: "create_phase",
        description:
          "Creates a phase inside a season's period. Phases of a season do not overlap.",
        input_schema:
          object(
            %{
              season_id: id("The season the phase belongs to"),
              name: string("The phase's name"),
              period: period("The phase's dates"),
              rationale: string("Why the phase exists, kept with it")
            },
            ["season_id", "name", "period", "rationale"]
          ),
        function: &create(&1, &2, :create_phase, "season_id", ["name", "period"])
      },
      %Tool{
        name: "create_block",
        description: "Creates a block inside a phase's period. Blocks of a phase do not overlap.",
        input_schema:
          object(
            %{
              phase_id: id("The phase the block belongs to"),
              focus: string("What the block trains"),
              period: period("The block's dates"),
              rationale: string("Why the block exists, kept with it")
            },
            ["phase_id", "focus", "period", "rationale"]
          ),
        function: &create(&1, &2, :create_block, "phase_id", ["focus", "period"])
      },
      %Tool{
        name: "create_cycle",
        description:
          "Creates a cycle inside a block's period, with one rest day per date. Without " <>
            "a period it runs from the day after the block's latest cycle, or the block's " <>
            "first day, through the following Sunday, within the block. Cycles of a block " <>
            "do not overlap.",
        input_schema:
          object(
            %{
              block_id: id("The block the cycle belongs to"),
              kind: enum(["load", "recovery"], "The cycle's kind"),
              period: period("The cycle's dates"),
              rationale: string("Why the cycle exists, kept with it")
            },
            ["block_id", "kind", "rationale"]
          ),
        function: &create(&1, &2, :create_cycle, "block_id", ["kind", "period"])
      },
      %Tool{
        name: "update_phase",
        description:
          "Changes a phase's name or period. A period stays inside its season and " <>
            "contains the phase's blocks.",
        input_schema:
          update_schema(%{
            name: string("The new name"),
            period: period("The new dates")
          }),
        function: &update(&1, &2, :update_phase, ["name", "period"])
      },
      %Tool{
        name: "update_block",
        description:
          "Changes a block's focus or period. A period stays inside its phase and " <>
            "contains the block's cycles.",
        input_schema:
          update_schema(%{
            focus: string("The new focus"),
            period: period("The new dates")
          }),
        function: &update(&1, &2, :update_block, ["focus", "period"])
      },
      %Tool{
        name: "update_cycle",
        description:
          "Changes a cycle's kind or period. A wider period gains a rest day per new " <>
            "date; a narrower one drops the days it leaves out and is refused while any " <>
            "of them holds a session or a note.",
        input_schema:
          update_schema(%{
            kind: enum(["load", "recovery"], "The new kind"),
            period: period("The new dates")
          }),
        function: &update(&1, &2, :update_cycle, ["kind", "period"])
      },
      delete_tool(
        "season",
        "Deletes a season with its phases, blocks, cycles, days and sessions."
      ),
      delete_tool("phase", "Deletes a phase with its blocks, cycles, days and sessions."),
      delete_tool("block", "Deletes a block with its cycles, days and sessions."),
      delete_tool("cycle", "Deletes a cycle with its days and their sessions."),
      %Tool{
        name: "update_day",
        description: "Changes the kind or the note of the day on a date.",
        input_schema:
          object(
            %{
              date: date("The day's date"),
              kind: enum(["training", "rest"], "The new kind"),
              note: %{type: ["string", "null"], description: "The new note, or null to clear it"},
              rationale: string("Why the change is made, kept in the change log")
            },
            ["date", "rationale"]
          ),
        function: &update_day/2
      },
      %Tool{
        name: "create_session",
        description:
          "Creates a session on the day of a date, which must lie in a cycle. The day " <>
            "becomes a training day.",
        input_schema:
          object(
            Map.put(
              session_properties(),
              :rationale,
              string("Why the session exists, kept with it")
            ),
            ["date", "position", "discipline", "rationale"]
          ),
        function: &create_session/2
      },
      %Tool{
        name: "update_session",
        description:
          "Changes a session. A new date or position moves it, and the day it lands on " <>
            "becomes a training day. Status may be set to done or skipped by hand.",
        input_schema:
          update_schema(
            Map.put(
              session_properties(),
              :status,
              enum(["planned", "done", "skipped"], "The new status")
            )
          ),
        function:
          &update(&1, &2, :update_session, [
            "date",
            "position",
            "discipline",
            "structure",
            "planned_seconds",
            "status"
          ])
      },
      %Tool{
        name: "delete_session",
        description: "Deletes a session.",
        input_schema: delete_schema("session"),
        function: &delete(&1, &2, :delete_session)
      },
      %Tool{
        name: "match_session",
        description:
          "Matches a session to an activity recorded on its date, which makes it done, " <>
            "or clears its match with a null activity_id, which makes it planned. " <>
            "Automatic matching leaves a session matched or cleared by hand alone.",
        input_schema:
          object(
            %{
              session_id: id("The session"),
              activity_id: %{
                type: ["string", "null"],
                format: "uuid",
                description: "The activity, or null to clear the match"
              },
              rationale: string("Why the match is set, kept in the change log")
            },
            ["session_id", "activity_id", "rationale"]
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

  defp session_properties do
    %{
      date: date("The session's date"),
      position: integer("The session's place in its day, from 0", 0),
      discipline: enum(@disciplines, "The session's discipline"),
      structure: %{
        type: "object",
        description: "The session's steps and targets, as any JSON object"
      },
      planned_seconds: integer("The planned duration in seconds", 0)
    }
  end

  defp update_schema(properties) do
    properties
    |> Map.merge(%{
      id: id("The row to change"),
      rationale: string("Why the change is made, kept in the change log")
    })
    |> object(["id", "rationale"])
  end

  defp delete_schema(level) do
    object(
      %{
        id: id("The #{level} to delete"),
        rationale: string("Why the #{level} is deleted, kept in the change log")
      },
      ["id", "rationale"]
    )
  end

  defp delete_tool(level, description) do
    %Tool{
      name: "delete_" <> level,
      description: description,
      input_schema: delete_schema(level),
      function: &delete(&1, &2, :"delete_#{level}")
    }
  end

  defp list_seasons(scope, _args),
    do: {:ok, %{seasons: scope |> Training.list_seasons() |> Enum.map(&Render.season/1)}}

  defp get_plan(scope, %{"season_id" => id} = args) when not is_map_key(args, "period") do
    case Training.get_plan(scope, id) do
      nil -> {:error, :not_found}
      season -> {:ok, %{seasons: [Render.season(season)]}}
    end
  end

  defp get_plan(scope, args)
       when is_map_key(args, "period") and not is_map_key(args, "season_id") do
    with {:ok, period} <- read_period(args, "period") do
      {:ok, %{seasons: scope |> Training.get_plan(period) |> Enum.map(&Render.season/1)}}
    end
  end

  defp get_plan(_scope, _args), do: {:error, "Give either season_id or period"}

  defp get_day(scope, args) do
    with {:ok, date} <- read_date(args, "date") do
      day = Training.get_day(scope, date)
      activities = Activities.list_activities(scope, Date.range(date, date))

      {:ok,
       %{
         date: date,
         day: day && Render.day(day),
         activities: Enum.map(activities, &Render.activity/1)
       }}
    end
  end

  defp create_season(scope, args) do
    scope
    |> Training.create_season(Map.take(args, ["name", "period", "rationale"]))
    |> rendered()
  end

  defp create(scope, args, function, parent, fields) do
    Training
    |> apply(function, [scope, args[parent], Map.take(args, ["rationale" | fields])])
    |> rendered()
  end

  defp update(scope, args, function, fields) do
    Training
    |> apply(function, [scope, args["id"], Map.take(args, fields), args["rationale"]])
    |> rendered()
  end

  defp delete(scope, args, function) do
    with {:ok, row} <- apply(Training, function, [scope, args["id"], args["rationale"]]) do
      {:ok, %{deleted: row.id}}
    end
  end

  defp update_day(scope, args) do
    with {:ok, date} <- read_date(args, "date") do
      scope
      |> Training.update_day(date, Map.take(args, ["kind", "note"]), args["rationale"])
      |> rendered()
    end
  end

  defp create_session(scope, args) do
    attrs =
      Map.take(args, [
        "date",
        "position",
        "discipline",
        "structure",
        "planned_seconds",
        "rationale"
      ])

    scope |> Training.create_session(attrs) |> rendered()
  end

  defp match_session(scope, args) do
    case Training.match_session(scope, args["session_id"], args["activity_id"], args["rationale"]) do
      {:error, :different_date} -> {:error, "The activity was recorded on another date"}
      result -> rendered(result)
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

  defp rendered({:ok, row}), do: {:ok, render(row)}
  defp rendered({:error, reason}), do: {:error, reason}

  defp render(%Training.Season{} = row), do: Render.season(row)
  defp render(%Training.Phase{} = row), do: Render.phase(row)
  defp render(%Training.Block{} = row), do: Render.block(row)
  defp render(%Training.Cycle{} = row), do: Render.cycle(row)
  defp render(%Training.Day{} = row), do: Render.day(row)
  defp render(%Training.Session{} = row), do: Render.session(row)
end
