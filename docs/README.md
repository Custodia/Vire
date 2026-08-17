---
title: Documentation index
lifecycle: living
---

# Documentation

## Map

```
docs/
├── README.md                  living         index and conventions
├── STATE.md                   living         where the repository stands
└── architecture/
    ├── overview.md            living         system shape, components, data flow
    └── adr/
        ├── README.md          living         decision index and conventions
        ├── template.md        —              starting point for a new record
        └── NNNN-<slug>.md     immutable      one decision per file
```

## Lifecycle

Every document declares a lifecycle in its frontmatter. The label tells a reader
how far to trust the text and whether they may edit it.

| Label | Meaning | Editing |
| --- | --- | --- |
| `living` | The text as it stands is the truth. | Edit whenever the information changes. |
| `immutable` | A decision, fixed at the moment it was accepted. | Never edit. Supersede with a new record. |
| `point-in-time` | True of the date it carries. Nobody maintains it. | Never edit. Check the date before relying on it. |

A living document describes what the repository contains now. Planned work belongs
in [STATE.md](STATE.md).

State that lives outside the repository — a library's behaviour, a hosted
service's interface, a vendor's documentation — moves without warning, and a claim
about it here goes stale unseen. Where such a fact is load-bearing, name the thing
and let the reader look it up.

A `point-in-time` document is the place for a spike write-up, a benchmark run or
an investigation. It carries a `date`, and a reader is expected to verify anything
they intend to act on.

## STATE.md

[STATE.md](STATE.md) says where the repository stands: a short statement of what
it holds, the questions still open, and what remains to implement.

It covers work that lands in this repository. Hosting, DNS and anything else
configured outside it stays out.

An entry is deleted as its work lands. Completion is not recorded there — that a
thing exists is evident from the architecture documentation, the ADRs and the code.

## Frontmatter

Living documents:

```yaml
---
title: Documentation index
lifecycle: living
---
```

Decision records:

```yaml
---
title: Documentation format
lifecycle: immutable
status: accepted
date: 2026-08-11
---
```

Point-in-time documents:

```yaml
---
title: FIT decoder throughput
lifecycle: point-in-time
date: 2026-08-11
---
```

## Adding a document

1. Pick the lifecycle first. It determines where the file goes and how it reads.
2. Add the frontmatter.
3. Link it from this index if it sits outside `adr/`, which indexes itself.

Filenames are lowercase and hyphenated. Decision records are prefixed with a
four-digit number.

## How to write

Every document here follows these rules:
* Do not define things by contrast ("unlike <other skill>" or "it is upkeep, not
  news")
* Describe things concisely, long documents go unread
* Explain things in plain English but without dumbing down the technical details
* Write only what has been decided. A suggestion that drew no objection is not a
  decision.
    * Anything that is unsettled and matters is named in [STATE.md](STATE.md) as
      a question, and stays out of the document that would have answered it.
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
