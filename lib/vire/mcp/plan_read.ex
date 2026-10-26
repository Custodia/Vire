defmodule Vire.Mcp.PlanRead do
  @moduledoc """
  `read_plan`: the plan as a list of rows of one level, each going down as
  far as asked, narrowed to dates, a season and the sessions a filter keeps.
  """

  import Vire.Mcp.Arguments

  alias Vire.Mcp.Render
  alias Vire.Mcp.When
  alias Vire.Training

  @levels ~w(season phase block cycle day session)
  @children %{
    "season" => :phases,
    "phase" => :blocks,
    "block" => :cycles,
    "cycle" => :days,
    "day" => :sessions
  }
  @plural %{
    "season" => :seasons,
    "phase" => :phases,
    "block" => :blocks,
    "cycle" => :cycles,
    "day" => :days,
    "session" => :sessions
  }

  @doc "The input schema of `read_plan`."
  def schema do
    object(%{
      when: When.schema("The dates to read; every row overlapping them is kept, at every level"),
      season_id: id("Only this season"),
      from: enum(@levels, "The level the answer lists, season by default"),
      to:
        enum(
          @levels ++ ["steps"],
          "How far down each row goes, steps by default; session keeps each session's " <>
            "structure title and note without its steps"
        ),
      filter: %{
        type: "object",
        description: "Keeps the sessions that match every given part, and the rows above them",
        properties: %{
          status: %{
            type: "array",
            items: enum(["planned", "done", "skipped"], "A status"),
            description: "Sessions of these statuses"
          },
          discipline: %{
            type: "array",
            items: enum(disciplines(), "A discipline"),
            description: "Sessions of these disciplines"
          },
          unmatched: %{
            type: "boolean",
            description: "With true, sessions still planned on a date before today"
          }
        },
        additionalProperties: false
      },
      summary: %{
        type: "boolean",
        description:
          "With true, every cycle answers its session counts and its planned and actual seconds"
      }
    })
  end

  @doc "Answers `read_plan` for the scope on `today`."
  def read(scope, args, today \\ Date.utc_today()) do
    from = Map.get(args, "from", "season")
    to = Map.get(args, "to", "steps")

    with :ok <- check_depth(from, to),
         {:ok, period} <- resolve(scope, args["when"], today) do
      rows =
        scope
        |> Training.get_plan(period)
        |> Enum.filter(&(args["season_id"] in [nil, &1.id]))
        |> Enum.map(&Render.season/1)
        |> filter(args["filter"], today)
        |> listed("season", from, %{})
        |> Enum.map(&cut(&1, from, to))
        |> with_candidates(scope, from, to)
        |> with_summaries(scope, from, to, args["summary"] == true, today)

      {:ok, %{:period => period && Map.from_struct(period), @plural[from] => rows}}
    end
  end

  defp check_depth(from, to) do
    if index(to) < index(from),
      do: {:error, {:invalid, [%{path: "to", message: "must not lie above from, #{from}"}]}},
      else: :ok
  end

  defp resolve(_scope, nil, _today), do: {:ok, nil}

  defp resolve(scope, value, today) do
    case When.resolve(scope, value, today) do
      {:ok, period} -> {:ok, period}
      {:error, error} -> {:error, {:invalid, [error]}}
    end
  end

  defp filter(seasons, nil, _today), do: seasons
  defp filter(seasons, filter, _today) when map_size(filter) == 0, do: seasons

  defp filter(seasons, filter, today) do
    keep = fn session ->
      included?(filter["status"], session.status) and
        included?(filter["discipline"], session.discipline) and
        (filter["unmatched"] != true or
           (session.status == :planned and Date.before?(session.date, today)))
    end

    prune(seasons, "season", keep)
  end

  defp included?(nil, _value), do: true
  defp included?(values, value), do: to_string(value) in values

  defp prune(rows, "session", keep), do: Enum.filter(rows, keep)

  defp prune(rows, level, keep) do
    key = @children[level]

    for row <- rows,
        children = prune(Map.get(row, key, []), child(level), keep),
        children != [],
        do: Map.put(row, key, children)
  end

  defp listed(rows, level, level, chain), do: Enum.map(rows, &with_chain(&1, level, chain))

  defp listed(rows, level, from, chain) do
    Enum.flat_map(rows, fn row ->
      row
      |> Map.get(@children[level], [])
      |> listed(child(level), from, link(chain, row, level))
    end)
  end

  defp with_chain(row, "season", _chain), do: row
  defp with_chain(row, _level, chain), do: Map.put(row, :chain, chain)

  defp link(chain, row, "season"), do: Map.put(chain, :season, Map.take(row, [:id, :name]))
  defp link(chain, row, "phase"), do: Map.put(chain, :phase, Map.take(row, [:id, :name]))
  defp link(chain, row, "block"), do: Map.put(chain, :block, Map.take(row, [:id, :focus]))
  defp link(chain, row, "cycle"), do: Map.put(chain, :cycle, Map.take(row, [:id, :kind]))
  defp link(chain, _row, "day"), do: chain

  defp cut(row, "session", "session"), do: Map.update!(row, :structure, &Map.delete(&1, "steps"))
  defp cut(row, "session", _to), do: row
  defp cut(row, level, level), do: Map.delete(row, @children[level])

  defp cut(row, level, to) do
    key = @children[level]
    Map.update(row, key, [], fn children -> Enum.map(children, &cut(&1, child(level), to)) end)
  end

  defp with_candidates(rows, scope, from, to) do
    if index(to) >= index("session"),
      do: put_candidates(rows, scope, from),
      else: rows
  end

  defp put_candidates(rows, scope, from) do
    open =
      rows
      |> collect(from, "session")
      |> Enum.filter(&(is_nil(&1.activity_id) and &1.status != :skipped))

    candidates = Training.list_candidates(scope, open)

    update(rows, from, "session", fn session ->
      case Map.get(candidates, session.id) do
        nil -> session
        list -> Map.put(session, :candidates, list)
      end
    end)
  end

  defp with_summaries(rows, scope, from, to, true, today) do
    if index(from) <= index("cycle") and index(to) >= index("cycle") do
      ids = rows |> collect(from, "cycle") |> Enum.map(& &1.id)
      summaries = Training.cycle_summaries(scope, ids, today)
      update(rows, from, "cycle", &Map.put(&1, :summary, summaries[&1.id]))
    else
      rows
    end
  end

  defp with_summaries(rows, _scope, _from, _to, _summary, _today), do: rows

  defp collect(rows, level, level), do: rows

  defp collect(rows, level, wanted),
    do: Enum.flat_map(rows, &collect(Map.get(&1, @children[level], []), child(level), wanted))

  defp update(rows, level, level, fun), do: Enum.map(rows, fun)

  defp update(rows, level, wanted, fun) do
    key = @children[level]

    Enum.map(rows, fn row ->
      case row do
        %{^key => children} -> %{row | key => update(children, child(level), wanted, fun)}
        row -> row
      end
    end)
  end

  defp child(level), do: Enum.at(@levels, index(level) + 1)

  defp index("steps"), do: length(@levels)
  defp index(level), do: Enum.find_index(@levels, &(&1 == level))
end
