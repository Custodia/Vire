defmodule Vire.Ingest.Garmin.Token do
  @moduledoc """
  A bearer token for Garmin's Personal API and the Unix time, in seconds, at
  which it expires. Inspecting one shows the expiry and hides the token.
  """

  @derive {Inspect, only: [:expires_at]}
  @enforce_keys [:value, :expires_at]
  defstruct [:value, :expires_at]

  @type t :: %__MODULE__{value: String.t(), expires_at: integer()}
end
