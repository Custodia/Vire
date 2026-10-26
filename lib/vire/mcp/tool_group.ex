defmodule Vire.Mcp.ToolGroup do
  @moduledoc """
  A module that defines a group of MCP tools. Listing it in `Vire.Mcp.Tools`
  registers every tool it answers.
  """

  @callback tools() :: [Vire.Mcp.Tool.t()]
end
