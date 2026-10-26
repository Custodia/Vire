defmodule Vire.Ingest.DownloadWorker do
  @moduledoc """
  Downloads the original file of one activity from Garmin. One download per
  activity is kept: a download that was cancelled or used up its attempts is
  not queued again until its job is pruned.
  """

  use Oban.Worker,
    queue: :garmin,
    max_attempts: 5,
    unique: [
      keys: [:activity_id],
      states: [:available, :scheduled, :executing, :retryable, :cancelled, :discarded],
      period: :infinity
    ]

  alias Vire.Activities
  alias Vire.Ingest.GarminSync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "activity_id" => activity_id}}) do
    with {:ok, scope, connection} <- GarminSync.connected(user_id) do
      case Activities.get_activity(scope, activity_id) do
        nil -> {:cancel, "the activity no longer exists"}
        activity -> GarminSync.download(scope, connection, activity)
      end
    end
  end
end
