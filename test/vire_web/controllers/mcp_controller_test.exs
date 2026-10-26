defmodule VireWeb.McpControllerTest do
  use VireWeb.ConnCase, async: true

  alias Vire.Mcp
  alias Vire.Mcp.Token
  alias Vire.Repo

  @metadata "http://localhost:4002/.well-known/oauth-protected-resource"

  setup do
    user = user_fixture()
    %{user: user, tokens: obtain_mcp_token(user)}
  end

  defp post_json(conn, body) do
    conn |> put_req_header("content-type", "application/json") |> post(~p"/mcp", body)
  end

  defp token(%{tokens: %{"access_token" => token}}), do: token

  defp request(method, params \\ %{}),
    do: %{jsonrpc: "2.0", id: 1, method: method, params: params}

  describe "the bearer check" do
    test "a request without a token is told where the metadata is", %{conn: conn} do
      for conn <- [conn, put_req_header(conn, "authorization", "Basic dXNlcjpwYXNz")] do
        conn = post_json(conn, Jason.encode!(request("ping")))

        assert json_response(conn, 401)

        assert get_resp_header(conn, "www-authenticate") == [
                 ~s(Bearer resource_metadata="#{@metadata}")
               ]
      end
    end

    test "an unknown, expired or revoked token is an invalid token",
         %{tokens: tokens} = context do
      assert_invalid = fn token ->
        conn = mcp_post(token, request("ping"))

        assert json_response(conn, 401)
        assert [header] = get_resp_header(conn, "www-authenticate")
        assert header =~ ~s(Bearer error="invalid_token")
        assert header =~ ~s(resource_metadata="#{@metadata}")
      end

      assert_invalid.("not-a-token")

      expiring = obtain_mcp_token(context.user)["access_token"]
      Repo.update_all(Token, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
      assert_invalid.(expiring)

      Repo.update_all(Token, set: [expires_at: DateTime.add(DateTime.utc_now(), 3600)])
      assert %{"result" => %{}} = mcp_request(token(context), "ping")

      token_request(%{
        "grant_type" => "refresh_token",
        "refresh_token" => tokens["refresh_token"],
        "client_id" => tokens["client"]["client_id"]
      })

      assert_invalid.(token(context))
    end

    test "a good token runs the request as the user over MCP with its client",
         %{user: user} = context do
      conn = mcp_post(token(context), request("ping"))

      assert json_response(conn, 200)
      client = Mcp.get_client(context.tokens["client"]["client_id"])

      assert %{user: %{id: user_id}, channel: :mcp, mcp_client_id: client_id} =
               conn.assigns.current_scope

      assert {user_id, client_id} == {user.id, client.id}
    end
  end

  describe "initialize" do
    test "negotiates the protocol version", context do
      for {asked, answered} <- [
            {"2025-06-18", "2025-06-18"},
            {"2025-11-25", "2025-06-18"},
            {"2025-03-26", "2025-03-26"},
            {"2024-11-05", "2025-06-18"},
            {nil, "2025-06-18"}
          ] do
        params = %{
          protocolVersion: asked,
          capabilities: %{},
          clientInfo: %{name: "t", version: "1"}
        }

        assert %{"result" => %{"protocolVersion" => ^answered}} =
                 mcp_request(token(context), "initialize", params)
      end
    end

    test "names the server and its capabilities, as JSON without a session", context do
      conn = mcp_post(token(context), request("initialize", %{protocolVersion: "2025-06-18"}))

      assert %{
               "capabilities" => %{"tools" => %{}, "resources" => %{}},
               "serverInfo" => %{"name" => "vire", "title" => "Vire", "version" => "0.1.0"}
             } = json_response(conn, 200)["result"]

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
      assert get_resp_header(conn, "mcp-session-id") == []
    end
  end

  describe "methods" do
    test "notifications and client responses are accepted without a body", context do
      for message <- [
            %{jsonrpc: "2.0", method: "notifications/initialized"},
            %{jsonrpc: "2.0", method: "notifications/cancelled", params: %{requestId: 1}},
            %{jsonrpc: "2.0", id: 7, result: %{}}
          ] do
        assert token(context) |> mcp_post(message) |> response(202) == ""
      end
    end

    test "ping, tools/list and the resource lists answer", context do
      token = token(context)

      assert %{"result" => %{}} = mcp_request(token, "ping")
      assert %{"result" => %{"tools" => [_ | _]}} = mcp_request(token, "tools/list")
      assert %{"result" => %{"resources" => []}} = mcp_request(token, "resources/list")

      assert %{"result" => %{"resourceTemplates" => []}} =
               mcp_request(token, "resources/templates/list")
    end

    test "reading a resource is not found", context do
      assert %{"error" => %{"code" => -32_002, "data" => %{"uri" => "vire://nothing"}}} =
               mcp_request(token(context), "resources/read", %{uri: "vire://nothing"})
    end

    test "an unknown tool or a call without a name is invalid params", context do
      token = token(context)

      assert %{"error" => %{"code" => -32_602, "message" => "Unknown tool: nothing"}} =
               mcp_request(token, "tools/call", %{name: "nothing", arguments: %{}})

      assert %{"error" => %{"code" => -32_602}} = mcp_request(token, "tools/call", %{})
      assert %{"error" => %{"code" => -32_602}} = mcp_request(token, "ping", [1])
    end

    test "an unknown method is not found", context do
      assert %{"error" => %{"code" => -32_601}} = mcp_request(token(context), "sampling/nothing")
    end
  end

  describe "malformed messages" do
    test "a body that is not JSON is a parse error", context do
      conn = mcp_post(token(context), "{not json")

      assert json_response(conn, 400) == %{
               "jsonrpc" => "2.0",
               "id" => nil,
               "error" => %{"code" => -32_700, "message" => "Parse error"}
             }
    end

    test "a batch or a message that is not JSON-RPC 2.0 is an invalid request", context do
      token = token(context)

      for body <- [
            [request("ping"), request("tools/list")],
            42,
            %{id: 3, method: "ping"},
            %{jsonrpc: "2.0", id: nil, method: "ping"},
            %{jsonrpc: "2.0", id: 4}
          ] do
        assert %{"error" => %{"code" => -32_600}} =
                 token |> mcp_post(body) |> json_response(400)
      end
    end

    test "a body over a megabyte is refused", context do
      body =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 1,
          method: "ping",
          params: %{pad: String.duplicate("x", 1_000_001)}
        })

      assert %{"error" => %{"code" => -32_600}} =
               token(context) |> mcp_post(body) |> json_response(413)
    end
  end

  describe "headers" do
    test "an Origin naming another host is forbidden", %{conn: conn} = context do
      for origin <- ["http://localhost:4002", "https://localhost"] do
        conn =
          conn |> put_req_header("origin", origin) |> mcp_post(token(context), request("ping"))

        assert json_response(conn, 200)
      end

      for origin <- ["https://evil.example", "null"] do
        conn =
          conn |> put_req_header("origin", origin) |> mcp_post(token(context), request("ping"))

        assert json_response(conn, 403)
      end

      conn = put_req_header(conn, "origin", "https://evil.example")
      assert conn |> post_json("{}") |> json_response(403)
    end

    test "an unsupported protocol version header is a bad request", %{conn: conn} = context do
      for version <- ["2025-06-18", "2025-03-26"] do
        conn =
          conn
          |> put_req_header("mcp-protocol-version", version)
          |> mcp_post(token(context), request("ping"))

        assert json_response(conn, 200)
      end

      conn =
        conn
        |> put_req_header("mcp-protocol-version", "2024-11-05")
        |> mcp_post(token(context), request("ping"))

      assert %{
               "id" => 1,
               "error" => %{"code" => -32_600, "data" => %{"requested" => "2024-11-05"}}
             } =
               json_response(conn, 400)

      conn =
        build_conn()
        |> put_req_header("mcp-protocol-version", "2024-11-05")
        |> mcp_post(token(context), request("initialize", %{protocolVersion: "2025-06-18"}))

      assert json_response(conn, 200)["result"]["protocolVersion"] == "2025-06-18"
    end
  end

  test "GET and DELETE answer 405", %{conn: conn} do
    for method <- [:get, :delete] do
      conn = dispatch(conn, @endpoint, method, ~p"/mcp")

      assert json_response(conn, 405)
      assert get_resp_header(conn, "allow") == ["POST"]
    end
  end
end
