defmodule Vire.ActivitiesTest do
  use Vire.DataCase, async: true

  alias Vire.Activities

  setup do
    scope = scope_fixture()

    %{
      scope: scope,
      ride: activity_fixture(scope, "ride.fit"),
      run: activity_fixture(scope, "run.fit"),
      swim: activity_fixture(scope, "swim.fit")
    }
  end

  describe "list_activities/3" do
    test "lists the activities with a local date in the range, newest first", ctx do
      ids =
        ctx.scope
        |> Activities.list_activities(Date.range(~D[2026-01-01], ~D[2026-12-31]))
        |> Enum.map(& &1.id)

      assert ids == [ctx.run.id, ctx.ride.id, ctx.swim.id]
    end

    test "places an activity by its local date", %{scope: scope, ride: ride} do
      assert [%{id: id}] =
               Activities.list_activities(scope, Date.range(~D[2026-07-14], ~D[2026-07-14]))

      assert id == ride.id
      assert [] = Activities.list_activities(scope, Date.range(~D[2026-07-15], ~D[2026-07-15]))
    end

    test "narrows the list to one discipline", %{scope: scope, swim: swim} do
      year = Date.range(~D[2026-01-01], ~D[2026-12-31])

      assert [%{id: id}] = Activities.list_activities(scope, year, discipline: :swim)
      assert id == swim.id
      assert [] = Activities.list_activities(scope, year, discipline: :strength)
    end

    test "lists none of another user's activities" do
      year = Date.range(~D[2026-01-01], ~D[2026-12-31])

      assert [] = Activities.list_activities(scope_fixture(), year)
    end
  end

  describe "get_activity/2" do
    test "reads the activity with its laps and lengths in order", %{scope: scope, swim: swim} do
      activity = Activities.get_activity(scope, swim.id)

      assert Enum.map(activity.laps, & &1.lap_index) == [0, 1, 2, 3, 4]
      assert Enum.map(activity.lengths, & &1.length_index) == Enum.to_list(0..13)
    end

    test "reads another user's activity or an unknown id as nil", %{ride: ride} do
      assert Activities.get_activity(scope_fixture(), ride.id) == nil
      assert Activities.get_activity(scope_fixture(), "not-a-uuid") == nil
    end
  end

  describe "get_activity_by_source_file/2" do
    test "reads the activity parsed from a file in the scope", %{scope: scope, run: run} do
      assert Activities.get_activity_by_source_file(scope, run.source_file_id).id == run.id
      assert Activities.get_activity_by_source_file(scope_fixture(), run.source_file_id) == nil
      assert Activities.get_activity_by_source_file(scope, "not-a-uuid") == nil
    end
  end

  describe "get_activity_streams/4" do
    test "returns the chosen channels at one sample per second", %{scope: scope, ride: ride} do
      streams = Activities.get_activity_streams(scope, ride.id, ["power", "missing"], 1)

      assert [{"power", %{unit: "watts", samples: samples}}] = Map.to_list(streams)
      assert length(samples) == 600
    end

    test "averages the recorded samples of each window", %{scope: scope, ride: ride} do
      %{"power" => %{samples: second_by_second}} =
        Activities.get_activity_streams(scope, ride.id, ["power"], 1)

      %{"power" => %{samples: minutes}} =
        Activities.get_activity_streams(scope, ride.id, ["power"], 60)

      assert length(minutes) == 10
      assert Enum.at(minutes, 6) == nil

      first_minute = Enum.take(second_by_second, 60)
      assert_in_delta hd(minutes), Enum.sum(first_minute) / 60, 1.0e-9
    end

    test "averages over the recorded samples where a window is partly empty", %{
      scope: scope,
      ride: ride
    } do
      %{"heart_rate" => %{samples: second_by_second}} =
        Activities.get_activity_streams(scope, ride.id, ["heart_rate"], 1)

      %{"heart_rate" => %{samples: windows}} =
        Activities.get_activity_streams(scope, ride.id, ["heart_rate"], 420)

      recorded = second_by_second |> Enum.take(420) |> Enum.reject(&is_nil/1)

      assert length(recorded) == 360
      assert [first, _rest] = windows
      assert_in_delta first, Enum.sum(recorded) / 360, 1.0e-9
    end

    test "takes the first recorded position of each window", %{scope: scope, run: run} do
      %{"position_lat" => %{samples: second_by_second}, "heart_rate" => %{samples: heart_rate}} =
        Activities.get_activity_streams(scope, run.id, :all, 1)

      %{"position_lat" => %{unit: "degrees", samples: windows}} =
        Activities.get_activity_streams(scope, run.id, ["position_lat"], 100)

      assert windows == Enum.take_every(second_by_second, 100)
      assert length(heart_rate) == 600
    end

    test "reads another user's activity as nil", %{ride: ride} do
      assert Activities.get_activity_streams(scope_fixture(), ride.id, :all, 1) == nil
    end
  end
end
