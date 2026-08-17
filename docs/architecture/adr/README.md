---
title: Architecture decision records
lifecycle: living
---

# Architecture decision records

Every large architectural decision gets a record, as does any choice whose
consequences someone would otherwise have to reverse-engineer from the code. A
record covers one decision and the reasoning that produced it, and lands alongside
the code that implements it.

A record states what is settled. A question still open is named in
[STATE.md](../../STATE.md) and stays out.

## Index

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-documentation-format.md) | Documentation format | Accepted |

## Status

| Status | Meaning |
| --- | --- |
| `accepted` | Binding. The codebase is expected to match it. |
| `superseded` | A later record replaces it. Kept for its reasoning. |

## Immutability

A record is fixed once accepted. To supersede one, write a new record that
references it, then set the old record's status to `superseded` and add
`superseded-by` to its frontmatter. Those two fields are the only part of an
accepted record that changes.

## Conventions

Files are named `NNNN-<slug>.md`, numbered sequentially from `0001`. Numbers are
never reused.

Start from [template.md](template.md). Add a row to the index.
