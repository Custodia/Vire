import Config

config :vire, VireWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [hosts: ["localhost", "127.0.0.1"], paths: ["/api/health"]]
  ]

config :logger, level: :info
