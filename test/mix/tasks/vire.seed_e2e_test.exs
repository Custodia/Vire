defmodule Mix.Tasks.Vire.SeedE2eTest do
  use Vire.DataCase, async: false

  alias Vire.Accounts
  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Accounts.User
  alias Vire.Training
  alias Vire.Training.Block
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.Period
  alias Vire.Training.Phase
  alias Vire.Training.PlanChange
  alias Vire.Training.Season
  alias Vire.Training.Session

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp seeded_scope do
    "e2e@example.com"
    |> Accounts.get_user_by_email_and_password("e2e-password-1234")
    |> Scope.for_user()
  end

  defp titles(scope, date) do
    scope |> Training.get_day(date) |> Map.fetch!(:sessions) |> Enum.map(& &1.structure["title"])
  end

  test "creates the e2e user with a Garmin connection" do
    Mix.Task.rerun("vire.seed_e2e")

    assert %Scope{user: %User{} = user} = seeded_scope()
    assert Repo.get_by!(ProviderConnection, user_id: user.id).provider == :garmin
  end

  test "gives a new user a plan around the fixture dates and today" do
    Mix.Task.rerun("vire.seed_e2e")

    scope = seeded_scope()
    today = Date.utc_today()

    assert [season] = Training.list_seasons(scope)
    assert season.period == Period.new(~D[2026-01-01], Date.new!(today.year + 1, 12, 31))
    assert [%Block{period: block_period}] = Repo.all(Block)
    assert block_period == season.period

    assert Cycle |> Repo.all() |> Enum.map(& &1.period) |> Enum.sort_by(& &1.first, Date) == [
             Period.new(~D[2026-07-13], ~D[2026-07-19]),
             Period.new(today, Date.add(today, 6))
           ]

    assert titles(scope, ~D[2026-07-14]) == ["Saddle check ride"]
    assert titles(scope, ~D[2026-07-16]) == ["Shakeout run"]
    assert titles(scope, today) == ["Threshold intervals", "Technique swim"]
    assert titles(scope, Date.add(today, 1)) == ["Threshold intervals", "Technique swim"]
    assert Training.get_day(scope, ~D[2026-01-20]) == nil

    [run, _swim] = Training.get_day(scope, today).sessions
    assert [_warmup, %{"repeat" => 3}, _cooldown] = run.structure["steps"]
  end

  test "changes nothing on a second run" do
    Mix.Task.rerun("vire.seed_e2e")

    counts = fn ->
      Enum.map(
        [User, ProviderConnection, Season, Phase, Block, Cycle, Day, Session, PlanChange],
        &Repo.aggregate(&1, :count)
      )
    end

    before = counts.()

    Mix.Task.rerun("vire.seed_e2e")

    assert counts.() == before
  end

  test "extends a season that has ended instead of adding one" do
    {:ok, user} =
      Accounts.create_user_with_provider_connection(
        %{email: "e2e@example.com", name: "End-to-end Athlete", password: "e2e-password-1234"},
        %{provider: :garmin, credential: "invented-garmin-key"}
      )

    scope = Scope.for_user(user)
    ended = %{first: ~D[2026-01-01], last: ~D[2026-01-31]}

    {:ok, season} =
      Training.create_season(scope, %{name: "Winter", period: ended, rationale: "Base."})

    {:ok, phase} =
      Training.create_phase(scope, season.id, %{name: "Base", period: ended, rationale: "Base."})

    {:ok, _block} =
      Training.create_block(scope, phase.id, %{focus: "Easy", period: ended, rationale: "Base."})

    Mix.Task.rerun("vire.seed_e2e")

    extended = Period.new(~D[2026-01-01], Date.new!(Date.utc_today().year + 1, 12, 31))
    assert [%Season{id: season_id, period: ^extended}] = Training.list_seasons(scope)
    assert season_id == season.id
    assert [%Phase{period: ^extended}] = Repo.all(Phase)
    assert [%Block{period: ^extended}] = Repo.all(Block)
    assert titles(scope, Date.utc_today()) == ["Threshold intervals", "Technique swim"]
  end

  test "matches the activities already recorded on a seeded session's date" do
    Mix.Task.rerun("vire.seed_e2e")
    scope = seeded_scope()
    [session] = Training.get_day(scope, ~D[2026-07-14]).sessions
    Repo.delete!(session)

    activity = Vire.ActivitiesFixtures.activity_fixture(scope, "ride.fit")

    Mix.Task.rerun("vire.seed_e2e")

    assert [%Session{status: :done, activity_id: activity_id}] =
             Training.get_day(scope, ~D[2026-07-14]).sessions

    assert activity_id == activity.id
  end

  test "clears a paused Garmin connection" do
    Mix.Task.rerun("vire.seed_e2e")
    scope = seeded_scope()
    connection = Accounts.get_provider_connection(scope, :garmin)
    {:ok, _paused} = Accounts.pause_provider_connection(scope, connection)

    Mix.Task.rerun("vire.seed_e2e")

    assert %ProviderConnection{paused_at: nil} = Accounts.get_provider_connection(scope, :garmin)
  end
end
