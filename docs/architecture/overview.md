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
                  FIT decoder ──port──▶ node decoder/decode.js
```

## Server

The supervision tree starts the Ecto repo, the FIT decoder, Oban, Phoenix PubSub
and the endpoint, in that order.

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
- **`GET /api/me`** answers with the signed-in user's id, email and name. It
  sits behind the `:authenticated` pipeline, which answers a JSON 401 to a
  request without a signed-in user. `/api/health` and `/api/session` are public.
- **Static files** come from `priv/static`. Files under `/assets` are cached
  indefinitely, because their names carry a hash of their content.
- **Every other `GET`** answers with the dashboard's `index.html`, uncached, and
  the dashboard's router resolves the path. Without a build the answer is a 503.

Oban runs a `default` queue and an `ingest` queue of two, which parses files, and
prunes finished jobs after seven days. Its tables
come from the first migration. Primary keys default to database-generated UUIDs,
and timestamps to `timestamptz`.

## Accounts

The `Accounts` context holds users, their provider connections and the request
scope ([0005](adr/0005-access.md)).

- **A user** has an email, unique whatever its case, a name, and a bcrypt hash of
  their password. The password itself is never stored.
- **A provider connection** holds one user's credential for one data provider,
  with Garmin the only provider: its API key, the key's expiry date, and the times
  of the last sync and of a pause. The key is encrypted with AES-256-GCM under the
  credential key, with a fresh nonce on every write, and a value that fails
  authentication does not load. A connection is deleted with its user.
- **A scope** carries the signed-in user and the channel the request came
  through: the dashboard by default, or MCP with the client's id. Every request
  under `/api` is assigned one as `current_scope` when its session names an
  existing user. Every function that reads or writes a user's data takes the
  scope as its first argument and filters by its user.

## Training

The `Training` context holds the plan ([0006](adr/0006-training-plan-storage.md)).
Every function takes the scope first; a
row of another user reads as `nil` or an empty list, and a write to it fails as
not found. Every write takes a rationale: a new row keeps its own, and an update
or a delete takes the reason for the change.

- **The hierarchy** runs season, phase, block, cycle, day, session. Every level
  above the day has a period, a rationale and its parent, and a child points at
  its parent together with its user, so it cannot reference another user's row.
  A day is one date with a kind, training or rest, and a note. A session has a
  position within its day, a discipline, a structure of steps and targets as
  JSON, planned seconds, a status and a rationale. Deleting a level deletes
  everything beneath it.
- **Periods** are bounded `daterange` columns. The `Period` Ecto type reads and
  writes them as an inclusive first and last date and stores the half-open range
  Postgres keeps. Exclusion constraints stop a user's seasons, and the children
  of one parent, from overlapping. Triggers keep a child inside its parent's
  period and a day inside its cycle, and stop a parent from shrinking past a
  child. They raise check violations named after the rule, so a breach comes
  back as a changeset error on the period.
- **Days** come with their cycle: creating a cycle creates one rest day per
  date in its period, so a user has at most one day per date. A cycle created
  without a period runs from the day after the block's latest cycle, or from the
  block's first day, through the following Sunday, and stops at the block's end.
  Widening a cycle adds rest days for the new dates. Narrowing it removes the
  days it leaves out, and is refused while one of them holds a session.
- **Sessions** are created for a date and land on that date's day, which becomes
  a training day. A new date or position moves a session. Its status starts as
  planned and can be set to done or skipped.
- **The change log** records every write in the same transaction as one row:
  the entity and its id, insert, update or delete, the row before and after as
  JSON, the rationale, and the scope's channel and MCP client. A delete's
  cascade, and the days a cycle gains or loses, fall under the change of the row
  the caller acted on. Changes list newest first, by entity and id.
- **Reads** are the list of seasons, the plan from season to sessions for one
  season or for the seasons overlapping a period, and one day with its sessions
  and the chain above it from the `training_day_contexts` view.

## Ingest

The `Ingest` context receives files and turns them into data
([0007](adr/0007-source-file-storage.md)). Every function takes the scope first,
and another user's file reads as `nil`, except the one that enqueues outdated
files for every user.

- **A source file** keeps the bytes of one received file with its kind, a
  `.fit` file or a nutrition export, its origin, Garmin's API, an upload or MCP,
  its SHA-256 and its size. Storing bytes the user already has by hash returns
  the stored file as it stands, and says so. A file is read without its bytes
  unless they are asked for.
- **Its status** is pending until a processor reads it, then processed with the
  processor's version, or failed with the error. Check constraints hold those
  pairings.
- **The decoder** is a supervised process owning an Erlang port to a Node
  process that runs `decoder/decode.js` with Garmin's FIT JavaScript SDK
  ([0008](adr/0008-fit-decoding.md)). Requests and answers are JSON framed by
  a four-byte big-endian length. Node checks a file's header, size and CRC and
  answers with the SDK's messages grouped by type, developer fields named after
  their descriptions, and the units of record and developer fields, or with an
  error naming what failed. Requests are served one at a time in the order they
  arrive, each with a timeout, 30 seconds by default, that kills the Node
  process. An answer that is not a response fails its request and kills the
  Node process too; the SDK's console output goes to stderr so that stdout
  carries only responses. A Node process that exits fails the request it was
  serving, and the next request starts a new one.
- **A parse job** on the `ingest` queue reads one `.fit` file: it decodes the
  file, normalises the messages into an activity with its laps, lengths and
  streams, writes them and marks the file processed in one transaction. A file
  the decoder or the parser rejects, or whose parse raises, is marked failed
  with the error and kept, and the job is cancelled; a decoder that does not
  answer marks it failed and the job is retried, up to three attempts. A file has at most one job waiting
  or running. Each parse stores the worker's processor version, and enqueuing
  outdated files queues a parse of every processed file an older version read.
- **Normalising** takes the start from the first session, and the UTC offset
  from the activity message's local timestamp against its timestamp, rounded
  to the quarter hour; the local date is the start at that offset. The
  duration is the sessions' timer time. Garmin's sport and sub-sport are kept
  in the FIT profile's snake-case names and map to a discipline: cycling to
  bike, running to run, swimming to swim, training or the strength-training
  sub-sport to strength, anything else to other. Every numeric record field
  becomes a stream with the SDK profile's unit, and every numeric developer
  field one named after its description unless a native field already holds
  the name. Enhanced speed and altitude stand in for the plain fields, position
  is in degrees, cadence carries its fractional part, and a run's cadence is in
  steps per minute. A swim's lengths belong to the last lap that starts at or
  before them.

## Activities

The `Activities` context holds what was recorded. Every function takes the
scope first, and another user's activity reads as `nil` or is left out.

- **An activity** has its start, its UTC offset and local date, a discipline,
  the recording's sport and sub-sport, a duration, a distance and, for pool
  swims, the pool length. It comes from one source file, which it points at
  with its user, or from a provider with an external id. Parsing a file again
  updates the activity and replaces its children.
- **Laps** carry their start, elapsed and moving seconds, distance and average
  heart rate, power and speed. **Lengths** of a pool swim carry their lap,
  start, elapsed seconds, whether they were swum or rested, the stroke and the
  stroke count.
- **A stream** is one recorded channel with its unit and one sample per elapsed
  second from the start, `null` where nothing was recorded, so a pause reads as
  `null`s.
- **Reads** are the activities with a local date in a range, newest first and
  optionally of one discipline; one activity with its laps and lengths; the
  activity of a source file; and chosen streams at a number of seconds per
  sample, each sample the mean of the window's recorded values, or the first
  recorded value for position.
- **A planned session** points at its matched activity with its user, and
  loses the match when the activity is deleted.

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

| Environment | Server | Database | Jobs | Credential key | Node |
| --- | --- | --- | --- | --- | --- |
| dev | Phoenix on 127.0.0.1:4000, and Vite's dev server on 127.0.0.1:5173 proxying `/api` to it | `vire_dev` | Running | Fixed in `config/dev.exs` | Vite's dev server and the FIT decoder |
| test | Not started; requests go through the endpoint in-process | `vire_test`, one sandboxed transaction per test | Run by the test with Oban's manual testing mode | Fixed in `config/test.exs` | The FIT decoder |
| test, `VIRE_E2E=true` | Phoenix on 127.0.0.1:4002, serving the built dashboard | `vire_e2e`, unsandboxed | Running | Fixed in `config/test.exs` | The FIT decoder |
| prod | Port from `PORT`, redirecting plain HTTP to HTTPS except from localhost and for the health check | `DATABASE_URL` | Running | `VIRE_CREDENTIAL_KEY`, 32 bytes in base64; the release does not start without it | The FIT decoder, run from `VIRE_DECODER_SCRIPT`, the path of `decode.js` in a copy of `decoder/` with its packages installed; the release does not start without it |

## Tests

Integration first ([0003](adr/0003-testing.md)): ExUnit drives requests through
the endpoint against Postgres and decodes the synthetic `.fit` fixtures in
`test/support/fixtures/fit` with the real decoder, and Vitest renders the whole
app against the MSW handlers in `assets/src/mocks`. Elixir tests tagged
`dashboard_build` need the built dashboard and are skipped without it.
Playwright (`e2e/`, Chromium only) opens the built dashboard served by Phoenix
against the real database. CI runs ExUnit, Vitest and Playwright as separate
jobs; the ExUnit and Vitest coverage thresholds fail the job when missed.
