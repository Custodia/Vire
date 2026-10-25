defmodule Vire.Training.Block do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  alias Vire.Training.Constraints
  alias Vire.Training.Period

  schema "training_blocks" do
    field :focus, :string
    field :period, Period
    field :rationale, :string
    field :user_id, :binary_id

    belongs_to :phase, Vire.Training.Phase
    has_many :cycles, Vire.Training.Cycle

    timestamps()
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:focus, :period, :rationale])
    |> validate_required([:focus, :period, :rationale])
    |> foreign_key_constraint(:phase_id, name: :training_blocks_phase_id_fkey)
    |> Constraints.period("training_blocks",
      sibling: "block of the phase",
      parent: "phase",
      children: "cycles"
    )
  end
end
