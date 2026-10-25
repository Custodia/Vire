# Vire

*Vire* (Finnish, [ˈʋire] — "VEE-reh") means tune, condition or state: the sense in
which an athlete is in good form.

Vire tracks workouts, nutrition, goals and athlete preferences, and serves them two
ways: an MCP server, so a conversational agent can coach the athlete from the full
history, and a web dashboard in any modern browser.

Workout files are uploaded to the application, decoded and stored.

## Development

Prerequisites: Elixir 1.20 on Erlang/OTP 29, Node 22, and Docker. Exact versions
are in `.tool-versions`.

```sh
docker compose up -d   # PostgreSQL 16 on localhost:5432, user and password postgres
mix setup              # dependencies, database, dashboard install and build
mix phx.server         # API on http://localhost:4000, which serves the last dashboard build
```

The dashboard is developed at http://localhost:5173, Vite's dev server, which
`mix phx.server` starts. It reloads on source edits and proxies `/api` to
Phoenix.

Suites:

```sh
mix precommit                       # compile, format, Credo, ExUnit with coverage
cd assets && npm run lint && npm run format:check && npm test
```

ExUnit runs the tests that need the built dashboard only after `mix assets.build`.

## Documentation

Everything lives in [docs/](docs/). Start with [docs/README.md](docs/README.md),
which describes what each document is for and how far to trust it.
