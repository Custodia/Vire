defmodule VireWeb.MeController do
  use VireWeb, :controller

  def show(conn, _params) do
    conn
    |> put_view(VireWeb.UserJSON)
    |> render(:show, user: conn.assigns.current_scope.user)
  end
end
