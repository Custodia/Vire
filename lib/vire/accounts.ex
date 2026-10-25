defmodule Vire.Accounts do
  @moduledoc """
  Users, sign-in and the connections that hold each user's provider credentials.
  """

  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.User
  alias Vire.Repo

  @doc "Creates a user from an email, a name and a password."
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    # Ecto logs a query's parameters, which here include the password hash.
    |> Repo.insert(log: false)
  end

  @doc """
  Creates a user and their first provider connection in one transaction. Neither
  is stored unless both are valid.
  """
  def create_user_with_provider_connection(user_attrs, connection_attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- create_user(user_attrs),
           {:ok, connection} <- create_provider_connection(user, connection_attrs) do
        {:ok, %{user | provider_connections: [connection]}}
      end
    end)
  end

  @doc "Stores a provider connection for `user`, its credential encrypted."
  def create_provider_connection(%User{} = user, attrs) do
    %ProviderConnection{user_id: user.id}
    |> ProviderConnection.create_changeset(attrs)
    # Ecto logs a query's parameters before they are encrypted.
    |> Repo.insert(log: false)
  end
end
