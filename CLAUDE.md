# CLAUDE.md

Vire tracks workouts, nutrition, goals and athlete preferences, and serves them
through an MCP server and a web dashboard.

## How to write

Documentation, comments, PR descriptions, chat answers to users and everything
else you can think of should follow these rules:
* Do not define things by contrast ("unlike <other skill>" or "it is upkeep, not
  news")
    * This is especially true for pull requests. If changes are requested on
      something you should only state what the thing is after the changes, not
      by comparison to what it was before changes were requested.
* Describe things concisely, long documents and answers go unread
* When describing a change, do not include information that is instantly
  discoverable by an AI agent.
    * This often means removing mentions of specific names of files or functions
      that were changed.
    * Eg. only specify what was changed and if necessary why. Only specify how
      something was changed if it's very relevant and almost never specify where
      something was changed.
    * Eg. explain things in plain English but without dumbing down the technical
      details.

These rules govern all writing unless otherwise stated.

Documentation and git commits also have the following additional rules:

* Write only what has been decided. A suggestion that drew no objection is not a
  decision.
    * For documentation anything that is unsettled and matters, name it in
      [docs/STATE.md](docs/STATE.md) as a question.
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

## Code comments

A comment needs a reason strong enough that the code cannot carry the
information itself: a constraint invisible from the surrounding lines, or an
external force on the shape of the code. Absent that reason, the code says it.

## Git history

The history is permanent. Each commit explains what changed and stands on its
own. Before a branch merges, its commits are squashed to the ones that describe
the change.

## Documentation

`docs/` holds the project's written context.
[docs/README.md](docs/README.md) describes what each document is for, how far to
trust it, and the conventions it follows.
