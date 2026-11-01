defmodule Vire.Repo do
  use Ecto.Repo,
    otp_app: :vire,
    adapter: Ecto.Adapters.Postgres
end
