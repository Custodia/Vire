---
title: State
lifecycle: living
---

# State

Vire is at the earliest stage of implementation. The repository holds a Phoenix
application with Ecto and Oban, operator-created users who sign in to the API
with a password, a training plan per user from season to session with every
change logged, the files each user sends kept once per content hash and the
`.fit` files among them parsed into activities with laps, lengths and streams,
each user's Garmin activities inside their seasons synced with their files,
an MCP endpoint behind an OAuth 2.1 authorization server with tools that read
and write the plan and read activities and their files,
and a React dashboard it serves, laid out for desktops and for phones, where a
user signs in and sees a calendar of months, weeks and days with each day's
sessions, a session against its matched activity and the last one like it, and
the plan of a season as a map of its phases and blocks, its blocks' days and a
log of the latest plan changes, matches activities to sessions, uploads `.fit`
files and starts a Garmin sync, following both as they run over a WebSocket.

## Open questions

**How a paused Garmin connection resumes.** A connection is paused when Garmin
refuses its key or every search of a sync fails, and nothing yet clears the
pause.

**What happens to an MCP client's plan changes when the client is deleted.**
Every change made over MCP names its client, and the change log requires that
name on every MCP change, so a client with logged changes cannot be deleted.
Nothing deletes clients yet.

**Where a cycle in the phone's plan leads.** A cycle row opens the week of its
first day, or of today while it runs. A cycle can be longer than a week and
start on any weekday, so that week does not show all of it.

**How nutrition data is entered.** Logging it through an MCP tool covers the
common case. Whether anything else feeds it is undecided.

## To implement

- MCP tools that write preferences, goals and nutrition logs.
- Dashboard screens for readiness, nutrition and settings.
- Data behind the trend weight, chronic load, weight row, season targets,
  readiness and weight trend the dashboard shows empty.
- A limit on how often each user can sync with Garmin.
- A stand-in Garmin server for the end-to-end suite, run as its own process
  and told by each spec what Garmin answers, with answers built by readable
  factories, so a spec can follow a sync to its end.
