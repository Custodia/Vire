defmodule Vire.Numeric do
  @moduledoc "An Ecto type for a `numeric` column, read and written as a float."

  use Ecto.Type

  def type, do: :decimal

  def cast(value) when is_number(value), do: {:ok, value / 1}
  def cast(_value), do: :error

  def load(%Decimal{} = value), do: {:ok, Decimal.to_float(value)}

  def dump(value) when is_float(value), do: {:ok, Decimal.from_float(value)}
  def dump(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  def dump(_value), do: :error
end
