defmodule VireWeb.McpClient do
  @moduledoc """
  Calls the MCP endpoint as a client holding an access token from
  `VireWeb.OAuthFlow.obtain_mcp_token/1`.
  """

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint VireWeb.Endpoint

  @doc "Posts `body`, a map encoded as JSON or a raw string, to /mcp with `token`."
  def mcp_post(conn \\ build_conn(), token, body) do
    body = if is_binary(body), do: body, else: Jason.encode!(body)

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", body)
  end

  @doc "Sends a JSON-RPC request and answers the decoded response."
  def mcp_request(token, method, params \\ %{}) do
    id = System.unique_integer([:positive])

    response =
      token
      |> mcp_post(%{jsonrpc: "2.0", id: id, method: method, params: params})
      |> json_response(200)

    %{"jsonrpc" => "2.0", "id" => ^id} = response
  end

  @doc "Calls a tool and answers its result."
  def call_tool(token, name, arguments \\ %{}) do
    %{"result" => result} = mcp_request(token, "tools/call", %{name: name, arguments: arguments})
    result
  end
end
