defmodule Mix.Tasks.Vire.SeedE2eTest do
  use Vire.DataCase, async: false

  alias Vire.Accounts
  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.User

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "creates the e2e user with a Garmin connection" do
    Mix.Task.rerun("vire.seed_e2e")

    user = Accounts.get_user_by_email_and_password("e2e@example.com", "e2e-password-1234")
    assert %User{} = user
    assert Repo.get_by!(ProviderConnection, user_id: user.id).provider == :garmin
  end

  test "leaves an existing e2e user alone" do
    Mix.Task.rerun("vire.seed_e2e")
    Mix.Task.rerun("vire.seed_e2e")

    assert Repo.aggregate(User, :count) == 1
  end
end
