defmodule VireWeb.OAuthTokenController do
  use VireWeb, :controller

  alias Vire.Mcp

  def create(conn, %{"grant_type" => "authorization_code"} = params) do
    with {:ok, [client_id, code, verifier, redirect_uri]} <-
           require_params(params, ~w(client_id code code_verifier redirect_uri)) do
      Mcp.exchange_authorization_code(client_id, code, verifier, redirect_uri)
    end
    |> respond(conn)
  end

  def create(conn, %{"grant_type" => "refresh_token"} = params) do
    with {:ok, [client_id, refresh_token]} <- require_params(params, ~w(client_id refresh_token)) do
      Mcp.refresh_access_token(client_id, refresh_token)
    end
    |> respond(conn)
  end

  def create(conn, %{"grant_type" => grant_type}) when is_binary(grant_type),
    do: respond({:error, :unsupported_grant_type}, conn)

  def create(conn, _params), do: respond({:error, {:invalid_request, "grant_type"}}, conn)

  defp require_params(params, names) do
    case Enum.find(names, &(not is_binary(params[&1]) or params[&1] == "")) do
      nil -> {:ok, Enum.map(names, &params[&1])}
      missing -> {:error, {:invalid_request, missing}}
    end
  end

  defp respond(result, conn) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")

    case result do
      {:ok, tokens} ->
        json(conn, %{
          access_token: tokens.access_token,
          token_type: "Bearer",
          expires_in: tokens.expires_in,
          refresh_token: tokens.refresh_token
        })

      {:error, {:invalid_request, missing}} ->
        error(conn, 400, "invalid_request", "#{missing} is required")

      {:error, :invalid_client} ->
        error(conn, 401, "invalid_client", "The client is not registered")

      {:error, :invalid_grant} ->
        error(conn, 400, "invalid_grant", "The grant is invalid, expired or already used")

      {:error, :unsupported_grant_type} ->
        error(conn, 400, "unsupported_grant_type", "The grant type is not supported")
    end
  end

  defp error(conn, status, error, description) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end
end
