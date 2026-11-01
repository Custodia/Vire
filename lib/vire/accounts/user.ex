defmodule Vire.Accounts.User do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    has_many :provider_connections, Vire.Accounts.ProviderConnection

    timestamps()
  end

  @doc """
  A changeset for a new user. The password is hashed with bcrypt and only the
  hash is kept.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password])
    |> update_change(:email, &String.trim/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:email, :name, :password])
    |> validate_format(:email, ~r/\A[^@\s]+@[^@\s]+\z/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> validate_length(:name, max: 160)
    |> validate_length(:password, min: 12, max: 72, count: :bytes)
    |> unique_constraint(:email)
    |> hash_password()
  end

  @doc """
  Returns `user` when `password` matches their hash, and `nil` otherwise.
  Without a user it still spends a hash's worth of time.
  """
  def verify_password(%__MODULE__{password_hash: hash} = user, password) when is_binary(hash) do
    if Bcrypt.verify_pass(password, hash), do: user
  end

  def verify_password(nil, _password) do
    Bcrypt.no_user_verify()
    nil
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
