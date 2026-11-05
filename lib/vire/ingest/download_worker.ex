defmodule Vire.Ingest.DownloadWorker do
  @moduledoc """
  Downloads the original file of one activity from Garmin, and counts it on
  the run with `run_id` once it is fetched or given up on. One download per
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
  alias Vire.Ingest.SyncRuns

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"user_id" => user_id, "activity_id" => activity_id, "run_id" => run_id}
        } = job
      ) do
    result =
      with {:ok, scope, connection} <- GarminSync.connected(user_id) do
        case Activities.get_activity(scope, activity_id) do
          nil -> {:cancel, "the activity no longer exists"}
          activity -> GarminSync.download(scope, connection, activity)
        end
      end

    case outcome(result, job) do
      nil -> :ok
      outcome -> SyncRuns.file_done(run_id, outcome)
    end

    result
  rescue
    exception ->
      if last_attempt?(job), do: SyncRuns.file_done(run_id, :failed)
      reraise exception, __STACKTRACE__
  end

  defp outcome(:ok, _job), do: :fetched
  defp outcome({:cancel, _reason}, _job), do: :failed
  defp outcome({:error, _reason}, job), do: if(last_attempt?(job), do: :failed)

  defp last_attempt?(%Oban.Job{attempt: attempt, max_attempts: max}), do: attempt >= max
end
