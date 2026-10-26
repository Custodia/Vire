import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { activities, mockSession, sessions } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
import { renderApp } from "../test/render.jsx";

function today(year, month, day) {
  vi.setSystemTime(new Date(year, month - 1, day, 9, 30));
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  today(2026, 11, 3);
});

afterEach(() => {
  vi.useRealTimers();
});

describe("Today on a training day", () => {
  test("opening the dashboard lands on Today", async () => {
    const { router } = renderApp("/");

    expect(await screen.findByRole("heading", { level: 1, name: "Today" })).toBeVisible();
    expect(router.state.location.pathname).toBe("/today");
  });

  test("shows the date, the plan above it and how much of the day is done", async () => {
    renderApp("/today");

    expect(
      await screen.findByText("Base · Aerobic endurance · Load cycle · Day 2 of 7"),
    ).toBeVisible();
    expect(screen.getByText("Tue 3 Nov")).toBeVisible();
    expect(screen.getByText("1 of 4 done · 4h08 total")).toBeVisible();
  });

  test("puts the upcoming sessions in a carousel, the next one first", async () => {
    renderApp("/today");

    const carousel = await screen.findByRole("region", { name: "Upcoming sessions" });
    expect(carousel).toHaveAttribute("tabindex", "0");

    const [next, then] = within(carousel).getAllByRole("article");
    expect(next).toHaveAccessibleName("Run / walk — Z2");
    expect(next).toHaveTextContent("Next");
    expect(next).toHaveTextContent("3 of 4");
    expect(next).toHaveTextContent("Easy aerobic, joints first.");
    expect(next).toHaveTextContent("35′Duration");
    expect(then).toHaveAccessibleName("Bike — threshold 3 × 12′");
    expect(then).toHaveTextContent("Then");
    expect(then).toHaveTextContent("4 of 4");
    expect(then).toHaveTextContent("1h45Duration");
  });

  test("lists the completed and skipped sessions as rows that open the session", async () => {
    const { router } = renderApp("/today");

    const done = await screen.findByRole("link", { name: /Swim — endurance/ });
    expect(done).toHaveTextContent("06:32 · 3.05 km · 1:08:40");
    expect(done).toHaveTextContent("✓ Done");

    const skipped = screen.getByRole("link", { name: /Strength.*Skipped/ });
    expect(skipped).toHaveTextContent("Planned 40′");
    expect(skipped).toHaveTextContent("✕ Skipped");

    await userEvent.click(done);

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/sessions/${sessions.swim.id}`),
    );
    expect(screen.getByRole("heading", { name: "Session" })).toBeVisible();
  });

  test("opens an upcoming session from its card", async () => {
    const { router } = renderApp("/today");

    await userEvent.click(await screen.findByRole("link", { name: "Run / walk — Z2" }));

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/sessions/${sessions.run.id}`),
    );
  });

  test("lists an activity no session is matched to and opens it", async () => {
    const { router } = renderApp("/today");

    const section = await screen.findByRole("region", { name: "Other activities" });
    const walk = within(section).getByRole("link", { name: /Other/ });
    expect(walk).toHaveTextContent("17:10 · 2.40 km · 25:00");

    await userEvent.click(walk);

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/activities/${activities.walk.id}`),
    );
    expect(screen.getByRole("heading", { name: "Activity" })).toBeVisible();

    await userEvent.click(screen.getByRole("link", { name: "‹ Today" }));

    expect(await screen.findByRole("heading", { level: 1, name: "Today" })).toBeVisible();
  });
});

describe("Today on other days", () => {
  test("shows a rest day with its note", async () => {
    today(2026, 11, 4);
    renderApp("/today");

    expect(await screen.findByText("Rest day. Nothing is planned.")).toBeVisible();
    expect(screen.getByText("Wed 4 Nov")).toBeVisible();
    expect(screen.getByText("Base · Aerobic endurance · Load cycle · Day 3 of 7")).toBeVisible();
    expect(screen.getByText("Rest")).toBeVisible();
    expect(screen.getByRole("heading", { name: "Day note" })).toBeVisible();
    expect(screen.getByText("Travel day. Walk the airport, nothing more.")).toBeVisible();
    expect(screen.queryByRole("region", { name: "Upcoming sessions" })).toBeNull();
  });

  test("says when a training day has no sessions left", async () => {
    server.use(
      http.get("/api/days/:date", () =>
        HttpResponse.json({
          date: "2026-11-03",
          day: {
            id: "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e03",
            date: "2026-11-03",
            kind: "training",
            note: null,
            chain: {
              season: { id: "s", name: "Winter base" },
              phase: { id: "p", name: "Base" },
              block: { id: "b", focus: "Aerobic endurance" },
              cycle: { id: "c", kind: "recovery", day_number: 2, length: 7 },
            },
            sessions: [],
          },
          activities: [],
        }),
      ),
    );
    renderApp("/today");

    expect(await screen.findByText("No sessions are planned for this day.")).toBeVisible();
    expect(
      screen.getByText("Base · Aerobic endurance · Recovery cycle · Day 2 of 7"),
    ).toBeVisible();
  });

  test("says a date outside the plan is outside it and still lists its activities", async () => {
    today(2026, 12, 25);
    renderApp("/today");

    expect(await screen.findByRole("heading", { name: "Outside your plan" })).toBeVisible();
    const section = screen.getByRole("region", { name: "Activities" });
    expect(within(section).getByRole("link", { name: /Run/ })).toHaveTextContent(
      "10:05 · 5.12 km · 30:45",
    );
  });

  test("shows only the outside-the-plan state for an empty date", async () => {
    today(2027, 1, 1);
    renderApp("/today");

    expect(await screen.findByRole("heading", { name: "Outside your plan" })).toBeVisible();
    expect(screen.queryByRole("region", { name: "Activities" })).toBeNull();
  });

  test("offers a retry when the day cannot be loaded", async () => {
    let failing = true;
    server.use(
      http.get("/api/days/:date", ({ params }) =>
        failing
          ? HttpResponse.json({}, { status: 500 })
          : HttpResponse.json({ date: params.date, day: null, activities: [] }),
      ),
    );
    renderApp("/today");

    expect(await screen.findByRole("status")).toHaveTextContent("Loading the day…");
    expect(await screen.findByRole("alert")).toHaveTextContent("The day could not be loaded.");

    failing = false;
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));

    expect(await screen.findByRole("heading", { name: "Outside your plan" })).toBeVisible();
  });
});

describe("Today after the session has ended", () => {
  test("returning to the page asks to sign in again", async () => {
    const { router } = renderApp("/today");
    expect(await screen.findByText("1 of 4 done · 4h08 total")).toBeVisible();

    mockSession.signedIn = false;
    window.dispatchEvent(new Event("visibilitychange"));

    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeVisible();
    expect(router.state.location.pathname).toBe("/sign-in");
    expect(router.state.location.search).toEqual({ redirect: "/today" });
  });
});
