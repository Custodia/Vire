defmodule VireWeb.Mcp.PlanToolsTest do
  use VireWeb.ConnCase, async: true
  use Oban.Testing, repo: Vire.Repo

  import Vire.ActivitiesFixtures
  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Ingest.SyncWorker
  alias Vire.Mcp
  alias Vire.Mcp.PlanRead
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

  defp errors!(token, name, args) do
    assert %{"isError" => true, "structuredContent" => %{"ok" => false, "errors" => errors}} =
             call_tool(token, name, args)

    Enum.map(errors, &{&1["path"], &1["message"]})
  end

  defp write!(token, ops, change_log \\ "Planning"),
    do: ok!(token, "write_plan", %{"change_log" => change_log, "ops" => ops})

  defp build_plan(token) do
    %{"results" => [season]} =
      write!(token, [
        %{
          "op" => "create",
          "level" => "season",
          "name" => "Summer",
          "period" => @summer,
          "rationale" => "Race season",
          "phases" => [
            %{
              "name" => "Build",
              "period" => @summer,
              "blocks" => [
                %{
                  "focus" => "Threshold",
                  "period" => %{"first" => "2026-07-06", "last" => "2026-07-26"},
                  "rationale" => "Raise threshold",
                  "cycles" => [%{"kind" => "load"}]
                }
              ]
            }
          ]
        }
      ])

    %{"phases" => [%{"blocks" => [%{"cycles" => [cycle]} = block]} = phase]} = season
    %{season: season, phase: phase, block: block, cycle: cycle}
  end

  test "tools/list describes the plan tools with strict object schemas", %{token: token} do
    tools = mcp_request(token, "tools/list")["result"]["tools"]
    names = Enum.map(tools, & &1["name"])

    assert ~w(read_plan write_plan match_session sync_now) -- names == []
    assert ~w(list_seasons get_plan get_day create_season update_session) -- names != []

    for tool <- tools do
      assert %{"type" => "object", "properties" => %{}, "additionalProperties" => false} =
               tool["inputSchema"]
    end

    write_plan = Enum.find(tools, &(&1["name"] == "write_plan"))
    assert write_plan["description"] =~ "a phase lies inside its season"
    assert write_plan["inputSchema"]["required"] == ["change_log", "ops"]

    branches = write_plan["inputSchema"]["properties"]["ops"]["items"]["oneOf"]
    assert length(branches) == 16
    assert %{"session" => _, "phase_tree" => _} = defs = write_plan["inputSchema"]["$defs"]

    assert defs["structure"]["description"] =~
             "A step has kind (warmup, work, recovery, cooldown or rest)"

    assert %{
             "anyOf" => [
               %{"required" => ["kind", "seconds"]},
               %{"required" => ["repeat", "steps"]}
             ]
           } = defs["structure"]["properties"]["steps"]["items"]
  end

  test "write_plan refuses a structure whose steps break their shape", %{token: token} do
    build_plan(token)

    assert errors!(token, "write_plan", %{
             "change_log" => "Strides",
             "ops" => [
               %{
                 "op" => "create",
                 "level" => "session",
                 "date" => "2026-07-07",
                 "position" => 0,
                 "discipline" => "run",
                 "structure" => %{"steps" => [%{"repeat" => 4, "steps" => [%{"seconds" => 60}]}]},
                 "rationale" => "Strides"
               }
             ]
           }) == [{"ops[0].structure.steps[0].steps[0].kind", "is required"}]
  end

  test "write_plan creates a season with everything beneath it in one call", ctx do
    %{token: token, scope: scope, client: client} = ctx
    plan = build_plan(token)

    assert plan.cycle["period"] == %{"first" => "2026-07-06", "last" => "2026-07-12"}
    assert plan.season["op"] == 0

    [season] = Training.list_seasons(scope)
    assert season.id == plan.season["id"]

    assert %{"seasons" => [read]} = ok!(token, "read_plan", %{})
    assert %{"name" => "Summer", "rationale" => "Race season"} = read

    assert [%{"name" => "Build", "rationale" => "Race season", "blocks" => [block]}] =
             read["phases"]

    assert %{"rationale" => "Raise threshold", "cycles" => [cycle]} = block
    assert %{"kind" => "load", "rationale" => "Raise threshold", "days" => days} = cycle
    assert length(days) == 7

    changes = Training.list_changes(scope)
    assert length(changes) == 4

    for change <- changes do
      assert {change.channel, change.mcp_client_id, change.rationale} ==
               {:mcp, client.id, "Planning"}
    end
  end

  test "write_plan adds a week of sessions with a day's note in one call", %{token: token} do
    plan = build_plan(token)

    assert %{"results" => [%{"op" => 0, "period" => period, "sessions" => [_, _, _]}]} =
             write!(token, [
               %{
                 "op" => "create",
                 "level" => "cycle",
                 "block_id" => plan.block["id"],
                 "kind" => "recovery",
                 "rationale" => "Absorb the load",
                 "days" => [%{"date" => "2026-07-19", "note" => "Easy if legs are heavy"}],
                 "sessions" => [
                   %{
                     "date" => "2026-07-14",
                     "position" => 0,
                     "discipline" => "bike",
                     "planned_seconds" => 3600,
                     "structure" => %{"title" => "Endurance"}
                   },
                   %{"date" => "2026-07-16", "position" => 0, "discipline" => "run"},
                   %{
                     "date" => "2026-07-18",
                     "position" => 0,
                     "discipline" => "strength",
                     "rationale" => "Keep the joints ready"
                   }
                 ]
               }
             ])

    assert period == %{"first" => "2026-07-13", "last" => "2026-07-19"}

    assert %{"days" => days} =
             ok!(token, "read_plan", %{
               "when" => %{"first" => "2026-07-14", "last" => "2026-07-19"},
               "from" => "day"
             })

    assert Enum.map(days, &{&1["date"], &1["kind"], length(&1["sessions"])}) == [
             {"2026-07-14", "training", 1},
             {"2026-07-15", "rest", 0},
             {"2026-07-16", "training", 1},
             {"2026-07-17", "rest", 0},
             {"2026-07-18", "training", 1},
             {"2026-07-19", "rest", 0}
           ]

    assert List.last(days)["note"] == "Easy if legs are heavy"

    assert Enum.map(Enum.flat_map(days, & &1["sessions"]), & &1["rationale"]) ==
             ["Absorb the load", "Absorb the load", "Keep the joints ready"]

    assert %{"season" => %{"name" => "Summer"}, "cycle" => %{"kind" => "recovery"}} =
             hd(days)["chain"]
  end

  test "write_plan writes nothing when any op is refused", %{token: token, scope: scope} do
    plan = build_plan(token)
    before = Training.list_changes(scope)

    assert errors!(token, "write_plan", %{
             "change_log" => "Second week",
             "ops" => [
               %{
                 "op" => "update",
                 "level" => "season",
                 "id" => plan.season["id"],
                 "name" => "Renamed"
               },
               %{
                 "op" => "create",
                 "level" => "cycle",
                 "block_id" => plan.block["id"],
                 "kind" => "load",
                 "rationale" => "Week two",
                 "sessions" => [
                   %{"date" => "2026-07-13", "position" => 0, "discipline" => "run"},
                   %{"date" => "2026-07-21", "position" => 0, "discipline" => "run"}
                 ]
               }
             ]
           }) == [
             {"ops[1].sessions[1].date",
              "2026-07-21 lies outside the cycle, 2026-07-13 to 2026-07-19"}
           ]

    assert Training.list_changes(scope) == before
    assert [%{name: "Summer"}] = Training.list_seasons(scope)
  end

  test "write_plan refuses unknown fields and malformed ops with their paths", %{token: token} do
    plan = build_plan(token)

    assert errors!(token, "write_plan", %{
             "change_log" => " ",
             "ops" => [
               %{
                 "op" => "create",
                 "level" => "season",
                 "name" => "Winter",
                 "period" => %{"first" => "2026-12-01", "last" => "2027-02-28"},
                 "rationale" => "Base",
                 "phases" => [%{"name" => "Base", "colour" => "blue"}]
               },
               %{"op" => "rename", "level" => "season"},
               %{"op" => "update", "level" => "session", "id" => "x", "status" => "late"},
               %{"op" => "delete", "level" => "day", "id" => plan.cycle["id"]}
             ]
           }) == [
             {"change_log", "can't be blank"},
             {"ops[0].phases[0].period", "is required"},
             {"ops[0].phases[0].colour", "is not a known field"},
             {"ops[1]",
              "op and level must be one of create season, create phase, create block, " <>
                "create cycle, create session, update season, update phase, update block, " <>
                "update cycle, update day, update session, delete season, delete phase, " <>
                "delete block, delete cycle, delete session"},
             {"ops[2].id", "must be a UUID"},
             {"ops[2].status", "must be one of planned, done, skipped"},
             {"ops[3]",
              "op and level must be one of create season, create phase, create block, " <>
                "create cycle, create session, update season, update phase, update block, " <>
                "update cycle, update day, update session, delete season, delete phase, " <>
                "delete block, delete cycle, delete session"}
           ]
  end

  test "write_plan answers a row's refusals at the paths of its fields", %{token: token} do
    plan = build_plan(token)

    session = %{
      "op" => "create",
      "level" => "session",
      "date" => "2026-07-08",
      "position" => 0,
      "discipline" => "run",
      "rationale" => "Easy run"
    }

    assert errors!(token, "write_plan", %{
             "change_log" => "Planning",
             "ops" => [Map.put(session, "date", "2026-12-24")]
           }) == [{"ops[0].date", "is not a day in the plan"}]

    assert errors!(token, "write_plan", %{"change_log" => "Planning", "ops" => [session, session]}) ==
             [{"ops[1].position", "is taken by another session that day"}]

    assert errors!(token, "write_plan", %{
             "change_log" => "Planning",
             "ops" => [
               %{
                 "op" => "update",
                 "level" => "season",
                 "id" => plan.season["id"],
                 "rationale" => " ",
                 "period" => %{"first" => "2026-07-06", "last" => "2026-07-01"}
               }
             ]
           }) == [
             {"ops[0].period", "must not end before it starts"},
             {"ops[0].rationale", "can't be blank"}
           ]
  end

  test "write_plan checks periods once every op has run", %{token: token, scope: scope} do
    plan = build_plan(token)

    %{"results" => [%{"id" => second_id}]} =
      write!(token, [
        %{
          "op" => "create",
          "level" => "block",
          "phase_id" => plan.phase["id"],
          "focus" => "VO2",
          "period" => %{"first" => "2026-07-27", "last" => "2026-08-09"},
          "rationale" => "Top end"
        }
      ])

    widen = %{
      "op" => "update",
      "level" => "block",
      "id" => second_id,
      "period" => %{"first" => "2026-07-20", "last" => "2026-08-09"}
    }

    assert errors!(token, "write_plan", %{"change_log" => "Earlier", "ops" => [widen]}) == [
             {"ops[0].period", "overlaps another block, 2026-07-06 to 2026-07-26"}
           ]

    write!(token, [
      widen,
      %{
        "op" => "update",
        "level" => "block",
        "id" => plan.block["id"],
        "period" => %{"first" => "2026-07-06", "last" => "2026-07-19"}
      }
    ])

    assert Enum.map(Training.list_periods(scope, :block), &{&1.first, &1.last}) == [
             {~D[2026-07-06], ~D[2026-07-19]},
             {~D[2026-07-20], ~D[2026-08-09]}
           ]

    assert errors!(token, "write_plan", %{
             "change_log" => "Shorter",
             "ops" => [
               %{
                 "op" => "update",
                 "level" => "phase",
                 "id" => plan.phase["id"],
                 "period" => %{"first" => "2026-07-06", "last" => "2026-07-31"}
               }
             ]
           }) == [
             {"ops[0].period",
              "2026-07-06 to 2026-07-31 no longer holds its block of 2026-07-20 to 2026-08-09"}
           ]
  end

  test "write_plan moves cycles' dates between neighbours in either order", %{token: token} do
    plan = build_plan(token)

    %{"results" => [%{"id" => second_id}]} =
      write!(token, [
        %{
          "op" => "create",
          "level" => "cycle",
          "block_id" => plan.block["id"],
          "kind" => "load",
          "rationale" => "Two"
        }
      ])

    write!(token, [
      %{
        "op" => "update",
        "level" => "cycle",
        "id" => second_id,
        "period" => %{"first" => "2026-07-11", "last" => "2026-07-19"}
      },
      %{
        "op" => "update",
        "level" => "cycle",
        "id" => plan.cycle["id"],
        "period" => %{"first" => "2026-07-06", "last" => "2026-07-10"}
      }
    ])

    assert %{"cycles" => [first, second]} =
             ok!(token, "read_plan", %{"from" => "cycle", "to" => "day"})

    assert Enum.map(first["days"], & &1["date"]) == Enum.map(6..10, &"2026-07-#{pad(&1)}")
    assert Enum.map(second["days"], & &1["date"]) == Enum.map(11..19, &"2026-07-#{pad(&1)}")
  end

  defp pad(day), do: String.pad_leading("#{day}", 2, "0")

  test "write_plan updates rationales, days and sessions and deletes rows", ctx do
    %{token: token, scope: scope} = ctx
    plan = build_plan(token)

    %{"results" => [%{"id" => session_id}]} =
      write!(token, [
        %{
          "op" => "create",
          "level" => "session",
          "date" => "2026-07-08",
          "position" => 0,
          "discipline" => "run",
          "rationale" => "Easy run"
        }
      ])

    assert %{"results" => [%{"op" => 0}, %{"op" => 1, "date" => "2026-07-09"}, %{"op" => 2}]} =
             write!(
               token,
               [
                 %{
                   "op" => "update",
                   "level" => "block",
                   "id" => plan.block["id"],
                   "rationale" => "Raise threshold before the race"
                 },
                 %{
                   "op" => "update",
                   "level" => "day",
                   "date" => "2026-07-09",
                   "note" => "Travel"
                 },
                 %{
                   "op" => "update",
                   "level" => "session",
                   "id" => session_id,
                   "status" => "skipped",
                   "change_log" => "Ill"
                 }
               ],
               "Adjusting"
             )

    assert %{"blocks" => [%{"rationale" => "Raise threshold before the race"}]} =
             ok!(token, "read_plan", %{"from" => "block", "to" => "block"})

    assert [skip, note, block | _created] = Training.list_changes(scope)
    assert {skip.rationale, note.rationale, block.rationale} == {"Ill", "Adjusting", "Adjusting"}

    assert %{"results" => [%{"op" => 0, "id" => ^session_id}, _cycle]} =
             write!(token, [
               %{"op" => "delete", "level" => "session", "id" => session_id},
               %{"op" => "delete", "level" => "cycle", "id" => plan.cycle["id"]}
             ])

    assert %{"cycles" => []} = ok!(token, "read_plan", %{"from" => "cycle"})
  end

  test "read_plan lists any level down to any depth, with chains", %{token: token} do
    plan = build_plan(token)

    write!(token, [
      %{
        "op" => "create",
        "level" => "session",
        "date" => "2026-07-08",
        "position" => 0,
        "discipline" => "run",
        "structure" => %{
          "title" => "Tempo",
          "note" => "Hold it",
          "steps" => [%{"kind" => "work", "seconds" => 1200, "zone" => 3}]
        },
        "rationale" => "Tempo"
      }
    ])

    assert %{"period" => nil, "seasons" => [season]} =
             ok!(token, "read_plan", %{"to" => "season"})

    refute Map.has_key?(season, "phases")

    assert %{"blocks" => [block]} = ok!(token, "read_plan", %{"from" => "block", "to" => "block"})
    refute Map.has_key?(block, "cycles")

    assert block["chain"] == %{
             "season" => %{"id" => plan.season["id"], "name" => "Summer"},
             "phase" => %{"id" => plan.phase["id"], "name" => "Build"}
           }

    assert %{"period" => period, "sessions" => [session]} =
             ok!(token, "read_plan", %{
               "when" => "2026-07-08",
               "from" => "session",
               "to" => "session"
             })

    assert period == %{"first" => "2026-07-08", "last" => "2026-07-08"}
    assert session["structure"] == %{"title" => "Tempo", "note" => "Hold it"}
    assert session["chain"]["cycle"] == %{"id" => plan.cycle["id"], "kind" => "load"}

    assert %{"sessions" => [%{"structure" => %{"steps" => [_step]}}]} =
             ok!(token, "read_plan", %{"from" => "session"})

    assert %{"cycles" => [%{"days" => [day]}]} =
             ok!(token, "read_plan", %{"when" => "2026-07-09", "from" => "cycle"})

    assert day["date"] == "2026-07-09"

    assert errors!(token, "read_plan", %{"from" => "day", "to" => "block"}) ==
             [{"to", "must not lie above from, day"}]

    assert errors!(token, "read_plan", %{"when" => "someday"}) == [
             {"when",
              "must be a date such as 2026-11-02, -3d, +2d or one of today, yesterday, " <>
                "tomorrow, last-week, this-week, next-week, last-month, this-month, " <>
                "next-month, last-cycle, this-cycle, next-cycle, this-block, this-phase, " <>
                "this-season"}
           ]
  end

  test "read_plan filters sessions, keeps the rows above them and sums cycles", ctx do
    %{token: token, scope: scope} = ctx
    build_plan(token)

    sessions =
      for {date, discipline, seconds} <- [
            {"2026-07-07", "run", 3600},
            {"2026-07-08", "bike", 5400},
            {"2026-07-10", "run", 1800}
          ] do
        %{
          "op" => "create",
          "level" => "session",
          "date" => date,
          "position" => 0,
          "discipline" => discipline,
          "planned_seconds" => seconds,
          "rationale" => "Planned"
        }
      end

    %{"results" => [%{"id" => first_run} | _rest]} = write!(token, sessions)

    write!(token, [
      %{"op" => "update", "level" => "session", "id" => first_run, "status" => "done"}
    ])

    assert %{"days" => [%{"date" => "2026-07-10"}]} =
             ok!(token, "read_plan", %{
               "from" => "day",
               "filter" => %{"discipline" => ["run"], "status" => ["planned"]}
             })

    assert {:ok, %{sessions: [%{date: ~D[2026-07-08]}]}} =
             PlanRead.read(
               scope,
               %{"from" => "session", "filter" => %{"unmatched" => true}},
               ~D[2026-07-10]
             )

    assert {:ok, %{cycles: [%{summary: summary}]}} =
             PlanRead.read(
               scope,
               %{"from" => "cycle", "to" => "cycle", "summary" => true},
               ~D[2026-07-10]
             )

    assert summary == %{
             sessions: %{planned: 2, done: 1, skipped: 0, unmatched: 1},
             seconds: %{planned: 10_800, actual: 0}
           }

    assert {:ok, %{seasons: []}} =
             PlanRead.read(scope, %{"filter" => %{"discipline" => ["swim"]}}, ~D[2026-07-10])
  end

  test "read_plan resolves relative dates on the UTC date", %{token: token, scope: scope} do
    build_plan(token)

    assert {:ok, %{period: %{first: ~D[2026-07-06], last: ~D[2026-07-12]}, days: days}} =
             PlanRead.read(scope, %{"when" => "this-week", "from" => "day"}, ~D[2026-07-09])

    assert length(days) == 7

    assert {:ok, %{period: %{first: ~D[2026-07-06], last: ~D[2026-07-26]}}} =
             PlanRead.read(scope, %{"when" => "this-block", "to" => "season"}, ~D[2026-07-09])

    assert {:error, {:invalid, [%{path: "when", message: "no cycle holds today, 2026-09-01"}]}} =
             PlanRead.read(scope, %{"when" => "this-cycle"}, ~D[2026-09-01])
  end

  test "an unmatched session carries candidates and is matched by hand", ctx do
    %{token: token, scope: scope} = ctx
    plan = build_plan(token)

    %{"results" => [%{"id" => cycle_id, "sessions" => [%{"id" => session_id}]}]} =
      write!(token, [
        %{
          "op" => "create",
          "level" => "cycle",
          "block_id" => plan.block["id"],
          "kind" => "load",
          "rationale" => "Week two",
          "sessions" => [
            %{
              "date" => "2026-07-14",
              "position" => 0,
              "discipline" => "bike",
              "planned_seconds" => 3600
            }
          ]
        }
      ])

    ride = activity_fixture(scope, "ride.fit")
    assert %{"status" => "planned"} = hd(sessions_on(token, "2026-07-14"))

    Training.match_activities(scope, ~D[2026-07-14])

    assert [%{"activity_id" => nil, "candidates" => [candidate]}] =
             sessions_on(token, "2026-07-14")

    assert %{"activity_id" => ride_id, "confidence" => confidence, "why" => why} = candidate
    assert ride_id == ride.id
    assert confidence > 0 and confidence < 0.8
    assert why =~ "of 60 min planned"

    assert %{"status" => "done", "activity_id" => ^ride_id} =
             matched =
             ok!(token, "match_session", %{
               "session_id" => session_id,
               "activity_id" => ride.id,
               "change_log" => "The spin was cut short"
             })

    refute Map.has_key?(matched, "candidates")

    assert %{"status" => "planned", "candidates" => [_ride]} =
             ok!(token, "match_session", %{
               "session_id" => session_id,
               "activity_id" => nil,
               "change_log" => "Wrong ride"
             })

    write!(token, [
      %{"op" => "update", "level" => "session", "id" => session_id, "date" => "2026-07-15"}
    ])

    assert error!(token, "match_session", %{
             "session_id" => session_id,
             "activity_id" => ride.id,
             "change_log" => "Try"
           }) == "The activity was recorded on another date"

    assert cycle_id
  end

  test "match_session refuses an activity matched to another session", ctx do
    %{token: token, scope: scope} = ctx
    plan = build_plan(token)

    %{"results" => [%{"sessions" => [%{"id" => first}, %{"id" => second}]}]} =
      write!(token, [
        %{
          "op" => "create",
          "level" => "cycle",
          "block_id" => plan.block["id"],
          "kind" => "load",
          "rationale" => "Week two",
          "sessions" => [
            %{"date" => "2026-07-14", "position" => 0, "discipline" => "bike"},
            %{"date" => "2026-07-14", "position" => 1, "discipline" => "bike"}
          ]
        }
      ])

    ride = activity_fixture(scope, "ride.fit")
    args = %{"activity_id" => ride.id, "change_log" => "The ride"}

    assert %{"status" => "done"} = ok!(token, "match_session", Map.put(args, "session_id", first))

    assert errors!(token, "match_session", Map.put(args, "session_id", second)) ==
             [{"activity_id", "is matched to another session"}]
  end

  defp sessions_on(token, date) do
    %{"sessions" => sessions} =
      ok!(token, "read_plan", %{"when" => date, "from" => "session", "to" => "session"})

    sessions
  end

  test "another user's plan is invisible and untouchable", %{token: token} do
    other = scope_fixture()
    %{season: season} = plan_fixture(other)
    session = session_fixture(other)

    assert %{"seasons" => []} = ok!(token, "read_plan", %{})
    assert %{"seasons" => []} = ok!(token, "read_plan", %{"season_id" => season.id})

    assert errors!(token, "write_plan", %{
             "change_log" => "Mine",
             "ops" => [%{"op" => "delete", "level" => "season", "id" => season.id}]
           }) == [{"ops[0].id", "names no season of the athlete"}]

    assert errors!(token, "write_plan", %{
             "change_log" => "Mine",
             "ops" => [
               %{
                 "op" => "create",
                 "level" => "phase",
                 "season_id" => season.id,
                 "name" => "Mine",
                 "period" => %{"first" => "2026-11-01", "last" => "2026-11-08"},
                 "rationale" => "Mine"
               }
             ]
           }) == [{"ops[0].season_id", "names no season of the athlete"}]

    assert error!(token, "match_session", %{
             "session_id" => session.id,
             "activity_id" => nil,
             "change_log" => "Mine"
           }) == "Not found"

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
