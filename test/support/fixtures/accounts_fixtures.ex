defmodule Vire.AccountsFixtures do
  alias Vire.Accounts

  def valid_password, do: "correct horse battery"

  def user_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: "athlete#{System.unique_integer([:positive])}@example.com",
      name: "Test Athlete",
      password: valid_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} = attrs |> user_attrs() |> Accounts.create_user()
    user
  end

  def provider_connection_fixture(user, attrs \\ %{}) do
    {:ok, connection} =
      Accounts.create_provider_connection(
        user,
        Enum.into(attrs, %{provider: :garmin, credential: "invented-garmin-key"})
      )

    connection
  end
end
