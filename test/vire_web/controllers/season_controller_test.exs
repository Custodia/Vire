defmodule VireWeb.SeasonControllerTest do
  use VireWeb.ConnCase, async: true

  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Activities
  alias Vire.Repo
  alias Vire.Training.Session

  setup %{conn: conn} do
    user = user_fixture()
    scope = Scope.for_user(user)

    season =
      season_fixture(scope,
        name: "Summer",
        period: period(~D[2026-07-01], ~D[2026-08-30]),
        rationale: "Everything points at the August race."
      )

    phase =
      phase_fixture(scope, season,
        name: "Build",
        period: season.period,
        rationale: "Threshold and race-pace work."
      )

    block =
      block_fixture(scope, phase,
        focus: "Threshold",
        period: period(~D[2026-07-13], ~D[2026-07-26])
      )

    cycle =
      cycle_fixture(scope, block, kind: :load, period: period(~D[2026-07-13], ~D[2026-07-19]))

    %{conn: sign_in(conn, user), scope: scope, season: season, block: block, cycle: cycle}
  end

  describe "index" do
    test "answers the user's seasons, earliest first", %{conn: conn, scope: scope} do
      season_fixture(scope, name: "Spring", period: period(~D[2026-03-01], ~D[2026-04-30]))

      assert %{"seasons" => [spring, summer]} =
               conn |> get(~p"/api/seasons") |> json_response(200)

      assert %{"name" => "Spring", "period" => %{"first" => "2026-03-01", "last" => "2026-04-30"}} =
               spring

      assert %{"name" => "Summer"} = summer
    end

    test "answers no seasons for a user who has none" do
      other = sign_in(build_conn(), user_fixture())

      assert %{"seasons" => []} = other |> get(~p"/api/seasons") |> json_response(200)
    end

    test "requires a signed-in user" do
      assert build_conn() |> get(~p"/api/seasons") |> json_response(401)
    end
  end

  describe "show" do
    test "answers the season with everything beneath it", %{
      conn: conn,
      scope: scope,
      season: season,
      block: block,
      cycle: cycle
    } do
      session_fixture(scope,
        date: ~D[2026-07-14],
        position: 0,
        discipline: :run,
        structure: %{"title" => "Threshold intervals"},
        planned_seconds: 3600,
        rationale: "Opens the block"
      )

      body = conn |> get(~p"/api/seasons/#{season.id}") |> json_response(200)

      assert body["id"] == season.id
      assert body["name"] == "Summer"
      assert body["rationale"] == "Everything points at the August race."
      assert body["period"] == %{"first" => "2026-07-01", "last" => "2026-08-30"}

      assert [
               %{
                 "name" => "Build",
                 "rationale" => "Threshold and race-pace work.",
                 "blocks" => [block_json]
               }
             ] = body["phases"]

      assert block_json["id"] == block.id
      assert block_json["focus"] == "Threshold"
      assert block_json["period"] == %{"first" => "2026-07-13", "last" => "2026-07-26"}

      assert [cycle_json] = block_json["cycles"]
      assert cycle_json["id"] == cycle.id
      assert cycle_json["kind"] == "load"
      assert cycle_json["period"] == %{"first" => "2026-07-13", "last" => "2026-07-19"}

      assert length(cycle_json["days"]) == 7
      assert [first_day | _] = cycle_json["days"]
      assert first_day["date"] == "2026-07-13"
      assert first_day["kind"] == "rest"
      assert first_day["sessions"] == []

      assert %{"date" => "2026-07-14", "sessions" => [session]} =
               Enum.find(cycle_json["days"], &(&1["date"] == "2026-07-14"))

      assert day_on(body, "2026-07-14")["kind"] == "training"
      assert session["title"] == "Threshold intervals"
      assert session["discipline"] == "run"
      assert session["planned_seconds"] == 3600
      assert session["status"] == "planned"
      assert session["position"] == 0
    end

    test "titles a session without one after its discipline", %{
      conn: conn,
      scope: scope,
      season: season
    } do
      session_fixture(scope, date: ~D[2026-07-15], discipline: :swim, structure: %{})

      body = conn |> get(~p"/api/seasons/#{season.id}") |> json_response(200)

      assert [%{"title" => "Swim"}] = sessions_on(body, "2026-07-15")
    end

    test "carries a day's kind and note", %{conn: conn, scope: scope, season: season} do
      {:ok, _day} =
        Vire.Training.update_day(
          scope,
          ~D[2026-07-16],
          %{kind: :rest, note: "Legs are flat."},
          "Recovering"
        )

      body = conn |> get(~p"/api/seasons/#{season.id}") |> json_response(200)

      assert %{"kind" => "rest", "note" => "Legs are flat."} = day_on(body, "2026-07-16")
    end

    test "lists the activities on the season's dates that no session is matched to", %{
      conn: conn,
      scope: scope,
      season: season
    } do
      walk = activity(scope, 1, ~U[2026-07-15 17:10:00Z], :other)
      matched = activity(scope, 2, ~U[2026-07-16 07:00:00Z], :run)
      activity(scope, 3, ~U[2026-09-01 07:00:00Z], :run)

      session_fixture(scope, date: ~D[2026-07-16], discipline: :run)
      |> Session.match_changeset(matched.id)
      |> Repo.update!()

      body = conn |> get(~p"/api/seasons/#{season.id}") |> json_response(200)

      assert [listed] = body["activities"]
      assert listed["id"] == walk.id
      assert listed["discipline"] == "other"
      assert listed["local_date"] == "2026-07-15"
      assert listed["duration_seconds"] == 1500
    end

    test "answers 404 for another user's season", %{season: season} do
      other = sign_in(build_conn(), user_fixture())

      assert other |> get(~p"/api/seasons/#{season.id}") |> json_response(404)
    end

    test "answers 404 for an unknown season and for an id that is not one", %{conn: conn} do
      assert conn |> get(~p"/api/seasons/#{Ecto.UUID.generate()}") |> json_response(404)
      assert conn |> get(~p"/api/seasons/not-a-uuid") |> json_response(404)
    end

    test "requires a signed-in user", %{season: season} do
      assert build_conn() |> get(~p"/api/seasons/#{season.id}") |> json_response(401)
    end
  end

  defp day_on(body, date) do
    for(
      phase <- body["phases"],
      block <- phase["blocks"],
      cycle <- block["cycles"],
      day <- cycle["days"],
      do: day
    )
    |> Enum.find(&(&1["date"] == date))
  end

  defp sessions_on(body, date), do: day_on(body, date)["sessions"]

  defp activity(scope, id, %DateTime{} = started_at, discipline) do
    {:ok, activity} =
      Activities.upsert_provider_activity(scope, %{
        provider: :garmin,
        external_id: to_string(id),
        started_at: started_at,
        utc_offset_seconds: 0,
        local_date: DateTime.to_date(started_at),
        discipline: discipline,
        duration_seconds: 1500,
        distance_m: 2400.0,
        provider_summary: %{"activityId" => id}
      })

    activity
  end
end
