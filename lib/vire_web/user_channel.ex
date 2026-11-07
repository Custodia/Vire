defmodule VireWeb.UserChannel do
  @moduledoc """
  The live updates of the signed-in user, on `user:<id>`. Every event of
  `Vire.Events` is pushed as the JSON the API answers for what changed:
  `sync` with the Garmin sync's state and `upload` with a file's status.
  """

  use Phoenix.Channel

  alias Vire.Activities
  alias Vire.Events
  alias Vire.Ingest
  alias VireWeb.SyncJSON
  alias VireWeb.UploadJSON

  @impl true
  def join("user:" <> user_id, _payload, %{assigns: %{scope: scope}} = socket) do
    if user_id == scope.user.id do
      :ok = Events.subscribe(scope)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:sync_run, run}, socket) do
    status = Ingest.sync_status(socket.assigns.scope, run)
    push(socket, "sync", SyncJSON.status(%{status: status}))
    {:noreply, socket}
  end

  def handle_info({:source_file, file}, socket) do
    activity = Activities.get_activity_by_source_file(socket.assigns.scope, file.id)
    push(socket, "upload", UploadJSON.show(%{file: file, activity: activity}))
    {:noreply, socket}
  end
end
