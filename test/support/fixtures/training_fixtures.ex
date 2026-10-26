defmodule Vire.TrainingFixtures do
  alias Vire.Accounts.Scope
  alias Vire.Training
  alias Vire.Training.Period

  def scope_fixture, do: Scope.for_user(Vire.AccountsFixtures.user_fixture())

  def period(first, last), do: Period.new(first, last)

  def season_fixture(scope, attrs \\ %{}) do
    {:ok, season} =
      Training.create_season(
        scope,
        Enum.into(attrs, %{
          name: "Winter base",
          period: period(~D[2026-11-02], ~D[2027-03-28]),
          rationale: "Aerobic base before the spring races"
        })
      )

    season
  end

  def phase_fixture(scope, season, attrs \\ %{}) do
    {:ok, phase} =
      Training.create_phase(
        scope,
        season.id,
        Enum.into(attrs, %{
          name: "Base",
          period: period(~D[2026-11-02], ~D[2027-01-31]),
          rationale: "Volume first"
        })
      )

    phase
  end

  def block_fixture(scope, phase, attrs \\ %{}) do
    {:ok, block} =
      Training.create_block(
        scope,
        phase.id,
        Enum.into(attrs, %{
          focus: "Aerobic endurance",
          period: period(~D[2026-11-02], ~D[2026-11-29]),
          rationale: "Long easy rides"
        })
      )

    block
  end

  def cycle_fixture(scope, block, attrs \\ %{}) do
    {:ok, cycle} =
      Training.create_cycle(
        scope,
        block.id,
        Enum.into(attrs, %{
          kind: :load,
          period: period(~D[2026-11-02], ~D[2026-11-08]),
          rationale: "First load week"
        })
      )

    cycle
  end

  def plan_fixture(scope) do
    season = season_fixture(scope)
    phase = phase_fixture(scope, season)
    block = block_fixture(scope, phase)
    cycle = cycle_fixture(scope, block)
    %{season: season, phase: phase, block: block, cycle: cycle}
  end

  def session_fixture(scope, attrs \\ %{}) do
    {:ok, session} =
      Training.create_session(
        scope,
        Enum.into(attrs, %{
          date: ~D[2026-11-03],
          position: 0,
          discipline: :bike,
          structure: %{"steps" => [%{"kind" => "work", "seconds" => 5400, "zone" => 2}]},
          planned_seconds: 5400,
          rationale: "Endurance ride"
        })
      )

    session
  end
end
