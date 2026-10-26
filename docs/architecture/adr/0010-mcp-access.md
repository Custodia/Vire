---
title: MCP access
lifecycle: immutable
status: accepted
date: 2026-10-26
---

# 0010. MCP access

## Context

A coach agent reads an athlete's history and writes their plan over MCP, with
nobody present when it calls. The first client is a claude.ai connector: it
registers itself, holds no secret, sends its users back to a fixed callback on
claude.ai, and calls from a server. A local MCP inspector is the second. The
MCP specification's authorization section has a server name its OAuth 2.1
authorization server in protected resource metadata, and has clients find that
server's endpoints in its metadata and register dynamically. Original `.fit`
files run to megabytes of binary, and an agent's context holds text.

## Decision

- **Vire is the authorization server.** It serves protected resource metadata
  for `/mcp` (RFC 9728), authorization server metadata (RFC 8414), dynamic
  client registration (RFC 7591), an authorization endpoint and a token
  endpoint, all in the application. The protocol and the OAuth endpoints are
  Phoenix controllers; there is no MCP or OAuth library.
- **Clients are public and use PKCE.** Registration takes a name and redirect
  URIs, each https or http on `localhost` or `127.0.0.1`, and answers a client
  id without a secret. An authorization request carries an S256 challenge and
  a redirect URI that matches a registered one exactly. A request that fails
  either check, or names an unknown client, is shown as an error and never
  redirected. A resource indicator (RFC 8707), when present, must be the
  `/mcp` URL.
- **The person signs in and consents.** The authorization endpoint shows the
  dashboard's password sign-in, which starts the same session as the
  dashboard's, and then a consent page naming the client, what it may do and
  where approving returns. Approving issues a code; denying returns
  `access_denied`. Both forms carry a CSRF token, and the pages forbid framing.
- **Codes and tokens are random and stored hashed.** Each is 32 random bytes,
  and only its SHA-256 is kept. A code lives ten minutes, is bound to its
  client, redirect URI and challenge, and is exchanged once; presented a second
  time, it revokes every token its user holds for that client. An access token
  lives an hour and a refresh token thirty days. A refresh revokes the old pair
  and issues a new one; a revoked refresh token presented again revokes every
  token its user holds for that client.
- **`/mcp` takes a bearer token.** A request without one answers 401 with a
  `WWW-Authenticate` header pointing at the protected resource metadata, which
  names Vire as the authorization server. An unknown, expired or revoked token
  answers 401 with `invalid_token`. A valid token runs the request in a scope
  with its user, the MCP channel and its client.
- **The transport is stateless streamable HTTP.** Each POST carries one
  JSON-RPC message and is answered with `application/json`. There are no
  server-sent events and no session id, and a GET answers 405. An `Origin`
  header, when present, must name Vire's host, which keeps a web page from
  reaching a local server through DNS rebinding; a client calling from a
  server sends none.
- **Writes name the client.** Every plan write over MCP lands in the change log
  with the MCP channel and the client's id.
- **Files leave by signed URL.** A tool offering an activity's original file
  answers a URL valid for fifteen minutes, with the file's size and SHA-256.
  The URL carries the user, the expiry and an HMAC over the file id, the user
  and the expiry, keyed from the secret key base, so fetching it needs no
  session or token. The agent downloads and decodes the file itself, and no
  file bytes pass through the protocol.

## Consequences

Anyone can register a client, and only a user's password and consent give it
access. A leaked access token works for at most an hour. Changing the secret
key base invalidates every file URL and signs every browser out, and leaves
MCP tokens valid. The server cannot push anything to a client: no progress,
list-changed or sampling messages.

## Alternatives considered

- **Operator-issued static tokens.** The claude.ai connector discovers and
  runs OAuth itself, and a static token would bypass the consent that names the
  client.
- **An external identity provider.** Another service to run and trust for a
  handful of users, while sign-in already lives in Vire.
- **Server-sent event streams and sessions.** Every tool answers in one
  response, so a stream would carry nothing a JSON answer does not, and a
  session would be state to keep across requests.
- **File bytes in a tool result.** Base64 of a long ride fills the agent's
  context before it reads anything else.
