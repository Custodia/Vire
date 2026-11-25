defmodule Vire.Ingest.SyncWorker do
  @moduledoc """
  Runs one user's Garmin sync, of every season or of the seasons' dates
  within `first` and `last`. One sync per user waits at a time.
  """

  use Oban.Worker,
    queue: :garmin,
    max_attempts: 3,
    unique: [keys: [:user_id], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Vire.Ingest.GarminSync
  alias Vire.Training.Period

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    with {:ok, scope, connection} <- GarminSync.connected(user_id) do
      GarminSync.run(scope, connection, range(args), Date.utc_today())
    end
  end

  defp range(%{"first" => first, "last" => last}) when is_binary(first) and is_binary(last),
    do: Period.new(Date.from_iso8601!(first), Date.from_iso8601!(last))

  defp range(_args), do: nil
end
