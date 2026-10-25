---
title: Vire design canvas
lifecycle: point-in-time
date: 2026-10-23
---

# Vire design canvas

The first design of Vire's screens: a dark, phone-first daily view plus a
desktop planning view. The canvas lives at
<https://claude.ai/artifact/1JxtDeG9r52qRj96kZr1y4>.
[2026-10-23-vire-design/](2026-10-23-vire-design/) holds its files as they
stood on the date above.

| Board | Screen |
| --- | --- |
| `Main.dc.html` | Today: upcoming sessions to swipe through, completed sessions, weight trend, readiness |
| `Session.dc.html` | A planned session: structure by intensity zone, rationale, optional fuel during |
| `SessionReview.dc.html` | A completed session: planned against actual, reps, coach review |
| `Readiness.dc.html` | HRV against its band, sleep, resting HR, stress, load |
| `Nutrition.dc.html` | Trend weight, expenditure, weekly intake averages |
| `Block.dc.html` | One block: its cycles and each day's sessions |
| `Season.dc.html` | Desktop: season map, blocks, cycles × days, targets, coach log |
| `Model.dc.html` | Plan hierarchy and how each data source connects to it |

The boards are Design-canvas components. They render inside the claude.ai
Design editor, which supplies `support.js`. A browser opening them directly
shows unrendered templates.

Values are illustrative. The HRV band (65–79 ms) and FTP (289 W) come from the
Garmin account. The race name and target time are placeholders.

## Direction set in review

- Today leads with the day's sessions. Readiness is a secondary row.
- MacroFactor data arrives by occasional export, so nutrition leads with trend
  weight and weekly averages, never daily totals.
- Fuelling advice covers only fuel during long sessions, and is optional.
- Readiness is shown as context. It does not decide what a day holds.
- Completed sessions get a review. Past sessions are marked done or skipped,
  distinct from upcoming ones. Rest days are shown.
