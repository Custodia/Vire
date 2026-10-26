defmodule VireWeb.OAuthAuthorizationController do
  use VireWeb, :html_controller

  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Mcp
  alias Vire.Mcp.AuthorizationRequest
  alias VireWeb.OAuthURL

  def new(conn, params) do
    with {:ok, request} <- authorization_request(conn, params) do
      case conn.assigns.current_scope do
        %Scope{} -> render_consent(conn, request)
        nil -> render_sign_in(conn, request, nil)
      end
    end
  end

  def sign_in(conn, params) do
    with {:ok, request} <- authorization_request(conn, params) do
      case Accounts.get_user_by_email_and_password(
             to_string(params["email"]),
             to_string(params["password"])
           ) do
        nil ->
          conn
          |> put_status(:unauthorized)
          |> render_sign_in(request, "Invalid email or password")

        user ->
          conn
          |> configure_session(renew: true)
          |> clear_session()
          |> put_session(:user_id, user.id)
          |> redirect(to: "/oauth/authorize?" <> URI.encode_query(request.params))
      end
    end
  end

  def create(conn, params) do
    with {:ok, request} <- authorization_request(conn, params) do
      case {conn.assigns.current_scope, params["decision"]} do
        {nil, _decision} ->
          render_sign_in(conn, request, nil)

        {%Scope{} = scope, "approve"} ->
          {:ok, code} = Mcp.create_authorization_code(scope, request)
          redirect(conn, external: AuthorizationRequest.redirect_to(request, %{"code" => code}))

        {%Scope{}, _deny} ->
          redirect(conn,
            external: AuthorizationRequest.redirect_to(request, %{"error" => "access_denied"})
          )
      end
    end
  end

  defp authorization_request(conn, params) do
    case AuthorizationRequest.new(params, OAuthURL.resource()) do
      {:ok, request} ->
        {:ok, request}

      {:error, {:redirect, uri}} ->
        redirect(conn, external: uri)

      {:error, {:page, message}} ->
        conn
        |> put_status(:bad_request)
        |> render(:error, page_title: "Cannot continue", message: message)
    end
  end

  defp render_sign_in(conn, request, error) do
    render(conn, :sign_in, page_title: "Sign in", request: request, error: error)
  end

  defp render_consent(conn, request) do
    render(conn, :consent,
      page_title: "Allow access",
      request: request,
      user: conn.assigns.current_scope.user,
      return_host: URI.parse(request.redirect_uri).host
    )
  end
end
