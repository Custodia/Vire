import "@testing-library/jest-dom/vitest";
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

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => {
  viewport.desktop = true;
  server.resetHandlers();
  resetMocks();
  forgetCsrfToken();
  cleanup();
});
afterAll(() => server.close());
