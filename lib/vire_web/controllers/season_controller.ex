defmodule VireWeb.SeasonController do
  use VireWeb, :controller

  alias Vire.Training

  def index(conn, _params) do
    render(conn, :index, seasons: Training.list_seasons(conn.assigns.current_scope))
  end

  def show(conn, %{"id" => id}) do
    case Training.get_plan(conn.assigns.current_scope, id) do
      nil ->
        conn |> put_status(:not_found) |> put_view(VireWeb.ErrorJSON) |> render(:"404")

      season ->
        render(conn, :show,
          season: season,
          unmatched: Training.list_unmatched_activities(conn.assigns.current_scope, season.period)
        )
    end
  end
end
