defmodule VireWeb.SyncJSON do
  @moduledoc """
  The state of a user's Garmin sync, as the API answers it and the user
  channel pushes it.
  """

  alias Vire.Ingest.SyncRun
  alias VireWeb.TrainingJSON

  @doc """
  The connection's state and last sync, and the run with its file counts and
  the activities it found, each with the session it is matched to.
  """
  def status(%{status: status}) do
    %{
      connection: status.connection,
      last_synced_at: status.last_synced_at,
      run: status.run && run(status.run, status.activities)
    }
  end

  defp run(%SyncRun{} = run, activities) do
    %{
      id: run.id,
      trigger: run.trigger,
      state: run.state,
      error: run.error,
      queued_at: run.inserted_at,
      started_at: run.started_at,
      finished_at: run.finished_at,
      files: %{total: run.files_total, fetched: run.files_fetched, failed: run.files_failed},
      activities: Enum.map(activities, &activity/1)
    }
  end

  defp activity(%{activity: activity, session: session}) do
    activity
    |> TrainingJSON.activity_summary()
    |> Map.merge(%{
      local_date: activity.local_date,
      session: session && %{id: session.id, title: TrainingJSON.title(session)}
    })
  end
end
