defmodule VireWeb.McpController do
  use VireWeb, :controller

  alias Vire.Mcp.Server

  @max_body 1_000_000

  def create(conn, _params) do
    case read_body(conn, length: @max_body) do
      {:ok, body, conn} ->
        conn |> decode(body) |> answer(conn)

      {:more, _partial, conn} ->
        conn
        |> put_status(:request_entity_too_large)
        |> json(Server.error(nil, -32_600, "Invalid request: the body is too large"))
    end
  end

  def method_not_allowed(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> put_status(:method_not_allowed)
    |> json(%{errors: %{detail: "Method Not Allowed"}})
  end

  defp decode(conn, body) do
    case Jason.decode(body) do
      {:ok, message} when is_map(message) ->
        with :ok <- check_protocol_version(conn, message) do
          Server.handle(conn.assigns.current_scope, message)
        end

      {:ok, messages} when is_list(messages) ->
        {:invalid, Server.error(nil, -32_600, "Invalid request: batches are not supported")}

      {:ok, message} ->
        {:invalid, Server.invalid_request(message)}

      {:error, _reason} ->
        {:invalid, Server.error(nil, -32_700, "Parse error")}
    end
  end

  defp check_protocol_version(_conn, %{"method" => "initialize"}), do: :ok

  defp check_protocol_version(conn, message) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] ->
        :ok

      [version] ->
        if version in Server.protocol_versions(),
          do: :ok,
          else: {:invalid, unsupported_version(message, version)}

      _versions ->
        {:invalid, unsupported_version(message, nil)}
    end
  end

  defp unsupported_version(message, version) do
    Server.error(message["id"], -32_600, "Unsupported protocol version", %{
      requested: version,
      supported: Server.protocol_versions()
    })
  end

  defp answer({:reply, response}, conn), do: json(conn, response)
  defp answer(:accepted, conn), do: send_resp(conn, :accepted, "")
  defp answer({:invalid, response}, conn), do: conn |> put_status(:bad_request) |> json(response)
end
