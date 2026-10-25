defmodule VireWeb.UserJSON do
  alias Vire.Accounts.User

  def show(%{user: %User{} = user}) do
    %{id: user.id, email: user.email, name: user.name}
  end
end
