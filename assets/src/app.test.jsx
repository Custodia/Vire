import { describe, expect, test } from "vitest";
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "./mocks/server.js";
import { renderApp } from "./test/render.jsx";
import { viewport } from "./test/setup.js";

describe("opening the dashboard", () => {
  test("lands on Today and shows the server as connected", async () => {
    const { router } = renderApp("/");

    expect(await screen.findByRole("heading", { level: 1, name: "Today" })).toBeInTheDocument();
    await waitFor(() => expect(router.state.location.pathname).toBe("/today"));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Connected"));
  });

  test("shows the server as unreachable when the health check fails", async () => {
    server.use(http.get("/api/health", () => HttpResponse.json({}, { status: 500 })));

    renderApp("/today");

    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Unreachable"));
  });
});

describe("the frame on a phone", () => {
  test("puts the screens in tabs along the bottom, and signing out under More", async () => {
    viewport.desktop = false;
    const { router } = renderApp("/today");

    const tabs = await screen.findByRole("navigation", { name: "Primary" });
    expect(within(tabs).getByRole("link", { name: "Today" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await userEvent.click(within(tabs).getByRole("button", { name: "More" }));

    const more = await screen.findByRole("dialog", { name: "Ada Lovelace" });
    expect(within(more).getByText("ada@example.com")).toBeVisible();
    await userEvent.click(within(more).getByRole("button", { name: "Sign out" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/sign-in"));
  });

  test("closes a sheet dragged down by its handle", async () => {
    viewport.desktop = false;
    renderApp("/today");

    await userEvent.click(await screen.findByRole("button", { name: "More" }));
    const more = await screen.findByRole("dialog", { name: "Ada Lovelace" });
    const handle = more.firstElementChild;
    fireEvent.pointerDown(handle, { clientY: 100, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientY: 140, pointerId: 1 });
    fireEvent.pointerUp(handle, { clientY: 140, pointerId: 1 });
    expect(screen.getByRole("dialog", { name: "Ada Lovelace" })).toBeVisible();

    fireEvent.pointerDown(handle, { clientY: 100, pointerId: 1 });
    fireEvent.pointerMove(handle, { clientY: 220, pointerId: 1 });
    fireEvent.pointerUp(handle, { clientY: 220, pointerId: 1 });
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});
