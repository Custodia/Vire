defmodule Vire.Activities.Lap do
  @moduledoc false

  use Vire.Schema

  schema "activity_laps" do
    field :lap_index, :integer
    field :started_at, :utc_datetime_usec
    field :elapsed_seconds, :integer
    field :moving_seconds, :integer
    field :distance_m, Vire.Numeric
    field :avg_heart_rate, :integer
    field :avg_power, :integer
    field :avg_speed_mps, Vire.Numeric

    belongs_to :activity, Vire.Activities.Activity

    timestamps()
  end
end
