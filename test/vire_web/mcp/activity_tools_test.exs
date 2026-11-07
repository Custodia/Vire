defmodule VireWeb.Mcp.ActivityToolsTest do
  use VireWeb.ConnCase, async: true

  import Vire.ActivitiesFixtures
  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Activities

  @year %{"first" => "2026-01-01", "last" => "2026-12-31"}

  setup do
    user = user_fixture()
    scope = Scope.for_user(user)

    %{
      scope: scope,
      token: obtain_mcp_token(user)["access_token"],
      ride: activity_fixture(scope, "ride.fit"),
      run: activity_fixture(scope, "run.fit"),
      swim: activity_fixture(scope, "swim.fit")
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
    assert %{"isError" => true, "structuredContent" => %{"errors" => errors}} =
             call_tool(token, name, args)

    Enum.map(errors, &{&1["path"], &1["message"]})
  end

  test "tools/list describes the activity tools", %{token: token} do
    tools = Map.new(mcp_request(token, "tools/list")["result"]["tools"], &{&1["name"], &1})

    for name <- ~w(list_activities get_activity get_activity_streams get_activity_files) do
      assert %{"inputSchema" => %{"type" => "object"}} = tools[name]
    end

    assert tools["get_activity_streams"]["inputSchema"]["required"] == [
             "id",
             "seconds_per_sample"
           ]
  end

  test "list_activities lists summaries on the dates when names, newest first", ctx do
    assert %{"period" => period, "activities" => activities} =
             ok!(ctx.token, "list_activities", %{"when" => @year})

    assert period == @year
    assert Enum.map(activities, & &1["id"]) == [ctx.run.id, ctx.ride.id, ctx.swim.id]

    assert %{
             "discipline" => "run",
             "local_date" => "2026-07-16",
             "duration_seconds" => 600,
             "source_file_id" => file_id,
             "session_id" => nil
           } = hd(activities)

    assert file_id == ctx.run.source_file_id
    refute Map.has_key?(hd(activities), "laps")

    assert %{"activities" => [%{"discipline" => "swim"}]} =
             ok!(ctx.token, "list_activities", %{"when" => @year, "discipline" => "swim"})

    assert %{"activities" => []} = ok!(ctx.token, "list_activities", %{"when" => "2026-07-15"})

    assert errors!(ctx.token, "list_activities", %{"when" => @year, "discipline" => "rowing"}) ==
             [{"discipline", "must be one of swim, bike, run, strength, other"}]

    assert errors!(ctx.token, "list_activities", %{"period" => @year}) ==
             [{"when", "is required"}, {"period", "is not a known field"}]
  end

  test "list_activities names each activity's session and can leave matched ones out", ctx do
    %{scope: scope, token: token, ride: ride} = ctx
    july = %{period: period(~D[2026-07-01], ~D[2026-07-31])}
    season = season_fixture(scope, july)
    phase = phase_fixture(scope, season, july)
    block = block_fixture(scope, phase, july)
    cycle_fixture(scope, block, %{period: period(~D[2026-07-13], ~D[2026-07-19])})

    session = session_fixture(scope, %{date: ~D[2026-07-14], planned_seconds: nil})
    {:ok, _session} = Vire.Training.match_session(scope, session.id, ride.id, "The ride")

    assert %{"activities" => [%{"id" => ride_id, "session_id" => session_id}]} =
             ok!(token, "list_activities", %{"when" => "2026-07-14"})

    assert {ride_id, session_id} == {ride.id, session.id}

    assert %{"activities" => activities} =
             ok!(token, "list_activities", %{"when" => @year, "unmatched" => true})

    assert Enum.map(activities, & &1["id"]) == [ctx.run.id, ctx.swim.id]
    assert %{"session_id" => ^session_id} = ok!(token, "get_activity", %{"id" => ride.id})
  end

  test "get_activity reads the summary with laps, lengths and the provider summary", ctx do
    assert %{"discipline" => "bike", "laps" => laps, "lengths" => [], "provider_summary" => nil} =
             ok!(ctx.token, "get_activity", %{"id" => ctx.ride.id})

    assert Enum.map(laps, & &1["lap_index"]) == [0, 1]
    assert %{"elapsed_seconds" => 240, "avg_power" => power} = hd(laps)
    assert is_integer(power)

    assert %{"pool_length_m" => 25.0, "laps" => laps, "lengths" => lengths} =
             ok!(ctx.token, "get_activity", %{"id" => ctx.swim.id})

    assert length(laps) == 5
    assert Enum.map(lengths, & &1["length_index"]) == Enum.to_list(0..13)
    assert %{"active" => true, "stroke" => "freestyle", "strokes" => strokes} = hd(lengths)
    assert is_integer(strokes)

    {:ok, provider} =
      Activities.upsert_provider_activity(ctx.scope, %{
        provider: :garmin,
        external_id: "4242",
        started_at: ~U[2026-08-01 06:00:00Z],
        utc_offset_seconds: 7200,
        local_date: ~D[2026-08-01],
        discipline: :run,
        duration_seconds: 1800,
        distance_m: 5000.0,
        training_load: 42.5,
        provider_summary: %{"activityName" => "Morning run"}
      })

    assert %{
             "provider" => "garmin",
             "training_load" => 42.5,
             "provider_summary" => %{"activityName" => "Morning run"}
           } = ok!(ctx.token, "get_activity", %{"id" => provider.id})

    assert %{"files" => [], "missing" => [%{"reason" => "No recorded file yet"}]} =
             ok!(ctx.token, "get_activity_files", %{"ids" => [provider.id]})
  end

  test "get_activity_streams reads chosen channels downsampled", ctx do
    assert %{"seconds_per_sample" => 60, "streams" => streams} =
             ok!(ctx.token, "get_activity_streams", %{
               "id" => ctx.ride.id,
               "channels" => ["power", "heart_rate", "nothing"],
               "seconds_per_sample" => 60
             })

    assert Map.keys(streams) == ["heart_rate", "power"]
    assert %{"unit" => "watts", "samples" => samples} = streams["power"]
    assert length(samples) == 10
    assert Enum.at(samples, 6) == nil

    assert %{"streams" => %{"position_lat" => %{"unit" => "degrees"}, "cadence" => _cadence}} =
             ok!(ctx.token, "get_activity_streams", %{
               "id" => ctx.run.id,
               "seconds_per_sample" => 600
             })

    for {args, errors} <- [
          {%{"seconds_per_sample" => 0}, [{"seconds_per_sample", "must be at least 1"}]},
          {%{"seconds_per_sample" => 1, "channels" => "power"}, [{"channels", "must be a list"}]},
          {%{"seconds_per_sample" => 1, "channels" => [1]}, [{"channels[0]", "must be a string"}]}
        ] do
      assert errors!(ctx.token, "get_activity_streams", Map.put(args, "id", ctx.ride.id)) ==
               errors
    end
  end

  test "get_activity_files answers URLs that download the original bytes", ctx do
    fit = fit_fixture("ride.fit")
    unknown = Ecto.UUID.generate()

    assert %{"files" => [link, _swim], "missing" => missing} =
             ok!(ctx.token, "get_activity_files", %{"ids" => [ctx.ride.id, unknown, ctx.swim.id]})

    assert missing == [%{"id" => unknown, "reason" => "Not found"}]

    assert %{
             "activity_id" => activity_id,
             "file_id" => file_id,
             "url" => url,
             "expires_at" => expires_at,
             "byte_size" => byte_size,
             "sha256" => sha256
           } = link

    assert {activity_id, file_id} == {ctx.ride.id, ctx.ride.source_file_id}
    assert byte_size == byte_size(fit)
    assert sha256 == :sha256 |> :crypto.hash(fit) |> Base.encode16(case: :lower)

    {:ok, expires_at, 0} = DateTime.from_iso8601(expires_at)
    assert DateTime.diff(expires_at, DateTime.utc_now()) in 890..900

    %URI{path: path, query: query} = URI.parse(url)
    conn = get(build_conn(), path <> "?" <> query)

    assert response(conn, 200) == fit
    assert get_resp_header(conn, "content-type") == ["application/vnd.ant.fit"]

    ids = for _ <- 1..51, do: Ecto.UUID.generate()

    assert errors!(ctx.token, "get_activity_files", %{"ids" => ids}) ==
             [{"ids", "must hold at most 50 items"}]
  end

  test "another user's activity or an unknown id is not found", ctx do
    other = scope_fixture()
    activity = activity_fixture(other, "ride.fit")

    for id <- [activity.id, Ecto.UUID.generate()] do
      assert error!(ctx.token, "get_activity", %{"id" => id}) == "Not found"
    end

    assert error!(ctx.token, "get_activity", %{"id" => "not-a-uuid"}) =~ "must be a UUID"

    assert %{"files" => [], "missing" => [%{"reason" => "Not found"}]} =
             ok!(ctx.token, "get_activity_files", %{"ids" => [activity.id]})

    assert error!(ctx.token, "get_activity_streams", %{
             "id" => activity.id,
             "seconds_per_sample" => 1
           }) == "Not found"

    assert %{"activities" => activities} =
             ok!(ctx.token, "list_activities", %{"when" => "2026-07-14"})

    assert Enum.map(activities, & &1["id"]) == [ctx.ride.id]
  end
end
