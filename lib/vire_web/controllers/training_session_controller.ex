defmodule VireWeb.TrainingSessionController do
  use VireWeb, :controller

  alias Vire.Activities
  alias Vire.Training
  alias Vire.Training.Session

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Training.get_session(scope, id) do
      nil ->
        not_found(conn)

      session ->
        render(conn, :show,
          session: session,
          activity: session.activity_id && Activities.get_activity(scope, session.activity_id),
          previous: previous(scope, session)
        )
    end
  end

  def match(conn, %{"id" => id} = params) do
    activity_id = params["activity_id"]
    rationale = if activity_id, do: "Matched on the dashboard", else: "Unmatched on the dashboard"

    case Training.match_session(conn.assigns.current_scope, id, activity_id, rationale) do
      {:ok, _session} ->
        show(conn, %{"id" => id})

      {:error, :not_found} ->
        not_found(conn)

      {:error, :different_date} ->
        unprocessable(conn, "the activity is on another date")

      {:error, %Ecto.Changeset{}} ->
        unprocessable(conn, "the activity is matched to another session")
    end
  end

  defp previous(scope, session) do
    with %Session{} = previous <- Training.get_previous_session(scope, session) do
      {previous, Activities.get_activity(scope, previous.activity_id)}
    end
  end

  defp not_found(conn),
    do: conn |> put_status(:not_found) |> put_view(VireWeb.ErrorJSON) |> render(:"404")

  defp unprocessable(conn, message),
    do: conn |> put_status(:unprocessable_entity) |> json(%{errors: %{detail: message}})
end
