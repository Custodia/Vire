import { describe, expect, test } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "./mocks/server.js";
import { renderApp } from "./test/render.jsx";

describe("opening the dashboard", () => {
  test("lands on Today and shows the server as connected", async () => {
    const { router } = renderApp("/");

    expect(await screen.findByRole("heading", { name: "Vire" })).toBeInTheDocument();
    await waitFor(() => expect(router.state.location.pathname).toBe("/today"));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Connected"));
  });

  test("shows the server as unreachable when the health check fails", async () => {
    server.use(http.get("/api/health", () => HttpResponse.json({}, { status: 500 })));

    renderApp("/today");

    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Unreachable"));
  });
});
