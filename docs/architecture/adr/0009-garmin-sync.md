---
title: Garmin sync
lifecycle: immutable
status: accepted
date: 2026-10-26
---

# 0009. Garmin sync

## Context

Most activities reach Vire through Garmin's Personal API. Garmin publishes no
rate limit for it. A bearer token lives 24 hours and is exchanged from an API
key that expires, and the terms cover personal use. An athlete's Garmin
history reaches back years, most of it outside any plan Vire holds. The same
activity can also arrive as an uploaded `.fit` file, before or after Garmin
reports it. A planned session is meant to be met by an activity of its
discipline on its day, and a day can hold several sessions of one discipline.

## Decision

- **Discovery is bounded by seasons.** A sync searches Garmin's activity list
  once per season of the user, from the season's first day to the earlier of
  its last day and today. An activity outside every season is never fetched.
  Creating a season, or widening one, enqueues a sync of the dates it adds.
  Every user with an unpaused connection is synced every three hours, and on
  request.
- **Garmin sees one request at a time.** Syncs and downloads share one job
  queue that runs one job at a time. A sync schedules the download of each
  activity without a file a few seconds after the one before, so a backfill
  paces itself. A 429 or 5xx response is retried with exponential back-off.
- **A refused connection is paused.** When the token endpoint refuses the key,
  or every search of a run fails, the connection is paused and no sync uses it.
- **The originals are stored.** Each activity's `.fit` file is downloaded once,
  taken out of the ZIP Garmin answers with, and kept as a source file from
  Garmin's API ([0007](0007-source-file-storage.md)).
- **An activity is one row, created by whichever side arrives first.** A
  summary creates an activity with Garmin's id, the training load and the whole
  summary; a file creates one with what it records. The other side attaches to
  that row when the two starts lie within a minute: a summary to an activity
  from a file without a provider, and a file to a Garmin activity without a
  file.
  Once a file backs the activity, its start, duration and distance come from
  the file, and the summary's own fields stay.
- **Activities are matched to planned sessions when the match is clear.**
  After an activity is stored, from a file or a summary, each of the day's
  unmatched activities is scored against each unmatched session of its
  discipline on how close its duration is to the planned one, whether its
  place by start time is the session's place by position, and whether the
  pair are the day's only ones of the discipline. A pair is matched only when
  it scores high and clearly ahead of every other pair of its activity and
  its session; anything less waits for a match by hand, with the scores
  offered as candidates. A matched session is done. A session is marked
  skipped only by hand, so a missing recording never counts as a skip.
- **Automatic matches stay out of the change log.** A match by hand, or its
  removal, is a plan change with a rationale and is logged. Automatic matching
  leaves a session matched or cleared by hand alone.

## Consequences

Garmin history before a user's first season stays in Garmin. A long season's
first sync takes minutes of paced downloads, and later syncs fetch only the
files Vire does not have. An upload and a Garmin summary of the same activity
end as one row in either order, carrying both the file's recording and
Garmin's training load. A day whose activities fit its sessions only loosely,
such as a ride far shorter than planned or two runs for one planned run,
stays unmatched until someone matches it by hand.
