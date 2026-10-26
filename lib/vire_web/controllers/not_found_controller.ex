defmodule VireWeb.NotFoundController do
  use VireWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_format("json")
    |> put_view(VireWeb.ErrorJSON)
    |> render(:"404")
  end
end
