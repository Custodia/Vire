---
title: Dashboard
lifecycle: immutable
status: accepted
date: 2026-10-25
---

# 0004. Dashboard

## Context

The dashboard sits behind sign-in, needs no search indexing, and is used on
phones as often as on desktops. It charts long series: a ride records power and
heart rate every second for hours.

## Decision

The dashboard is a **React single-page app in plain JavaScript with JSX, built
with Vite** from `assets/`.

- **Phoenix serves the build.** Vite writes it to `priv/static`. Files under
  `/assets` carry a content hash and are cached indefinitely. Every other path
  outside `/api` answers with the app's `index.html`, and the client router
  resolves it.
- **In development**, Vite's dev server runs beside Phoenix as a watcher and
  proxies `/api` to it.
- **TanStack Router** holds dates and plan levels in the URL, with routes defined
  in code. **TanStack Query** caches server data and refreshes it in the
  background.
- **Tailwind v4 is themed from one token file**, `src/styles/tokens.css`. Every
  colour, font, radius and spacing step is defined there, and the utilities it
  generates are how a component gets a value.
- **A web app manifest** lets a phone add the dashboard to its home screen and
  launch it full screen.

## Consequences

The API's JSON is the only contract between the dashboard and the server, and
inputs are validated once, on the server. Building a release needs Node to build
the dashboard first. Pages render in the browser only.
