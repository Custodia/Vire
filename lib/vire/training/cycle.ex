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
    |> validate()
  end

  @doc """
  A changeset for a new cycle. Without a period in `attrs` it takes
  `default`; a `nil` default means the block has no days left.
  """
  def create_changeset(cycle, attrs, default) do
    cycle
    |> cast(attrs, [:kind, :period, :rationale])
    |> put_default_period(default)
    |> validate()
  end

  defp put_default_period(changeset, default) do
    cond do
      get_field(changeset, :period) || changeset.errors[:period] -> changeset
      default -> put_change(changeset, :period, default)
      true -> add_error(changeset, :period, "has no days left in the block")
    end
  end

  defp validate(changeset) do
    changeset
    |> validate_required([:kind, :period, :rationale])
    |> foreign_key_constraint(:block_id, name: :training_cycles_block_id_fkey)
    |> Constraints.period("training_cycles",
      sibling: "cycle of the block",
      parent: "block",
      children: "days with sessions or notes"
    )
  end
end
