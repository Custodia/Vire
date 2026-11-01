---
title: Testing approach
lifecycle: immutable
status: accepted
date: 2026-10-25
---

# 0003. Testing approach

## Context

Vire's behaviour lives mostly at its boundaries: SQL constraints and triggers,
HTTP endpoints, a decoder in another process, and screens rendering API
responses. A test that replaces those boundaries with mocks passes while the real
thing breaks.

## Decision

**Integration tests come first.** A test runs against the real database and the
real HTTP layer wherever it can. A mock stands in only for what a test cannot
reach: Garmin's API in the Elixir suite, and the server in the browser suite. A
unit test with a mocked dependency carries a sentence saying why an integration
test could not cover it.

There are three layers:

| Layer | Tools | Runs against |
| --- | --- | --- |
| Elixir | ExUnit, Ecto SQL sandbox, Oban testing mode | A real Postgres, one transaction per test, requests through the endpoint and router |
| Frontend | Vitest, React Testing Library, MSW | The whole app rendered at a URL, with MSW handlers that mirror the API's responses |
| End to end | Playwright | The application running as a server in the test configuration, driven through a real browser |

**Coverage is enforced.** `mix test --cover` fails below 90% of lines. Vitest fails
below 90% of lines, statements, functions and branches. CI runs both. Modules that
run only at compile time, and test support modules, are left out of the Elixir
figure.

## Consequences

The Elixir suite needs Postgres to run. The MSW handlers double as the documented
shape of each API response, and drift between them and the server shows up only
in the end-to-end suite.
