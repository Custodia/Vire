defmodule Vire.Encrypted do
  @moduledoc """
  An Ecto type for a binary encrypted at rest with AES-256-GCM.

  Each write draws a fresh 12-byte nonce. The stored value is the nonce, the
  16-byte authentication tag and the ciphertext, in that order. A value that
  fails authentication does not load.
  """

  use Ecto.Type

  @nonce_size 12
  @tag_size 16
  @aad "vire"

  @impl true
  def type, do: :binary

  @impl true
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl true
  def dump(value) when is_binary(value), do: {:ok, encrypt(value)}
  def dump(_value), do: :error

  @impl true
  def load(value) when is_binary(value), do: decrypt(value)
  def load(_value), do: :error

  @doc "Encrypts `plaintext` under the configured credential key."
  def encrypt(plaintext) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, plaintext, @aad, @tag_size, true)

    nonce <> tag <> ciphertext
  end

  @doc "Decrypts a value written by `encrypt/1`."
  def decrypt(
        <<nonce::binary-size(@nonce_size), tag::binary-size(@tag_size), ciphertext::binary>>
      ) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end

  def decrypt(_value), do: :error

  defp key, do: Application.fetch_env!(:vire, :credential_key)
end
