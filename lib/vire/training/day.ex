defmodule Vire.Training.Day do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  schema "training_days" do
    field :day, :date
    field :kind, Ecto.Enum, values: [:training, :rest]
    field :note, :string
    field :user_id, :binary_id

    belongs_to :cycle, Vire.Training.Cycle
    has_many :sessions, Vire.Training.Session
    has_one :context, Vire.Training.DayContext

    timestamps()
  end

  def changeset(day, attrs) do
    day
    |> cast(attrs, [:kind, :note])
    |> validate_required([:kind])
  end
end
