defmodule Vire.EncryptedTest do
  use ExUnit.Case, async: true

  alias Vire.Encrypted

  test "decrypts what it encrypts" do
    assert {:ok, "gk_invented"} = "gk_invented" |> Encrypted.encrypt() |> Encrypted.decrypt()
  end

  test "fails to decrypt a value whose tag was altered" do
    <<nonce::binary-size(12), tag, rest::binary>> = Encrypted.encrypt("gk_invented")

    assert Encrypted.decrypt(<<nonce::binary, Bitwise.bxor(tag, 1), rest::binary>>) == :error
  end

  test "fails to decrypt a value too short to hold a nonce and a tag" do
    assert Encrypted.decrypt(<<1, 2, 3>>) == :error
  end

  test "casts, dumps and loads binaries only" do
    assert Encrypted.cast("gk") == {:ok, "gk"}
    assert Encrypted.cast(1) == :error
    assert Encrypted.dump(1) == :error
    assert Encrypted.load(1) == :error
    assert {:ok, dumped} = Encrypted.dump("gk")
    assert Encrypted.load(dumped) == {:ok, "gk"}
  end
end
