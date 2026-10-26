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
an MCP endpoint with no tools yet behind an OAuth 2.1 authorization server,
and a React dashboard it serves, with no screens yet.

## Open questions

**How a paused Garmin connection resumes.** A connection is paused when Garmin
refuses its key or every search of a sync fails, and nothing yet clears the
pause.

**What happens to an MCP client's plan changes when the client is deleted.**
Every change made over MCP names its client, and the change log requires that
name on every MCP change, so a client with logged changes cannot be deleted.
Nothing deletes clients yet.

**How nutrition data is entered.** Logging it through an MCP tool covers the
common case. Whether anything else feeds it is undecided.

## To implement

- MCP tools that read workout history.
- MCP tools that write plans, preferences, goals and nutrition logs.
- Dashboard screens.
