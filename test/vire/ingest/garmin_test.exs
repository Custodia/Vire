defmodule Vire.Ingest.GarminTest do
  use Vire.DataCase, async: true

  import ExUnit.CaptureLog

  alias Vire.Accounts.Scope
  alias Vire.Ingest.Garmin
  alias Vire.Ingest.Garmin.Token

  @token_path "/personalapitoken-service/personal-api/personal-api-key/token"
  @search_path "/activitylist-service/activities/search/activities"

  setup do
    Req.Test.verify_on_exit!()
    user = user_fixture()
    connection = provider_connection_fixture(user, %{credential: "invented-key-#{user.id}"})
    %{scope: Scope.for_user(user), connection: connection}
  end

  defp jwt(expires_in) do
    claims = %{"exp" => System.os_time(:second) + expires_in, "scope" => ["CONNECT_READ"]}
    encode = &Base.url_encode64(Jason.encode!(&1), padding: false)
    encode.(%{"alg" => "none"}) <> "." <> encode.(claims) <> ".c2lnbmF0dXJl"
  end

  defp expect_token(token, test \\ self()) do
    Req.Test.expect(Garmin, fn %{request_path: @token_path} = conn ->
      send(test, {:token_request, conn.method, Plug.Conn.get_req_header(conn, "authorization")})
      Req.Test.text(conn, token)
    end)
  end

  defp summary(id), do: %{"activityId" => id, "activityName" => "Invented #{id}"}

  defp expect_page(ids, test \\ self()) do
    Req.Test.expect(Garmin, fn %{request_path: @search_path} = conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test, {:search, conn.query_params, Plug.Conn.get_req_header(conn, "authorization")})
      Req.Test.json(conn, Enum.map(ids, &summary/1))
    end)
  end

  describe "the token" do
    test "is exchanged from the API key with the ApiKey header", %{scope: scope} = context do
      token = jwt(24 * 3600)
      expect_token(token)

      assert {:ok, %Token{value: ^token}} = Garmin.token(scope, context.connection)

      expected_header = "ApiKey " <> context.connection.credential
      assert_received {:token_request, "POST", [^expected_header]}
    end

    test "is cached per connection while more than an hour remains", context do
      token = jwt(24 * 3600)
      expect_token(token)

      assert {:ok, %Token{value: ^token}} = Garmin.token(context.scope, context.connection)
      assert {:ok, %Token{value: ^token}} = Garmin.token(context.scope, context.connection)
    end

    test "is exchanged again once less than an hour remains", context do
      expiring = jwt(59 * 60)
      fresh = jwt(24 * 3600)
      expect_token(expiring)
      expect_token(fresh)

      assert {:ok, %Token{value: ^expiring}} = Garmin.token(context.scope, context.connection)
      assert {:ok, %Token{value: ^fresh}} = Garmin.token(context.scope, context.connection)
      assert {:ok, %Token{value: ^fresh}} = Garmin.token(context.scope, context.connection)
    end

    test "without a readable expiry lives 24 hours", context do
      expect_token("not-a-jwt\n")

      assert {:ok, %Token{value: "not-a-jwt", expires_at: expires_at}} =
               Garmin.token(context.scope, context.connection)

      assert_in_delta expires_at, System.os_time(:second) + 24 * 3600, 5
    end

    test "is exchanged again after the key changes", context do
      first = jwt(24 * 3600)
      second = jwt(24 * 3600)
      expect_token(first)
      expect_token(second)

      assert {:ok, %Token{value: ^first}} = Garmin.token(context.scope, context.connection)

      changed = %{context.connection | credential: "another-invented-key"}
      assert {:ok, %Token{value: ^second}} = Garmin.token(context.scope, changed)
    end

    test "is refused for a key Garmin refuses", context do
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 401, ""))

      assert Garmin.token(context.scope, context.connection) == {:error, {:key_refused, 401}}
    end

    test "is not exchanged for another user's connection", context do
      other = Scope.for_user(user_fixture())

      assert_raise FunctionClauseError, fn -> Garmin.token(other, context.connection) end
    end

    test "and the key show in no inspected value or log line", context do
      token = jwt(24 * 3600)
      expect_token(token)

      log =
        capture_log(fn ->
          {:ok, inspected} = Garmin.token(context.scope, context.connection)
          refute inspect(inspected) =~ token
          refute inspect(context.connection) =~ context.connection.credential
        end)

      refute log =~ token
      refute log =~ context.connection.credential
    end
  end

  describe "the activity search" do
    test "asks for the dates with the bearer token", context do
      token = jwt(24 * 3600)
      expect_token(token)
      expect_page([1001, 1002])

      assert {:ok, [%{"activityId" => 1001}, %{"activityId" => 1002}]} =
               Garmin.search_activities(
                 context.scope,
                 context.connection,
                 ~D[2026-07-01],
                 ~D[2026-07-31]
               )

      expected_header = "Bearer " <> token
      assert_received {:search, params, [^expected_header]}

      assert %{
               "startDate" => "2026-07-01",
               "endDate" => "2026-07-31",
               "start" => "0",
               "limit" => "99"
             } = params
    end

    test "follows pages of 99 until a short page", context do
      expect_token(jwt(24 * 3600))
      expect_page(Enum.to_list(1..99))
      expect_page(Enum.to_list(100..198))
      expect_page([199])

      assert {:ok, summaries} =
               Garmin.search_activities(
                 context.scope,
                 context.connection,
                 ~D[2026-01-01],
                 ~D[2026-12-31]
               )

      assert Enum.map(summaries, & &1["activityId"]) == Enum.to_list(1..199)
      assert_received {:search, %{"start" => "0"}, _}
      assert_received {:search, %{"start" => "99"}, _}
      assert_received {:search, %{"start" => "198"}, _}
    end

    test "after a full page asks once more and stops on an empty one", context do
      expect_token(jwt(24 * 3600))
      expect_page(Enum.to_list(1..99))
      expect_page([])

      assert {:ok, summaries} =
               Garmin.search_activities(
                 context.scope,
                 context.connection,
                 ~D[2026-01-01],
                 ~D[2026-12-31]
               )

      assert length(summaries) == 99
    end

    test "after a 401 exchanges the key again and retries with the new token", context do
      stale = jwt(24 * 3600)
      fresh = jwt(24 * 3600)
      expect_token(stale)
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 401, ""))
      expect_token(fresh)
      expect_page([7])

      assert {:ok, [%{"activityId" => 7}]} =
               Garmin.search_activities(
                 context.scope,
                 context.connection,
                 ~D[2026-07-01],
                 ~D[2026-07-31]
               )

      expected_header = "Bearer " <> fresh
      assert_received {:search, _params, [^expected_header]}
      assert {:ok, %Token{value: ^fresh}} = Garmin.token(context.scope, context.connection)
    end

    test "after a 401 to the fresh token too drops it and names the status", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 401, ""))
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 401, ""))
      fresh = jwt(24 * 3600)
      expect_token(fresh)

      assert Garmin.search_activities(
               context.scope,
               context.connection,
               ~D[2026-07-01],
               ~D[2026-07-31]
             ) == {:error, {:status, 401}}

      assert {:ok, %Token{value: ^fresh}} = Garmin.token(context.scope, context.connection)
    end

    test "after a 401 a refused key is named as refused", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 401, ""))
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 403, ""))

      assert Garmin.search_activities(
               context.scope,
               context.connection,
               ~D[2026-07-01],
               ~D[2026-07-31]
             ) == {:error, {:key_refused, 403}}
    end

    test "retries a 429 and succeeds", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 429, ""))
      expect_page([1001])

      assert {:ok, [%{"activityId" => 1001}]} =
               Garmin.search_activities(
                 context.scope,
                 context.connection,
                 ~D[2026-07-01],
                 ~D[2026-07-31]
               )
    end

    test "gives up on a 500 after three retries", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, 4, &Plug.Conn.send_resp(&1, 500, ""))

      assert Garmin.search_activities(
               context.scope,
               context.connection,
               ~D[2026-07-01],
               ~D[2026-07-31]
             ) == {:error, {:status, 500}}
    end

    test "names a transport failure", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, 4, &Req.Test.transport_error(&1, :timeout))

      assert Garmin.search_activities(
               context.scope,
               context.connection,
               ~D[2026-07-01],
               ~D[2026-07-31]
             ) == {:error, {:transport, :timeout}}
    end

    test "refuses an answer that is not a list", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, &Req.Test.json(&1, %{"error" => "invented"}))

      assert Garmin.search_activities(
               context.scope,
               context.connection,
               ~D[2026-07-01],
               ~D[2026-07-31]
             ) == {:error, :unexpected_body}
    end

    test "with a refused key never searches", context do
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 403, ""))

      assert Garmin.search_activities(
               context.scope,
               context.connection,
               ~D[2026-07-01],
               ~D[2026-07-31]
             ) == {:error, {:key_refused, 403}}
    end
  end

  describe "the activity download" do
    defp zip(entries) do
      {:ok, {_name, archive}} =
        :zip.create(~c"activity.zip", Enum.map(entries, fn {n, c} -> {~c"#{n}", c} end), [
          :memory
        ])

      archive
    end

    defp expect_download(archive, test \\ self()) do
      Req.Test.expect(Garmin, fn conn ->
        send(test, {:download, conn.request_path})

        conn
        |> Plug.Conn.put_resp_content_type("application/x-zip-compressed")
        |> Plug.Conn.send_resp(200, archive)
      end)
    end

    test "answers the .fit file inside the ZIP", context do
      fit = fit_fixture("ride.fit")
      expect_token(jwt(24 * 3600))
      expect_download(zip([{"20000001_ACTIVITY.fit", fit}]))

      assert Garmin.download_activity_file(context.scope, context.connection, 20_000_001) ==
               {:ok, fit}

      assert_received {:download, "/download-service/files/activity/20000001"}
    end

    test "finds the .fit file among other entries", context do
      fit = fit_fixture("run.fit")
      expect_token(jwt(24 * 3600))
      expect_download(zip([{"readme.txt", "invented"}, {"20000002_ACTIVITY.FIT", fit}]))

      assert Garmin.download_activity_file(context.scope, context.connection, "20000002") ==
               {:ok, fit}
    end

    test "refuses an archive without a .fit file", context do
      expect_token(jwt(24 * 3600))
      expect_download(zip([{"readme.txt", "invented"}]))

      assert Garmin.download_activity_file(context.scope, context.connection, 20_000_003) ==
               {:error, :no_fit_file}
    end

    test "refuses an answer that is not a ZIP", context do
      expect_token(jwt(24 * 3600))
      expect_download("not a zip")

      assert Garmin.download_activity_file(context.scope, context.connection, 20_000_004) ==
               {:error, :no_fit_file}
    end

    test "names the status of a failed download", context do
      expect_token(jwt(24 * 3600))
      Req.Test.expect(Garmin, &Plug.Conn.send_resp(&1, 404, ""))

      assert Garmin.download_activity_file(context.scope, context.connection, 20_000_005) ==
               {:error, {:status, 404}}
    end
  end
end
