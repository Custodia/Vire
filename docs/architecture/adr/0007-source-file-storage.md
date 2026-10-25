---
title: Source file storage
lifecycle: immutable
status: accepted
date: 2026-10-25
---

# 0007. Source file storage

## Context

Activities arrive as `.fit` files, from Garmin's Personal API and from uploads,
and nutrition arrives as spreadsheet exports. Everything Vire knows about an
activity is derived from its file, and the derivation will change: a new parser
version, or a channel Vire did not read before, means reading old files again.
Garmin publishes no rate limit for its API, its keys expire after at most a
year, and its terms cover personal use. An uploaded file exists nowhere else.
A recorded hour is in the order of 100 KB; ten sessions a week come to about
70 MB a year per user.

## Decision

- **Every file is kept byte for byte in Postgres**, in a `bytea` column on a
  `source_files` row with its kind, its origin (Garmin's API, an upload or MCP),
  its SHA-256 and its size.
- **A file is unique by hash within a user.** Storing bytes the user already
  has returns the stored file instead of a second copy, so a file that arrives
  from both the API and an upload is kept once. Two users with the same bytes
  each keep their own row.
- **A file records the outcome of processing it**: pending, processed with the
  version of the processor that read it, or failed with the error. The database
  enforces those pairings.

## Consequences

Re-parsing every file needs no call to Garmin, and a user's history keeps
working after their key lapses. Files share the database's backups and
transactions with the rows parsed from them, so a parse commits or rolls back
together with the file's status. The database grows with every file, and
queries that do not need a file's bytes must leave the column out.

## Alternatives considered

- **Fetching files from Garmin again when needed.** A re-parse would mean
  hundreds of downloads against an API with unknown limits, and uploads have no
  second source.
- **A filesystem or object store.** It keeps large values out of the row set,
  at the cost of a second store to back up and keep consistent with the rows.
  Files of this size do not justify it.
