defmodule VireWeb.Auth do
  @moduledoc """
  Plugs that put the signed-in user's scope on the connection and keep
  anonymous requests out of authenticated routes.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Vire.Accounts
  alias Vire.Accounts.Scope

  @doc "Assigns `:current_scope` from the session's user, or `nil` without one."
  def fetch_current_scope(conn, _opts) do
    user =
      case get_session(conn, :user_id) do
        nil -> nil
        user_id -> Accounts.get_user(user_id)
      end

    assign(conn, :current_scope, Scope.for_user(user))
  end

  @doc "Answers 401 unless a user is signed in."
  def require_authenticated(%{assigns: %{current_scope: %Scope{}}} = conn, _opts), do: conn

  def require_authenticated(conn, _opts) do
    conn
    |> put_status(:unauthorized)
    |> put_view(VireWeb.ErrorJSON)
    |> render(:"401")
    |> halt()
  end
end
