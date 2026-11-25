defmodule Vire.Ingest.ParseWorker do
  @moduledoc """
  Parses one source file into its activity, and counts it on the sync run
  with `run_id`, when the job names one, once it is parsed or given up on.
  One job per file waits or runs at a time.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 3,
    unique: [keys: [:source_file_id], states: :incomplete, period: :infinity]

  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Ingest
  alias Vire.Ingest.SyncRuns

  @processor_version 1

  @doc "The version stored on every file this worker parses."
  def processor_version, do: @processor_version

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_file_id" => file_id, "user_id" => user_id} = args} = job) do
    result =
      case Accounts.get_user(user_id) do
        nil -> {:cancel, "the file's user no longer exists"}
        user -> user |> Scope.for_user() |> Ingest.parse_file(file_id)
      end

    count(args["run_id"], result, job)
    result
  end

  defp count(nil, _result, _job), do: :ok
  defp count(run_id, :ok, _job), do: SyncRuns.file_done(run_id, :parsed)
  defp count(run_id, {:cancel, _reason}, _job), do: SyncRuns.file_done(run_id, :failed)

  defp count(run_id, {:error, _reason}, %Oban.Job{attempt: attempt, max_attempts: max}) do
    if attempt >= max, do: SyncRuns.file_done(run_id, :failed)
  end
end
