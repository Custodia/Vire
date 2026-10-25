defmodule Vire.Training.ConstraintsTest do
  use Vire.DataCase, async: true

  alias Vire.Accounts.User
  alias Vire.Training.Block
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.Phase
  alias Vire.Training.Season
  alias Vire.Training.Session

  setup do
    scope = scope_fixture()
    Map.put(plan_fixture(scope), :scope, scope)
  end

  defp violation(sql, params) do
    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn -> Repo.query!(sql, params) end)
      end

    {error.postgres.code, error.postgres.constraint}
  end

  defp uuid(id), do: Ecto.UUID.dump!(id)

  test "every level's period must have a first and a last day", %{scope: scope} do
    assert violation(
             "insert into training_seasons (user_id, name, period, rationale)
              values ($1, 'Open', '[2028-01-01,)', 'Why')",
             [uuid(scope.user.id)]
           ) == {:check_violation, "training_seasons_period_bounded"}

    assert violation(
             "insert into training_seasons (user_id, name, period, rationale)
              values ($1, 'Empty', 'empty', 'Why')",
             [uuid(scope.user.id)]
           ) == {:check_violation, "training_seasons_period_bounded"}
  end

  test "siblings may not overlap on any level", %{season: season, phase: phase, block: block} do
    other_user = user_fixture()

    assert violation(
             "insert into training_seasons (user_id, name, period, rationale)
              values ($1, 'Second', '[2027-03-28,2027-05-01)', 'Why')",
             [uuid(season.user_id)]
           ) == {:exclusion_violation, "training_seasons_period_overlap"}

    Repo.query!(
      "insert into training_seasons (user_id, name, period, rationale)
       values ($1, 'Same dates, other user', '[2026-11-02,2027-03-29)', 'Why')",
      [uuid(other_user.id)]
    )

    assert violation(
             "insert into training_phases (user_id, season_id, name, period, rationale)
              values ($1, $2, 'Second', '[2027-01-31,2027-02-10)', 'Why')",
             [uuid(season.user_id), uuid(season.id)]
           ) == {:exclusion_violation, "training_phases_period_overlap"}

    assert violation(
             "insert into training_blocks (user_id, phase_id, focus, period, rationale)
              values ($1, $2, 'Second', '[2026-11-29,2026-12-10)', 'Why')",
             [uuid(phase.user_id), uuid(phase.id)]
           ) == {:exclusion_violation, "training_blocks_period_overlap"}

    assert violation(
             "insert into training_cycles (user_id, block_id, kind, period, rationale)
              values ($1, $2, 'load', '[2026-11-08,2026-11-15)', 'Why')",
             [uuid(block.user_id), uuid(block.id)]
           ) == {:exclusion_violation, "training_cycles_period_overlap"}
  end

  test "a child's period lies inside its parent's", %{season: season, phase: phase} = plan do
    assert violation(
             "insert into training_phases (user_id, season_id, name, period, rationale)
              values ($1, $2, 'Late', '[2027-03-01,2027-04-10)', 'Why')",
             [uuid(season.user_id), uuid(season.id)]
           ) == {:check_violation, "training_phases_period_within_parent"}

    assert violation(
             "insert into training_blocks (user_id, phase_id, focus, period, rationale)
              values ($1, $2, 'Late', '[2027-01-20,2027-02-10)', 'Why')",
             [uuid(phase.user_id), uuid(phase.id)]
           ) == {:check_violation, "training_blocks_period_within_parent"}

    assert violation(
             "insert into training_cycles (user_id, block_id, kind, period, rationale)
              values ($1, $2, 'load', '[2026-11-23,2026-12-07)', 'Why')",
             [uuid(plan.block.user_id), uuid(plan.block.id)]
           ) == {:check_violation, "training_cycles_period_within_parent"}

    assert violation(
             "insert into training_days (user_id, cycle_id, day, kind)
              values ($1, $2, '2026-11-09', 'rest')",
             [uuid(plan.cycle.user_id), uuid(plan.cycle.id)]
           ) == {:check_violation, "training_days_day_within_cycle"}

    assert violation(
             "update training_phases set period = '[2026-10-01,2027-01-31)' where id = $1",
             [uuid(phase.id)]
           ) == {:check_violation, "training_phases_period_within_parent"}

    assert violation(
             "update training_days set day = '2026-11-09' where cycle_id = $1 and day = '2026-11-08'",
             [uuid(plan.cycle.id)]
           ) == {:check_violation, "training_days_day_within_cycle"}
  end

  test "a parent may not shrink past its children", plan do
    for {table, id, range} <- [
          {"training_seasons", plan.season.id, "[2026-11-03,2027-03-29)"},
          {"training_phases", plan.phase.id, "[2026-11-02,2026-11-20)"},
          {"training_blocks", plan.block.id, "[2026-11-03,2026-11-30)"},
          {"training_cycles", plan.cycle.id, "[2026-11-02,2026-11-08)"}
        ] do
      assert violation("update #{table} set period = '#{range}' where id = $1", [uuid(id)]) ==
               {:check_violation, "#{table}_period_contains_children"}
    end
  end

  test "a child cannot point at another user's parent", plan do
    other = user_fixture()

    {:error, phase} =
      %Phase{user_id: other.id, season_id: plan.season.id}
      |> Phase.changeset(%{
        name: "Stray",
        period: period(~D[2027-02-01], ~D[2027-02-28]),
        rationale: "Why"
      })
      |> Repo.insert()

    {:error, block} =
      %Block{user_id: other.id, phase_id: plan.phase.id}
      |> Block.changeset(%{
        focus: "Stray",
        period: period(~D[2026-11-30], ~D[2026-12-13]),
        rationale: "Why"
      })
      |> Repo.insert()

    {:error, cycle} =
      %Cycle{user_id: other.id, block_id: plan.block.id}
      |> Cycle.changeset(%{
        kind: :load,
        period: period(~D[2026-11-09], ~D[2026-11-15]),
        rationale: "Why"
      })
      |> Repo.insert()

    {:error, session} =
      %Session{user_id: other.id, day_id: Repo.get_by!(Day, day: ~D[2026-11-02]).id}
      |> Session.changeset(%{
        date: ~D[2026-11-02],
        position: 0,
        discipline: :run,
        rationale: "Why"
      })
      |> Repo.insert()

    assert %{season_id: ["does not exist"]} = errors_on(phase)
    assert %{phase_id: ["does not exist"]} = errors_on(block)
    assert %{block_id: ["does not exist"]} = errors_on(cycle)
    assert %{day_id: ["does not exist"]} = errors_on(session)

    assert violation(
             "insert into training_days (user_id, cycle_id, day, kind)
              values ($1, $2, '2026-11-02', 'rest')",
             [uuid(other.id), uuid(plan.cycle.id)]
           ) == {:foreign_key_violation, "training_days_cycle_id_fkey"}
  end

  test "a user has one day per date", %{cycle: cycle} do
    assert violation(
             "insert into training_days (user_id, cycle_id, day, kind)
              values ($1, $2, '2026-11-02', 'rest')",
             [uuid(cycle.user_id), uuid(cycle.id)]
           ) == {:unique_violation, "training_days_user_id_day_index"}
  end

  describe "a session" do
    setup %{scope: scope} do
      %{session: session_fixture(scope)}
    end

    test "is done while it is matched to an activity", %{session: session} do
      {:error, changeset} =
        session
        |> Session.changeset(%{})
        |> Ecto.Changeset.put_change(:activity_id, Ecto.UUID.generate())
        |> Repo.update()

      assert %{status: ["must be done while an activity is matched"]} = errors_on(changeset)

      Repo.query!(
        "update training_sessions set status = 'done', activity_id = $1 where id = $2",
        [
          uuid(Ecto.UUID.generate()),
          uuid(session.id)
        ]
      )
    end

    test "is matched to an activity at most once", %{scope: scope, session: session} do
      activity_id = uuid(Ecto.UUID.generate())
      other = session_fixture(scope, position: 1)
      sql = "update training_sessions set status = 'done', activity_id = $1 where id = $2"

      Repo.query!(sql, [activity_id, uuid(session.id)])

      assert violation(sql, [activity_id, uuid(other.id)]) ==
               {:unique_violation, "training_sessions_activity_id_index"}
    end

    test "carries a review with its time, and a score from 1 to 5 only with a review",
         %{session: session} do
      sql = "update training_sessions set review = $1, review_score = $2, reviewed_at = $3
             where id = $4"

      now = DateTime.utc_now()

      Repo.query!(sql, ["Strong", 5, now, uuid(session.id)])

      assert violation(sql, ["Strong", 6, now, uuid(session.id)]) ==
               {:check_violation, "training_sessions_review_score_range"}

      assert violation(sql, ["Strong", nil, nil, uuid(session.id)]) ==
               {:check_violation, "training_sessions_review_written"}

      assert violation(sql, [nil, 3, nil, uuid(session.id)]) ==
               {:check_violation, "training_sessions_score_with_review"}
    end
  end

  test "deleting a season or the user removes everything beneath", %{scope: scope} = plan do
    session_fixture(scope)
    Repo.delete!(plan.season)

    for schema <- [Phase, Block, Cycle, Day, Session], do: refute(Repo.exists?(schema))

    other = scope_fixture()
    plan_fixture(other)
    session_fixture(other)
    Repo.delete!(other.user)

    for schema <- [Season, Phase, Block, Cycle, Day, Session], do: refute(Repo.exists?(schema))
    refute Repo.get(User, other.user.id)
  end
end
