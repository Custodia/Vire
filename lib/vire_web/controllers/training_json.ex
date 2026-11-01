defmodule VireWeb.TrainingJSON do
  @moduledoc """
  The dashboard's JSON for sessions.
  """

  alias Vire.Training.Session

  @titles %{
    swim: "Swim",
    bike: "Bike",
    run: "Run",
    strength: "Strength",
    other: "Session"
  }

  @doc "A session's own title, or the name of its discipline."
  def title(%Session{structure: %{"title" => title}}) when is_binary(title) and title != "",
    do: title

  def title(%Session{discipline: discipline}), do: Map.fetch!(@titles, discipline)
end
