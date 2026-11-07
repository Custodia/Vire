defmodule Vire.Ingest.SyncWorker do
  @moduledoc """
  Runs one user's Garmin sync, of every season or of the seasons' dates
  within `first` and `last`, and records it on the run with `run_id`. One sync
  per user waits at a time.
  """

  use Oban.Worker,
    queue: :garmin,
    max_attempts: 3,
    unique: [keys: [:user_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Vire.Ingest.GarminSync
  alias Vire.Ingest.SyncRuns
  alias Vire.Training.Period

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "run_id" => run_id} = args} = job) do
    SyncRuns.start(run_id)

    result =
      with {:ok, scope, connection} <- GarminSync.connected(user_id) do
        GarminSync.run(scope, connection, range(args), Date.utc_today(), run_id)
      end

    record(result, job)
    result
  rescue
    exception ->
      if last_attempt?(job), do: SyncRuns.fail(run_id, Exception.message(exception))
      reraise exception, __STACKTRACE__
  end

  defp record(:ok, %{args: %{"run_id" => run_id}}), do: SyncRuns.searched(run_id)

  defp record({:cancel, reason}, %{args: %{"run_id" => run_id}}),
    do: SyncRuns.fail(run_id, message(reason))

  defp record({:error, reason}, %{args: %{"run_id" => run_id}} = job) do
    if last_attempt?(job),
      do: SyncRuns.fail(run_id, message(reason)),
      else: SyncRuns.retrying(run_id, message(reason))
  end

  defp message(reason) when is_binary(reason), do: reason
  defp message(reason), do: inspect(reason)

  defp last_attempt?(%Oban.Job{attempt: attempt, max_attempts: max}), do: attempt >= max

  defp range(%{"first" => first, "last" => last}) when is_binary(first) and is_binary(last),
    do: Period.new(Date.from_iso8601!(first), Date.from_iso8601!(last))

  defp range(_args), do: nil
end
