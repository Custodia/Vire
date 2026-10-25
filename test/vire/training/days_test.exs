defmodule Vire.Training.DaysTest do
  use Vire.DataCase, async: true

  import Ecto.Query

  alias Vire.Training
  alias Vire.Training.Day

  setup do
    scope = scope_fixture()
    Map.put(plan_fixture(scope), :scope, scope)
  end

  defp days(cycle) do
    Repo.all(
      from d in Day, where: d.cycle_id == ^cycle.id, order_by: d.day, select: {d.day, d.kind}
    )
  end

  defp create_cycle(scope, block, attrs \\ %{}),
    do: Training.create_cycle(scope, block.id, Enum.into(attrs, %{kind: :load, rationale: "Why"}))

  test "creating a cycle creates one rest day per date", %{scope: scope, block: block} do
    {:ok, cycle} = create_cycle(scope, block, period: period(~D[2026-11-09], ~D[2026-11-18]))

    assert days(cycle) ==
             for(date <- Date.range(~D[2026-11-09], ~D[2026-11-18]), do: {date, :rest})
  end

  test "a cycle without a period starts on the block's first day and ends on Sunday",
       %{scope: scope, phase: phase} do
    monday = block_fixture(scope, phase, period: period(~D[2026-11-30], ~D[2026-12-27]))
    wednesday = block_fixture(scope, phase, period: period(~D[2027-01-06], ~D[2027-01-31]))

    {:ok, week} = create_cycle(scope, monday)
    {:ok, short} = create_cycle(scope, wednesday)

    assert week.period == period(~D[2026-11-30], ~D[2026-12-06])
    assert short.period == period(~D[2027-01-06], ~D[2027-01-10])
    assert length(days(week)) == 7
    assert length(days(short)) == 5
  end

  test "a cycle without a period follows the block's latest cycle, within the block",
       %{scope: scope, phase: phase} = plan do
    {:ok, next} = create_cycle(scope, plan.block)
    assert next.period == period(~D[2026-11-09], ~D[2026-11-15])

    block = block_fixture(scope, phase, period: period(~D[2026-11-30], ~D[2026-12-23]))
    {:ok, _long} = create_cycle(scope, block, period: period(~D[2026-11-30], ~D[2026-12-20]))
    {:ok, clipped} = create_cycle(scope, block, kind: :recovery)
    {:error, full} = create_cycle(scope, block)

    assert clipped.period == period(~D[2026-12-21], ~D[2026-12-23])

    assert days(clipped) == [
             {~D[2026-12-21], :rest},
             {~D[2026-12-22], :rest},
             {~D[2026-12-23], :rest}
           ]

    assert %{period: ["has no days left in the block"]} = errors_on(full)
  end

  test "a given period still has to fit the block", %{scope: scope, block: block} do
    {:error, changeset} =
      create_cycle(scope, block, period: period(~D[2026-11-23], ~D[2026-12-06]))

    assert %{period: ["lies outside its block"]} = errors_on(changeset)
    refute Repo.exists?(from d in Day, where: d.day > ^~D[2026-11-08])
  end

  test "widening a cycle adds rest days and keeps the ones it had", %{scope: scope, cycle: cycle} do
    Training.update_day(scope, ~D[2026-11-08], %{note: "Long ride"}, "Plan")

    {:ok, wider} =
      Training.update_cycle(
        scope,
        cycle.id,
        %{period: period(~D[2026-11-02], ~D[2026-11-11])},
        "Longer"
      )

    assert length(days(wider)) == 10
    assert Repo.get_by!(Day, day: ~D[2026-11-08]).note == "Long ride"
    assert Repo.get_by!(Day, day: ~D[2026-11-11]).kind == :rest
  end

  test "shrinking a cycle removes the plain rest days it leaves out",
       %{scope: scope, cycle: cycle} do
    session_fixture(scope, date: ~D[2026-11-04])

    {:ok, narrower} =
      Training.update_cycle(
        scope,
        cycle.id,
        %{period: period(~D[2026-11-03], ~D[2026-11-05])},
        "Shorter"
      )

    assert Enum.map(days(narrower), &elem(&1, 0)) == [
             ~D[2026-11-03],
             ~D[2026-11-04],
             ~D[2026-11-05]
           ]
  end

  test "shrinking a cycle past a day with a session is refused and keeps every day",
       %{scope: scope, cycle: cycle} do
    session_fixture(scope, date: ~D[2026-11-07])

    {:error, changeset} =
      Training.update_cycle(
        scope,
        cycle.id,
        %{period: period(~D[2026-11-02], ~D[2026-11-05])},
        "Shorter"
      )

    assert %{period: ["no longer contains all of its days with sessions or notes"]} =
             errors_on(changeset)

    assert length(days(cycle)) == 7
  end

  test "shrinking a cycle past a training day or a day with a note is refused",
       %{scope: scope, cycle: cycle} do
    session = session_fixture(scope, date: ~D[2026-11-07])
    {:ok, _} = Training.delete_session(scope, session.id, "Dropped")
    Training.update_day(scope, ~D[2026-11-08], %{note: "Race recon"}, "Plan")

    for last <- [~D[2026-11-07], ~D[2026-11-06]] do
      {:error, changeset} =
        Training.update_cycle(scope, cycle.id, %{period: period(~D[2026-11-02], last)}, "Shorter")

      assert %{period: ["no longer contains all of its days with sessions or notes"]} =
               errors_on(changeset)
    end

    assert days(cycle) |> Enum.map(&elem(&1, 1)) |> Enum.count(&(&1 == :training)) == 1
    assert Repo.get_by!(Day, day: ~D[2026-11-08]).note == "Race recon"
  end

  test "moving a cycle within its block moves its rest days", %{scope: scope, cycle: cycle} do
    {:ok, moved} =
      Training.update_cycle(
        scope,
        cycle.id,
        %{period: period(~D[2026-11-05], ~D[2026-11-11])},
        "Later"
      )

    assert Enum.map(days(moved), &elem(&1, 0)) ==
             Enum.to_list(Date.range(~D[2026-11-05], ~D[2026-11-11]))
  end

  test "an invalid change leaves the days alone", %{scope: scope, cycle: cycle} do
    {:error, changeset} =
      Training.update_cycle(
        scope,
        cycle.id,
        %{period: period(~D[2026-11-03], ~D[2026-11-05])},
        " "
      )

    assert %{rationale: ["can't be blank"]} = errors_on(changeset)
    assert length(days(cycle)) == 7
  end
end
