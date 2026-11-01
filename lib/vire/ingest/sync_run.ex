defmodule Vire.Ingest.SyncRun do
  @moduledoc """
  One Garmin sync of one user, from the moment it is queued: what started it,
  how far it got, the activities it found that Vire did not hold yet, and the
  files it queued, fetched and gave up on.

  A run is `queued` until its job starts and `running` while it searches
  Garmin and fetches files. It is `finished` once every search has succeeded
  and every file it queued has been fetched or given up on, and `failed`, with
  the error, when its searches fail for good or its connection cannot be used.
  """

  use Vire.Schema

  @type t :: %__MODULE__{}

  schema "sync_runs" do
    field :trigger, Ecto.Enum, values: [:manual, :scheduled, :plan]
    field :state, Ecto.Enum, values: [:queued, :running, :finished, :failed], default: :queued
    field :error, :string
    field :new_activity_ids, {:array, :binary_id}, default: []
    field :files_total, :integer, default: 0
    field :files_fetched, :integer, default: 0
    field :files_failed, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :searched_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :user, Vire.Accounts.User

    timestamps()
  end
end
