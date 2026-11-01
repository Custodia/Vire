defmodule Vire.Training.Phase do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  alias Vire.Training.Constraints
  alias Vire.Training.Period

  schema "training_phases" do
    field :name, :string
    field :period, Period
    field :rationale, :string
    field :user_id, :binary_id

    belongs_to :season, Vire.Training.Season
    has_many :blocks, Vire.Training.Block

    timestamps()
  end

  def changeset(phase, attrs) do
    phase
    |> cast(attrs, [:name, :period, :rationale])
    |> validate_required([:name, :period, :rationale])
    |> foreign_key_constraint(:season_id, name: :training_phases_season_id_fkey)
    |> Constraints.period("training_phases",
      sibling: "phase of the season",
      parent: "season",
      children: "blocks"
    )
  end
end
