defmodule VireWeb.Mcp.PlanToolsTest do
  use VireWeb.ConnCase, async: true
  use Oban.Testing, repo: Vire.Repo

  import Vire.ActivitiesFixtures
  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Ingest.SyncWorker
  alias Vire.Mcp
  alias Vire.Training

  @summer %{"first" => "2026-07-06", "last" => "2026-08-30"}

  setup do
    user = user_fixture()
    tokens = obtain_mcp_token(user)

    %{
      user: user,
      scope: Scope.for_user(user),
      token: tokens["access_token"],
      client: Mcp.get_client(tokens["client"]["client_id"])
    }
  end

  defp ok!(token, name, args) do
    assert %{"structuredContent" => data, "content" => [%{"type" => "text", "text" => text}]} =
             result = call_tool(token, name, args)

    refute result["isError"]
    assert Jason.decode!(text) == data
    data
  end

  defp error!(token, name, args) do
    assert %{"isError" => true, "content" => [%{"type" => "text", "text" => text}]} =
             call_tool(token, name, args)

    text
  end

  defp build_plan(token) do
    season =
      ok!(token, "create_season", %{
        "name" => "Summer",
        "period" => @summer,
        "rationale" => "Race season"
      })

    phase =
      ok!(token, "create_phase", %{
        "season_id" => season["id"],
        "name" => "Build",
        "period" => @summer,
        "rationale" => "Sharpen"
      })

    block =
      ok!(token, "create_block", %{
        "phase_id" => phase["id"],
        "focus" => "Threshold",
        "period" => %{"first" => "2026-07-06", "last" => "2026-07-26"},
        "rationale" => "Raise threshold"
      })

    cycle =
      ok!(token, "create_cycle", %{
        "block_id" => block["id"],
        "kind" => "load",
        "rationale" => "First week"
      })

    %{season: season, phase: phase, block: block, cycle: cycle}
  end

  test "tools/list describes every plan tool with an object schema", %{token: token} do
    tools = mcp_request(token, "tools/list")["result"]["tools"]

    names =
      ~w(list_seasons get_plan get_day create_season update_season create_phase create_block
         create_cycle update_phase update_block update_cycle delete_season delete_phase
         delete_block delete_cycle update_day create_session update_session delete_session
         match_session sync_now)

    assert names -- Enum.map(tools, & &1["name"]) == []

    for tool <- tools do
      assert %{"type" => "object", "properties" => %{}} = tool["inputSchema"]
      assert is_binary(tool["description"])
    end

    create_season = Enum.find(tools, &(&1["name"] == "create_season"))
    assert create_season["inputSchema"]["required"] == ["name", "period", "rationale"]
  end

  test "the plan is built, read and changed level by level", %{token: token} do
    plan = build_plan(token)

    assert %{"period" => @summer, "rationale" => "Race season"} = plan.season
    assert plan.cycle["period"] == %{"first" => "2026-07-06", "last" => "2026-07-12"}

    assert Enum.map(plan.cycle["days"], & &1["date"]) ==
             Enum.map(6..12, &"2026-07-#{String.pad_leading("#{&1}", 2, "0")}")

    assert %{"seasons" => [%{"name" => "Summer"}]} = ok!(token, "list_seasons", %{})

    assert %{"focus" => "Tempo"} =
             ok!(token, "update_block", %{
               "id" => plan.block["id"],
               "focus" => "Tempo",
               "rationale" => "Earlier race"
             })

    assert %{"name" => "Peak"} =
             ok!(token, "update_phase", %{
               "id" => plan.phase["id"],
               "name" => "Peak",
               "rationale" => "Renamed"
             })

    assert %{"kind" => "recovery", "days" => days} =
             ok!(token, "update_cycle", %{
               "id" => plan.cycle["id"],
               "kind" => "recovery",
               "period" => %{"first" => "2026-07-06", "last" => "2026-07-14"},
               "rationale" => "Tired"
             })

    assert length(days) == 9

    assert %{"name" => "Summer races"} =
             ok!(token, "update_season", %{
               "id" => plan.season["id"],
               "name" => "Summer races",
               "rationale" => "Clearer"
             })

    assert %{"seasons" => [season]} = ok!(token, "get_plan", %{"season_id" => plan.season["id"]})
    assert [%{"name" => "Peak", "blocks" => [%{"cycles" => [cycle]}]}] = season["phases"]
    assert %{"kind" => "recovery", "days" => [%{"sessions" => []} | _days]} = cycle

    assert %{"seasons" => [%{"phases" => [%{"blocks" => [%{"cycles" => [%{"days" => days}]}]}]}]} =
             ok!(token, "get_plan", %{
               "period" => %{"first" => "2026-07-08", "last" => "2026-07-09"}
             })

    assert Enum.map(days, & &1["date"]) == ["2026-07-08", "2026-07-09"]

    assert %{"seasons" => []} =
             ok!(token, "get_plan", %{
               "period" => %{"first" => "2027-01-01", "last" => "2027-01-02"}
             })
  end

  test "days and sessions are planned, matched and read with the day's activities",
       %{token: token, scope: scope} do
    %{block: block} = build_plan(token)
    ride = activity_fixture(scope, "ride.fit")

    assert %{"period" => %{"first" => "2026-07-13", "last" => "2026-07-19"}} =
             ok!(token, "create_cycle", %{
               "block_id" => block["id"],
               "kind" => "load",
               "rationale" => "Second week"
             })

    assert %{"date" => "2026-07-14", "kind" => "rest", "note" => "Travel"} =
             ok!(token, "update_day", %{
               "date" => "2026-07-14",
               "note" => "Travel",
               "rationale" => "Flight in the evening"
             })

    session =
      ok!(token, "create_session", %{
        "date" => "2026-07-14",
        "position" => 0,
        "discipline" => "bike",
        "structure" => %{"steps" => [%{"minutes" => 10, "zone" => 2}]},
        "planned_seconds" => 600,
        "rationale" => "Short spin"
      })

    assert %{"date" => "2026-07-14", "status" => "planned", "activity_id" => nil} = session

    assert %{"date" => "2026-07-14", "day" => day, "activities" => [activity]} =
             ok!(token, "get_day", %{"date" => "2026-07-14"})

    assert %{"id" => ride_id, "discipline" => "bike", "local_date" => "2026-07-14"} = activity
    assert ride_id == ride.id

    assert %{"kind" => "training", "note" => "Travel", "sessions" => [%{"status" => "planned"}]} =
             day

    assert %{
             "season" => %{"name" => "Summer"},
             "phase" => %{"name" => "Build"},
             "block" => %{"focus" => "Threshold"},
             "cycle" => %{"kind" => "load"}
           } = day["chain"]

    assert %{"status" => "done", "activity_id" => ^ride_id} =
             ok!(token, "match_session", %{
               "session_id" => session["id"],
               "activity_id" => ride.id,
               "rationale" => "This was the spin"
             })

    assert %{"status" => "planned", "activity_id" => nil} =
             ok!(token, "match_session", %{
               "session_id" => session["id"],
               "activity_id" => nil,
               "rationale" => "Wrong ride"
             })

    assert %{"date" => "2026-07-15", "position" => 1, "discipline" => "run"} =
             ok!(token, "update_session", %{
               "id" => session["id"],
               "date" => "2026-07-15",
               "position" => 1,
               "discipline" => "run",
               "rationale" => "Moved after the flight"
             })

    assert error!(token, "match_session", %{
             "session_id" => session["id"],
             "activity_id" => ride.id,
             "rationale" => "Try"
           }) == "The activity was recorded on another date"

    assert %{"deleted" => session_id} =
             ok!(token, "delete_session", %{"id" => session["id"], "rationale" => "Rest"})

    assert session_id == session["id"]
    assert %{"day" => nil, "activities" => []} = ok!(token, "get_day", %{"date" => "2026-09-01"})
  end

  test "deletes remove a level with everything beneath it", %{token: token, scope: scope} do
    plan = build_plan(token)

    for level <- [:cycle, :block, :phase, :season] do
      id = plan[level]["id"]

      assert %{"deleted" => ^id} =
               ok!(token, "delete_#{level}", %{"id" => id, "rationale" => "Start over"})
    end

    assert Training.list_seasons(scope) == []
  end

  test "every write is logged under the MCP channel and the calling client",
       %{token: token, scope: scope, client: client} do
    plan = build_plan(token)

    ok!(token, "update_season", %{
      "id" => plan.season["id"],
      "name" => "S",
      "rationale" => "Short"
    })

    changes = Training.list_changes(scope)

    assert Enum.map(changes, &{&1.entity, &1.action}) == [
             {:training_season, :update},
             {:training_cycle, :insert},
             {:training_block, :insert},
             {:training_phase, :insert},
             {:training_season, :insert}
           ]

    for change <- changes do
      assert {change.channel, change.mcp_client_id} == {:mcp, client.id}
    end

    assert hd(changes).rationale == "Short"
  end

  test "invalid arguments answer an error result explaining them", %{token: token} do
    assert error!(token, "create_season", %{}) == "Missing arguments: name, period, rationale"

    assert error!(token, "create_season", %{
             "name" => "Backwards",
             "period" => %{"first" => "2026-07-06", "last" => "2026-07-01"},
             "rationale" => "Oops"
           }) == "Invalid arguments: period must not end before it starts"

    plan = build_plan(token)

    assert error!(token, "create_phase", %{
             "season_id" => plan.season["id"],
             "name" => "Late",
             "period" => %{"first" => "2026-08-01", "last" => "2026-09-30"},
             "rationale" => "Too long"
           }) =~ "period lies outside its season"

    assert error!(token, "update_season", %{"id" => plan.season["id"], "rationale" => " "}) ==
             "Invalid arguments: rationale can't be blank"

    assert error!(token, "create_session", %{
             "date" => "2026-12-24",
             "position" => 0,
             "discipline" => "run",
             "rationale" => "Holiday run"
           }) == "Invalid arguments: date is not a day in the plan"

    assert error!(token, "get_day", %{"date" => "tomorrow"}) ==
             "date must be an ISO 8601 date such as 2026-11-02"

    assert error!(token, "update_day", %{"date" => 20_260_714, "rationale" => "x"}) =~
             "date must be an ISO 8601 date"

    assert error!(token, "get_plan", %{"period" => "July"}) =~
             "period must be an object with first and last dates"

    assert error!(token, "get_plan", %{}) == "Give either season_id or period"
  end

  test "an unknown id answers not found", %{token: token} do
    id = Ecto.UUID.generate()

    assert error!(token, "get_plan", %{"season_id" => id}) == "Not found"
    assert error!(token, "update_season", %{"id" => id, "rationale" => "x"}) == "Not found"

    assert error!(token, "delete_session", %{"id" => "not-a-uuid", "rationale" => "x"}) ==
             "Not found"

    assert error!(token, "match_session", %{
             "session_id" => id,
             "activity_id" => nil,
             "rationale" => "x"
           }) == "Not found"

    assert error!(token, "update_day", %{"date" => "2026-07-14", "rationale" => "x"}) ==
             "Not found"
  end

  test "another user's plan is invisible and untouchable", %{token: token} do
    other = scope_fixture()
    %{season: season} = plan_fixture(other)
    session = session_fixture(other)

    assert %{"seasons" => []} = ok!(token, "list_seasons", %{})
    assert error!(token, "get_plan", %{"season_id" => season.id}) == "Not found"

    assert %{"seasons" => []} =
             ok!(token, "get_plan", %{
               "period" => %{"first" => "2026-11-01", "last" => "2026-11-30"}
             })

    assert %{"day" => nil} = ok!(token, "get_day", %{"date" => "2026-11-03"})

    assert error!(token, "delete_season", %{"id" => season.id, "rationale" => "Mine"}) ==
             "Not found"

    assert error!(token, "update_session", %{"id" => session.id, "rationale" => "Mine"}) ==
             "Not found"

    assert [_season] = Training.list_seasons(other)
  end

  test "sync_now enqueues a Garmin sync for a connected athlete", %{token: token, user: user} do
    assert error!(token, "sync_now", %{}) == "The athlete has no Garmin connection"

    connection = provider_connection_fixture(user)

    assert %{"job_id" => job_id} = ok!(token, "sync_now", %{})
    assert_enqueued(worker: SyncWorker, args: %{"user_id" => user.id, "first" => nil})
    assert is_integer(job_id)

    {:ok, _paused} =
      Vire.Accounts.pause_provider_connection(Scope.for_user(user), connection)

    assert error!(token, "sync_now", %{}) == "The athlete's Garmin connection is paused"
  end
end
