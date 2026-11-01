---
title: Training plan storage
lifecycle: immutable
status: accepted
date: 2026-10-25
---

# 0006. Training plan storage

## Context

A training plan runs season, phase, block, cycle, day and session, and each
level splits the dates of the one above it. The athlete edits it from the
dashboard and a coach agent edits it over MCP, so two writers change the same
rows, and either can leave the plan with overlapping weeks or a block hanging
outside its phase. The athlete needs to see why the plan looks the way it does
and who changed it.

## Decision

- **Periods are bounded `daterange` columns, and the database keeps them
  consistent.** Exclusion constraints stop a user's seasons, and the children of
  one parent, from overlapping. Triggers keep a child's period inside its
  parent's and a day inside its cycle, and stop a parent from shrinking past a
  child. They raise check violations named after the rule, which Ecto turns into
  changeset errors. In Elixir a period is an inclusive first and last date.
- **Days are rows, created with their cycle.** Creating a cycle creates one rest
  day per date. Widening a cycle adds days; narrowing it removes the rest days
  without a note that it leaves out, and is refused while any day it leaves out
  is a training day, holds a note or holds a session. A session lands on the
  day of its date and makes it a training day.
- **Monday to Sunday is the default cycle.** A cycle created without a period
  runs from the day after the block's latest cycle, or from the block's first
  day, through the following Sunday, within the block. A cycle with explicit
  dates can have any length; the schema fixes no week.
- **Every write is logged in the same transaction.** Each write to the plan
  records one change row with the entity, the action, the row before and after
  as JSON, the rationale, the channel and the MCP client. The change and the
  write commit or roll back together. Rows removed by a cascade, and days created
  or removed with their cycle, are covered by the change of the row the caller
  acted on.
- **The scope carries the channel.** A scope names the channel a request came
  through, dashboard or MCP, and for MCP the client's id. The change log takes
  both from the scope.

## Consequences

No writer, whether the dashboard, MCP or a console session, can store an
overlapping or escaping period. A cycle's dates and its day rows always match,
so a session always has a day to sit on and a date always has at most one day
per user. Every plan change has a reason and an origin on record.
