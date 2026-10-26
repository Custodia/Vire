import Config

config :vire,
  ecto_repos: [Vire.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :vire, Vire.Repo,
  migration_primary_key: [type: :uuid, default: {:fragment, "gen_random_uuid()"}],
  migration_timestamps: [type: :timestamptz, default: {:fragment, "now()"}]

config :vire, VireWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: VireWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Vire.PubSub

config :vire, Oban,
  repo: Vire.Repo,
  queues: [default: 10, ingest: 2],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

config :vire, Vire.Ingest.Garmin, base_url: "https://personal.connectapi.garmin.com"

config :vire, Vire.Ingest.Decoder,
  script: Path.expand("../decoder/decode.js", __DIR__),
  timeout: 30_000

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
