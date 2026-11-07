defmodule Vire.Ingest.SyncRuns do
  @moduledoc """
  A sync run's progress as its jobs move through it. Every change is one
  statement on the run's row, so jobs of one run never overwrite each other's
  counts, and the changed run is published to its user once it is written.
  """

  import Ecto.Query

  alias Vire.Events
  alias Vire.Ingest.SyncRun
  alias Vire.Repo

  @doc "Marks the queued run searching. A run already started, on a retry, is left as it is."
  def start(run_id),
    do: change(where(runs(run_id), state: :queued), set: [state: :searching, started_at: now()])

  @doc """
  Adds the activities a search found that Vire did not hold, and the number of
  file downloads it queued, to the run.
  """
  def found(run_id, new_activity_ids, files_queued) do
    runs(run_id)
    |> update([r],
      set: [
        new_activity_ids:
          fragment(
            "array_cat(?, ?)",
            r.new_activity_ids,
            type(^new_activity_ids, {:array, :binary_id})
          )
      ],
      inc: [files_total: ^files_queued]
    )
    |> change([])
  end

  @doc """
  Records that every search succeeded, which moves the run to fetching, or
  finishes it when no file of it is left to parse.
  """
  def searched(run_id) do
    change(searching(run_id), set: [state: :fetching, searched_at: now(), error: nil])
    finish_when_done(run_id)
  end

  @doc "Records the error of a search the job tries again; the run keeps searching."
  def retrying(run_id, error), do: change(searching(run_id), set: [error: error])

  @doc "Fails a run that has not finished, with `error`."
  def fail(run_id, error) do
    run_id
    |> runs()
    |> where([r], r.state in [:queued, :searching, :fetching])
    |> change(set: [state: :failed, error: error, finished_at: now()])
  end

  @doc """
  Counts one of the run's files as fetched, as parsed, or as given up on in
  its download or its parse. Once every file is parsed or given up on, a run
  done searching finishes.
  """
  def file_done(run_id, outcome) when outcome in [:fetched, :parsed, :failed] do
    change(runs(run_id), inc: [{field(outcome), 1}])
    finish_when_done(run_id)
  end

  defp field(:fetched), do: :files_fetched
  defp field(:parsed), do: :files_parsed
  defp field(:failed), do: :files_failed

  defp finish_when_done(run_id) do
    runs(run_id)
    |> where(state: :fetching)
    |> where([r], r.files_parsed + r.files_failed >= r.files_total)
    |> change(set: [state: :finished, finished_at: now()])
  end

  defp runs(run_id), do: where(SyncRun, id: ^run_id)

  defp searching(run_id), do: where(runs(run_id), state: :searching)

  defp change(query, updates) do
    case query |> select([r], r) |> Repo.update_all(updates) do
      {1, [run]} ->
        Events.publish(run.user_id, {:sync_run, run})
        {:ok, run}

      {0, []} ->
        :unchanged
    end
  end

  defp now, do: DateTime.utc_now()
end
