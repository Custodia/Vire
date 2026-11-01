import Config

if System.get_env("PHX_SERVER") do
  config :vire, VireWeb.Endpoint, server: true
end

# The Playwright suite drives the test configuration as a real server.
if config_env() == :test and System.get_env("VIRE_E2E") == "true" do
  config :vire, Vire.Repo, database: "vire_e2e", pool: DBConnection.ConnectionPool
  config :vire, VireWeb.Endpoint, server: true
  config :vire, Oban, testing: :disabled
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :vire, Vire.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :vire, VireWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
