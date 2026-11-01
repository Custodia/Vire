defmodule Vire.Accounts.Scope do
  @moduledoc """
  The user a request acts for. Every function that reads or writes a user's
  data takes a scope as its first argument and touches only that user's rows.
  """

  alias Vire.Accounts.User

  defstruct user: nil

  @type t :: %__MODULE__{user: User.t()}

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
