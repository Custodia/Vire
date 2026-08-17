---
title: Documentation format
lifecycle: immutable
status: accepted
date: 2026-08-11
---

# 0001. Documentation format

## Context

A reader needs to know, before reading a document, how far to trust it and whether
they may edit it. The sentences inside it need to stay true without anyone
revisiting them.

## Decision

Documentation lives in `docs/`, indexed by `docs/README.md`.

**Every document declares a lifecycle** in its frontmatter:

- `living` — the text as it stands is the truth; edit it whenever the information
  changes.
- `immutable` — a decision, fixed at the moment it was accepted; supersede with a
  new record.
- `point-in-time` — true of the date it carries, maintained by nobody; verify
  before acting on it.

A living document describes what the repository contains now. Planned work belongs
in `docs/STATE.md`. State that lives outside the repository moves without warning,
and a claim about it here goes stale unseen.

**Decisions are recorded as numbered ADRs** under `docs/architecture/adr/`, one
decision per file, immutable once accepted. A record that no longer reflects
reality is superseded by a new record; its status and `superseded-by` field are
the only parts that change.

**`docs/STATE.md` says where the repository stands** — what it holds, what is
unresolved, and what remains to implement here. Work that lands outside the
repository stays out of it. Entries are deleted as the work lands.

**Documentation follows these rules:**
* Do not define things by contrast ("unlike <other skill>" or "it is upkeep, not
  news")
* Describe things concisely, long documents go unread
* Explain things in plain English but without dumbing down the technical details
* Write only what has been decided. A suggestion that drew no objection is not a
  decision.
    * Anything that is unsettled and matters is named in `docs/STATE.md` as a
      question, and stays out of the document that would have answered it.
    * A correction applies to the thing it corrected. Do not generalise a narrow
      remark into a standing rule.
* No references to how something used to be ("down from fourteen agents")
* No references that are time bound to when they are written, including
  states of external systems, repositories or websites.
    * Explicitly dated point-in-time documents are the exception that proves the
      rule

When the rules above do not obviously settle a sentence, apply the test: could
this sentence survive being read in isolation, a year from now, by someone who
has never seen the old version or the sibling?

## Consequences

Documentation can be trusted without checking its age. A `living` document is
correct or it is a bug; a `point-in-time` document is an observation and reads as
one; an `immutable` record means what it says regardless of what the code has
since become.

Superseding preserves why a decision was made, which is the part that cannot be
recovered from the code. The record set grows monotonically, and a reader follows
supersession links to reach the current position. The index absorbs most of that.

Deleting STATE.md entries as work lands keeps the file the size of the remaining
work. STATE.md never answers what was achieved.
