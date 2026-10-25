# Vire

*Vire* (Finnish, [ˈʋire] — "VEE-reh") means tune, condition or state: the sense in
which an athlete is in good form.

Vire tracks workouts, nutrition, goals and athlete preferences, and serves them two
ways: an MCP server, so a conversational agent can coach the athlete from the full
history, and a web dashboard in any modern browser.

Workout files are uploaded to the application, decoded and stored.

## Development

Prerequisites: Elixir 1.20 on Erlang/OTP 29, and PostgreSQL 16 on localhost:5432
with user and password `postgres`. Exact versions are in `.tool-versions`.

```sh
mix setup              # dependencies and database
mix phx.server         # http://localhost:4000
mix precommit          # compile, format, Credo, ExUnit with coverage
```

## Documentation

Everything lives in [docs/](docs/). Start with [docs/README.md](docs/README.md),
which describes what each document is for and how far to trust it.
