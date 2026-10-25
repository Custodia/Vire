import Config

config :vire, Vire.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "vire_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :vire, VireWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "0YTV+5HvF+OA5dR5DbqtBvOli16bMJ1Yh2UWfEX0kxyMWgmAhn0FnMGV6csZrYuF",
  watchers: [
    npm: ["run", "dev", cd: Path.expand("../assets", __DIR__)]
  ]

config :vire, :credential_key, Base.decode64!("6s3ZFtEvMeIqkS/3YDLfy0xxuW4jtTEjaOfka8is3Gs=")

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
