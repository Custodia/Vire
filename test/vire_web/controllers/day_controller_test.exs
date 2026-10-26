defmodule VireWeb.DayControllerTest do
  use VireWeb.ConnCase, async: true

  import Vire.ActivitiesFixtures
  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Training

  setup %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    season =
      season_fixture(scope, name: "Summer", period: period(~D[2026-07-01], ~D[2026-08-30]))

    phase = phase_fixture(scope, season, name: "Build", period: season.period)

    block =
      block_fixture(scope, phase,
        focus: "Threshold",
        period: period(~D[2026-07-13], ~D[2026-07-26])
      )

    cycle = cycle_fixture(scope, block, period: period(~D[2026-07-13], ~D[2026-07-19]))

    %{
      conn: sign_in(conn, user),
      scope: scope,
      plan: %{season: season, phase: phase, block: block, cycle: cycle}
    }
  end

  defp session(scope, attrs) do
    session_fixture(scope, Enum.into(attrs, %{date: ~D[2026-07-14], rationale: "Planned"}))
  end

  test "answers a training day with its chain, its sessions and their matched activity",
       %{conn: conn, scope: scope, plan: plan} do
    ride_session =
      session(scope,
        position: 0,
        discipline: :bike,
        structure: %{
          "title" => "Bike — threshold 3 × 12′",
          "steps" => [%{"kind" => "work", "seconds" => 600, "zone" => 4}]
        },
        planned_seconds: 600
      )

    run_session =
      session(scope, position: 1, discipline: :run, structure: %{}, planned_seconds: 1800)

    strength = session(scope, position: 2, discipline: :strength, planned_seconds: 2400)
    {:ok, _skipped} = Training.update_session(scope, strength.id, %{status: :skipped}, "Tired")
    {:ok, _day} = Training.update_day(scope, ~D[2026-07-14], %{note: "Travel"}, "Flight")

    ride = activity_fixture(scope, "ride.fit")

    assert %{"date" => "2026-07-14", "day" => day, "activities" => []} =
             json_response(get(conn, ~p"/api/days/2026-07-14"), 200)

    assert %{"kind" => "training", "note" => "Travel", "date" => "2026-07-14"} = day

    assert day["chain"] == %{
             "season" => %{"id" => plan.season.id, "name" => "Summer"},
             "phase" => %{"id" => plan.phase.id, "name" => "Build"},
             "block" => %{"id" => plan.block.id, "focus" => "Threshold"},
             "cycle" => %{
               "id" => plan.cycle.id,
               "kind" => "load",
               "day_number" => 2,
               "length" => 7
             }
           }

    assert [bike, run, skipped] = day["sessions"]

    assert bike == %{
             "id" => ride_session.id,
             "position" => 0,
             "discipline" => "bike",
             "title" => "Bike — threshold 3 × 12′",
             "structure" => %{
               "title" => "Bike — threshold 3 × 12′",
               "steps" => [%{"kind" => "work", "seconds" => 600, "zone" => 4}]
             },
             "planned_seconds" => 600,
             "status" => "done",
             "rationale" => "Planned",
             "activity" => %{
               "id" => ride.id,
               "discipline" => "bike",
               "started_at" => "2026-07-15T02:00:00.000000Z",
               "utc_offset_seconds" => -25_200,
               "duration_seconds" => ride.duration_seconds,
               "distance_m" => ride.distance_m,
               "training_load" => nil
             }
           }

    assert %{
             "id" => run_id,
             "title" => "Run",
             "status" => "planned",
             "planned_seconds" => 1800,
             "activity" => nil
           } = run

    assert run_id == run_session.id
    assert %{"title" => "Strength", "status" => "skipped", "position" => 2} = skipped
  end

  test "lists the date's activities no session is matched to", %{conn: conn, scope: scope} do
    session(scope, date: ~D[2026-07-16], position: 0, discipline: :swim)
    run = activity_fixture(scope, "run.fit")

    assert %{"day" => %{"sessions" => [%{"activity" => nil}]}, "activities" => [activity]} =
             json_response(get(conn, ~p"/api/days/2026-07-16"), 200)

    assert %{"id" => run_id, "discipline" => "run", "duration_seconds" => 600} = activity
    assert run_id == run.id
  end

  test "answers a rest day without sessions", %{conn: conn} do
    assert %{"day" => %{"kind" => "rest", "note" => nil, "sessions" => []}, "activities" => []} =
             json_response(get(conn, ~p"/api/days/2026-07-19"), 200)
  end

  test "answers no day with the date's activities outside every cycle",
       %{conn: conn, scope: scope} do
    swim = activity_fixture(scope, "swim.fit")

    assert %{"date" => "2026-01-20", "day" => nil, "activities" => [activity]} =
             json_response(get(conn, ~p"/api/days/2026-01-20"), 200)

    assert %{"id" => swim_id, "discipline" => "swim", "distance_m" => 300.0} = activity
    assert swim_id == swim.id
  end

  test "answers another user's date as empty", %{scope: scope} do
    activity_fixture(scope, "ride.fit")
    conn = sign_in(build_conn(), user_fixture())

    assert json_response(get(conn, ~p"/api/days/2026-07-14"), 200) == %{
             "date" => "2026-07-14",
             "day" => nil,
             "activities" => []
           }
  end

  test "answers 400 for a date that is not one", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/days/2026-02-30"), 400) ==
             %{"errors" => %{"detail" => "Bad Request"}}
  end

  test "answers 401 without a session" do
    assert json_response(get(build_conn(), ~p"/api/days/2026-07-14"), 401) ==
             %{"errors" => %{"detail" => "Unauthorized"}}
  end
end
