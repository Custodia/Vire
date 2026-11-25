import { afterEach, describe, expect, test } from "vitest";
import { http, HttpResponse } from "msw";
import { mockSession, password, user } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
import { api, ApiError, signIn } from "./client.js";

describe("api", () => {
  test("returns the decoded body of a successful request", async () => {
    await expect(api("/health")).resolves.toEqual({ status: "ok" });
  });

  test("returns null for a response without content", async () => {
    server.use(http.delete("/api/things/1", () => new HttpResponse(null, { status: 204 })));

    await expect(api("/things/1", { method: "DELETE" })).resolves.toBeNull();
  });

  test("sends JSON accept alongside the caller's headers", async () => {
    let headers;
    server.use(
      http.post("/api/things", ({ request }) => {
        headers = request.headers;
        return HttpResponse.json({}, { status: 201 });
      }),
    );

    await api("/things", { method: "POST", headers: { "content-type": "application/json" } });

    expect(headers.get("accept")).toBe("application/json");
    expect(headers.get("content-type")).toBe("application/json");
  });

  test("throws an error carrying the status and body of a failed request", async () => {
    server.use(
      http.get("/api/health", () =>
        HttpResponse.json({ errors: { detail: "Not Found" } }, { status: 404 }),
      ),
    );

    const error = await api("/health").catch((e) => e);

    expect(error).toBeInstanceOf(ApiError);
    expect(error.status).toBe(404);
    expect(error.body).toEqual({ errors: { detail: "Not Found" } });
  });

  test("throws an error carrying the status and text of a failed non-JSON response", async () => {
    server.use(http.get("/api/health", () => HttpResponse.text("Bad Gateway", { status: 502 })));

    const error = await api("/health").catch((e) => e);

    expect(error).toBeInstanceOf(ApiError);
    expect(error.status).toBe(502);
    expect(error.body).toBe("Bad Gateway");
  });
});

describe("the CSRF token", () => {
  const recordTokens = (method) => {
    const tokens = [];
    server.use(
      http[method]("/api/things", ({ request }) => {
        tokens.push(request.headers.get("x-csrf-token"));
        return HttpResponse.json({});
      }),
    );
    return tokens;
  };

  const countTokenFetches = () => {
    const fetches = { count: 0 };
    server.events.on("request:start", ({ request }) => {
      if (new URL(request.url).pathname === "/api/csrf") fetches.count++;
    });
    return fetches;
  };

  afterEach(() => server.events.removeAllListeners());

  test("goes with every unsafe request, fetched once for all of them", async () => {
    const tokens = recordTokens("post");
    const fetches = countTokenFetches();

    await Promise.all([api("/things", { method: "POST" }), api("/things", { method: "POST" })]);

    expect(tokens).toEqual([mockSession.csrfToken, mockSession.csrfToken]);
    expect(fetches.count).toBe(1);
  });

  test("stays off a GET", async () => {
    const tokens = recordTokens("get");
    const fetches = countTokenFetches();

    await api("/things");

    expect(tokens).toEqual([null]);
    expect(fetches.count).toBe(0);
  });

  test("is fetched again and the request sent once more when the server refuses it", async () => {
    const tokens = [];
    server.use(
      http.delete("/api/things", ({ request }) => {
        const token = request.headers.get("x-csrf-token");
        tokens.push(token);
        return token === mockSession.csrfToken
          ? new HttpResponse(null, { status: 204 })
          : HttpResponse.json({ reason: "invalid_csrf_token" }, { status: 403 });
      }),
    );
    await api("/things", { method: "DELETE" });
    const first = tokens[0];

    mockSession.csrfToken = "the-session-s-next-token";
    await expect(api("/things", { method: "DELETE" })).resolves.toBeNull();

    expect(tokens).toEqual([first, first, "the-session-s-next-token"]);
  });

  test("leaves another 403 to the caller", async () => {
    let calls = 0;
    server.use(
      http.post("/api/things", () => {
        calls++;
        return HttpResponse.json({ errors: { detail: "Forbidden" } }, { status: 403 });
      }),
    );

    const error = await api("/things", { method: "POST" }).catch((e) => e);

    expect(error.status).toBe(403);
    expect(calls).toBe(1);
  });

  test("is fetched anew after signing in, which ends the session's token", async () => {
    const tokens = recordTokens("post");
    mockSession.signedIn = false;
    await api("/things", { method: "POST" });

    await signIn({ email: user.email, password });
    await api("/things", { method: "POST" });

    expect(tokens).toHaveLength(2);
    expect(tokens[1]).toBe(mockSession.csrfToken);
    expect(tokens[1]).not.toBe(tokens[0]);
  });
});
