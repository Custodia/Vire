defmodule Vire.Mcp.Server do
  @moduledoc """
  Answers one JSON-RPC 2.0 message of the Model Context Protocol for a scope.
  A request gets a response, a notification or a client's response gets
  nothing, and a message that is neither is invalid.
  """

  require Logger

  alias Vire.Accounts.Scope
  alias Vire.Mcp.Tool
  alias Vire.Mcp.Tools

  @latest "2025-06-18"
  @versions [@latest, "2025-03-26"]

  @doc "The protocol versions the server speaks, newest first."
  def protocol_versions, do: @versions

  @spec handle(Scope.t(), map()) :: {:reply, map()} | :accepted | {:invalid, map()}
  def handle(%Scope{} = scope, %{"jsonrpc" => "2.0", "method" => method} = message)
      when is_binary(method) do
    case message do
      %{"id" => id} when is_binary(id) or is_integer(id) ->
        {:reply, respond(id, call(scope, method, Map.get(message, "params", %{})))}

      %{"id" => id} ->
        {:invalid, error(id, -32_600, "Invalid request: the id must be a string or an integer")}

      _notification ->
        :accepted
    end
  end

  def handle(%Scope{}, %{"jsonrpc" => "2.0", "id" => _id} = message)
      when is_map_key(message, "result") or is_map_key(message, "error"),
      do: :accepted

  def handle(%Scope{}, message), do: {:invalid, invalid_request(message)}

  @doc "The error answering a message that is not a JSON-RPC 2.0 message."
  def invalid_request(message) do
    id = if is_map(message), do: Map.get(message, "id")
    error(id, -32_600, "Invalid request")
  end

  @doc "A JSON-RPC error response."
  def error(id, code, message, data \\ nil) do
    error = %{code: code, message: message}
    error = if data, do: Map.put(error, :data, data), else: error
    %{jsonrpc: "2.0", id: id, error: error}
  end

  defp respond(id, {:ok, result}), do: %{jsonrpc: "2.0", id: id, result: result}
  defp respond(id, {:error, code, message}), do: error(id, code, message)
  defp respond(id, {:error, code, message, data}), do: error(id, code, message, data)

  defp call(scope, method, nil), do: call(scope, method, %{})

  defp call(_scope, _method, params) when not is_map(params),
    do: {:error, -32_602, "Invalid params: params must be an object"}

  defp call(_scope, "initialize", params) do
    {:ok,
     %{
       protocolVersion: negotiate(params["protocolVersion"]),
       capabilities: %{tools: %{listChanged: false}, resources: %{listChanged: false}},
       serverInfo: %{
         name: "vire",
         title: "Vire",
         version: :vire |> Application.spec(:vsn) |> to_string()
       }
     }}
  end

  defp call(_scope, "ping", _params), do: {:ok, %{}}

  defp call(_scope, "tools/list", _params),
    do: {:ok, %{tools: Enum.map(Tools.all(), &Tool.describe/1)}}

  defp call(scope, "tools/call", %{"name" => name} = params) when is_binary(name) do
    case {Tools.fetch(name), Map.get(params, "arguments") || %{}} do
      {:error, _arguments} ->
        {:error, -32_602, "Unknown tool: #{name}"}

      {{:ok, _tool}, arguments} when not is_map(arguments) ->
        {:error, -32_602, "Invalid params: arguments must be an object"}

      {{:ok, tool}, arguments} ->
        run(tool, scope, arguments)
    end
  end

  defp call(_scope, "tools/call", _params),
    do: {:error, -32_602, "Invalid params: a tool name is required"}

  defp call(_scope, "resources/list", _params), do: {:ok, %{resources: []}}

  defp call(_scope, "resources/templates/list", _params), do: {:ok, %{resourceTemplates: []}}

  defp call(_scope, "resources/read", params),
    do: {:error, -32_002, "Resource not found", %{uri: params["uri"]}}

  defp call(_scope, method, _params), do: {:error, -32_601, "Method not found: #{method}"}

  defp negotiate(version) when is_binary(version) and version >= @latest, do: @latest
  defp negotiate("2025-03-26"), do: "2025-03-26"
  defp negotiate(_version), do: @latest

  defp run(tool, scope, arguments) do
    {:ok, Tool.call(tool, scope, arguments)}
  rescue
    exception ->
      Logger.error(
        "MCP tool #{tool.name} raised: " <> Exception.format(:error, exception, __STACKTRACE__)
      )

      {:error, -32_603, "Internal error"}
  end
end
