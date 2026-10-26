defmodule VireWeb.McpAuth do
  @moduledoc """
  Plugs in front of the MCP endpoint: the `Origin` check, and the bearer check
  that assigns the access token's scope as `:current_scope`. A refused token
  answers 401 with a `WWW-Authenticate` header pointing at the protected
  resource metadata, where a client finds the authorization server.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Vire.Mcp
  alias VireWeb.OAuthURL

  @refused "The access token is invalid, expired or revoked"

  @doc """
  Answers 403 to a request whose `Origin` header names a host other than the
  endpoint's. A request without the header passes.
  """
  def check_origin(conn, _opts) do
    case get_req_header(conn, "origin") do
      [] ->
        conn

      [origin] ->
        if URI.parse(origin).host == VireWeb.Endpoint.host(), do: conn, else: forbid(conn)

      _origins ->
        forbid(conn)
    end
  end

  @doc "Assigns the scope of the request's bearer token, or answers 401."
  def require_mcp_token(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, scope} <- Mcp.fetch_scope(token) do
      assign(conn, :current_scope, scope)
    else
      :missing ->
        challenge(conn, "", "An access token is required")

      :error ->
        challenge(
          conn,
          ~s(error="invalid_token", error_description="#{@refused}", ),
          @refused
        )
    end
  end

  defp bearer_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(~r/\ABearer +(\S+) *\z/i, header) do
      {:ok, token}
    else
      _missing -> :missing
    end
  end

  defp challenge(conn, error, detail) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer #{error}resource_metadata="#{OAuthURL.resource_metadata()}")
    )
    |> put_status(:unauthorized)
    |> json(%{errors: %{detail: detail}})
    |> halt()
  end

  defp forbid(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{errors: %{detail: "The Origin header names another host"}})
    |> halt()
  end
end
