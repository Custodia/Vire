import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { sessions } from "../mocks/handlers.js";
import { renderApp } from "../test/render.jsx";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(2026, 10, 3, 9, 30));
});

afterEach(() => {
  vi.useRealTimers();
});

function heading(name) {
  return screen.findByRole("heading", { level: 1, name });
}

describe("Moving between days", () => {
  test("steps from Today to the next day and back", async () => {
    const { router } = renderApp("/today");

    await heading("Today");
    await userEvent.click(screen.getByRole("link", { name: "Next day" }));

    expect(await heading("Wed 4 Nov")).toBeVisible();
    expect(router.state.location.pathname).toBe("/days/2026-11-04");
    expect(screen.getByText("2026")).toBeVisible();
    expect(await screen.findByText("Rest day. Nothing is planned.")).toBeVisible();
    expect(screen.getByText("Base · Aerobic endurance · Load cycle · Day 3 of 7")).toBeVisible();

    await userEvent.click(screen.getByRole("link", { name: "Previous day" }));

    expect(await heading("Today")).toBeVisible();
    expect(router.state.location.pathname).toBe("/today");
  });

  test("steps back from Today into a day outside the plan", async () => {
    const { router } = renderApp("/today");

    await heading("Today");
    await userEvent.click(screen.getByRole("link", { name: "Previous day" }));

    expect(await heading("Mon 2 Nov")).toBeVisible();
    expect(router.state.location.pathname).toBe("/days/2026-11-02");
    expect(await screen.findByRole("heading", { name: "Outside your plan" })).toBeVisible();
  });

  test("shows any date's sessions from the URL and opens one", async () => {
    vi.setSystemTime(new Date(2026, 10, 20, 9, 30));
    const { router } = renderApp("/days/2026-11-03");

    expect(await heading("Tue 3 Nov")).toBeVisible();
    expect(await screen.findByText("1 of 4 done · 4h08 total")).toBeVisible();
    const carousel = screen.getByRole("region", { name: "Upcoming sessions" });
    expect(within(carousel).getAllByRole("article")).toHaveLength(2);

    await userEvent.click(screen.getByRole("link", { name: /Swim — endurance/ }));

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/sessions/${sessions.swim.id}`),
    );
  });

  test("returns to Today from any day", async () => {
    const { router } = renderApp("/days/2026-11-04");

    await heading("Wed 4 Nov");
    await userEvent.click(screen.getByRole("link", { name: "Back to Today" }));

    expect(await heading("Today")).toBeVisible();
    expect(router.state.location.pathname).toBe("/today");
  });
});

describe("A day's empty states", () => {
  test("lists the activities of a date outside the plan", async () => {
    renderApp("/days/2026-12-25");

    expect(await heading("Fri 25 Dec")).toBeVisible();
    expect(await screen.findByRole("heading", { name: "Outside your plan" })).toBeVisible();
    const section = screen.getByRole("region", { name: "Activities" });
    expect(within(section).getByRole("link", { name: /Run/ })).toHaveTextContent(
      "10:05 · 5.12 km · 30:45",
    );
  });

  test("shows a date with nothing on it as outside the plan", async () => {
    renderApp("/days/2027-01-01");

    expect(await screen.findByRole("heading", { name: "Outside your plan" })).toBeVisible();
    expect(screen.queryByRole("region", { name: "Activities" })).toBeNull();
    expect(screen.queryByRole("region", { name: "Upcoming sessions" })).toBeNull();
  });

  test("says when the URL does not hold a date", async () => {
    renderApp("/days/2026-02-30");

    expect(await heading("Not a date")).toBeVisible();
    expect(screen.getByText(/“2026-02-30” is not a date/)).toBeVisible();
    expect(screen.getByRole("link", { name: "Back to Today" })).toBeVisible();
  });
});
