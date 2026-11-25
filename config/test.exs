import Config

config :vire, Vire.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "vire_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :vire, VireWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "lElUE2fKquWZXLWr/NTjxZoPFRk5udKd1Y6vrr40GsvyI2JqLEWXwoMdWZh31LjY",
  server: false

config :vire, Oban, testing: :manual, plugins: false

# Nothing listens on port 9, so a request that escapes the stub reaches no one.
config :vire, Vire.Ingest.Garmin,
  base_url: "http://127.0.0.1:9",
  req_options: [plug: {Req.Test, Vire.Ingest.Garmin}, retry_delay: 0, retry_log_level: false]

config :vire, :credential_key, Base.decode64!("Fx1NFCZJdHxZRnhgYGmHFoyjtPtXnfF4X0JE6g1dFRg=")

config :bcrypt_elixir, log_rounds: 1

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix, sort_verified_routes_query_params: true
