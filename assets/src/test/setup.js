import "@testing-library/jest-dom/vitest";
import { File as NodeFile } from "node:buffer";
import { afterAll, afterEach, beforeAll } from "vitest";
import { cleanup } from "@testing-library/react";
import { forgetCsrfToken } from "../api/client.js";
import { resetMocks } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";

// jsdom has no layout, and the router scrolls the window on every navigation.
window.scrollTo = () => {};

// jsdom has no media queries. Screens get the desktop layout unless a test
// sets `viewport.desktop` to false before it renders.
export const viewport = { desktop: true };
window.matchMedia = (query) => ({
  media: query,
  get matches() {
    return viewport.desktop;
  },
  addEventListener: () => {},
  removeEventListener: () => {},
});

// Vitest sends a request with jsdom's FormData past MSW to the network, so a
// form reaches MSW rebuilt from Node's own FormData and File.
async function nodeForm(form) {
  const empty = new Response("", {
    headers: { "content-type": "application/x-www-form-urlencoded" },
  });
  const rebuilt = new (await empty.formData()).constructor();
  for (const [name, value] of form) {
    rebuilt.append(
      name,
      value instanceof window.Blob
        ? new NodeFile([await value.arrayBuffer()], value.name, { type: value.type })
        : value,
    );
  }
  return rebuilt;
}

beforeAll(() => {
  server.listen({ onUnhandledRequest: "error" });
  const intercepted = globalThis.fetch;
  globalThis.fetch = async (input, init) =>
    init?.body instanceof window.FormData
      ? intercepted(input, { ...init, body: await nodeForm(init.body) })
      : intercepted(input, init);
});
afterEach(() => {
  viewport.desktop = true;
  localStorage.clear();
  server.resetHandlers();
  resetMocks();
  forgetCsrfToken();
  cleanup();
});
afterAll(() => server.close());
