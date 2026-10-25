defmodule Vire.TrainingTest do
  use Vire.DataCase, async: true

  alias Vire.Training
  alias Vire.Training.Block
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.DayContext
  alias Vire.Training.Phase
  alias Vire.Training.Season
  alias Vire.Training.Session

  setup do
    scope = scope_fixture()
    Map.merge(plan_fixture(scope), %{scope: scope, other: scope_fixture()})
  end

  describe "list_seasons/1" do
    test "lists the scope's seasons, earliest first", %{
      scope: scope,
      season: season,
      other: other
    } do
      later = season_fixture(scope, period: period(~D[2027-04-01], ~D[2027-09-30]))
      season_fixture(other)

      assert Enum.map(Training.list_seasons(scope), & &1.id) == [season.id, later.id]
      assert [%Season{name: "Winter base"}] = Training.list_seasons(other)
    end
  end

  describe "get_plan/2 by season id" do
    test "returns the season with everything beneath it in order, with rationales", plan do
      %{scope: scope, season: season} = plan

      later =
        phase_fixture(scope, season,
          name: "Build",
          period: period(~D[2027-02-01], ~D[2027-03-28])
        )

      second = session_fixture(scope, position: 1, discipline: :run, rationale: "Easy run")
      first = session_fixture(scope)

      tree = Training.get_plan(scope, season.id)

      assert tree.rationale == "Aerobic base before the spring races"
      assert [%Phase{rationale: "Volume first"} = phase, %Phase{id: later_id}] = tree.phases
      assert later_id == later.id
      assert [%Block{rationale: "Long easy rides"} = block] = phase.blocks
      assert [%Cycle{rationale: "First load week"} = cycle] = block.cycles

      assert Enum.map(cycle.days, & &1.day) ==
               Enum.to_list(Date.range(~D[2026-11-02], ~D[2026-11-08]))

      day = Enum.find(cycle.days, &(&1.day == ~D[2026-11-03]))

      assert Enum.map(day.sessions, &{&1.id, &1.rationale}) == [
               {first.id, "Endurance ride"},
               {second.id, "Easy run"}
             ]
    end

    test "returns nil for another user's season, an unknown id or a malformed one", plan do
      assert Training.get_plan(plan.other, plan.season.id) == nil
      assert Training.get_plan(plan.scope, Ecto.UUID.generate()) == nil
      assert Training.get_plan(plan.scope, "not-a-uuid") == nil
    end
  end

  describe "get_plan/2 by period" do
    test "returns the seasons overlapping the period with only what overlaps it beneath", plan do
      %{scope: scope, block: block} = plan
      cycle_fixture(scope, block, period: period(~D[2026-11-09], ~D[2026-11-15]))
      season_fixture(scope, name: "Summer", period: period(~D[2027-05-01], ~D[2027-09-30]))
      plan_fixture(plan.other)

      assert [season] = Training.get_plan(scope, period(~D[2026-11-07], ~D[2026-11-10]))
      assert season.id == plan.season.id
      assert [%{blocks: [%{cycles: [first, second]}]}] = season.phases
      assert Enum.map(first.days, & &1.day) == [~D[2026-11-07], ~D[2026-11-08]]
      assert Enum.map(second.days, & &1.day) == [~D[2026-11-09], ~D[2026-11-10]]

      assert [%{name: "Summer", phases: []}] =
               Training.get_plan(scope, period(~D[2027-06-01], ~D[2027-06-30]))

      assert Training.get_plan(scope, period(~D[2027-04-01], ~D[2027-04-30])) == []
    end
  end

  describe "get_day/2" do
    test "returns the day with its chain and its sessions in position order", plan do
      %{scope: scope} = plan
      late = session_fixture(scope, position: 2, discipline: :swim)
      early = session_fixture(scope, position: 0)

      day = Training.get_day(scope, ~D[2026-11-03])

      assert %Day{day: ~D[2026-11-03], kind: :training} = day

      assert %DayContext{
               day_kind: :training,
               cycle_kind: :load,
               block_focus: "Aerobic endurance",
               phase_name: "Base",
               season_name: "Winter base"
             } = day.context

      assert {day.context.cycle_id, day.context.block_id, day.context.phase_id,
              day.context.season_id} ==
               {plan.cycle.id, plan.block.id, plan.phase.id, plan.season.id}

      assert Enum.map(day.sessions, &{&1.id, &1.date}) == [
               {early.id, ~D[2026-11-03]},
               {late.id, ~D[2026-11-03]}
             ]
    end

    test "returns nil for a date without a day or with another user's day", plan do
      assert Training.get_day(plan.scope, ~D[2026-11-09]) == nil
      assert Training.get_day(plan.other, ~D[2026-11-03]) == nil
    end
  end

  describe "create_season/2" do
    test "stores the season for the scope's user", %{other: other} do
      {:ok, season} =
        Training.create_season(other, %{
          name: "Spring",
          period: %{"first" => "2027-04-01", "last" => "2027-06-30"},
          rationale: "Race block"
        })

      assert Repo.get!(Season, season.id).user_id == other.user.id
      assert season.period == period(~D[2027-04-01], ~D[2027-06-30])
    end

    test "requires a name, a period and a rationale", %{scope: scope} do
      {:error, changeset} = Training.create_season(scope, %{rationale: "  "})

      assert %{
               name: ["can't be blank"],
               period: ["can't be blank"],
               rationale: ["can't be blank"]
             } =
               errors_on(changeset)
    end

    test "refuses to overlap another of the user's seasons", %{scope: scope, other: other} do
      attrs = %{name: "Overlap", period: period(~D[2027-03-28], ~D[2027-05-01]), rationale: "Why"}

      {:error, changeset} = Training.create_season(scope, attrs)

      assert %{period: ["overlaps another season"]} = errors_on(changeset)
      assert {:ok, _season} = Training.create_season(other, attrs)
    end
  end

  describe "update_season/4" do
    test "changes the name, the period and the row's rationale", %{scope: scope, season: season} do
      {:ok, updated} =
        Training.update_season(
          scope,
          season.id,
          %{
            name: "Long winter",
            period: period(~D[2026-11-01], ~D[2027-04-30]),
            rationale: "Base through April"
          },
          "The spring race moved"
        )

      assert %Season{name: "Long winter", rationale: "Base through April"} =
               Repo.get!(Season, updated.id)

      assert updated.period == period(~D[2026-11-01], ~D[2027-04-30])
    end

    test "refuses to shrink past a phase or overlap a sibling", %{scope: scope, season: season} do
      season_fixture(scope, name: "Summer", period: period(~D[2027-05-01], ~D[2027-09-30]))

      {:error, shrunk} =
        Training.update_season(
          scope,
          season.id,
          %{period: period(~D[2026-11-10], ~D[2027-03-28])},
          "Later start"
        )

      {:error, overlapping} =
        Training.update_season(
          scope,
          season.id,
          %{period: period(~D[2026-11-02], ~D[2027-05-10])},
          "Longer"
        )

      assert %{period: ["no longer contains all of its phases"]} = errors_on(shrunk)
      assert %{period: ["overlaps another season"]} = errors_on(overlapping)
      assert Repo.get!(Season, season.id).period == season.period
    end
  end

  describe "create_phase/3" do
    test "stores a phase inside its season", %{scope: scope, season: season} do
      {:ok, phase} =
        Training.create_phase(scope, season.id, %{
          name: "Build",
          period: period(~D[2027-02-01], ~D[2027-03-28]),
          rationale: "Intensity"
        })

      assert %Phase{season_id: season_id, user_id: user_id} = Repo.get!(Phase, phase.id)
      assert {season_id, user_id} == {season.id, scope.user.id}
    end

    test "refuses a period outside the season or over a sibling", %{scope: scope, season: season} do
      {:error, outside} =
        Training.create_phase(scope, season.id, %{
          name: "Late",
          period: period(~D[2027-03-01], ~D[2027-04-10]),
          rationale: "Why"
        })

      {:error, overlapping} =
        Training.create_phase(scope, season.id, %{
          name: "Twin",
          period: period(~D[2027-01-31], ~D[2027-02-14]),
          rationale: "Why"
        })

      {:error, missing} = Training.create_phase(scope, season.id, %{})

      assert %{period: ["lies outside its season"]} = errors_on(outside)
      assert %{period: ["overlaps another phase of the season"]} = errors_on(overlapping)

      assert %{
               name: ["can't be blank"],
               period: ["can't be blank"],
               rationale: ["can't be blank"]
             } =
               errors_on(missing)
    end
  end

  describe "update_phase/4" do
    test "moves the phase within its season", %{scope: scope, phase: phase} do
      {:ok, updated} =
        Training.update_phase(
          scope,
          phase.id,
          %{name: "Early base", period: period(~D[2026-11-02], ~D[2027-02-14])},
          "Two more weeks of base"
        )

      assert %Phase{name: "Early base"} = Repo.get!(Phase, updated.id)
      assert updated.period.last == ~D[2027-02-14]
    end

    test "refuses to leave the season or shrink past a block", %{scope: scope, phase: phase} do
      {:error, outside} =
        Training.update_phase(
          scope,
          phase.id,
          %{period: period(~D[2026-10-01], ~D[2027-01-31])},
          "Why"
        )

      {:error, shrunk} =
        Training.update_phase(
          scope,
          phase.id,
          %{period: period(~D[2026-11-02], ~D[2026-11-20])},
          "Why"
        )

      assert %{period: ["lies outside its season"]} = errors_on(outside)
      assert %{period: ["no longer contains all of its blocks"]} = errors_on(shrunk)
    end
  end

  describe "create_block/3 and update_block/4" do
    test "store a block inside its phase", %{scope: scope, phase: phase} do
      {:ok, block} =
        Training.create_block(scope, phase.id, %{
          focus: "Threshold",
          period: period(~D[2026-11-30], ~D[2026-12-27]),
          rationale: "Raise FTP"
        })

      {:ok, updated} = Training.update_block(scope, block.id, %{focus: "Sweet spot"}, "Gentler")

      assert %Block{phase_id: phase_id, focus: "Sweet spot"} = Repo.get!(Block, updated.id)
      assert phase_id == phase.id
    end

    test "refuse a period outside the phase, over a sibling or past a cycle", plan do
      %{scope: scope, phase: phase, block: block} = plan
      attrs = %{focus: "Late", rationale: "Why"}

      {:error, outside} =
        Training.create_block(
          scope,
          phase.id,
          Map.put(attrs, :period, period(~D[2027-01-25], ~D[2027-02-07]))
        )

      {:error, overlapping} =
        Training.create_block(
          scope,
          phase.id,
          Map.put(attrs, :period, period(~D[2026-11-29], ~D[2026-12-06]))
        )

      {:error, shrunk} =
        Training.update_block(
          scope,
          block.id,
          %{period: period(~D[2026-11-05], ~D[2026-11-29])},
          "Why"
        )

      assert %{period: ["lies outside its phase"]} = errors_on(outside)
      assert %{period: ["overlaps another block of the phase"]} = errors_on(overlapping)
      assert %{period: ["no longer contains all of its cycles"]} = errors_on(shrunk)
    end
  end

  describe "create_cycle/3 and update_cycle/4" do
    test "store a cycle inside its block", %{scope: scope, block: block} do
      {:ok, cycle} =
        Training.create_cycle(scope, block.id, %{
          kind: :recovery,
          period: period(~D[2026-11-09], ~D[2026-11-12]),
          rationale: "Absorb the load"
        })

      {:ok, updated} = Training.update_cycle(scope, cycle.id, %{kind: :load}, "Felt fresh")

      assert %Cycle{block_id: block_id, kind: :load} = Repo.get!(Cycle, updated.id)
      assert block_id == block.id
    end

    test "refuse a period outside the block or over a sibling, and a bad kind", plan do
      %{scope: scope, block: block} = plan
      attrs = %{kind: :load, rationale: "Why"}

      {:error, outside} =
        Training.create_cycle(
          scope,
          block.id,
          Map.put(attrs, :period, period(~D[2026-11-23], ~D[2026-12-06]))
        )

      {:error, overlapping} =
        Training.create_cycle(
          scope,
          block.id,
          Map.put(attrs, :period, period(~D[2026-11-08], ~D[2026-11-15]))
        )

      {:error, kind} =
        Training.create_cycle(
          scope,
          block.id,
          %{attrs | kind: :taper} |> Map.put(:period, period(~D[2026-11-09], ~D[2026-11-15]))
        )

      assert %{period: ["lies outside its block"]} = errors_on(outside)
      assert %{period: ["overlaps another cycle of the block"]} = errors_on(overlapping)
      assert %{kind: ["is invalid"]} = errors_on(kind)
    end
  end

  describe "deleting a season, phase, block or cycle" do
    test "removes the row and everything beneath it", %{scope: scope} = plan do
      session_fixture(scope)

      assert {:ok, _cycle} = Training.delete_cycle(scope, plan.cycle.id, "Replanned")
      refute Repo.exists?(Day)
      refute Repo.exists?(Session)

      assert {:ok, _block} = Training.delete_block(scope, plan.block.id, "Replanned")
      assert {:ok, _phase} = Training.delete_phase(scope, plan.phase.id, "Replanned")
      assert {:ok, _season} = Training.delete_season(scope, plan.season.id, "Replanned")

      for schema <- [Season, Phase, Block, Cycle], do: refute(Repo.exists?(schema))
    end

    test "cascades from the season down to the sessions", %{scope: scope, season: season} do
      session_fixture(scope)

      assert {:ok, _season} = Training.delete_season(scope, season.id, "Season cancelled")

      for schema <- [Season, Phase, Block, Cycle, Day, Session], do: refute(Repo.exists?(schema))
    end
  end

  describe "update_day/4" do
    test "changes the day's kind and note", %{scope: scope} do
      {:ok, day} =
        Training.update_day(scope, ~D[2026-11-04], %{kind: :training, note: "Travel"}, "Trip")

      assert %Day{kind: :training, note: "Travel"} = Repo.get!(Day, day.id)
    end

    test "refuses a missing kind and returns not found without a day", %{scope: scope} do
      {:error, changeset} = Training.update_day(scope, ~D[2026-11-04], %{kind: nil}, "Why")

      assert %{kind: ["can't be blank"]} = errors_on(changeset)

      assert Training.update_day(scope, ~D[2026-11-09], %{note: "x"}, "Why") ==
               {:error, :not_found}
    end
  end

  describe "create_session/2" do
    test "stores the session as planned and makes the day a training day", %{scope: scope} do
      session = session_fixture(scope)

      assert %Session{
               status: :planned,
               position: 0,
               discipline: :bike,
               planned_seconds: 5400,
               structure: %{"steps" => [%{"minutes" => 90, "zone" => 2}]},
               rationale: "Endurance ride"
             } = Repo.get!(Session, session.id)

      assert session.date == ~D[2026-11-03]
      assert Repo.get_by!(Day, day: ~D[2026-11-03]).kind == :training
      assert Repo.get_by!(Day, day: ~D[2026-11-04]).kind == :rest
    end

    test "refuses a date without a day, a taken or negative position and a missing rationale",
         %{scope: scope} do
      session_fixture(scope)
      attrs = %{date: ~D[2026-11-03], position: 1, discipline: :run, rationale: "Why"}

      {:error, no_day} = Training.create_session(scope, %{attrs | date: ~D[2026-11-09]})
      {:error, taken} = Training.create_session(scope, %{attrs | position: 0})
      {:error, negative} = Training.create_session(scope, %{attrs | position: -1})
      {:error, blank} = Training.create_session(scope, %{attrs | rationale: ""})
      {:error, missing} = Training.create_session(scope, %{})

      assert %{date: ["is not a day in the plan"]} = errors_on(no_day)
      assert %{position: ["is taken by another session that day"]} = errors_on(taken)
      assert %{position: ["must be greater than or equal to 0"]} = errors_on(negative)
      assert %{rationale: ["can't be blank"]} = errors_on(blank)

      assert %{
               date: ["can't be blank"],
               position: ["can't be blank"],
               discipline: ["can't be blank"],
               rationale: ["can't be blank"]
             } = errors_on(missing)

      assert Repo.get_by!(Day, day: ~D[2026-11-03])
             |> Repo.preload(:sessions)
             |> Map.get(:sessions)
             |> length() == 1
    end
  end

  describe "update_session/4" do
    setup %{scope: scope} do
      %{session: session_fixture(scope)}
    end

    test "changes the planned parts and sets the status by hand", %{
      scope: scope,
      session: session
    } do
      {:ok, updated} =
        Training.update_session(
          scope,
          session.id,
          %{planned_seconds: 3600, structure: %{"steps" => []}, status: :done},
          "Shortened"
        )

      assert %Session{planned_seconds: 3600, structure: %{"steps" => []}, status: :done} =
               Repo.get!(Session, updated.id)

      {:ok, skipped} = Training.update_session(scope, session.id, %{status: :skipped}, "Ill")
      assert skipped.status == :skipped

      {:error, changeset} = Training.update_session(scope, session.id, %{status: :matched}, "Why")
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "moves the session to another date's day and position", %{scope: scope, session: session} do
      {:ok, moved} =
        Training.update_session(scope, session.id, %{date: ~D[2026-11-05], position: 3}, "Rain")

      target = Repo.get_by!(Day, day: ~D[2026-11-05])
      assert %Session{position: 3, day_id: day_id} = Repo.get!(Session, moved.id)
      assert day_id == target.id
      assert target.kind == :training
      assert moved.date == ~D[2026-11-05]
    end

    test "refuses a move to a taken position or a date without a day", %{
      scope: scope,
      session: session
    } do
      session_fixture(scope, date: ~D[2026-11-05], position: 0)

      {:error, taken} = Training.update_session(scope, session.id, %{date: ~D[2026-11-05]}, "Why")
      {:error, no_day} = Training.update_session(scope, session.id, %{date: "2026-12-25"}, "Why")

      assert %{position: ["is taken by another session that day"]} = errors_on(taken)
      assert %{date: ["is not a day in the plan"]} = errors_on(no_day)
      assert Repo.get!(Session, session.id).day_id == session.day_id
    end
  end

  describe "delete_session/3" do
    test "removes the session", %{scope: scope} do
      session = session_fixture(scope)

      assert {:ok, _session} = Training.delete_session(scope, session.id, "Not needed")
      refute Repo.get(Session, session.id)
    end
  end

  describe "a write's rationale" do
    test "is required to update or delete at every level", plan do
      %{scope: scope} = plan
      session = session_fixture(scope)

      writes = [
        fn r -> Training.update_season(scope, plan.season.id, %{name: "x"}, r) end,
        fn r -> Training.update_phase(scope, plan.phase.id, %{name: "x"}, r) end,
        fn r -> Training.update_block(scope, plan.block.id, %{focus: "x"}, r) end,
        fn r -> Training.update_cycle(scope, plan.cycle.id, %{kind: :recovery}, r) end,
        fn r -> Training.update_day(scope, ~D[2026-11-03], %{note: "x"}, r) end,
        fn r -> Training.update_session(scope, session.id, %{position: 4}, r) end,
        fn r -> Training.delete_session(scope, session.id, r) end,
        fn r -> Training.delete_cycle(scope, plan.cycle.id, r) end,
        fn r -> Training.delete_block(scope, plan.block.id, r) end,
        fn r -> Training.delete_phase(scope, plan.phase.id, r) end,
        fn r -> Training.delete_season(scope, plan.season.id, r) end
      ]

      for write <- writes, rationale <- [nil, " "] do
        assert {:error, changeset} = write.(rationale)
        assert %{rationale: ["can't be blank"]} = errors_on(changeset)
      end

      assert Training.get_plan(scope, plan.season.id).name == "Winter base"
      assert Repo.get!(Session, session.id).position == 0
    end
  end

  describe "another user's plan" do
    setup %{scope: scope} do
      %{session: session_fixture(scope)}
    end

    test "cannot be written through a scope at any level",
         %{other: other, session: session} = plan do
      writes = [
        fn -> Training.create_phase(other, plan.season.id, %{}) end,
        fn -> Training.create_block(other, plan.phase.id, %{}) end,
        fn -> Training.create_cycle(other, plan.block.id, %{}) end,
        fn -> Training.update_season(other, plan.season.id, %{name: "Mine"}, "Why") end,
        fn -> Training.update_phase(other, plan.phase.id, %{name: "Mine"}, "Why") end,
        fn -> Training.update_block(other, plan.block.id, %{focus: "Mine"}, "Why") end,
        fn -> Training.update_cycle(other, plan.cycle.id, %{kind: :recovery}, "Why") end,
        fn -> Training.update_day(other, ~D[2026-11-03], %{note: "Mine"}, "Why") end,
        fn -> Training.update_session(other, session.id, %{position: 5}, "Why") end,
        fn -> Training.delete_session(other, session.id, "Why") end,
        fn -> Training.delete_cycle(other, plan.cycle.id, "Why") end,
        fn -> Training.delete_block(other, plan.block.id, "Why") end,
        fn -> Training.delete_phase(other, plan.phase.id, "Why") end,
        fn -> Training.delete_season(other, plan.season.id, "Why") end,
        fn -> Training.delete_season(other, "not-a-uuid", "Why") end
      ]

      for write <- writes, do: assert(write.() == {:error, :not_found})

      {:error, changeset} =
        Training.create_session(other, %{
          date: ~D[2026-11-03],
          position: 1,
          discipline: :run,
          rationale: "Why"
        })

      assert %{date: ["is not a day in the plan"]} = errors_on(changeset)

      tree = Training.get_plan(plan.scope, plan.season.id)
      assert tree.name == "Winter base"

      assert [%{name: "Base", blocks: [%{focus: "Aerobic endurance", cycles: [cycle]}]}] =
               tree.phases

      assert cycle.kind == :load
      assert Repo.get!(Session, session.id).position == 0
      assert Repo.get_by!(Day, day: ~D[2026-11-03]).note == nil
    end

    test "is not visible through a scope", %{other: other} = plan do
      assert Training.list_seasons(other) == []
      assert Training.get_plan(other, plan.season.id) == nil
      assert Training.get_plan(other, period(~D[2026-11-01], ~D[2026-11-30])) == []
      assert Training.get_day(other, ~D[2026-11-03]) == nil
    end
  end
end
