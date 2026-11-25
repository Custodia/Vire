defmodule VireWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :vire

  @session_options [
    store: :cookie,
    key: "_vire_session",
    signing_salt: "tuUStOrb",
    encryption_salt: "Bv51Hzsx",
    http_only: true,
    same_site: "Lax",
    secure: Application.compile_env(:vire, :secure_session_cookie, false)
  ]

  # Vite names every file under assets/ after a hash of its content.
  plug Plug.Static,
    at: "/",
    from: :vire,
    only: ~w(assets),
    cache_control_for_etags: "public, max-age=31536000, immutable"

  plug Plug.Static,
    at: "/",
    from: :vire,
    only: ~w(favicon.svg manifest.webmanifest robots.txt)

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :vire
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: 20_000_000}, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug Plug.Session, @session_options
  plug VireWeb.Router
end
