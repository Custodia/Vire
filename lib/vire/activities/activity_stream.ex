defmodule Vire.Activities.ActivityStream do
  @moduledoc false

  use Vire.Schema

  @primary_key false
  schema "activity_streams" do
    field :channel, :string, primary_key: true
    field :unit, :string
    field :samples, {:array, :float}

    belongs_to :activity, Vire.Activities.Activity, primary_key: true

    timestamps()
  end
end
