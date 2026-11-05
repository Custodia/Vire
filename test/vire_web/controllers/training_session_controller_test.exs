defmodule VireWeb.TrainingSessionControllerTest do
  use VireWeb.ConnCase, async: true

  import Vire.ActivitiesFixtures
  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Activities
  alias Vire.Training

  setup %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)
    %{conn: sign_in(conn, user), scope: scope}
  end

  defp plan(scope, first, last) do
    season = season_fixture(scope, name: "Season", period: period(first, last))
    phase = phase_fixture(scope, season, name: "Build", period: season.period)
    block = block_fixture(scope, phase, focus: "Threshold", period: season.period)
    cycle = cycle_fixture(scope, block, period: period(first, Date.add(first, 6)))
    %{season: season, phase: phase, block: block, cycle: cycle}
  end

  test "answers a done session with its day, its chain and the ride with its laps",
       %{conn: conn, scope: scope} do
    plan = plan(scope, ~D[2026-07-13], ~D[2026-07-26])

    session =
      session_fixture(scope,
        date: ~D[2026-07-14],
        position: 0,
        discipline: :bike,
        structure: %{"title" => "Threshold", "steps" => [%{"kind" => "work", "seconds" => 600}]},
        planned_seconds: 600,
        rationale: "Lift threshold power"
      )

    ride = activity_fixture(scope, "ride.fit")

    assert %{"day" => day, "activity" => activity} =
             body = json_response(get(conn, ~p"/api/sessions/#{session.id}"), 200)

    assert Map.drop(body, ["day", "activity"]) == %{
             "last_time" => nil,
             "id" => session.id,
             "position" => 0,
             "discipline" => "bike",
             "title" => "Threshold",
             "structure" => %{
               "title" => "Threshold",
               "steps" => [%{"kind" => "work", "seconds" => 600}]
             },
             "planned_seconds" => 600,
             "status" => "done",
             "rationale" => "Lift threshold power"
           }

    assert day == %{
             "id" => session.day_id,
             "date" => "2026-07-14",
             "kind" => "training",
             "note" => nil,
             "chain" => %{
               "season" => %{"id" => plan.season.id, "name" => "Season"},
               "phase" => %{"id" => plan.phase.id, "name" => "Build"},
               "block" => %{"id" => plan.block.id, "focus" => "Threshold"},
               "cycle" => %{
                 "id" => plan.cycle.id,
                 "kind" => "load",
                 "day_number" => 2,
                 "length" => 7
               }
             }
           }

    assert %{
             "id" => ride_id,
             "discipline" => "bike",
             "local_date" => "2026-07-14",
             "started_at" => "2026-07-15T02:00:00.000000Z",
             "utc_offset_seconds" => -25_200,
             "duration_seconds" => duration,
             "pool_length_m" => nil,
             "lengths" => [],
             "laps" => [first_lap, second_lap]
           } = activity

    assert ride_id == ride.id
    assert duration == ride.duration_seconds

    assert %{"lap_index" => 0, "elapsed_seconds" => 240, "avg_power" => power} = first_lap
    assert is_integer(power)
    assert %{"lap_index" => 1, "elapsed_seconds" => 360, "moving_seconds" => 300} = second_lap
  end

  defp activity(scope, id, %DateTime{} = started_at, discipline) do
    {:inserted, activity} =
      Activities.upsert_provider_activity(scope, %{
        provider: :garmin,
        external_id: to_string(id),
        started_at: started_at,
        utc_offset_seconds: 0,
        local_date: DateTime.to_date(started_at),
        discipline: discipline,
        duration_seconds: 2400,
        distance_m: 5100.0,
        training_load: 41.0,
        provider_summary: %{"activityId" => id}
      })

    activity
  end

  defp titled(scope, date, position, discipline, title) do
    session_fixture(scope,
      date: date,
      position: position,
      discipline: discipline,
      structure: %{"title" => title}
    )
  end

  describe "last time" do
    setup %{scope: scope} do
      plan(scope, ~D[2026-07-13], ~D[2026-07-26])
      :ok
    end

    test "is the latest earlier matched session with the same discipline and title",
         %{conn: conn, scope: scope} do
      older = titled(scope, ~D[2026-07-13], 0, :run, "Run / walk")
      latest = titled(scope, ~D[2026-07-15], 0, :run, "Run / walk")
      titled(scope, ~D[2026-07-16], 0, :run, "Intervals")
      titled(scope, ~D[2026-07-16], 1, :bike, "Run / walk")
      today = titled(scope, ~D[2026-07-17], 0, :run, "Run / walk")

      for {session, id, at} <- [
            {older, 1, ~U[2026-07-13 06:00:00Z]},
            {latest, 2, ~U[2026-07-15 06:00:00Z]}
          ] do
        run = activity(scope, id, at, :run)
        {:ok, _matched} = Training.match_session(scope, session.id, run.id, "Matched")
      end

      assert %{"last_time" => last_time} =
               json_response(get(conn, ~p"/api/sessions/#{today.id}"), 200)

      assert %{
               "session_id" => session_id,
               "date" => "2026-07-15",
               "activity" => %{
                 "duration_seconds" => 2400,
                 "distance_m" => 5100.0,
                 "training_load" => 41.0,
                 "avg_heart_rate" => nil
               }
             } = last_time

      assert session_id == latest.id
    end

    test "is null without an earlier matched session", %{conn: conn, scope: scope} do
      titled(scope, ~D[2026-07-15], 0, :run, "Run / walk")
      today = titled(scope, ~D[2026-07-17], 0, :run, "Run / walk")

      assert %{"last_time" => nil} = json_response(get(conn, ~p"/api/sessions/#{today.id}"), 200)
    end

    test "averages the heart rate of the activity's laps by time", %{conn: conn, scope: scope} do
      session_fixture(scope, date: ~D[2026-07-14], position: 0, discipline: :bike)
      ride = activity_fixture(scope, "ride.fit")
      %{laps: laps} = Activities.get_activity(scope, ride.id)
      today = session_fixture(scope, date: ~D[2026-07-18], position: 0, discipline: :bike)

      expected =
        round(
          Enum.sum_by(laps, &(&1.avg_heart_rate * &1.elapsed_seconds)) /
            Enum.sum_by(laps, & &1.elapsed_seconds)
        )

      assert %{"last_time" => %{"activity" => %{"avg_heart_rate" => ^expected}}} =
               json_response(get(conn, ~p"/api/sessions/#{today.id}"), 200)
    end
  end

  describe "matching" do
    setup %{scope: scope} do
      plan(scope, ~D[2026-07-13], ~D[2026-07-26])
      :ok
    end

    test "matches an activity on the session's date and logs it", %{conn: conn, scope: scope} do
      session = session_fixture(scope, date: ~D[2026-07-15], position: 0, discipline: :run)
      walk = activity(scope, 1, ~U[2026-07-15 12:10:00Z], :other)

      assert %{"status" => "done", "activity" => %{"id" => walk_id}} =
               conn
               |> put(~p"/api/sessions/#{session.id}/activity", %{activity_id: walk.id})
               |> json_response(200)

      assert walk_id == walk.id

      assert [%{rationale: "Matched on the dashboard", channel: :dashboard} | _inserted] =
               Training.list_changes(scope, entity: :training_session, entity_id: session.id)
    end

    test "clears a match with a null activity", %{conn: conn, scope: scope} do
      session = session_fixture(scope, date: ~D[2026-07-15], position: 0, discipline: :run)
      run = activity(scope, 1, ~U[2026-07-15 06:00:00Z], :run)
      {:ok, _matched} = Training.match_session(scope, session.id, run.id, "Matched")

      assert %{"status" => "planned", "activity" => nil} =
               conn
               |> put(~p"/api/sessions/#{session.id}/activity", %{activity_id: nil})
               |> json_response(200)
    end

    test "refuses an activity on another date or matched elsewhere", %{conn: conn, scope: scope} do
      session = session_fixture(scope, date: ~D[2026-07-15], position: 0, discipline: :run)
      other = session_fixture(scope, date: ~D[2026-07-15], position: 1, discipline: :run)
      tuesday = activity(scope, 1, ~U[2026-07-14 06:00:00Z], :run)
      wednesday = activity(scope, 2, ~U[2026-07-15 06:00:00Z], :run)
      {:ok, _matched} = Training.match_session(scope, other.id, wednesday.id, "Matched")

      assert %{"errors" => %{"detail" => "the activity is on another date"}} =
               conn
               |> put(~p"/api/sessions/#{session.id}/activity", %{activity_id: tuesday.id})
               |> json_response(422)

      assert %{"errors" => %{"detail" => "the activity is matched to another session"}} =
               conn
               |> put(~p"/api/sessions/#{session.id}/activity", %{activity_id: wednesday.id})
               |> json_response(422)
    end

    test "answers 404 for another user's session or activity", %{conn: conn, scope: scope} do
      other = scope_fixture()
      plan(other, ~D[2026-07-13], ~D[2026-07-26])
      theirs = session_fixture(other, date: ~D[2026-07-15], position: 0, discipline: :run)
      their_run = activity(other, 1, ~U[2026-07-15 06:00:00Z], :run)
      mine = session_fixture(scope, date: ~D[2026-07-15], position: 0, discipline: :run)

      assert conn
             |> put(~p"/api/sessions/#{theirs.id}/activity", %{activity_id: nil})
             |> json_response(404)

      assert conn
             |> put(~p"/api/sessions/#{mine.id}/activity", %{activity_id: their_run.id})
             |> json_response(404)
    end
  end

  test "answers a swim's pool lengths", %{conn: conn, scope: scope} do
    plan(scope, ~D[2026-01-19], ~D[2026-02-01])
    session = session_fixture(scope, date: ~D[2026-01-20], position: 0, discipline: :swim)
    activity_fixture(scope, "swim.fit")

    assert %{"status" => "done", "activity" => activity} =
             json_response(get(conn, ~p"/api/sessions/#{session.id}"), 200)

    assert %{"pool_length_m" => 25.0, "distance_m" => 300.0, "lengths" => lengths} = activity
    assert length(lengths) == 14
    assert [%{"length_index" => 0, "active" => true, "stroke" => "freestyle"} | _rest] = lengths
    assert Enum.count(lengths, &(not &1["active"])) == 2
  end

  test "answers a planned and a skipped session without an activity",
       %{conn: conn, scope: scope} do
    plan(scope, ~D[2026-07-13], ~D[2026-07-26])
    planned = session_fixture(scope, date: ~D[2026-07-15], position: 0, discipline: :run)
    skipped = session_fixture(scope, date: ~D[2026-07-15], position: 1, discipline: :strength)
    {:ok, _skipped} = Training.update_session(scope, skipped.id, %{status: :skipped}, "Tired")

    assert %{"status" => "planned", "title" => "Run", "activity" => nil, "day" => day} =
             json_response(get(conn, ~p"/api/sessions/#{planned.id}"), 200)

    assert %{"date" => "2026-07-15", "chain" => %{"cycle" => %{"day_number" => 3}}} = day

    assert %{"status" => "skipped", "activity" => nil} =
             json_response(get(conn, ~p"/api/sessions/#{skipped.id}"), 200)
  end

  test "answers 404 for another user's session and for an id that is not one",
       %{conn: conn, scope: scope} do
    other = scope_fixture()
    plan(other, ~D[2026-07-13], ~D[2026-07-26])
    session = session_fixture(other, date: ~D[2026-07-14], position: 0, discipline: :run)
    plan(scope, ~D[2026-07-13], ~D[2026-07-26])

    assert json_response(get(conn, ~p"/api/sessions/#{session.id}"), 404) ==
             %{"errors" => %{"detail" => "Not Found"}}

    assert json_response(get(conn, ~p"/api/sessions/not-an-id"), 404)
  end

  test "answers 401 without a session" do
    assert json_response(get(build_conn(), ~p"/api/sessions/#{Ecto.UUID.generate()}"), 401) ==
             %{"errors" => %{"detail" => "Unauthorized"}}
  end
end
