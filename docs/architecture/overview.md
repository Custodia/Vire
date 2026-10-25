---
title: Architecture overview
lifecycle: living
---

# Architecture overview

Vire is one Elixir application, `vire`, against one PostgreSQL database
([0002](adr/0002-backend-stack.md)). It serves a JSON API and a single-page
dashboard, and runs background jobs in the same VM.

```
browser ──HTTP──▶ Phoenix endpoint ──▶ /api/*      JSON API
                                   ──▶ /assets/*   built dashboard files
                                   ──▶ /*          dashboard index.html
                  Oban ◀──────────────▶ PostgreSQL ◀── Ecto repo
```

## Server

The supervision tree starts the Ecto repo, Oban, Phoenix PubSub and the endpoint,
in that order.

- **`/api`** answers JSON only. `GET /api/health` runs a query against the
  database and answers `{"status": "ok"}`. Any other path under `/api` answers
  a JSON 404.
- **Static files** come from `priv/static`. Files under `/assets` are cached
  indefinitely, because their names carry a hash of their content.
- **Every other `GET`** answers with the dashboard's `index.html`, uncached, and
  the dashboard's router resolves the path. Without a build the answer is a 503.

Oban runs one `default` queue and prunes finished jobs after seven days. Its tables
come from the first migration. Primary keys default to database-generated UUIDs,
and timestamps to `timestamptz`.

## Environments

| Environment | Server | Database | Jobs |
| --- | --- | --- | --- |
| dev | Phoenix on 127.0.0.1:4000 | `vire_dev` | Running |
| test | Not started; requests go through the endpoint in-process | `vire_test`, one sandboxed transaction per test | Run by the test with Oban's manual testing mode |
| test, `VIRE_E2E=true` | Phoenix on 127.0.0.1:4002, serving the built dashboard | `vire_e2e`, unsandboxed | Running |
| prod | Port from `PORT`, redirecting plain HTTP to HTTPS except from localhost and for the health check | `DATABASE_URL` | Running |

## Tests

Integration first ([0003](adr/0003-testing.md)): ExUnit drives requests through
the endpoint against Postgres.
