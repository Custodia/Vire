defmodule VireWeb.SyncController do
  use VireWeb, :controller

  alias Vire.Ingest

  def create(conn, _params) do
    case Ingest.sync_now(conn.assigns.current_scope) do
      {:ok, job} ->
        conn |> put_status(:accepted) |> json(%{job_id: job.id})

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
