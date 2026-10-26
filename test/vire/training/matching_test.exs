defmodule Vire.Training.MatchingTest do
  use Vire.DataCase, async: true

  alias Vire.Activities
  alias Vire.Training
  alias Vire.Training.Session

  @day ~D[2026-11-03]

  setup do
    scope = scope_fixture()
    Map.merge(plan_fixture(scope), %{scope: scope, other: scope_fixture()})
  end

  defp activity(scope, id, %DateTime{} = started_at, discipline) do
    {:ok, activity} =
      Activities.upsert_provider_activity(scope, %{
        provider: :garmin,
        external_id: to_string(id),
        started_at: started_at,
        utc_offset_seconds: 0,
        local_date: DateTime.to_date(started_at),
        discipline: discipline,
        duration_seconds: 3600,
        distance_m: 10_000.0,
        provider_summary: %{"activityId" => id}
      })

    activity
  end

  defp session(scope, position, discipline, date \\ @day) do
    session_fixture(scope, date: date, position: position, discipline: discipline)
  end

  defp reload(session), do: Repo.get!(Session, session.id)

  defp matches(sessions), do: Enum.map(sessions, &{reload(&1).activity_id, reload(&1).status})

  describe "match_activities/2" do
    test "pairs one activity with one session and marks it done", %{scope: scope} do
      session = session(scope, 0, :bike)
      ride = activity(scope, 1, ~U[2026-11-03 07:00:00Z], :bike)

      assert :ok = Training.match_activities(scope, @day)

      assert matches([session]) == [{ride.id, :done}]

      assert Training.list_changes(scope, entity: :training_session, entity_id: session.id)
             |> length() == 1
    end

    test "pairs two activities with two sessions by start time and position", %{scope: scope} do
      first = session(scope, 0, :run)
      second = session(scope, 1, :run)
      evening = activity(scope, 2, ~U[2026-11-03 17:00:00Z], :run)
      morning = activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)

      Training.match_activities(scope, @day)

      assert matches([first, second]) == [{morning.id, :done}, {evening.id, :done}]
    end

    test "leaves a day with more activities than sessions unmatched", %{scope: scope} do
      session = session(scope, 0, :run)
      activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)
      activity(scope, 2, ~U[2026-11-03 17:00:00Z], :run)

      Training.match_activities(scope, @day)

      assert matches([session]) == [{nil, :planned}]
    end

    test "leaves a day with more sessions than activities unmatched", %{scope: scope} do
      first = session(scope, 0, :run)
      second = session(scope, 1, :run)
      activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)

      Training.match_activities(scope, @day)

      assert matches([first, second]) == [{nil, :planned}, {nil, :planned}]
    end

    test "matches each discipline on its own", %{scope: scope} do
      ride_session = session(scope, 0, :bike)
      run_session = session(scope, 1, :run)
      ride = activity(scope, 1, ~U[2026-11-03 07:00:00Z], :bike)
      activity(scope, 2, ~U[2026-11-03 06:00:00Z], :run)
      activity(scope, 3, ~U[2026-11-03 18:00:00Z], :run)
      activity(scope, 4, ~U[2026-11-03 12:00:00Z], :swim)

      Training.match_activities(scope, @day)

      assert matches([ride_session, run_session]) == [{ride.id, :done}, {nil, :planned}]
    end

    test "matches only on the date asked for", %{scope: scope} do
      session = session(scope, 0, :bike, ~D[2026-11-04])
      activity(scope, 1, ~U[2026-11-03 07:00:00Z], :bike)

      Training.match_activities(scope, @day)
      Training.match_activities(scope, ~D[2026-11-04])

      assert matches([session]) == [{nil, :planned}]
    end

    test "pairs what is still unmatched once a day already holds a match", %{scope: scope} do
      first = session(scope, 0, :run)
      morning = activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)
      Training.match_activities(scope, @day)

      second = session(scope, 1, :run)
      evening = activity(scope, 2, ~U[2026-11-03 17:00:00Z], :run)
      Training.match_activities(scope, @day)

      assert matches([first, second]) == [{morning.id, :done}, {evening.id, :done}]
    end

    test "leaves another user's sessions and activities alone", %{scope: scope, other: other} do
      plan_fixture(other)
      session = session(scope, 0, :bike)
      theirs = session(other, 0, :bike)
      activity(other, 1, ~U[2026-11-03 07:00:00Z], :bike)

      Training.match_activities(scope, @day)

      assert matches([session, theirs]) == [{nil, :planned}, {nil, :planned}]
    end
  end

  describe "match_session/4" do
    test "matches by hand, marks the session done and logs the change", %{scope: scope} do
      session = session(scope, 0, :run)
      morning = activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)
      activity(scope, 2, ~U[2026-11-03 17:00:00Z], :run)

      assert {:ok, %Session{status: :done}} =
               Training.match_session(scope, session.id, morning.id, "The morning run was it")

      assert matches([session]) == [{morning.id, :done}]

      assert [change | _insert] =
               Training.list_changes(scope, entity: :training_session, entity_id: session.id)

      assert change.action == :update
      assert change.rationale == "The morning run was it"
      assert change.before["activity_id"] == nil
      assert change.after["activity_id"] == morning.id
    end

    test "clears a match, marks the session planned and logs the change", %{scope: scope} do
      session = session(scope, 0, :run)
      run = activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)
      Training.match_activities(scope, @day)

      assert {:ok, %Session{status: :planned, activity_id: nil}} =
               Training.match_session(scope, session.id, nil, "That was a commute")

      assert [change | _insert] =
               Training.list_changes(scope, entity: :training_session, entity_id: session.id)

      assert change.before["activity_id"] == run.id
      assert change.after["activity_id"] == nil
      assert change.after["status"] == "planned"
    end

    test "leaves a session matched or cleared by hand to the hand", %{scope: scope} do
      session = session(scope, 0, :run)
      activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)
      Training.match_activities(scope, @day)
      {:ok, _session} = Training.match_session(scope, session.id, nil, "That was a commute")

      Training.match_activities(scope, @day)

      assert matches([session]) == [{nil, :planned}]
    end

    test "refuses an activity of another user or another date", %{scope: scope, other: other} do
      session = session(scope, 0, :run)
      theirs = activity(other, 1, ~U[2026-11-03 06:00:00Z], :run)
      next_day = activity(scope, 2, ~U[2026-11-04 06:00:00Z], :run)

      assert Training.match_session(scope, session.id, theirs.id, "Why") == {:error, :not_found}

      assert Training.match_session(scope, session.id, "not-a-uuid", "Why") ==
               {:error, :not_found}

      assert Training.match_session(scope, session.id, next_day.id, "Why") ==
               {:error, :different_date}

      assert matches([session]) == [{nil, :planned}]
    end

    test "refuses another user's session, a taken activity and a missing rationale", context do
      %{scope: scope, other: other} = context
      first = session(scope, 0, :run)
      second = session(scope, 1, :run)
      run = activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)
      {:ok, _first} = Training.match_session(scope, first.id, run.id, "The run")

      assert Training.match_session(other, first.id, nil, "Why") == {:error, :not_found}
      assert {:error, taken} = Training.match_session(scope, second.id, run.id, "Also the run")
      assert {:error, blank} = Training.match_session(scope, second.id, run.id, " ")

      assert %{activity_id: ["is matched to another session"]} = errors_on(taken)
      assert %{rationale: ["can't be blank"]} = errors_on(blank)
      assert matches([first, second]) == [{run.id, :done}, {nil, :planned}]
    end
  end

  describe "skip_missed_sessions/3" do
    test "marks planned sessions before today within the periods skipped", %{scope: scope} do
      missed = session(scope, 0, :run, ~D[2026-11-03])
      today = session(scope, 0, :run, ~D[2026-11-05])
      outside = session(scope, 0, :run, ~D[2026-11-07])
      done = session(scope, 0, :bike, ~D[2026-11-02])
      {:ok, _done} = Training.update_session(scope, done.id, %{status: :done}, "Rode indoors")

      periods = [period(~D[2026-11-02], ~D[2026-11-05])]
      assert Training.skip_missed_sessions(scope, periods, ~D[2026-11-05]) == 1

      assert Enum.map([missed, today, outside, done], &reload(&1).status) ==
               [:skipped, :planned, :planned, :done]
    end

    test "a skipped session is done once a match arrives", %{scope: scope} do
      session = session(scope, 0, :run)
      Training.skip_missed_sessions(scope, [period(@day, @day)], ~D[2026-11-05])
      run = activity(scope, 1, ~U[2026-11-03 06:00:00Z], :run)

      Training.match_activities(scope, @day)

      assert matches([session]) == [{run.id, :done}]
    end

    test "a session's status stays settable by hand", %{scope: scope} do
      session = session(scope, 0, :run)
      Training.skip_missed_sessions(scope, [period(@day, @day)], ~D[2026-11-05])

      assert {:ok, %Session{status: :done}} =
               Training.update_session(scope, session.id, %{status: :done}, "Ran without a watch")
    end
  end
end
