import { createHash, randomBytes } from "node:crypto";
import { expect, test } from "@playwright/test";
import { email, ensureUploaded, password } from "./helpers.js";

// Nothing listens here: the client reads the code from the browser's request.
const redirectUri = "http://127.0.0.1:43117/callback";

test.beforeAll(async ({ browser }) => {
  await ensureUploaded(browser, ["ride.fit"]);
});

test("an MCP client authorizes through the browser and reads a day", async ({ page, request }) => {
  const registration = await request.post("/oauth/register", {
    data: { client_name: "End-to-end client", redirect_uris: [redirectUri] },
  });
  expect(registration.status()).toBe(201);
  const client = await registration.json();

  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const state = randomBytes(16).toString("hex");
  const query = new URLSearchParams({
    response_type: "code",
    client_id: client.client_id,
    redirect_uri: redirectUri,
    code_challenge: challenge,
    code_challenge_method: "S256",
    state,
  });

  await page.goto(`/oauth/authorize?${query}`);
  await expect(page.getByRole("heading", { name: "Sign in to Vire" })).toBeVisible();
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page.getByRole("heading", { name: "Allow End-to-end client?" })).toBeVisible();
  const callback = page.waitForRequest((request) => request.url().startsWith(redirectUri));
  await page.getByRole("button", { name: "Approve" }).click();
  const returned = new URL((await callback).url());

  expect(returned.searchParams.get("state")).toBe(state);
  const code = returned.searchParams.get("code");
  expect(code).toBeTruthy();

  const tokenResponse = await request.post("/oauth/token", {
    form: {
      grant_type: "authorization_code",
      code,
      code_verifier: verifier,
      client_id: client.client_id,
      redirect_uri: redirectUri,
    },
  });
  expect(tokenResponse.status()).toBe(200);
  const { access_token: token } = await tokenResponse.json();

  let id = 0;
  const call = async (method, params = {}) => {
    const response = await request.post("/mcp", {
      headers: {
        authorization: `Bearer ${token}`,
        accept: "application/json, text/event-stream",
      },
      data: { jsonrpc: "2.0", id: ++id, method, params },
    });
    expect(response.status()).toBe(200);
    return (await response.json()).result;
  };

  const initialized = await call("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "End-to-end client", version: "1" },
  });
  expect(initialized.serverInfo.name).toBe("vire");

  const { tools } = await call("tools/list");
  expect(tools.map((tool) => tool.name)).toContain("get_day");

  const { structuredContent: day } = await call("tools/call", {
    name: "get_day",
    arguments: { date: "2026-07-14" },
  });
  const [ride] = day.activities;
  expect(ride).toMatchObject({ discipline: "bike", local_date: "2026-07-14" });
  expect(day.day.sessions).toEqual([
    expect.objectContaining({
      discipline: "bike",
      status: "done",
      activity_id: ride.id,
      structure: expect.objectContaining({ title: "Saddle check ride" }),
    }),
  ]);
});

test("the MCP endpoint refuses a request without a token", async ({ request }) => {
  const response = await request.post("/mcp", {
    data: { jsonrpc: "2.0", id: 1, method: "tools/list" },
  });

  expect(response.status()).toBe(401);
  expect(response.headers()["www-authenticate"]).toMatch(
    /^Bearer resource_metadata="http:\/\/[^"]+\/\.well-known\/oauth-protected-resource"$/,
  );
});
