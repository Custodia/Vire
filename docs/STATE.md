---
title: State
lifecycle: living
---

# State

Vire is at the earliest stage of implementation. The repository holds
documentation and no application code.

## Open questions

**How `.fit` files are decoded.** The parser is third-party. One embedded in the
application keeps deployment to a single artifact and decodes in-process. One in a
separate process isolates a crash from the application, and can wrap a vendor SDK,
which tracks the FIT profile as the vendor revises it.

**Whether raw uploaded files are retained, and where.** Keeping them allows
decoding to be re-run over old uploads as the parser improves, at the cost of
storing every upload twice. A database column keeps backup and retention as one
concern; a filesystem or object store keeps multi-megabyte blobs out of the row
set.

**How the dashboard is built.** It renders workout data on desktop and mobile
browsers. A ride records power and heart rate every second across several hours,
so the series it charts are long.

**How a user proves who they are, and how an MCP client is granted access.** A
handful of users, across both the dashboard and the MCP server. An MCP client
presents its credential with no person present at the moment of the request.

**How nutrition data is entered.** Logging it through an MCP tool covers the
common case. Whether anything else feeds it is undecided.

## To implement

- Application skeleton and database setup.
- `.fit` decoding.
- Upload endpoint and storage of uploaded workouts.
- MCP endpoint, and the tools that read workout history.
- MCP tools that write plans, preferences, goals and nutrition logs.
- Web dashboard.
- Authentication.
- Access control for MCP clients.
