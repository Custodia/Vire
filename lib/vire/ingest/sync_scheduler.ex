defmodule Vire.Ingest.SyncScheduler do
  @moduledoc "Enqueues a Garmin sync for every user whose connection is not paused."

  use Oban.Worker, queue: :default, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Vire.Ingest.enqueue_scheduled_syncs()
    :ok
  end
end
