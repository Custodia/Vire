defmodule Vire.Schema do
  @moduledoc """
  Defaults for every Ecto schema: database-generated UUID keys and microsecond
  UTC timestamps.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, :binary_id, read_after_writes: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
