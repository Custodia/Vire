defmodule VireWeb.PlanChangeJSON do
  @moduledoc """
  The dashboard's JSON for the plan change log: what changed, why, when, and
  through which channel and MCP client.
  """

  alias Vire.Training.PlanChange

  @entities %{
    training_season: "season",
    training_phase: "phase",
    training_block: "block",
    training_cycle: "cycle",
    training_day: "day",
    training_session: "session",
    training_goal: "goal",
    event: "event"
  }

  @titles %{
    "swim" => "Swim",
    "bike" => "Bike",
    "run" => "Run",
    "strength" => "Strength",
    "other" => "Session"
  }

  def index(%{changes: changes}), do: %{changes: Enum.map(changes, &change/1)}

  defp change({%PlanChange{} = change, client}) do
    %{
      id: change.id,
      entity: Map.fetch!(@entities, change.entity),
      action: change.action,
      subject: subject(change.entity, change.after || change.before),
      rationale: change.rationale,
      channel: change.channel,
      client: client,
      at: change.inserted_at
    }
  end

  defp subject(_entity, nil), do: nil
  defp subject(entity, row) when entity in [:training_season, :training_phase], do: row["name"]
  defp subject(:training_block, row), do: row["focus"]
  defp subject(:training_cycle, row), do: row["kind"]
  defp subject(:training_day, row), do: row["day"]

  defp subject(:training_session, row) do
    case row["structure"] do
      %{"title" => title} when is_binary(title) and title != "" -> title
      _untitled -> Map.get(@titles, row["discipline"], "Session")
    end
  end

  defp subject(_entity, _row), do: nil
end
