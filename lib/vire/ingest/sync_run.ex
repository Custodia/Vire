defmodule Vire.Ingest.SyncRun do
  @moduledoc """
  One Garmin sync of one user, from the moment it is queued: what started it,
  how far it got, the activities it found that Vire did not hold yet, and the
  files it queued, fetched, parsed and gave up on.

  A run is `queued` until its job starts and `searching` while it asks Garmin
  for activities, storing and matching each one as it arrives. It is
  `fetching` once every search has succeeded, while the files it queued are
  downloaded and parsed, and `finished` once every one of them has been parsed
  or given up on. It is `failed`, with the error, when its searches fail for
  good or its connection cannot be used.
  """

  use Vire.Schema

  @type t :: %__MODULE__{}

  schema "sync_runs" do
    field :trigger, Ecto.Enum, values: [:manual, :scheduled, :plan]

    field :state, Ecto.Enum,
      values: [:queued, :searching, :fetching, :finished, :failed],
      default: :queued

    field :error, :string
    field :new_activity_ids, {:array, :binary_id}, default: []
    field :files_total, :integer, default: 0
    field :files_fetched, :integer, default: 0
    field :files_parsed, :integer, default: 0
    field :files_failed, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :searched_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :user, Vire.Accounts.User

    timestamps()
  end
end
