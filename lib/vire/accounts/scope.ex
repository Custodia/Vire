defmodule Vire.Accounts.Scope do
  @moduledoc """
  The user a request acts for, and the channel it came through: the
  dashboard, or MCP with the client's id. Every function that reads or writes
  a user's data takes a scope as its first argument and touches only that
  user's rows.
  """

  alias Vire.Accounts.User

  defstruct user: nil, channel: :dashboard, mcp_client_id: nil

  @type t :: %__MODULE__{
          user: User.t(),
          channel: :dashboard | :mcp,
          mcp_client_id: Ecto.UUID.t() | nil
        }

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
