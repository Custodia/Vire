defmodule Mix.Tasks.Vire.CreateUser do
  @shortdoc "Creates a user with their Garmin API key"

  @moduledoc """
  Creates a user and their Garmin connection in one transaction.

      mix vire.create_user --email EMAIL --name NAME --password "$PASSWORD" --garmin-key "$GARMIN_KEY"

  Every option is required. Prints the new user's id and email.
  """

  use Mix.Task

  alias Vire.Accounts

  @switches [email: :string, name: :string, password: :string, garmin_key: :string]
  @usage ~s(mix vire.create_user --email EMAIL --name NAME --password "$PASSWORD" --garmin-key "$GARMIN_KEY")

  @impl Mix.Task
  def run(args) do
    opts = parse!(args)

    Mix.Task.run("app.start")

    user_attrs = Map.new(Keyword.take(opts, [:email, :name, :password]))
    connection_attrs = %{provider: :garmin, credential: opts[:garmin_key]}

    case Accounts.create_user_with_provider_connection(user_attrs, connection_attrs) do
      {:ok, user} ->
        Mix.shell().info("Created user #{user.id} #{user.email}")

      {:error, changeset} ->
        Mix.raise("Could not create the user: #{format_errors(changeset)}")
    end
  end

  defp parse!(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} ->
        case Enum.reject(Keyword.keys(@switches), &present?(opts[&1])) do
          [] ->
            opts

          missing ->
            Mix.raise("Missing #{Enum.map_join(missing, ", ", &switch/1)}.\nUsage: #{@usage}")
        end

      {_opts, [], [{name, _value} | _]} ->
        Mix.raise("Unknown or invalid option #{name}.\nUsage: #{@usage}")

      {_opts, [_ | _], _invalid} ->
        Mix.raise("Unexpected argument; every value follows its option.\nUsage: #{@usage}")
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp switch(key), do: "--" <> String.replace(Atom.to_string(key), "_", "-")

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, message ->
        String.replace(message, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.sort()
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
