defmodule Vire.Accounts.CredentialLogTest do
  use Vire.DataCase, async: false

  import ExUnit.CaptureLog

  alias Vire.Accounts.User

  setup do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  test "keeps the password hash and the credential out of the query log" do
    {user, log} =
      with_log(fn ->
        user = user_fixture()
        provider_connection_fixture(user, credential: "gk_never_logged")
        Repo.get!(User, user.id)
      end)

    assert log =~ ~s(FROM "users")
    refute log =~ user.password_hash
    refute log =~ "gk_never_logged"
  end
end
