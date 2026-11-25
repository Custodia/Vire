---
title: FIT decoding
lifecycle: immutable
status: accepted
date: 2026-10-25
---

# 0008. FIT decoding

## Context

Every activity reaches Vire as a `.fit` file. The format is Garmin's, and so is
its profile of messages and fields, which Garmin revises as devices gain
sensors and metrics. Real files carry dozens of message types, many of them
undocumented, and developer fields defined by apps such as indoor trainers.
Garmin publishes and maintains SDKs that track the profile; no Elixir decoder
does. A decoder fed a malformed file must not take the application down with
it.

## Decision

- **Garmin's FIT JavaScript SDK decodes, in a Node process behind an Erlang
  port.** The SDK is pinned in the `decoder/` package. One long-lived process
  is owned by a supervised Elixir process, started with `node` from `PATH`.
- **The port speaks JSON framed by a four-byte big-endian length** in both
  directions, which Erlang's `{:packet, 4}` reads natively. A request carries
  the file's bytes in base64; the answer carries the decoded messages or an
  error.
- **Node verifies and decodes; Elixir does everything after.** The Node side
  checks the header, size and CRC, decodes with the SDK's scaling, components
  and developer fields applied, and returns the messages grouped by type.
  Normalising them into activities, laps, lengths and streams, and storing
  them, happens in Elixir.
- **A crash fails one job.** Requests are served one at a time, each with a
  timeout that kills the Node process. A process that exits fails only the
  request it was serving, and the next request starts a new one. The VM is
  untouched.
- **Each parse records its processor version.** After the version is raised,
  one call queues a parse of every file an older version read, and a parse
  replaces what an earlier parse of the same file stored.
- **Test fixtures are synthetic and generated with the SDK's encoder**, by a
  script committed next to them. No real recording enters the repository.

## Consequences

Node is a runtime requirement of the application in every environment, and the
decoder's packages are installed alongside the dashboard's. Profile updates
arrive by raising the pinned SDK version. Every decode copies the file into the
Node process and the messages back as JSON, which costs memory and time in
proportion to the file. Tests run the real decoder.

## Alternatives considered

- **A decoder written in Elixir or an existing Hex package.** It decodes in
  the VM with no second runtime, but tracking Garmin's profile, components
  and developer fields would fall to Vire.
- **A NIF around Garmin's C SDK.** It decodes in-process and fast, but a crash
  in native code takes the whole VM down.
