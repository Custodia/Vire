defmodule Vire.Mcp.WhenTest do
  use Vire.DataCase, async: true

  alias Vire.Mcp.When
  alias Vire.Training.Period

  @today ~D[2026-11-05]

  setup do
    scope = scope_fixture()
    %{scope: scope, plan: plan_fixture(scope)}
  end

  defp resolve(scope, value, today \\ @today) do
    case When.resolve(scope, value, today) do
      {:ok, %Period{first: first, last: last}} -> {first, last}
      {:error, %{path: path, message: message}} -> {path, message}
    end
  end

  test "resolves dates and days from today", %{scope: scope} do
    assert resolve(scope, "2026-10-01") == {~D[2026-10-01], ~D[2026-10-01]}
    assert resolve(scope, "today") == {@today, @today}
    assert resolve(scope, "yesterday") == {~D[2026-11-04], ~D[2026-11-04]}
    assert resolve(scope, "tomorrow") == {~D[2026-11-06], ~D[2026-11-06]}
    assert resolve(scope, "-3d") == {~D[2026-11-02], ~D[2026-11-02]}
    assert resolve(scope, "+30d") == {~D[2026-12-05], ~D[2026-12-05]}
  end

  test "resolves weeks from Monday to Sunday and calendar months", %{scope: scope} do
    assert resolve(scope, "this-week") == {~D[2026-11-02], ~D[2026-11-08]}
    assert resolve(scope, "last-week") == {~D[2026-10-26], ~D[2026-11-01]}
    assert resolve(scope, "next-week") == {~D[2026-11-09], ~D[2026-11-15]}
    assert resolve(scope, "this-month") == {~D[2026-11-01], ~D[2026-11-30]}
    assert resolve(scope, "last-month") == {~D[2026-10-01], ~D[2026-10-31]}
    assert resolve(scope, "next-month") == {~D[2026-12-01], ~D[2026-12-31]}
  end

  test "resolves the plan's rows holding today and the cycles around it", ctx do
    %{scope: scope, plan: plan} = ctx

    assert resolve(scope, "this-cycle") == {plan.cycle.period.first, plan.cycle.period.last}
    assert resolve(scope, "this-block") == {plan.block.period.first, plan.block.period.last}
    assert resolve(scope, "this-phase") == {plan.phase.period.first, plan.phase.period.last}
    assert resolve(scope, "this-season") == {plan.season.period.first, plan.season.period.last}

    next = cycle_fixture(scope, plan.block, %{period: period(~D[2026-11-09], ~D[2026-11-15])})
    assert resolve(scope, "next-cycle") == {next.period.first, next.period.last}

    assert resolve(scope, "last-cycle", Date.add(next.period.first, 1)) ==
             {plan.cycle.period.first, plan.cycle.period.last}

    assert resolve(scope, "last-cycle") ==
             {"when", "no cycle comes before the one holding 2026-11-05"}

    assert resolve(scope, "this-cycle", ~D[2027-06-01]) ==
             {"when", "no cycle holds today, 2027-06-01"}
  end

  test "resolves a span from the first date of first to the last date of last", %{scope: scope} do
    assert resolve(scope, %{"first" => "last-week", "last" => "yesterday"}) ==
             {~D[2026-10-26], ~D[2026-11-04]}

    assert resolve(scope, %{"first" => "tomorrow", "last" => "yesterday"}) ==
             {"when", "ends on 2026-11-04, before it starts on 2026-11-06"}

    assert resolve(scope, %{"first" => "soon", "last" => "today"}) ==
             {"when.first",
              "must be a date such as 2026-11-02, -3d, +2d or one of today, yesterday, " <>
                "tomorrow, last-week, this-week, next-week, last-month, this-month, " <>
                "next-month, last-cycle, this-cycle, next-cycle, this-block, this-phase, " <>
                "this-season"}
  end
end
