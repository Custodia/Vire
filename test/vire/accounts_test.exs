defmodule Vire.AccountsTest do
  use Vire.DataCase, async: true

  alias Vire.Accounts
  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Accounts.User

  describe "create_user/1" do
    test "stores the user with a bcrypt hash of the password" do
      {:ok, user} =
        Accounts.create_user(user_attrs(email: " Athlete@Example.com ", name: " Ada "))

      stored = Repo.get!(User, user.id)
      assert stored.email == "Athlete@Example.com"
      assert stored.name == "Ada"
      assert "$2b$" <> _ = stored.password_hash
      assert Bcrypt.verify_pass(valid_password(), stored.password_hash)
      assert stored.password == nil
    end

    test "keeps the password out of the returned user and its inspection" do
      {:ok, user} = Accounts.create_user(user_attrs())

      assert user.password == nil
      refute inspect(user) =~ valid_password()
      refute inspect(user) =~ user.password_hash
    end

    test "requires an email, a name and a password" do
      {:error, changeset} = Accounts.create_user(%{})

      assert %{email: ["can't be blank"], name: ["can't be blank"], password: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "rejects an email without an @ sign or with spaces" do
      for email <- ["athlete.example.com", "ath lete@example.com"] do
        {:error, changeset} = Accounts.create_user(user_attrs(email: email))

        assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
      end
    end

    test "rejects a password shorter than 12 or longer than 72 bytes" do
      {:error, short} = Accounts.create_user(user_attrs(password: "elevenchars"))
      {:error, long} = Accounts.create_user(user_attrs(password: String.duplicate("ä", 37)))

      assert %{password: ["should be at least 12 byte(s)"]} = errors_on(short)
      assert %{password: ["should be at most 72 byte(s)"]} = errors_on(long)
    end

    test "rejects an email already taken, whatever its case" do
      user_fixture(email: "athlete@example.com")

      {:error, changeset} = Accounts.create_user(user_attrs(email: "ATHLETE@example.com"))

      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user for their email, whatever its case, and password" do
      user = user_fixture(email: "ada@example.com")

      assert %User{id: id} =
               Accounts.get_user_by_email_and_password("ADA@example.com", valid_password())

      assert id == user.id
    end

    test "returns nil for a wrong password or an unknown email" do
      user = user_fixture()

      assert Accounts.get_user_by_email_and_password(user.email, "not the password") == nil

      assert Accounts.get_user_by_email_and_password("nobody@example.com", valid_password()) ==
               nil
    end
  end

  describe "create_user_with_provider_connection/2" do
    test "stores the user and the connection together" do
      {:ok, user} =
        Accounts.create_user_with_provider_connection(user_attrs(), %{
          provider: :garmin,
          credential: "gk_invented"
        })

      assert Repo.get!(User, user.id)

      assert %ProviderConnection{credential: "gk_invented"} =
               Repo.get_by!(ProviderConnection, user_id: user.id, provider: :garmin)
    end

    test "stores neither when the connection is invalid" do
      attrs = user_attrs()

      {:error, changeset} =
        Accounts.create_user_with_provider_connection(attrs, %{provider: :strava, credential: "x"})

      assert %{provider: ["is invalid"]} = errors_on(changeset)
      refute Repo.get_by(User, email: attrs.email)
    end

    test "stores neither when the user is invalid" do
      {:error, changeset} =
        Accounts.create_user_with_provider_connection(%{}, %{provider: :garmin, credential: "x"})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
      refute Repo.exists?(ProviderConnection)
    end
  end

  describe "create_provider_connection/2" do
    test "stores the credential encrypted and reads it back in clear" do
      user = user_fixture()

      {:ok, connection} =
        Accounts.create_provider_connection(Scope.for_user(user), %{
          provider: :garmin,
          credential: "gk_invented_123"
        })

      assert Repo.get!(ProviderConnection, connection.id).credential == "gk_invented_123"

      stored = raw_credential(connection.id)
      assert byte_size(stored) == 12 + 16 + byte_size("gk_invented_123")
      refute stored =~ "gk_invented_123"
    end

    test "writes a different ciphertext each time the same key is stored" do
      first = provider_connection_fixture(user_fixture(), credential: "gk_same")
      second = provider_connection_fixture(user_fixture(), credential: "gk_same")

      refute raw_credential(first.id) == raw_credential(second.id)
    end

    test "refuses to load a credential whose ciphertext was altered" do
      connection = provider_connection_fixture(user_fixture())
      <<head::binary-size(30), byte, rest::binary>> = raw_credential(connection.id)

      Repo.query!("update provider_connections set credential = $1 where id = $2", [
        <<head::binary, Bitwise.bxor(byte, 1), rest::binary>>,
        Ecto.UUID.dump!(connection.id)
      ])

      assert_raise ArgumentError, ~r/cannot load/, fn ->
        Repo.get!(ProviderConnection, connection.id)
      end
    end

    test "requires a provider and a credential" do
      {:error, changeset} =
        Accounts.create_provider_connection(Scope.for_user(user_fixture()), %{})

      assert %{provider: ["can't be blank"], credential: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "rejects a second connection to the same provider" do
      user = user_fixture()
      provider_connection_fixture(user)

      {:error, changeset} =
        Accounts.create_provider_connection(Scope.for_user(user), %{
          provider: :garmin,
          credential: "gk_other"
        })

      assert %{user_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "rejects a user that does not exist" do
      {:error, changeset} =
        Accounts.create_provider_connection(Scope.for_user(%User{id: Ecto.UUID.generate()}), %{
          provider: :garmin,
          credential: "gk_invented"
        })

      assert %{user: ["does not exist"]} = errors_on(changeset)
    end

    test "goes away with its user" do
      user = user_fixture()
      connection = provider_connection_fixture(user)

      Repo.delete!(user)

      refute Repo.get(ProviderConnection, connection.id)
    end
  end

  describe "get_provider_connection/2" do
    test "returns the scope's user's connection and never another user's" do
      ada = user_fixture()
      grace = user_fixture()
      ada_connection = provider_connection_fixture(ada, credential: "gk_ada")
      provider_connection_fixture(grace, credential: "gk_grace")

      assert %ProviderConnection{id: id, credential: "gk_ada"} =
               Accounts.get_provider_connection(Scope.for_user(ada), :garmin)

      assert id == ada_connection.id
    end

    test "returns nil when only another user has a connection" do
      provider_connection_fixture(user_fixture())

      assert Accounts.get_provider_connection(Scope.for_user(user_fixture()), :garmin) == nil
    end
  end

  describe "get_user/1" do
    test "returns the user with the id, or nil" do
      user = user_fixture()

      assert Accounts.get_user(user.id).id == user.id
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "the database" do
    test "enforces one user per email, ignoring case" do
      user_fixture(email: "athlete@example.com")

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.query!(
            "insert into users (email, name, password_hash) values ('Athlete@EXAMPLE.com', 'B', 'x')"
          )
        end

      assert %{postgres: %{code: :unique_violation, constraint: "users_email_index"}} = error
    end

    test "enforces one connection per user and provider" do
      connection = provider_connection_fixture(user_fixture())

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.query!(
            "insert into provider_connections (user_id, provider, credential) values ($1, 'garmin', '\\x00')",
            [Ecto.UUID.dump!(connection.user_id)]
          )
        end

      assert %{
               postgres: %{
                 code: :unique_violation,
                 constraint: "provider_connections_user_id_provider_index"
               }
             } = error
    end
  end

  defp raw_credential(id) do
    %{rows: [[credential]]} =
      Repo.query!("select credential from provider_connections where id = $1", [
        Ecto.UUID.dump!(id)
      ])

    credential
  end
end
