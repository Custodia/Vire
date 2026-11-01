defmodule VireWeb.ActivityControllerTest do
  use VireWeb.ConnCase, async: true

  import Vire.ActivitiesFixtures

  alias Vire.Accounts.Scope

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: sign_in(conn, user), scope: Scope.for_user(user)}
  end

  test "answers a run with its lap", %{conn: conn, scope: scope} do
    run = activity_fixture(scope, "run.fit")

    assert %{
             "id" => id,
             "discipline" => "run",
             "local_date" => "2026-07-16",
             "utc_offset_seconds" => 10_800,
             "duration_seconds" => 600,
             "laps" => [%{"lap_index" => 0, "elapsed_seconds" => 600, "avg_heart_rate" => hr}],
             "lengths" => []
           } = json_response(get(conn, ~p"/api/activities/#{run.id}"), 200)

    assert id == run.id
    assert is_integer(hr)
  end

  test "answers a ride's power and heart rate downsampled to the step",
       %{conn: conn, scope: scope} do
    ride = activity_fixture(scope, "ride.fit")

    assert %{"activity_id" => id, "step" => 60, "streams" => streams} =
             json_response(
               get(
                 conn,
                 ~p"/api/activities/#{ride.id}/streams?channels=power,heart_rate&step=60"
               ),
               200
             )

    assert id == ride.id
    assert Map.keys(streams) == ["heart_rate", "power"]
    assert %{"unit" => _unit, "samples" => samples} = streams["power"]
    assert length(samples) == 10
    assert Enum.at(samples, 6) == nil
    assert Enum.all?(List.delete_at(samples, 6), &is_number/1)
  end

  test "answers every recorded channel when none are named", %{conn: conn, scope: scope} do
    run = activity_fixture(scope, "run.fit")

    assert %{"streams" => streams} =
             json_response(get(conn, ~p"/api/activities/#{run.id}/streams?step=600"), 200)

    assert %{"heart_rate" => %{"samples" => [_one]}, "speed" => _speed} = streams
  end

  test "answers 400 for a step that is missing or below 1", %{conn: conn, scope: scope} do
    run = activity_fixture(scope, "run.fit")

    for query <- ["", "?step=0", "?step=1.5", "?step=fast"] do
      assert json_response(get(conn, "/api/activities/#{run.id}/streams#{query}"), 400) ==
               %{"errors" => %{"detail" => "step must be a whole number of seconds from 1"}}
    end
  end

  test "answers 404 for another user's activity", %{conn: conn} do
    other = Scope.for_user(user_fixture())
    ride = activity_fixture(other, "ride.fit")

    assert json_response(get(conn, ~p"/api/activities/#{ride.id}"), 404) ==
             %{"errors" => %{"detail" => "Not Found"}}

    assert json_response(get(conn, ~p"/api/activities/#{ride.id}/streams?step=1"), 404) ==
             %{"errors" => %{"detail" => "Not Found"}}
  end

  test "answers 401 without a session" do
    id = Ecto.UUID.generate()

    for path <- ["/api/activities/#{id}", "/api/activities/#{id}/streams?step=1"] do
      assert json_response(get(build_conn(), path), 401) ==
               %{"errors" => %{"detail" => "Unauthorized"}}
    end
  end
end
