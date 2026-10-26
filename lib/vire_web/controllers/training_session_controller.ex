defmodule VireWeb.TrainingSessionController do
  use VireWeb, :controller

  alias Vire.Activities
  alias Vire.Training

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Training.get_session(scope, id) do
      nil ->
        conn |> put_status(:not_found) |> put_view(VireWeb.ErrorJSON) |> render(:"404")

      session ->
        activity = session.activity_id && Activities.get_activity(scope, session.activity_id)
        render(conn, :show, session: session, activity: activity)
    end
  end
end
