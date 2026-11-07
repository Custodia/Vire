---
title: Live updates
lifecycle: immutable
status: accepted
date: 2026-11-01
---

# 0012. Live updates

## Context

Uploads and Garmin syncs finish in background jobs, seconds to minutes after
the request that started them. The dashboard needs to show their progress and
outcome as they happen, and later features will need the same for other
changes made outside the page, such as plan edits from an MCP client.

## Decision

- **The dashboard holds one WebSocket per page**, a Phoenix socket at
  `/socket`, websocket transport only. It connects with the session cookie and
  the session's CSRF token, for a signed-in user only. The socket's id comes
  from the session, so signing out closes that session's sockets.
- **Each user has one channel**, `user:<id>`, which only that user can join.
  Every kind of change is an event on it.
- **Domain code publishes events, the web layer pushes them.** A context
  publishes a change on the user's PubSub topic after its transaction commits,
  carrying the changed row. The channel turns each event into the JSON the API
  answers for that resource, and adding an event is one handler on each side.
- **REST stays the source of truth.** A push replaces the cached answer of the
  GET for the same resource. On every join, including after a dropped
  connection, the dashboard reads those resources again, so a push missed while
  disconnected costs nothing.
- **A Garmin sync is recorded as a run** from the moment it is queued, with
  what started it, its state, the activities it found that Vire did not hold
  and its file counts. Its jobs update the run with single-statement increments
  and a conditional finish, so concurrent downloads never lose a count and a
  run finishes once.

## Consequences

Background work can show progress anywhere in the dashboard without polling.
Every new live feature needs an event, a push and a cache update, and its
resource must be readable over REST. The socket shares the session's lifetime
and its CSRF protection; a session without a CSRF token cannot connect.

## Alternatives considered

- **Polling** each resource until it settles. It is what upload status did
  first; it adds requests per open page and makes every new live feature
  another poll loop.
- **Server-sent events.** One-way is enough today, but Phoenix channels give
  joins, reconnects with backoff and per-topic authorization already, and the
  same connection can carry messages from the browser later.
- **LiveView.** The dashboard is a React app over a JSON API
  ([0004](0004-dashboard.md)); LiveView would mean a second rendering model.
