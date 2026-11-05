defmodule Vire.Training.PlanChangesTest do
  use Vire.DataCase, async: true

  alias Vire.Accounts.Scope
  alias Vire.Mcp
  alias Vire.Training
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.PlanChange
  alias Vire.Training.Season

  setup do
    scope = scope_fixture()
    plan = plan_fixture(scope)
    Map.merge(plan, %{scope: scope, session: session_fixture(scope)})
  end

  defp changes_since(count) do
    PlanChange
    |> Repo.all()
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.drop(count)
  end

  defp count, do: Repo.aggregate(PlanChange, :count)

  test "every write records one change of the row it acted on", %{scope: scope} = plan do
    later = period(~D[2027-02-01], ~D[2027-03-28])

    writes = [
      {:training_season, :insert,
       fn ->
         Training.create_season(scope, %{
           name: "Summer",
           period: period(~D[2027-05-01], ~D[2027-09-30]),
           rationale: "Racing"
         })
       end},
      {:training_phase, :insert,
       fn ->
         Training.create_phase(scope, plan.season.id, %{
           name: "Build",
           period: later,
           rationale: "Intensity"
         })
       end},
      {:training_block, :insert,
       fn ->
         Training.create_block(scope, plan.phase.id, %{
           focus: "Threshold",
           period: period(~D[2026-11-30], ~D[2026-12-27]),
           rationale: "FTP"
         })
       end},
      {:training_cycle, :insert,
       fn ->
         Training.create_cycle(scope, plan.block.id, %{kind: :load, rationale: "Week two"})
       end},
      {:training_session, :insert,
       fn ->
         Training.create_session(scope, %{
           date: ~D[2026-11-05],
           position: 0,
           discipline: :swim,
           rationale: "Technique"
         })
       end},
      {:training_season, :update,
       fn -> Training.update_season(scope, plan.season.id, %{name: "Base"}, "Rename") end},
      {:training_phase, :update,
       fn -> Training.update_phase(scope, plan.phase.id, %{name: "Early"}, "Rename") end},
      {:training_block, :update,
       fn -> Training.update_block(scope, plan.block.id, %{focus: "Endurance"}, "Rename") end},
      {:training_cycle, :update,
       fn -> Training.update_cycle(scope, plan.cycle.id, %{kind: :recovery}, "Tired") end},
      {:training_day, :update,
       fn -> Training.update_day(scope, ~D[2026-11-04], %{note: "Travel"}, "Trip") end},
      {:training_session, :update,
       fn -> Training.update_session(scope, plan.session.id, %{position: 2}, "Later") end},
      {:training_session, :delete,
       fn -> Training.delete_session(scope, plan.session.id, "Dropped") end},
      {:training_cycle, :delete, fn -> Training.delete_cycle(scope, plan.cycle.id, "Replan") end},
      {:training_block, :delete, fn -> Training.delete_block(scope, plan.block.id, "Replan") end},
      {:training_phase, :delete, fn -> Training.delete_phase(scope, plan.phase.id, "Replan") end},
      {:training_season, :delete,
       fn -> Training.delete_season(scope, plan.season.id, "Replan") end}
    ]

    for {entity, action, write} <- writes do
      before = count()
      assert {:ok, row} = write.()

      assert [%PlanChange{entity: ^entity, action: ^action} = change] = changes_since(before)
      assert change.entity_id == row.id
      assert change.user_id == scope.user.id
      assert {change.channel, change.mcp_client_id} == {:dashboard, nil}
    end
  end

  test "an insert stores the new row and its own rationale", %{scope: scope} do
    {:ok, season} =
      Training.create_season(scope, %{
        name: "Summer",
        period: period(~D[2027-05-01], ~D[2027-09-30]),
        rationale: "Racing"
      })

    [change] = Training.list_changes(scope, entity: :training_season, entity_id: season.id)

    assert change.before == nil
    assert change.rationale == "Racing"

    assert %{
             "id" => id,
             "user_id" => user_id,
             "name" => "Summer",
             "period" => %{"first" => "2027-05-01", "last" => "2027-09-30"},
             "rationale" => "Racing"
           } = change.after

    assert {id, user_id} == {season.id, scope.user.id}
  end

  test "an update stores the row before and after and the reason for the change",
       %{scope: scope, session: session} do
    {:ok, _moved} =
      Training.update_session(
        scope,
        session.id,
        %{date: ~D[2026-11-06], position: 1, status: :skipped},
        "Rain"
      )

    [change, %PlanChange{action: :insert}] =
      Training.list_changes(scope, entity: :training_session, entity_id: session.id)

    target = Repo.get_by!(Day, day: ~D[2026-11-06])

    assert change.rationale == "Rain"

    assert %{"position" => 0, "status" => "planned", "rationale" => "Endurance ride"} =
             change.before

    assert %{"position" => 1, "status" => "skipped", "rationale" => "Endurance ride"} =
             change.after

    assert {change.before["day_id"], change.after["day_id"]} == {session.day_id, target.id}

    assert change.before["structure"] == %{
             "steps" => [%{"kind" => "work", "seconds" => 5400, "zone" => 2}]
           }
  end

  test "a delete stores the row before it went", %{scope: scope, cycle: cycle} do
    {:ok, _cycle} = Training.delete_cycle(scope, cycle.id, "Replan")

    [change, %PlanChange{action: :insert}] =
      Training.list_changes(scope, entity: :training_cycle, entity_id: cycle.id)

    assert change.after == nil
    assert change.rationale == "Replan"

    assert %{"kind" => "load", "period" => %{"first" => "2026-11-02", "last" => "2026-11-08"}} =
             change.before
  end

  test "deleting a season records one change for everything beneath it",
       %{scope: scope, season: season} do
    before = count()

    {:ok, _season} = Training.delete_season(scope, season.id, "Season cancelled")

    assert [%PlanChange{entity: :training_season, action: :delete}] = changes_since(before)
    refute Repo.exists?(Day)
  end

  test "creating or widening a cycle records only the cycle's change", %{scope: scope} = plan do
    before = count()

    {:ok, cycle} = Training.create_cycle(scope, plan.block.id, %{kind: :load, rationale: "Next"})

    {:ok, _cycle} =
      Training.update_cycle(
        scope,
        cycle.id,
        %{period: period(~D[2026-11-09], ~D[2026-11-20])},
        "Longer"
      )

    assert [
             %PlanChange{entity: :training_cycle, action: :insert},
             %PlanChange{entity: :training_cycle, action: :update}
           ] = changes_since(before)

    assert Repo.aggregate(Day, :count) == 19
  end

  test "a change made over MCP names the client", %{season: season, scope: scope} do
    {:ok, %{id: client_id}} =
      Mcp.register_client(%{name: "Coach", redirect_uris: ["https://coach.example/cb"]})

    mcp = %Scope{user: scope.user, channel: :mcp, mcp_client_id: client_id}

    {:ok, _season} = Training.update_season(mcp, season.id, %{name: "Coach's base"}, "Coach")

    [change, %PlanChange{action: :insert}] =
      Training.list_changes(scope, entity: :training_season, entity_id: season.id)

    assert {change.channel, change.mcp_client_id} == {:mcp, client_id}
  end

  test "the write and its change roll back together", %{scope: scope} = plan do
    before = count()
    unnamed = %Scope{user: scope.user, channel: :mcp}

    {:error, created} =
      Training.create_season(unnamed, %{
        name: "Summer",
        period: period(~D[2027-05-01], ~D[2027-09-30]),
        rationale: "Racing"
      })

    {:error, updated} = Training.update_season(unnamed, plan.season.id, %{name: "Lost"}, "Why")
    {:error, deleted} = Training.delete_cycle(unnamed, plan.cycle.id, "Why")

    {:error, _widened} =
      Training.update_cycle(
        unnamed,
        plan.cycle.id,
        %{period: period(~D[2026-11-02], ~D[2026-11-12])},
        "Why"
      )

    for changeset <- [created, updated, deleted] do
      assert %{mcp_client_id: ["must name the MCP client exactly when the channel is mcp"]} =
               errors_on(changeset)
    end

    assert count() == before
    assert [%Season{name: "Winter base"}] = Repo.all(Season)
    assert Repo.get!(Cycle, plan.cycle.id).period == plan.cycle.period
    assert Repo.aggregate(Day, :count) == 7
  end

  test "a refused write records nothing", %{scope: scope, season: season} do
    before = count()

    {:error, _changeset} =
      Training.update_season(
        scope,
        season.id,
        %{period: period(~D[2026-11-10], ~D[2027-03-28])},
        "Why"
      )

    assert count() == before
  end

  describe "list_changes/2" do
    test "lists the scope's changes newest first, by entity and id", %{scope: scope} = plan do
      {:ok, _} = Training.update_season(scope, plan.season.id, %{name: "One"}, "First rename")
      {:ok, _} = Training.update_season(scope, plan.season.id, %{name: "Two"}, "Second rename")

      assert ["Second rename", "First rename", "Aerobic base before the spring races"] =
               scope
               |> Training.list_changes(entity: :training_season, entity_id: plan.season.id)
               |> Enum.map(& &1.rationale)

      assert [%{entity: :training_phase}] = Training.list_changes(scope, entity: :training_phase)

      assert [%{rationale: "Second rename"} | _] = all = Training.list_changes(scope)
      assert length(all) == 7
    end

    test "returns nothing of another user's or for a malformed id", %{
      scope: scope,
      season: season
    } do
      other = scope_fixture()

      assert Training.list_changes(other) == []
      assert Training.list_changes(other, entity: :training_season, entity_id: season.id) == []
      assert Training.list_changes(scope, entity_id: "not-a-uuid") == []
    end
  end
end
