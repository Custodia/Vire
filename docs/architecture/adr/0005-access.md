---
title: Access
lifecycle: immutable
status: accepted
date: 2026-10-25
---

# 0005. Access

## Context

Vire serves a handful of athletes, each with their own history, plan and Garmin
API key. The dashboard runs in the browser on the same origin as the API. A
Garmin key opens the athlete's whole Garmin history, and Vire keeps it so that
syncs run with nobody present.

## Decision

- **An operator creates every user** with a mix task that takes an email, a
  name, a password and the Garmin API key, and writes the user and the provider
  connection in one transaction. There is no sign-up.
- **The dashboard signs in with a password**, hashed with bcrypt. A wrong
  password and an unknown email get the same 401 after the same bcrypt work. A
  successful sign-in starts a fresh session.
- **The session is an encrypted cookie** holding the user's id: signed and
  encrypted under the secret key base, HttpOnly, SameSite Lax, and Secure in
  production.
- **Provider credentials are encrypted at rest** with AES-256-GCM under a
  32-byte key read from `VIRE_CREDENTIAL_KEY`, with a random nonce on every write
  and the authentication tag stored with the ciphertext. The release does not
  start without the key.
- **Every query runs in a scope.** A request's scope carries the signed-in user.
  Every function that reads or writes a user's data takes the scope as its first
  argument and filters by its user. Routes behind the `:authenticated` pipeline
  answer 401 to a request without one.

Access for MCP clients is decided in a record of its own.

## Consequences

A copy of the database without the credential key yields no Garmin keys. Losing
the credential key makes every stored key unreadable, and each has to be entered
again.

The server keeps no session state. Signing out clears the cookie in that browser;
a copy of the cookie stays valid until its user is deleted or the secret key base
changes, and changing the secret key base signs everyone out.
