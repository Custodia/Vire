defmodule Mix.Tasks.Vire.SeedE2e do
  @shortdoc "Creates the user the end-to-end suite signs in as"

  @moduledoc """
  Creates the user e2e@example.com with the password `e2e-password-1234` and an
  invented Garmin key, unless the user exists. Run it against the end-to-end
  database before the server starts.
  """

  use Mix.Task

  alias Vire.Accounts

  @email "e2e@example.com"
  @password "e2e-password-1234"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Accounts.get_user_by_email_and_password(@email, @password) do
      nil -> create()
      _user -> :ok
    end
  end

  defp create do
    user_attrs = %{email: @email, name: "End-to-end Athlete", password: @password}
    connection_attrs = %{provider: :garmin, credential: "invented-garmin-key"}

    case Accounts.create_user_with_provider_connection(user_attrs, connection_attrs) do
      {:ok, user} ->
        Mix.shell().info("Created user #{user.id} #{user.email}")

      {:error, changeset} ->
        Mix.raise("Could not create the e2e user: #{inspect(changeset.errors)}")
    end
  end
end
