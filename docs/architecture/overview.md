---
title: Architecture overview
lifecycle: living
---

# Architecture overview

Vire is one Elixir application, `vire`, against one PostgreSQL database
([0002](adr/0002-backend-stack.md)). It serves a JSON API, a single-page
dashboard, and an MCP endpoint with the OAuth endpoints its clients authorize
through, and runs background jobs in the same VM.

```
browser ────HTTP──▶ Phoenix endpoint ──▶ /api/*          JSON API
MCP client ─HTTP──▶                  ──▶ /mcp            MCP, JSON-RPC over streamable HTTP
                                     ──▶ /.well-known/*  OAuth metadata
                                     ──▶ /oauth/*        OAuth 2.1 authorization server
                                     ──▶ /assets/*       built dashboard files
                                     ──▶ /*              dashboard index.html
                  Oban ◀──────────────▶ PostgreSQL ◀── Ecto repo
                  Oban jobs ──HTTPS──▶ Garmin Personal API
                  FIT decoder ──port──▶ node decoder/decode.js
```

## Server

The supervision tree starts the Ecto repo, the FIT decoder, the Garmin token
cache, Oban, Phoenix PubSub and the endpoint, in that order.

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
- **Unsafe requests under `/api`**, all but GET, HEAD and OPTIONS, carry the
  session's CSRF token in an `x-csrf-token` header; one without it answers 403
  with the reason `invalid_csrf_token`. **`GET /api/csrf`** answers the
  session's token. Signing in ends the token the session held.
- **`GET /api/me`** answers with the signed-in user's id, email and name. It
  sits behind the `:authenticated` pipeline, which answers a JSON 401 to a
  request without a signed-in user. `/api/health`, `/api/csrf` and
  `/api/session` are public.
- **`POST /api/uploads`** takes a multipart upload in the field `file`, capped at
  20 MB. A file with a FIT header is stored as a `.fit` file from an upload and
  its parse job enqueued in one transaction; the answer is 201 with the file's
  id and status. A file the user already has answers 200 with the existing file
  and enqueues nothing. A missing file or one without a FIT header answers 422.
  **`GET /api/uploads/:id`** answers the file's status, processor version, error
  and, once processed, its activity's id. Another user's file answers 404. Both
  sit behind the `:authenticated` pipeline.
- **`GET /api/days/:date`** answers one date for the dashboard, behind the
  `:authenticated` pipeline: `date`; `day`, with its kind, its note, the chain
  of season, phase, block and cycle above it, the cycle with its kind, the
  day's number within it and its length, and its sessions in position order,
  each with its title (the structure's `title`, or the discipline's name),
  structure, planned seconds, status, rationale and the summary of its matched
  activity; and `activities`, the summaries of the date's activities no
  session is matched to. An activity summary is its id, discipline, start, UTC
  offset, duration, distance and training load. A date outside every cycle
  answers `day: null`; a malformed date answers 400.
  **`GET /api/days?from=&to=`** answers `days`, every date from `from` to `to`
  in order, each as `GET /api/days/:date` answers it, from one query per kind
  of row. A range longer than 42 days, reversed or missing an end answers 400.
- **`GET /api/seasons`** answers the user's seasons, earliest first, each with
  its id, name and period, behind the `:authenticated` pipeline.
  **`GET /api/seasons/:id`** answers one season with its rationale and
  everything beneath it: its phases with their rationale, each phase's blocks
  with their focus,
  each block's cycles with their kind, and each cycle's days with their kind,
  note and sessions, a session as its discipline, title, planned seconds,
  status and position. Every level carries its period. Beside the phases are
  the activities on the season's dates that no session is matched to, each with
  its id, discipline, local date, start, UTC offset, duration, distance and
  training load. Another user's season, an unknown one, and an id that is not a
  UUID all answer 404.
- **`GET /api/plan_changes`** answers the user's eight latest plan changes,
  newest first, behind the `:authenticated` pipeline. A change is its entity,
  action, subject (the name, focus, cycle kind, date or session title of the
  row it acted on), rationale, channel, MCP client name and time.
- **`GET /api/sessions/:id`** answers a session as a day lists it, with its
  day (id, date, kind, note and chain), its matched activity in full, and
  `last_time`: the latest session before its date with the same discipline
  and title that has a matched activity, as its id, date and that activity's
  summary with its average heart rate, or `null`.
  **`PUT /api/sessions/:id/activity`** matches the session to the activity
  with the JSON `activity_id`, which makes it done, or clears its match with
  `null`, logging the change from the dashboard; it answers the session as
  `GET` does. An activity on another date or matched to another session
  answers 422.
  **`GET /api/activities/:id`** answers an activity in full: its summary, local
  date, pool length, average heart rate (its laps' heart rates weighted by
  their time), laps and pool lengths.
  **`GET /api/activities/:id/streams?channels=&step=`** answers the named
  channels, or every recorded one, at `step` seconds per sample; a `step` that
  is not a whole number from 1 answers 400. All four sit behind the
  `:authenticated` pipeline and answer 404 for another user's session or
  activity.
- **`POST /mcp`** is the MCP endpoint ([0010](adr/0010-mcp-access.md)). The
  `:mcp` pipeline answers 403 to an `Origin` header naming another host than
  the endpoint's, and then checks the bearer token. Without one it answers 401
  with `WWW-Authenticate: Bearer resource_metadata="<protected resource
  metadata URL>"`; an unknown, expired or revoked token adds
  `error="invalid_token"`. A valid token assigns `current_scope` with its
  user, the MCP channel and its client. Each request carries one JSON-RPC 2.0
  message, which the endpoint reads and decodes itself, outside the body
  parsers, up to a megabyte. A request is answered with JSON, a notification or
  a client's response with 202 and no body; there is no session id. A body
  that is not JSON answers 400 with -32700, and a batch or a message that is
  not JSON-RPC 2.0 answers 400 with -32600. An `MCP-Protocol-Version` header
  naming an unsupported version answers 400, except on `initialize`. **`GET`
  and `DELETE /mcp`** answer 405.
- **`GET /files/:id`** serves one source file's bytes to whoever holds a URL
  signed for it ([0010](adr/0010-mcp-access.md)), with no session or token. A
  `.fit` file answers as `application/vnd.ant.fit`, any other as
  `application/octet-stream`, as an attachment named after the file's id and
  uncached. A missing, altered or expired signature, or a file that is not the
  signing user's, answers a JSON 404.
- **The OAuth metadata** for MCP clients ([0010](adr/0010-mcp-access.md)):
  `GET /.well-known/oauth-protected-resource`, also served at
  `/.well-known/oauth-protected-resource/mcp`, names `/mcp` as the resource
  and the application's URL as its authorization server.
  `GET /.well-known/oauth-authorization-server` names the issuer, the
  authorization, token and registration endpoints, the `code` response type,
  the `authorization_code` and `refresh_token` grants, the S256 challenge
  method and the `none` token endpoint auth method. Every URL is built from the
  endpoint's configured URL.
- **`POST /oauth/register`** registers a client from a JSON `client_name` and
  `redirect_uris` and answers 201 with its `client_id` and no secret. A bad
  redirect URI answers 400 with `invalid_redirect_uri`, a missing name with
  `invalid_client_metadata`.
- **`GET /oauth/authorize`** takes `response_type=code`, `client_id`,
  `redirect_uri`, an S256 `code_challenge`, `state`, and optionally `scope`,
  which is ignored, and `resource`. An unknown client, an unregistered redirect
  URI or a missing challenge answers a 400 page; a wrong response type or
  resource redirects to the client with the error. Without a signed-in user it
  answers a sign-in page whose form posts to **`POST /oauth/sign_in`**, which
  signs in as `POST /api/session` does and redirects back to the same request.
  With one it answers a consent page whose approve and deny buttons post to
  **`POST /oauth/authorize`**: approve redirects to the redirect URI with
  `code` and `state`, deny with `error=access_denied` and `state`.
- **`POST /oauth/token`** takes a form. The `authorization_code` grant takes
  `code`, `code_verifier`, `client_id` and `redirect_uri`; the `refresh_token`
  grant takes `refresh_token` and `client_id`. Both answer a Bearer access
  token, `expires_in` and a refresh token, uncached. Errors are RFC 6749
  JSON: `invalid_request`, `invalid_grant` and `unsupported_grant_type` with
  400, `invalid_client` with 401.
- **Cross-origin calls**: the metadata, registration and token endpoints answer
  any origin and its preflight, because browser-based clients call them from
  their own origin. None of them reads the session.
- **The `:browser` pipeline** serves the sign-in and consent pages: HTML from
  server-rendered templates with an inline stylesheet, the session, CSRF protection
  on every post, the signed-in scope, and secure headers whose content security
  policy admits only that stylesheet, by hash, and forbids framing.
- **Static files** come from `priv/static`. Files under `/assets` are cached
  indefinitely, because their names carry a hash of their content.
- **Every other `GET`** answers with the dashboard's `index.html`, uncached, and
  the dashboard's router resolves the path. Without a build the answer is a 503.

Oban runs a `default` queue, an `ingest` queue of two, which parses files, and a
`garmin` queue of one, which makes every call to Garmin. Outside tests its cron
enqueues the Garmin syncs every three hours, and it prunes finished jobs after
seven days. Its tables come from the first migration. Primary keys default to
database-generated UUIDs, and timestamps to `timestamptz`.

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
  existing user, and every request to `/mcp` one from its access token. Every function that reads or writes a user's data takes the
  scope as its first argument and filters by its user.

## Mcp

The `Mcp` context holds MCP clients, the grants that let them act for a user,
and the protocol server with its tools ([0010](adr/0010-mcp-access.md)). Codes and tokens are 32 random bytes,
and only their SHA-256 is stored.

- **A client** has a random client id, a name and one to ten redirect URIs,
  each https, or http on `localhost` or `127.0.0.1`, without a fragment. A
  registered client is public and has no secret.
- **An authorization request** is checked in order: the client, the exact
  redirect URI, and the S256 challenge, whose failures are shown and not
  redirected; then the response type and the resource, whose failures go
  back to the redirect URI with the request's state.
- **An authorization code** names its user, client, redirect URI and
  challenge, and lives ten minutes. It is exchanged once, for the same client
  and redirect URI, with a verifier whose S256 hash is the challenge. A code
  presented again revokes every token its user holds for that client.
- **A token** row holds an access token's hash and expiry, an hour after
  issue, its refresh token's hash and a revocation time. The refresh token
  lasts thirty days from the row's creation. A refresh revokes the row and
  issues a new one; a revoked refresh token presented again revokes every
  token its user holds for that client. Codes and tokens are deleted with
  their user or client.
- **The change log** points at the client of a change made over MCP.
- **The protocol server** answers one message for a scope. `initialize`
  answers protocol version 2025-06-18 when asked for it or a newer one,
  2025-03-26 when asked for that, and 2025-06-18 otherwise, with the tools and
  resources capabilities and the application's name and version. It answers
  `ping`, `tools/list`, `tools/call`, `resources/list` and
  `resources/templates/list`, both empty, and `resources/read`, which is
  always -32002. An unknown method is -32601, params that are not an object
  -32602.
- **Tools** are defined in groups. A group module answers a list of tools,
  each a name, a description, a JSON Schema for its arguments and a function
  of the scope and the arguments, and the registry lists the groups. `tools/list`
  describes every registered tool, and `tools/call` of an unknown name is
  -32602. Arguments are checked against the schema before the tool runs, and
  a field it does not name is refused. A tool answering `{:ok, map}` gives a
  result with the map as its structured content and the same JSON as text.
  Refused arguments and a changeset give a result with `isError` whose
  structured content and text are `{ok: false, errors}`, each error a path
  such as `ops[3].sessions[2].date` and a message; `:not_found` or a message
  gives one with a text explaining it. A tool that raises is logged and
  answers -32603.
- **The plan tools** call the `Training` and `Ingest` functions. Dates are
  ISO 8601 strings, ids are UUID strings, and a period is an object of an
  inclusive `first` and `last` date. A `when` argument names dates absolute
  or relative to the UTC date: a date, `today`, `yesterday`, `tomorrow`,
  `-3d` or `+2d`, the last, this or next week (Monday to Sunday), month or
  cycle, this block, phase or season, or `{first, last}` of those; answers
  give it back as a period.
  - `read_plan` lists the rows of one level, `from`, each going down to
    `to`, by default from the season to every step; `to: "session"` keeps a
    session's structure title and note without its steps. Rows below a
    season carry their chain of the rows above. `when` keeps the rows
    overlapping its dates at every level, `season_id` one season, and
    `filter` the sessions of given statuses and disciplines, or the planned
    ones before today, with the rows above them. `summary` adds each cycle's
    session counts and its planned and matched seconds. A session without an
    activity carries the candidates the matcher scores above 0.
  - `write_plan` takes a `change_log` and a list of creates, updates and
    deletes, each one shape per level, run in order as one batch. A create
    carries the rows beneath it, down to a cycle's days and sessions, and a
    day is updated by its date. A create's root requires a `rationale`, which
    the rows nested in it inherit unless they give their own; an update's
    rationale replaces the row's. The change log entry goes to every write of
    the op, or the op's own when it gives one. It answers the ids of the rows
    written in the shape of the ops, or every error with its path and nothing
    written. The plan's rules are written in its description.
  - `match_session` sets or clears a session's activity with a change log
    entry and answers the session with its candidates; `sync_now` enqueues a
    sync.
- **The activity tools** call the `Activities`, `Ingest` and `Training`
  functions: `list_activities` for the summaries on the dates a `when` names,
  optionally of one discipline or only those no session is matched to, each
  with the id of its matched session; `get_activity` with its laps, lengths,
  the provider's summary and its matched session; `get_activity_streams` for
  chosen channels, or every recorded one, at a number of seconds per sample;
  and `get_activity_files`, which answers for up to 50 activities a signed URL
  for each original file with its expiry, the file's size and its SHA-256 in
  hex, and the activities it has no file for with the reason.

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
  position within its day, a discipline, a structure as JSON, planned seconds,
  a status and a rationale. Deleting a level deletes everything beneath it.
- **A session's structure** may hold `title` and `note` strings and a list of
  `steps` ([0011](adr/0011-dashboard-design-system.md)). A step has a kind
  (warmup, work, recovery, cooldown or rest), seconds, and optionally a zone
  from 1 to 5, a target and a note; a repeat has a count and its own steps.
  The changeset checks the steps and names the path of the first step at
  fault; other keys are kept as given.
- **Periods** are bounded `daterange` columns. The `Period` Ecto type reads and
  writes them as an inclusive first and last date and stores the half-open range
  Postgres keeps. Exclusion constraints stop a user's seasons, and the children
  of one parent, from overlapping. Triggers keep a child inside its parent's
  period and a day inside its cycle, and stop a parent from shrinking past a
  child. They raise check violations named after the rule, so a breach comes
  back as a changeset error on the period. The overlap and trigger checks are
  deferrable, and a batch defers them to its end.
- **Days** come with their cycle: creating a cycle creates one rest day per
  date in its period, so a user has at most one day per date. A cycle created
  without a period runs from the day after the block's latest cycle, or from the
  block's first day, through the following Sunday, and stops at the block's end.
  Widening a cycle adds rest days for the new dates. Narrowing it removes the
  days it leaves out, and is refused while one of them holds a session.
- **Sessions** are created for a date and land on that date's day, which becomes
  a training day. A new date or position moves a session. Its status starts as
  planned and can be set to done or skipped.
- **Matching** pairs one local date's activities with its sessions, after a
  parse stores an activity and after a Garmin summary is stored. Each of the
  day's unmatched activities gets a confidence for each unmatched session of
  its discipline, from how close its duration is to the planned one, whether
  its place by start time is the session's place by position, and whether it
  is the day's only one of the discipline. A pair at 0.8 or above that leads
  every other pair of its activity and its session by 0.15 is matched, which
  makes the session done and writes no change; the rest stay unmatched. A
  match by hand sets or clears a session's activity, which must be the user's
  and on the session's date, makes it done or planned, and is logged;
  automatic matching leaves such a session out, and a skipped one too. Only a
  hand sets a session skipped. A per-user advisory lock serialises matching.
- **A batch** runs many writes in one transaction and checks the period rules
  once they have all run, so a block can shrink and its neighbour grow in
  either order. It first gives every cycle a rest day for each date it lacks
  one, then reports every row breaking a rule with the rule, rolling
  everything back.
- **The change log** records every write in the same transaction as one row:
  the entity and its id, insert, update or delete, the row before and after as
  JSON, the reason given or a new row's own rationale, and the scope's channel
  and MCP client. A delete's
  cascade, and the days a cycle gains or loses, fall under the change of the row
  the caller acted on. Changes list newest first, by entity and id, or as the
  latest few with the name of the MCP client behind each.
- **Reads** are the list of seasons, the start and end of every row of a
  level, the plan from season to sessions for one season, for the seasons
  overlapping a period or for every season, one day with its cycle, its
  sessions and the chain above it from the `training_day_contexts` view, and
  the activities on a local date that no session is matched to, earliest
  first. Candidates are the unmatched activities on an unmatched session's
  date the matcher scores above 0, most likely first. A cycle's summary counts
  its sessions planned, done, skipped and still planned before today, and sums
  their planned seconds and their matched activities' seconds.

## Ingest

The `Ingest` context receives files and turns them into data
([0007](adr/0007-source-file-storage.md)), and syncs activities from Garmin
([0009](adr/0009-garmin-sync.md)). Every function takes the scope first, and
another user's file reads as `nil`, except the ones that enqueue outdated
files and scheduled syncs for every user.

- **A source file** keeps the bytes of one received file with its kind, a
  `.fit` file or a nutrition export, its origin, Garmin's API, an upload or MCP,
  its SHA-256 and its size. Storing bytes the user already has by hash returns
  the stored file as it stands, and says so. A file is read without its bytes
  unless they are asked for.
- **A signed file URL** names one of the user's files under `/files/:id`
  with the user's id, an expiry fifteen minutes after it is made, and an
  HMAC-SHA256 over the file id, the user id and the expiry, keyed by a key
  derived from the endpoint's secret key base, which production reads from
  `SECRET_KEY_BASE`. Building one answers the URL and its expiry.
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
  sub-sport to strength, anything else to other. The same lookup maps Garmin's
  activity type keys, such as virtual ride or lap swimming. Every numeric
  record field becomes a stream with the SDK profile's unit, and every numeric
  developer field one named after its description unless a native field
  already holds the name. Enhanced speed and altitude stand in for the plain
  fields, position is in degrees, cadence carries its fractional part, and a
  run's cadence is in steps per minute. A swim's lengths belong to the last lap that starts at or
  before them.
- **The Garmin client** acts for one user's provider connection. It exchanges
  the API key for a bearer token, kept in memory per connection and exchanged
  again once less than an hour of its 24 remains or after the key changes. A
  request Garmin answers 401 to is sent once more with a newly exchanged token.
  It searches activities between two local dates in pages of 99, and
  downloads an activity's `.fit` file out of Garmin's ZIP. A 429 or 5xx
  answer, or a request with no answer, is retried up to three times with
  exponential back-off. The key and the token appear in no log line and no
  error.
- **A sync** runs one user's discovery on the `garmin` queue, of every season
  or of the seasons' dates within a range. It searches each season from its
  first day to the earlier of its last day and the day after today's UTC
  date, since Garmin filters on local dates, and stores
  each summary as an activity. Every activity without a file, except manual
  ones, gets a download job, each scheduled five seconds after the one before.
  A run in which every search succeeds records the time on the connection. A
  key the token endpoint refuses, or a run in which every search fails, pauses
  the connection and cancels the job; a run with only some searches failing
  is retried, up to three attempts. One sync per user waits at a time:
  enqueuing another widens the waiting one to cover both ranges. A sync is
  enqueued only for a user with an unpaused Garmin connection: by the
  three-hourly cron for every such user, for the dates of a season created or
  the dates a season's new period gains, or on request.
- **A download** fetches one activity's file, stores it as a `.fit` file from
  Garmin's API, attaches it to the activity and enqueues its parse, in one
  transaction. A file the user already has is attached as it is; when an
  activity from an upload already holds it, the Garmin activity's provider
  fields move to that one and the Garmin activity is deleted. Garmin answering
  404, or a ZIP without a `.fit` file, cancels the download; other failures
  are retried, up to five attempts. One download job per activity is kept, so
  a cancelled or discarded download is not queued again until its job is
  pruned.

## Activities

The `Activities` context holds what was recorded. Every function takes the
scope first, and another user's activity reads as `nil` or is left out.

- **An activity** has its start, its UTC offset and local date, a discipline,
  the recording's sport and sub-sport, a duration, a distance and, for pool
  swims, the pool length. It comes from one source file, which it points at
  with its user, or from a provider with an external id, its training load and
  the provider's whole summary as JSON, or from both. Parsing a file again
  updates the activity and replaces its children.
- **One row per activity, whichever side arrives first.** A provider summary
  updates the activity with its provider and external id, or else attaches to
  the activity from a file without a provider that started within a minute of
  it.
  A parsed file goes to the activity that holds it, or else to the provider
  activity without a file that started within a minute of it. Only the file
  sets the recorded fields once it backs the activity; the summary keeps the
  provider fields. A per-user advisory lock serialises these writes.
- **Laps** carry their start, elapsed and moving seconds, distance and average
  heart rate, power and speed. **Lengths** of a pool swim carry their lap,
  start, elapsed seconds, whether they were swum or rested, the stroke and the
  stroke count.
- **A stream** is one recorded channel with its unit and one sample per elapsed
  second from the start, `null` where nothing was recorded, so a pause reads as
  `null`s.
- **Reads** are the activities with a local date in a range, newest first and
  optionally of one discipline; the activities with given ids; one activity
  with its laps and lengths; the activity of a source file; and chosen streams
  at a number of seconds per sample, each sample the mean of the window's
  recorded values, or the first recorded value for position.
- **A planned session** points at its matched activity with its user, and
  loses the match when the activity is deleted.

## Dashboard

A React single-page app under `assets/`, built by Vite into `priv/static`
([0004](adr/0004-dashboard.md)).

- TanStack Router defines the routes in code. `/` redirects to `/calendar`,
  which redirects to the browser's date in the day view.
  `/sign-in` is public; every other route sits behind a guard that asks
  `GET /api/me` once, through a query cached for the life of the page, and
  sends a 401 to `/sign-in` with the path it came from in `redirect`. Any
  other request answering 401 means the session has ended: the dashboard goes
  to `/sign-in` the same way and clears every cached query.
- TanStack Query fetches through one API client, which sends cookies on the same
  origin and throws an error carrying the status and body of a failed response.
  A failed query is retried up to three times, and never after a 4xx answer.
- **Sign-in** posts the email and password to `POST /api/session`, says so on a
  401, and on success caches the user and goes to `redirect` when it names a
  path on the same origin, or to `/calendar`. **Sign-out** posts
  `DELETE /api/session`, clears every cached query and returns to `/sign-in`.
  A route whose data fails to load shows an error with a retry.
- **Unsafe requests** carry the session's CSRF token, which the dashboard fetches
  from `GET /api/csrf` before the first one and forgets on signing in and out. A
  request the server refuses for its token is sent once more with a fresh one.
- **The frame** holds every signed-in screen and stays put as the screens
  change. A window at least 64rem wide gets the desktop layout: a board under a
  bar holding the wordmark, links to the calendar and the plan and the Sign out
  action. A narrower one gets the phone layout: the screen in a column inside
  the safe area, over tabs for the calendar, the plan and More. More opens a
  sheet with the user and Sign out. A sheet rises from the bottom edge on a
  phone and closes when dragged down by its handle; on a desktop it is a card
  in the middle. A session still planned on a day before the browser's date
  shows as skipped on every screen; its stored status stays planned.
- **States** draw the same on every screen. A session is a ring: thick with a
  tick when done, thin in its discipline's colour while upcoming, thin with a
  cross when skipped, and thick grey with a plus for an activity no session is
  matched to; in a calendar day it is a chip in the same states, and on the
  phone's month a dot. A day is one ring split evenly between its sessions,
  each arc thick when done and thin otherwise, circled in the accent on today.
  A day without sessions is a dashed ring and a Rest chip, green and ticked once
  it is past.
- **The calendar** shows a month, a week or a day around a date, at
  `/calendar/:view/:date`. It reads `GET /api/days` for the dates the view
  shows, under the query key `["days", from, to]`, prefetches the periods on
  either side, and reads the season above them for block numbers, cycle names
  and the weeks to the season's end. On a desktop a bar steps a period back
  and on, goes to today and switches between Month, Week and Day, keeping the
  date; in the view switch the view shown leads to today. The calendar opens
  on today in the view last shown, kept in local storage. On a phone the view
  switch sits in a bar above the tabs, and a finger sliding along it carries
  the selection to another view. A sideways drag on the page pulls the period
  before or after in under the finger, stepping to it when let go far or fast
  enough.
  Recorded sessions and activities are listed by their start, then the
  sessions left in plan order, the first still planned today marked Next.
  - **Month** holds the whole weeks the month touches. On a desktop each day
    lists its sessions as chips and links to its day, each week ends in a cell
    of its cycles and hours that links to its week, and the header counts the
    month's sessions done and hours trained. On a phone each day shows its
    sessions as dots; choosing one selects it and lists its sessions below.
  - **Week** runs Monday to Sunday: each day's hours trained as a bar against
    those planned, then a row for each day with its ring and hours, linking to
    it. On a desktop the row holds a card for each session and activity,
    linking to it, and the header counts the week's sessions done and skipped
    and its hours.
  - **Day** on a desktop lays its week across the top, its sessions and
    unmatched activities on the left over empty readiness and weight trend
    cards, and the shown session or activity beside them: the day's next
    session, else its first session or activity. On a phone the week is a
    strip of day rings over the day's progress and a timeline: each session
    and activity a card that opens to its figures and a link to its page, the
    next session open, and an unmatched activity offering Match. Match offers
    the day's sessions without an activity and puts the match through
    `PUT /api/sessions/:id/activity`.
  - **A session** (`/sessions/:id`) and **an activity** (`/activities/:id`, or
    the session it is matched to) show beside their day on a desktop, and as a
    page of their own on a phone, under a link back to the day that a swipe to
    the right also follows. A session shows its state, its stats, or its
    recorded duration, distance, training load and heart rate against the
    plan, its structure as a workout profile with the zone legend, the steps
    and its rationale, and the last session like it. An activity shows its
    stats. A recording adds its laps, its pool lengths for a swim, and for a
    ride or a run a chart of power and heart rate or heart rate and pace. The
    chart asks `GET /api/activities/:id/streams` for about one sample per two
    pixels of its width, and uPlot, loaded only where the browser can draw on a
    canvas, draws it in the token colours. A URL that holds no calendar date
    says so.
- **The plan** (`/plan`) reads `GET /api/seasons` and then the chosen season,
  which is the one holding the browser's date unless `season` in the query
  names another; with more than one season, buttons above the header switch.
  The season leads as the goal, with its rationale and the weeks left to its
  end, beside empty trend weight and chronic load stats. A season map lays the
  phases, the blocks, the hours each week and an empty weight row along the
  season's dates, marking what is done, current and planned, the spans no
  phase or block covers, and today. Each week's bar outlines its planned hours
  and fills them with its done sessions, its activities outside the plan and
  the sessions still to come, leaving the hours of skipped sessions empty.
  Hovering or focusing a week lists them, and choosing it opens its week in
  the calendar. Choosing a phase or block on the map selects it, opening on the block
  holding today. A table lists the selected phase's blocks with their dates,
  cycles drawn to length with their pattern, focus and planned hours. The
  selected block's days form a calendar of weeks from Monday, each row naming
  the cycles in it, a cycle longer than a week continuing on the next row and
  a cycle starting mid-week named on its first day. A day shows its sessions
  in their discipline's colours, or marked done or skipped, and links to its
  day in the calendar. Beside them, an empty season targets card and a coach
  log of `GET /api/plan_changes`. On a phone the map is a strip that scrolls
  through the season from today, and the chosen phase's blocks are cards, the
  one holding today open, each opening to its cycles as rows of day rings that
  link to the week of the cycle. A user without a season is told the plan
  starts with one.
- Tailwind v4 takes its colours, fonts, radii, spacing step, board width and
  the text sizes the boards add to Tailwind's scale from `src/styles/tokens.css`
  ([0011](adr/0011-dashboard-design-system.md)), with Tailwind's default
  colours, fonts and radii cleared. Other text sizes, tracking, weights and
  container widths come from Tailwind's defaults. Inter and Barlow Condensed
  are bundled from fontsource packages.
- `src/ui/` holds the components screens are built from, one per file: `Stat`,
  `StatusChip`, `SessionChip`, `DisciplineIcon`, `TrainingZoneBadge`,
  `TrainingZoneLegend`, `WorkoutProfile`, `SessionRow`, `CoachNote`, `Empty`,
  `Button`, `TextField`, `StreamChart`, `Card`, `PageHeader`, `TopBar`,
  `TabBar`, `Sheet`, the marks of sessions and days, the signed-in `Frame` and
  `PhoneFrame` and the signed-out `Screen`, a narrow column.
  `WorkoutProfile` draws a session's steps as an SVG of bars as wide as their
  seconds and as tall as their zone, with repeats written out.
- A web app manifest starts the installed app at `/calendar` in its own window,
  with PNG icons for Android and iOS home screens.

## Environments

| Environment | Server | Database | Jobs | Credential key | Node | Garmin API |
| --- | --- | --- | --- | --- | --- | --- |
| dev | Phoenix on 127.0.0.1:4000, and Vite's dev server on 127.0.0.1:5173 proxying `/api` to it | `vire_dev` | Running, with the cron | Fixed in `config/dev.exs` | Vite's dev server and the FIT decoder | `personal.connectapi.garmin.com` |
| test | Not started; requests go through the endpoint in-process | `vire_test`, one sandboxed transaction per test | Run by the test with Oban's manual testing mode | Fixed in `config/test.exs` | The FIT decoder | `Req.Test` stubs; the base URL is 127.0.0.1:9, where nothing listens |
| test, `VIRE_E2E=true` | Phoenix on 127.0.0.1:4002, serving the built dashboard | `vire_e2e`, unsandboxed | Running, without the cron | Fixed in `config/test.exs` | The FIT decoder | 127.0.0.1:9, where nothing listens |
| prod | Port from `PORT`, redirecting plain HTTP to HTTPS except from localhost and for the health check | `DATABASE_URL` | Running, with the cron | `VIRE_CREDENTIAL_KEY`, 32 bytes in base64; the release does not start without it | The FIT decoder, run from `VIRE_DECODER_SCRIPT`, the path of `decode.js` in a copy of `decoder/` with its packages installed; the release does not start without it | `personal.connectapi.garmin.com` |

## Tests

Integration first ([0003](adr/0003-testing.md)): ExUnit drives requests through
the endpoint against Postgres and decodes the synthetic `.fit` fixtures in
`test/support/fixtures/fit` with the real decoder, with Garmin's API stubbed by
`Req.Test` answering invented JSON and ZIPs built from the fixtures, and Vitest
renders the whole app against the MSW handlers in `assets/src/mocks`, which
hold the API's response shapes, whether the browser is signed in and the
session's CSRF token, which they check as the server does. OAuth
tests register a client and drive the sign-in and consent pages with their
CSRF tokens checked, as a browser's posts are, and MCP tests call `/mcp` with
the access token that flow ends in. Elixir
tests tagged `dashboard_build` need the built dashboard and are skipped without
it.
Playwright (`e2e/`, Chromium only) opens the built dashboard served by Phoenix
against the real database. CI runs ExUnit, Vitest and Playwright as separate
jobs; the ExUnit and Vitest coverage thresholds fail the job when missed.
