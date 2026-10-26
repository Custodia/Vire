import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, beforeAll } from "vitest";
import { cleanup } from "@testing-library/react";
import { resetMocks } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";

// jsdom has no layout, and the router scrolls the window on every navigation.
window.scrollTo = () => {};

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => {
  server.resetHandlers();
  resetMocks();
  cleanup();
});
afterAll(() => server.close());
