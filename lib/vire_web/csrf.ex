defmodule VireWeb.CSRF do
  @moduledoc """
  CSRF protection for the API. The session holds a token, and every request
  other than a GET, HEAD or OPTIONS carries it in the `x-csrf-token` header.
  """

  import Plug.Conn
  import Phoenix.Controller

  @protection Plug.CSRFProtection.init([])

  @doc "Answers 403 to an unsafe request that does not carry the session's token."
  def require_csrf_token(conn, _opts) do
    Plug.CSRFProtection.call(conn, @protection)
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError ->
      conn
      |> put_status(:forbidden)
      |> json(%{
        reason: "invalid_csrf_token",
        errors: %{detail: "The request does not carry the session's CSRF token"}
      })
      |> halt()
  end

  @doc "Ends the session's token; the session holds none until one is asked for."
  def drop_token, do: Plug.CSRFProtection.delete_csrf_token()
end
