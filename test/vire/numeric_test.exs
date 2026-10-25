defmodule Vire.NumericTest do
  use ExUnit.Case, async: true

  alias Vire.Numeric

  test "casts numbers to floats and nothing else" do
    assert Numeric.cast(25) == {:ok, 25.0}
    assert Numeric.cast(8.555) == {:ok, 8.555}
    assert Numeric.cast("25") == :error
  end

  test "dumps floats and integers to decimals and loads decimals as floats" do
    assert {:ok, decimal} = Numeric.dump(4590.5)
    assert Numeric.load(decimal) == {:ok, 4590.5}
    assert Numeric.dump(25) == {:ok, Decimal.new(25)}
    assert Numeric.dump("25") == :error
  end
end
