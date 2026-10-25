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
- **`POST /api/session`** signs in with a JSON email and password. The right pair
  answers 200 with the user's id, email and name, in a new session that keeps
  nothing from the one before. A wrong password and an unknown email both answer
  401 with the same body, after the same bcrypt work. **`DELETE /api/session`**
  drops the session and answers 204.
- **The session** is a cookie, signed and encrypted under the secret key base,
  HttpOnly, SameSite Lax, and Secure in production. It holds the user's id.
- **Static files** come from `priv/static`. Files under `/assets` are cached
  indefinitely, because their names carry a hash of their content.
- **Every other `GET`** answers with the dashboard's `index.html`, uncached, and
  the dashboard's router resolves the path. Without a build the answer is a 503.

Oban runs one `default` queue and prunes finished jobs after seven days. Its tables
come from the first migration. Primary keys default to database-generated UUIDs,
and timestamps to `timestamptz`.

## Accounts

The `Accounts` context holds users and their provider connections.

- **A user** has an email, unique whatever its case, a name, and a bcrypt hash of
  their password. The password itself is never stored.
- **A provider connection** holds one user's credential for one data provider,
  with Garmin the only provider: its API key, the key's expiry date, and the times
  of the last sync and of a pause. The key is encrypted with AES-256-GCM under the
  credential key, with a fresh nonce on every write, and a value that fails
  authentication does not load. A connection is deleted with its user.

## Dashboard

A React single-page app under `assets/`, built by Vite into `priv/static`
([0004](adr/0004-dashboard.md)).

- TanStack Router defines the routes in code. `/` redirects to `/today`.
- TanStack Query fetches through one API client, which sends cookies on the same
  origin and throws an error carrying the status and body of a failed response.
- Tailwind v4 takes its colours, fonts, radii and spacing step from
  `src/styles/tokens.css`, with Tailwind's default colours, fonts and radii
  cleared. Text sizes, tracking, weights and container widths come from
  Tailwind's defaults.
- A web app manifest starts the installed app at `/today`.

## Environments

| Environment | Server | Database | Jobs | Credential key |
| --- | --- | --- | --- | --- |
| dev | Phoenix on 127.0.0.1:4000, and Vite's dev server on 127.0.0.1:5173 proxying `/api` to it | `vire_dev` | Running | Fixed in `config/dev.exs` |
| test | Not started; requests go through the endpoint in-process | `vire_test`, one sandboxed transaction per test | Run by the test with Oban's manual testing mode | Fixed in `config/test.exs` |
| test, `VIRE_E2E=true` | Phoenix on 127.0.0.1:4002, serving the built dashboard | `vire_e2e`, unsandboxed | Running | Fixed in `config/test.exs` |
| prod | Port from `PORT`, redirecting plain HTTP to HTTPS except from localhost and for the health check | `DATABASE_URL` | Running | `VIRE_CREDENTIAL_KEY`, 32 bytes in base64; the release does not start without it |

## Tests

Integration first ([0003](adr/0003-testing.md)): ExUnit drives requests through
the endpoint against Postgres, and Vitest renders the whole app against the MSW
handlers in `assets/src/mocks`. Elixir tests tagged `dashboard_build` need the
built dashboard and are skipped without it. Playwright (`e2e/`, Chromium only)
opens the built dashboard served by Phoenix against the real database.
CI runs ExUnit, Vitest and Playwright as separate jobs; the ExUnit and Vitest
coverage thresholds fail the job when missed.
