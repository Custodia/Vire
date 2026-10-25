defmodule Vire.Activities.Length do
  @moduledoc false

  use Vire.Schema

  schema "activity_lengths" do
    field :length_index, :integer
    field :lap_index, :integer
    field :started_at, :utc_datetime_usec
    field :elapsed_seconds, Vire.Numeric
    field :active, :boolean
    field :stroke, :string
    field :strokes, :integer

    belongs_to :activity, Vire.Activities.Activity

    timestamps()
  end
end
