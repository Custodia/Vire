import { describe, expect, test } from "vitest";
import { http, HttpResponse } from "msw";
import { server } from "../mocks/server.js";
import { api, ApiError } from "./client.js";

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
