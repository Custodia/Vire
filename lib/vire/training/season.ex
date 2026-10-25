defmodule Vire.Training.Season do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  alias Vire.Training.Constraints
  alias Vire.Training.Period

  schema "training_seasons" do
    field :name, :string
    field :period, Period
    field :rationale, :string

    belongs_to :user, Vire.Accounts.User
    has_many :phases, Vire.Training.Phase

    timestamps()
  end

  def changeset(season, attrs) do
    season
    |> cast(attrs, [:name, :period, :rationale])
    |> validate_required([:name, :period, :rationale])
    |> Constraints.period("training_seasons", sibling: "season", children: "phases")
  end
end
