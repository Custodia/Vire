defmodule Vire.Mcp.Tools do
  @moduledoc """
  The registry of MCP tools: every tool of every group listed here, in order.
  `tools/list` and `tools/call` read it.
  """

  alias Vire.Mcp.Tool

  @groups [Vire.Mcp.PlanTools]

  @doc "Every registered tool."
  @spec all() :: [Tool.t()]
  def all, do: Enum.flat_map(@groups, & &1.tools())

  @doc "The tool named `name`."
  @spec fetch(String.t()) :: {:ok, Tool.t()} | :error
  def fetch(name) do
    case Enum.find(all(), &(&1.name == name)) do
      %Tool{} = tool -> {:ok, tool}
      nil -> :error
    end
  end
end
