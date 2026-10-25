defmodule Vire.Training.DayContext do
  @moduledoc """
  A day with the cycle, block, phase and season above it, read from the
  `training_day_contexts` view.
  """

  use Vire.Schema

  @primary_key false
  schema "training_day_contexts" do
    field :day_id, :binary_id
    field :user_id, :binary_id
    field :day, :date
    field :day_kind, Ecto.Enum, values: [:training, :rest]
    field :cycle_id, :binary_id
    field :cycle_kind, Ecto.Enum, values: [:load, :recovery]
    field :block_id, :binary_id
    field :block_focus, :string
    field :phase_id, :binary_id
    field :phase_name, :string
    field :season_id, :binary_id
    field :season_name, :string
  end
end
