defmodule Vire.Training.Session do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  alias Vire.Training.Structure

  schema "training_sessions" do
    field :date, :date, virtual: true
    field :position, :integer
    field :discipline, Ecto.Enum, values: [:swim, :bike, :run, :strength, :other]
    field :structure, :map, default: %{}
    field :planned_seconds, :integer
    field :status, Ecto.Enum, values: [:planned, :done, :skipped], default: :planned
    field :activity_id, :binary_id
    field :rationale, :string
    field :review, :string
    field :review_score, :integer
    field :reviewed_at, :utc_datetime_usec
    field :user_id, :binary_id

    belongs_to :day, Vire.Training.Day

    timestamps()
  end

  @doc """
  A changeset for the planned parts of a session. A `date` names the day the
  session sits on; the context resolves it to that day. The structure's steps
  are checked against `Vire.Training.Structure`.
  """
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :date,
      :position,
      :discipline,
      :structure,
      :planned_seconds,
      :status,
      :rationale
    ])
    |> validate_required([:date, :position, :discipline, :rationale])
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than: 32_768)
    |> validate_number(:planned_seconds, greater_than_or_equal_to: 0)
    |> validate_change(:structure, &validate_structure/2)
    |> unique_constraint(:position,
      name: :training_sessions_day_id_position_index,
      message: "is taken by another session that day"
    )
    |> foreign_key_constraint(:day_id, name: :training_sessions_day_id_fkey)
    |> check_constraint(:status,
      name: :training_sessions_matched_session_done,
      message: "must be done while an activity is matched"
    )
  end

  @doc """
  A changeset matching the session to the activity with `activity_id`, which
  makes it done, or clearing its match with `nil`, which makes it planned.
  """
  def match_changeset(session, activity_id) do
    session
    |> change(activity_id: activity_id, status: if(activity_id, do: :done, else: :planned))
    |> unique_constraint(:activity_id,
      name: :training_sessions_activity_id_index,
      message: "is matched to another session"
    )
    |> foreign_key_constraint(:activity_id, name: :training_sessions_activity_id_fkey)
  end

  defp validate_structure(:structure, structure) do
    case Structure.validate(structure) do
      :ok -> []
      {:error, message} -> [structure: message]
    end
  end
end
