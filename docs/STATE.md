---
title: State
lifecycle: living
---

# State

Vire is at the earliest stage of implementation. The repository holds a Phoenix
application with Ecto and Oban, operator-created users who sign in to the API
with a password, a training plan per user from season to session with every
change logged, the files each user sends kept once per content hash, and a
React dashboard it serves, with no screens yet.

## Open questions

**How `.fit` files are decoded.** The parser is third-party. One embedded in the
application keeps deployment to a single artifact and decodes in-process. One in a
separate process isolates a crash from the application, and can wrap a vendor SDK,
which tracks the FIT profile as the vendor revises it.

**How an MCP client is granted access.** An MCP client presents its credential
with no person present at the moment of the request.

**How nutrition data is entered.** Logging it through an MCP tool covers the
common case. Whether anything else feeds it is undecided.

## To implement

- `.fit` decoding.
- Upload endpoint and storage of uploaded workouts.
- MCP endpoint, and the tools that read workout history.
- MCP tools that write plans, preferences, goals and nutrition logs.
- Dashboard screens.
- Access control for MCP clients.
