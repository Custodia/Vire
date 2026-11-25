defmodule Vire.Mcp.PlanWrite do
  @moduledoc """
  `write_plan`: a batch of creates, updates and deletes across the plan's
  levels, written in one transaction through `Vire.Training.batch/2`, each
  error answered with the path of the value it names.
  """

  import Vire.Mcp.Arguments

  alias Vire.Mcp.Schema
  alias Vire.Mcp.Tool
  alias Vire.Training
  alias Vire.Training.Structure

  @description """
  Writes the plan: every op in ops runs in order in one transaction, and any \
  refusal writes nothing and answers each error with its path, such as \
  ops[2].sessions[0].date. change_log says why and goes to the change log; an \
  op's own change_log replaces it for that op. A create may carry the rows \
  beneath it: a season its phases, a phase its blocks, a block its cycles, a \
  cycle its days and sessions. rationale says why a row exists and is kept on \
  it: required at the root of a create, inherited by the rows nested in it \
  unless they give their own, and replaced by an update that gives one.

  Rules, checked once every op has run: a phase lies inside its season, a \
  block inside its phase and a cycle inside its block; seasons do not overlap, \
  nor do the phases of a season, the blocks of a phase or the cycles of a \
  block. A cycle has one day per date, a rest day until a session lands on it, \
  and cannot narrow past a day holding a session or a note. A cycle created \
  without a period runs from the day after its block's latest cycle, or the \
  block's first day, to the next Sunday within the block. A session's date \
  must be a day of a cycle, of its own cycle when nested in one, and its \
  position is unique in its day. A day is addressed by its date. Status is set \
  by hand: skipped is never set automatically. Fields not listed are refused.\
  """

  @doc "The description of `write_plan`."
  def description, do: @description

  @doc "The input schema of `write_plan`."
  def schema do
    %{
      type: "object",
      properties: %{
        change_log: change_log(),
        ops: %{
          type: "array",
          minItems: 1,
          description: "The writes, in order, all or none",
          items: %{oneOf: creates() ++ updates() ++ deletes()}
        }
      },
      required: ["change_log", "ops"],
      additionalProperties: false,
      "$defs": %{
        period: period("The row's dates"),
        structure: structure(),
        day:
          object(
            %{
              date: date("The day's date"),
              kind: enum(["training", "rest"], "The day's kind"),
              note: %{
                type: ["string", "null"],
                description: "The day's note, or null to clear it"
              }
            },
            ["date"]
          ),
        session: object(Map.put(session_fields(), :rationale, rationale()), required_session()),
        cycle_tree: object(cycle_fields(), ["kind"]),
        block_tree: object(block_fields(), ["focus", "period"]),
        phase_tree: object(phase_fields(), ["name", "period"])
      }
    }
  end

  defp creates do
    [
      create("season", season_fields(), ["name", "period"]),
      create("phase", Map.put(phase_fields(), :season_id, id("The season")), [
        "season_id",
        "name",
        "period"
      ]),
      create("block", Map.put(block_fields(), :phase_id, id("The phase")), [
        "phase_id",
        "focus",
        "period"
      ]),
      create("cycle", Map.put(cycle_fields(), :block_id, id("The block")), ["block_id", "kind"]),
      create("session", session_fields(), required_session())
    ]
  end

  defp updates do
    [
      update("season", %{id: id("The season"), name: string("The new name"), period: ref(:period)}),
      update("phase", %{id: id("The phase"), name: string("The new name"), period: ref(:period)}),
      update("block", %{
        id: id("The block"),
        focus: string("The new focus"),
        period: ref(:period)
      }),
      update("cycle", %{
        id: id("The cycle"),
        kind: enum(["load", "recovery"], "The new kind"),
        period: ref(:period)
      }),
      branch("update", "day", %{
        date: date("The day's date"),
        kind: enum(["training", "rest"], "The new kind"),
        note: %{type: ["string", "null"], description: "The new note, or null to clear it"}
      })
      |> Map.put(:required, ["op", "level", "date"]),
      update(
        "session",
        session_fields()
        |> Map.put(:id, id("The session"))
        |> Map.put(:status, enum(["planned", "done", "skipped"], "The new status"))
      )
    ]
  end

  defp deletes do
    for level <- ~w(season phase block cycle session) do
      "delete"
      |> branch(level, %{id: id("The #{level}, with everything beneath it")})
      |> Map.put(:required, ["op", "level", "id"])
    end
  end

  defp create(level, fields, required) do
    "create"
    |> branch(level, Map.put(fields, :rationale, rationale()))
    |> Map.put(:required, ["op", "level", "rationale" | required])
  end

  defp update(level, fields) do
    "update"
    |> branch(level, Map.put(fields, :rationale, string("A new rationale, kept on the row")))
    |> Map.put(:required, ["op", "level", "id"])
  end

  defp branch(op, level, fields) do
    fields
    |> Map.merge(%{op: %{const: op}, level: %{const: level}, change_log: change_log()})
    |> object()
  end

  defp season_fields do
    %{
      name: string("The name"),
      period: ref(:period),
      phases: list(:phase_tree)
    }
  end

  defp phase_fields do
    %{
      name: string("The name"),
      period: ref(:period),
      rationale: rationale(),
      blocks: list(:block_tree)
    }
  end

  defp block_fields do
    %{
      focus: string("What the block trains"),
      period: ref(:period),
      rationale: rationale(),
      cycles: list(:cycle_tree)
    }
  end

  defp cycle_fields do
    %{
      kind: enum(["load", "recovery"], "The cycle's kind"),
      period: ref(:period),
      rationale: rationale(),
      days: list(:day),
      sessions: list(:session)
    }
  end

  defp session_fields do
    %{
      date: date("The session's date"),
      position: integer("The session's place in its day, from 0", 0),
      discipline: enum(disciplines(), "The session's discipline"),
      structure: ref(:structure),
      planned_seconds: integer("The planned duration in seconds", 0)
    }
  end

  defp required_session, do: ["date", "position", "discipline"]

  defp structure do
    %{
      type: "object",
      description:
        "The session's plan. title (a string) names the session and note (a string) " <>
          "describes it in a line; both are shown on the dashboard. steps lists the " <>
          "session in order. A step has kind (warmup, work, recovery, cooldown or " <>
          "rest), seconds (a whole number above 0), and optionally zone (1 to 5), " <>
          "target (a string such as 275–289 W or 4:30 /km) and note (a " <>
          "string). A step may instead be a repeat: repeat (a count of at least 1) " <>
          "with its own steps, which may hold repeats too. Other keys are kept as " <>
          "given.",
      properties: %{
        title: %{type: "string"},
        note: %{type: "string"},
        steps: %{type: "array", items: step_schema(2)}
      }
    }
  end

  defp step_schema(depth) do
    single = %{
      type: "object",
      properties: %{
        kind: enum(Structure.kinds(), "What the step is for"),
        seconds: integer("How long the step lasts", 1),
        zone: %{type: "integer", minimum: 1, maximum: 5, description: "The training zone"},
        target: string("The target, such as a power, pace or heart-rate range"),
        note: string("A cue for the step")
      },
      required: ["kind", "seconds"]
    }

    if depth == 0 do
      single
    else
      repeat = %{
        type: "object",
        properties: %{
          repeat: integer("How many times the steps run", 1),
          steps: %{type: "array", minItems: 1, items: step_schema(depth - 1)}
        },
        required: ["repeat", "steps"]
      }

      %{anyOf: [single, repeat]}
    end
  end

  defp rationale, do: string("Why the row exists, kept with it")

  defp change_log,
    do: Map.put(string("Why the change is made, kept in the change log"), :minLength, 1)

  defp ref(name), do: %{"$ref": "#/$defs/#{name}"}
  defp list(name), do: %{type: "array", items: ref(name)}

  @doc "Runs `write_plan` for the scope."
  def write(scope, %{"change_log" => change_log, "ops" => ops}) do
    case Training.batch(scope, fn -> run_all(scope, ops, change_log) end) do
      {:ok, {results, _written}} -> {:ok, %{ok: true, results: results}}
      {:error, {:periods, violations, {_results, written}}} -> invalid(violations, written)
      {:error, errors} when is_list(errors) -> {:error, {:invalid, errors}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in Postgrex.Error ->
      {:error, {:invalid, [%{path: "ops", message: Exception.message(error)}]}}
  end

  defp run_all(scope, ops, change_log) do
    ops
    |> Enum.with_index()
    |> reduce_ok(fn {op, index} ->
      with {:ok, result, rows} <- run(scope, op, ["ops", index], op["change_log"] || change_log) do
        {:ok, Map.put(result, :op, index), rows}
      end
    end)
    |> case do
      {:ok, results, written} -> {:ok, {results, written}}
      error -> error
    end
  end

  defp invalid(violations, written) do
    errors =
      violations
      |> Enum.flat_map(fn violation ->
        case written[violation.id] do
          nil -> []
          path -> [%{path: format(path ++ ["period"]), message: violation.message}]
        end
      end)
      |> Enum.uniq()

    errors =
      if errors == [],
        do: Enum.map(violations, &%{path: "ops", message: &1.message}),
        else: errors

    {:error, {:invalid, errors}}
  end

  defp run(scope, %{"op" => "create", "level" => level} = op, path, reason),
    do: create_row(scope, level, op, parent_id(level, op), path, reason, nil)

  defp run(scope, %{"op" => "update", "level" => "day"} = op, path, reason) do
    {:ok, date} = Date.from_iso8601(op["date"])

    case Training.update_day(scope, date, Map.take(op, ["kind", "note"]), reason) do
      {:ok, day} ->
        {:ok, %{id: day.id, date: day.day}, %{}}

      {:error, :not_found} ->
        {:error, error(path ++ ["date"], "no cycle holds #{date}")}

      {:error, changeset} ->
        {:error, Tool.changeset_errors(changeset, path)}
    end
  end

  defp run(scope, %{"op" => "update", "level" => level, "id" => id} = op, path, reason) do
    {function, fields} = update_function(level)

    case apply(Training, function, [scope, id, Map.take(op, fields), reason]) do
      {:ok, row} -> {:ok, %{id: row.id}, %{row.id => path}}
      {:error, reason} -> {:error, refusal(reason, level, path)}
    end
  end

  defp run(scope, %{"op" => "delete", "level" => level, "id" => id}, path, reason) do
    case apply(Training, :"delete_#{level}", [scope, id, reason]) do
      {:ok, row} -> {:ok, %{id: row.id}, %{}}
      {:error, reason} -> {:error, refusal(reason, level, path)}
    end
  end

  defp update_function("season"), do: {:update_season, ["name", "period", "rationale"]}
  defp update_function("phase"), do: {:update_phase, ["name", "period", "rationale"]}
  defp update_function("block"), do: {:update_block, ["focus", "period", "rationale"]}
  defp update_function("cycle"), do: {:update_cycle, ["kind", "period", "rationale"]}

  defp update_function("session"),
    do:
      {:update_session,
       ["date", "position", "discipline", "structure", "planned_seconds", "status", "rationale"]}

  defp parent_id("season", _op), do: nil
  defp parent_id("phase", op), do: {"season_id", op["season_id"]}
  defp parent_id("block", op), do: {"phase_id", op["phase_id"]}
  defp parent_id("cycle", op), do: {"block_id", op["block_id"]}
  defp parent_id("session", _op), do: nil

  # Creates one row and the rows nested in it, answering its result and the
  # paths of the rows written, by id. `inherited` is the rationale of the
  # row above, kept by a nested row that gives none.
  defp create_row(scope, level, fields, parent, path, reason, inherited) do
    attrs =
      fields
      |> Map.take(attr_fields(level))
      |> Map.put_new("rationale", inherited)

    case insert(scope, level, parent, attrs, reason) do
      {:ok, row} ->
        with {:ok, nested, rows} <- create_nested(scope, level, row, fields, path, reason) do
          {:ok, Map.merge(%{id: row.id}, nested), Map.put(rows, row.id, path)}
        end

      {:error, :not_found} ->
        {key, _id} = parent

        {:error,
         error(path ++ [key], "names no #{String.trim_trailing(key, "_id")} of the athlete")}

      {:error, changeset} ->
        {:error, Tool.changeset_errors(changeset, path)}
    end
  end

  defp attr_fields("season"), do: ["name", "period", "rationale"]
  defp attr_fields("phase"), do: ["name", "period", "rationale"]
  defp attr_fields("block"), do: ["focus", "period", "rationale"]
  defp attr_fields("cycle"), do: ["kind", "period", "rationale"]

  defp attr_fields("session"),
    do: ["date", "position", "discipline", "structure", "planned_seconds", "rationale"]

  defp insert(scope, "season", nil, attrs, reason),
    do: Training.create_season(scope, attrs, reason)

  defp insert(scope, "session", nil, attrs, reason),
    do: Training.create_session(scope, attrs, reason)

  defp insert(scope, level, {_key, parent_id}, attrs, reason),
    do: apply(Training, :"create_#{level}", [scope, parent_id, attrs, reason])

  defp create_nested(scope, "season", season, fields, path, reason),
    do: create_children(scope, "phase", :phases, season, fields["phases"], path, reason)

  defp create_nested(scope, "phase", phase, fields, path, reason),
    do: create_children(scope, "block", :blocks, phase, fields["blocks"], path, reason)

  defp create_nested(scope, "block", block, fields, path, reason),
    do: create_children(scope, "cycle", :cycles, block, fields["cycles"], path, reason)

  defp create_nested(scope, "cycle", cycle, fields, path, reason) do
    with {:ok, _days, _rows} <-
           plan_days(scope, cycle, fields["days"] || [], path ++ ["days"], reason),
         {:ok, sessions, rows} <-
           plan_sessions(scope, cycle, fields["sessions"] || [], path ++ ["sessions"], reason) do
      result = %{period: Map.from_struct(cycle.period)}
      result = if fields["sessions"], do: Map.put(result, :sessions, sessions), else: result
      {:ok, result, rows}
    end
  end

  defp create_nested(_scope, "session", _session, _fields, _path, _reason), do: {:ok, %{}, %{}}

  defp create_children(_scope, _level, _key, _parent, nil, _path, _reason), do: {:ok, %{}, %{}}

  defp create_children(scope, level, key, parent, children, path, reason) do
    parent_key = {"#{parent_name(level)}_id", parent.id}

    children
    |> Enum.with_index()
    |> reduce_ok(fn {child, index} ->
      create_row(
        scope,
        level,
        child,
        parent_key,
        path ++ [Atom.to_string(key), index],
        reason,
        parent.rationale
      )
    end)
    |> case do
      {:ok, results, rows} -> {:ok, %{key => results}, rows}
      error -> error
    end
  end

  defp parent_name("phase"), do: "season"
  defp parent_name("block"), do: "phase"
  defp parent_name("cycle"), do: "block"

  defp plan_days(scope, cycle, days, path, reason) do
    days
    |> Enum.with_index()
    |> reduce_ok(fn {day, index} -> plan_day(scope, cycle, day, path ++ [index], reason) end)
  end

  defp plan_day(scope, cycle, day, path, reason) do
    with {:ok, date} <- inside(cycle, day["date"], path) do
      case Training.update_day(scope, date, Map.take(day, ["kind", "note"]), reason) do
        {:ok, day} -> {:ok, day.id, %{}}
        {:error, changeset} -> {:error, Tool.changeset_errors(changeset, path)}
      end
    end
  end

  defp plan_sessions(scope, cycle, sessions, path, reason) do
    sessions
    |> Enum.with_index()
    |> reduce_ok(fn {session, index} ->
      plan_session(scope, cycle, session, path ++ [index], reason)
    end)
  end

  defp plan_session(scope, cycle, session, path, reason) do
    attrs =
      session
      |> Map.take(attr_fields("session"))
      |> Map.put_new("rationale", cycle.rationale)

    with {:ok, _date} <- inside(cycle, session["date"], path) do
      case Training.create_session(scope, attrs, reason) do
        {:ok, created} -> {:ok, %{id: created.id}, %{}}
        {:error, changeset} -> {:error, Tool.changeset_errors(changeset, path)}
      end
    end
  end

  defp inside(cycle, value, path) do
    {:ok, date} = Date.from_iso8601(value)
    %{first: first, last: last} = cycle.period

    if Date.compare(date, first) == :lt or Date.compare(date, last) == :gt,
      do:
        {:error, error(path ++ ["date"], "#{date} lies outside the cycle, #{first} to #{last}")},
      else: {:ok, date}
  end

  defp reduce_ok(items, fun) do
    items
    |> Enum.reduce_while({:ok, [], %{}}, fn item, {:ok, results, rows} ->
      case fun.(item) do
        {:ok, result, more} -> {:cont, {:ok, [result | results], Map.merge(rows, more)}}
        {:error, errors} -> {:halt, {:error, List.wrap(errors)}}
      end
    end)
    |> case do
      {:ok, results, rows} -> {:ok, Enum.reverse(results), rows}
      error -> error
    end
  end

  defp refusal(:not_found, level, path),
    do: error(path ++ ["id"], "names no #{level} of the athlete")

  defp refusal(%Ecto.Changeset{} = changeset, _level, path),
    do: Tool.changeset_errors(changeset, path)

  defp error(path, message), do: %{path: format(path), message: message}

  defp format(path), do: Schema.format_path(path)
end
