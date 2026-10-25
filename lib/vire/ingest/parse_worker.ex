defmodule Vire.Ingest.ParseWorker do
  @moduledoc """
  Parses one source file into its activity. One job per file waits or runs at
  a time.
  """

  use Oban.Worker,
    queue: :ingest,
    max_attempts: 3,
    unique: [keys: [:source_file_id], states: :incomplete, period: :infinity]

  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Ingest

  @processor_version 1

  @doc "The version stored on every file this worker parses."
  def processor_version, do: @processor_version

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_file_id" => file_id, "user_id" => user_id}}) do
    case Accounts.get_user(user_id) do
      nil -> {:cancel, "the file's user no longer exists"}
      user -> user |> Scope.for_user() |> Ingest.parse_file(file_id)
    end
  end
end
