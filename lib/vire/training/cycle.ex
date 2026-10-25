defmodule Vire.Training.Cycle do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  alias Vire.Training.Constraints
  alias Vire.Training.Period

  schema "training_cycles" do
    field :kind, Ecto.Enum, values: [:load, :recovery]
    field :period, Period
    field :rationale, :string
    field :user_id, :binary_id

    belongs_to :block, Vire.Training.Block
    has_many :days, Vire.Training.Day

    timestamps()
  end

  def changeset(cycle, attrs) do
    cycle
    |> cast(attrs, [:kind, :period, :rationale])
    |> validate_required([:kind, :period, :rationale])
    |> foreign_key_constraint(:block_id, name: :training_cycles_block_id_fkey)
    |> Constraints.period("training_cycles",
      sibling: "cycle of the block",
      parent: "block",
      children: "days"
    )
  end
end
