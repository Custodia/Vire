defmodule Vire.Accounts do
  @moduledoc """
  Users, sign-in, the connections that hold each user's provider credentials,
  and the scope every request runs in.
  """

  import Ecto.Query

  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Accounts.User
  alias Vire.Repo

  @doc "Creates a user from an email, a name and a password."
  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    # Ecto logs a query's parameters, which here include the password hash.
    |> Repo.insert(log: false)
  end

  @doc "Returns the user with `id`, or `nil`. Builds the scope of a signed-in session."
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Returns the user with `email` when `password` is theirs, and `nil` otherwise.
  An unknown email costs the same bcrypt work as a wrong password.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    User
    |> Repo.get_by(email: email)
    |> User.verify_password(password)
  end

  @doc """
  Creates a user and their first provider connection in one transaction. Neither
  is stored unless both are valid.
  """
  def create_user_with_provider_connection(user_attrs, connection_attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- create_user(user_attrs),
           {:ok, connection} <- create_provider_connection(Scope.for_user(user), connection_attrs) do
        {:ok, %{user | provider_connections: [connection]}}
      end
    end)
  end

  @doc "Stores a provider connection for the scope's user, its credential encrypted."
  def create_provider_connection(%Scope{user: %User{id: user_id}}, attrs) do
    %ProviderConnection{user_id: user_id}
    |> ProviderConnection.create_changeset(attrs)
    # Ecto logs a query's parameters before they are encrypted.
    |> Repo.insert(log: false)
  end

  @doc "Returns the scope's user's connection to `provider`, or `nil`."
  def get_provider_connection(%Scope{user: %User{id: user_id}}, provider) do
    ProviderConnection
    |> where(user_id: ^user_id, provider: ^provider)
    |> Repo.one()
  end

  @doc "Every user's unpaused connection to `provider`, with its user."
  def list_unpaused_provider_connections(provider) do
    ProviderConnection
    |> where(provider: ^provider)
    |> where([c], is_nil(c.paused_at))
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Records that the scope's connection finished a sync now."
  def mark_provider_connection_synced(%Scope{} = scope, %ProviderConnection{} = connection),
    do: update_connection_time(scope, connection, :last_synced_at)

  @doc "Pauses the scope's connection, so no sync uses it."
  def pause_provider_connection(%Scope{} = scope, %ProviderConnection{} = connection),
    do: update_connection_time(scope, connection, :paused_at)

  defp update_connection_time(
         %Scope{user: %User{id: user_id}},
         %ProviderConnection{user_id: user_id} = connection,
         field
       ) do
    connection
    |> Ecto.Changeset.change(%{field => DateTime.utc_now()})
    |> Repo.update()
  end
end
