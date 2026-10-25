defmodule Vire.Training.PlanChange do
  @moduledoc """
  One write to the plan: the row before and after as JSON, the rationale, and
  the channel and MCP client it came through.
  """

  use Vire.Schema

  import Ecto.Changeset

  alias Vire.Training.Block
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.Phase
  alias Vire.Training.Season
  alias Vire.Training.Session

  @entities %{
    Season => :training_season,
    Phase => :training_phase,
    Block => :training_block,
    Cycle => :training_cycle,
    Day => :training_day,
    Session => :training_session
  }

  schema "plan_changes" do
    field :entity, Ecto.Enum, values: Map.values(@entities) ++ [:training_goal, :event]

    field :entity_id, :binary_id
    field :action, Ecto.Enum, values: [:insert, :update, :delete]
    field :before, :map
    field :after, :map
    field :rationale, :string
    field :channel, Ecto.Enum, values: [:dashboard, :mcp]
    field :mcp_client_id, :binary_id
    field :user_id, :binary_id

    timestamps(updated_at: false)
  end

  def changeset(change) do
    change
    |> change()
    |> validate_required([:entity, :entity_id, :action, :rationale, :channel])
    |> check_constraint(:mcp_client_id,
      name: :plan_changes_mcp_names_client,
      message: "must name the MCP client exactly when the channel is mcp"
    )
  end

  @doc "The entity a plan row is logged as."
  def entity(%schema{}), do: Map.fetch!(@entities, schema)

  @doc "A row's columns as the JSON object the log stores, or `nil`."
  def snapshot(nil), do: nil

  def snapshot(%schema{} = row) do
    row
    |> Map.take(schema.__schema__(:fields))
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
