# Vire

*Vire* (Finnish, [ˈʋire] — "VEE-reh") means tune, condition or state: the sense in
which an athlete is in good form.

Vire tracks workouts, nutrition, goals and athlete preferences, and serves them two
ways: an MCP server, so a conversational agent can coach the athlete from the full
history, and a web dashboard in any modern browser.

Workout files are uploaded to the application, decoded and stored.

## Development

Prerequisites: Elixir 1.20 on Erlang/OTP 29, Node 22, and Docker. Exact versions
are in `.tool-versions`. Node is also a runtime requirement: `.fit` files are
decoded by a Node process, so `node` must be on the application's `PATH`.

```sh
docker compose up -d   # PostgreSQL 16 on localhost:5432, user and password postgres
mix setup              # dependencies, database, dashboard and decoder packages
mix phx.server         # API on http://localhost:4000, which serves the last dashboard build
```

The dashboard is developed at http://localhost:5173, Vite's dev server, which
`mix phx.server` starts. It reloads on source edits and proxies `/api` to
Phoenix.

`mix decoder.setup` installs the decoder's packages alone.

Users are created by an operator; there is no sign-up. The task writes the user
and their Garmin connection together and prints the new user's id and email:

```sh
read -rs VIRE_PASSWORD && read -rs GARMIN_KEY   # type or paste each; nothing is echoed
mix vire.create_user --email ada@example.com --name "Ada Lovelace" \
  --password "$VIRE_PASSWORD" --garmin-key "$GARMIN_KEY"
```

The password and the Garmin API key go in as shell variables, so neither appears
in shell history.

Provider API keys are encrypted at rest under a 32-byte credential key. Development
and test carry a fixed key in their config. Production reads it in base64 from
`VIRE_CREDENTIAL_KEY`; `openssl rand -base64 32` generates one.

An MCP client connects to http://localhost:4000/mcp and authorizes through
Vire's OAuth sign-in. `npx @modelcontextprotocol/inspector` drives the flow locally.

Suites:

```sh
mix precommit                       # compile, format, Credo, ExUnit with coverage
cd assets && npm run lint && npm run format:check && npm test
cd e2e && npm ci && npx playwright install chromium   # once
mix assets.build && cd e2e && npm test               # Playwright against Phoenix on :4002
```

ExUnit runs the tests that need the built dashboard only after `mix assets.build`.
Playwright starts the application itself in the test configuration and reuses a
server already running on port 4002.

## Documentation

Everything lives in [docs/](docs/). Start with [docs/README.md](docs/README.md),
which describes what each document is for and how far to trust it.
