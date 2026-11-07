defmodule VireWeb.SyncController do
  use VireWeb, :controller

  alias Vire.Ingest

  def show(conn, _params),
    do: render(conn, :status, status: Ingest.sync_status(conn.assigns.current_scope))

  def create(conn, _params) do
    scope = conn.assigns.current_scope

    case Ingest.sync_now(scope) do
      {:ok, run} ->
        conn |> put_status(:accepted) |> render(:status, status: Ingest.sync_status(scope, run))

      {:error, :not_connected} ->
        conflict(conn, "not_connected", "No Garmin connection is set up")

      {:error, :paused} ->
        conflict(conn, "paused", "The Garmin connection is paused")

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> put_view(VireWeb.ErrorJSON)
        |> render(:"500")
    end
  end

  defp conflict(conn, reason, detail) do
    conn |> put_status(:conflict) |> json(%{reason: reason, errors: %{detail: detail}})
  end
end
