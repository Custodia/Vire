defmodule Mix.Tasks.Vire.CreateUserTest do
  use Vire.DataCase, async: false

  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.User

  @args [
    "--email",
    "ada@example.com",
    "--name",
    "Ada Lovelace",
    "--password",
    "invented password",
    "--garmin-key",
    "gk_invented_task"
  ]

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "creates the user with their Garmin key and prints the id and email" do
    Mix.Task.rerun("vire.create_user", @args)

    user = Repo.get_by!(User, email: "ada@example.com")
    assert user.name == "Ada Lovelace"
    assert Bcrypt.verify_pass("invented password", user.password_hash)

    assert %ProviderConnection{provider: :garmin, credential: "gk_invented_task"} =
             Repo.get_by!(ProviderConnection, user_id: user.id)

    assert_received {:mix_shell, :info, [output]}
    assert output == "Created user #{user.id} ada@example.com"
  end

  test "names every missing option" do
    error =
      assert_raise Mix.Error, fn ->
        Mix.Task.rerun("vire.create_user", ["--email", "ada@example.com", "--password", "  "])
      end

    assert error.message =~ "Missing --name, --password, --garmin-key."
    assert error.message =~ "Usage: mix vire.create_user"
    refute Repo.exists?(User)
  end

  test "rejects an unknown option" do
    assert_raise Mix.Error, ~r/Unknown or invalid option --admin/, fn ->
      Mix.Task.rerun("vire.create_user", @args ++ ["--admin"])
    end
  end

  test "rejects a value that follows no option without echoing it" do
    error =
      assert_raise Mix.Error, fn ->
        Mix.Task.rerun("vire.create_user", @args ++ ["stray secret"])
      end

    assert error.message =~ "Unexpected argument"
    refute error.message =~ "stray secret"
  end

  test "reports invalid values and stores nothing" do
    args = List.replace_at(@args, 1, "not-an-email") |> List.replace_at(5, "short")

    error = assert_raise Mix.Error, fn -> Mix.Task.rerun("vire.create_user", args) end

    assert error.message ==
             "Could not create the user: email must have the @ sign and no spaces; " <>
               "password should be at least 12 byte(s)"

    refute Repo.exists?(User)
    refute Repo.exists?(ProviderConnection)
  end

  test "refuses an email that is taken" do
    user_fixture(email: "ADA@example.com")

    assert_raise Mix.Error, ~r/email has already been taken/, fn ->
      Mix.Task.rerun("vire.create_user", @args)
    end
  end
end
