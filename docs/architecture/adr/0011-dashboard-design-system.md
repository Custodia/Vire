---
title: Dashboard design system
lifecycle: immutable
status: accepted
date: 2026-10-26
---

# 0011. Dashboard design system

## Context

The dashboard's screens were designed on a canvas whose boards are HTML with
inline styles ([design canvas](../../design/2026-10-23-vire-design.md)). The
boards repeat the same colours, type and shapes across screens, and some of
them, the training zone scale and the discipline colours, carry meaning that
must read the same everywhere. A planned session's structure is drawn as a
workout profile, so the dashboard needs to know its shape, while the coach
agent writes it over MCP.

## Decision

- **`assets/src/styles/tokens.css` is the truth.** The canvas's values were
  copied into it once; from then on the canvas is a reference and the file
  decides. It holds every colour, named by role: ground and surfaces, borders,
  ink, the accent and its hover, the four discipline colours with the tints,
  edges and tiles their cards use, the training zone scale Z1 to Z5, and the
  session states done, skipped, upcoming and rest, each with its tint and edge.
  It also holds the two font families, a few text sizes the boards use beyond
  Tailwind's scale, the radii (18 px cards, 12 px tiles, 6 px chips) and the
  4 px spacing step.
- **Tailwind's theme is generated from that file** through `@theme static`,
  with Tailwind's default colours, fonts and radii cleared. A utility such as
  `bg-surface`, `text-discipline-run` or `fill-training-zone-4` is the only way
  a component gets a value.
- **Fonts are self-hosted** from fontsource packages and bundled by Vite: Inter
  for interface text, Barlow Condensed for numbers and headings, in the weights
  the boards use. Numbers use tabular figures.
- **Components live in `assets/src/ui/`, one per file**, each a port of its
  board fragment: `Stat`, `StatusChip`, `DisciplineIcon`, `TrainingZoneBadge`,
  `WorkoutProfile`, `SessionCard`, `SessionRow`, `CoachNote`, `Button`,
  `TextField` and the `Screen` shell. Screens compose them and add no colours of
  their own. Interactive elements are at least 44 px and show a focus ring in
  the accent; text keeps a contrast of at least 4.5:1 against its ground.
- **The session structure has a defined shape.** `steps` is a list of steps in
  order. A step has a `kind` (warmup, work, recovery, cooldown or rest),
  `seconds`, and optionally a `zone` from 1 to 5, a `target` and a `note`. A
  step may instead be a repeat: a `repeat` count with its own `steps`. `title`
  and `note` are optional strings naming and describing the session. The
  session changeset checks `steps` when it is present and leaves every other
  key as given; the MCP session tools describe the shape to the agent.

## Consequences

The workout profile, the session screen's steps and any later chart read one
shape, and an agent that writes another is refused with the path of the step
at fault. A new colour or size is added to the token file before a component
uses it.

## Alternatives considered

- **Reading values from the canvas at build time.** The canvas renders only in
  its editor and its values are illustrative, so it cannot be a build input.
- **Leaving the structure free-form.** The dashboard would have to guess at
  every agent's way of writing a workout, and could draw none of them reliably.
