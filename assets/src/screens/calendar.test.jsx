import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { activities, sessions } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
import { renderApp } from "../test/render.jsx";
import { viewport } from "../test/setup.js";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(2026, 10, 3, 9, 30));
});

afterEach(() => {
  vi.useRealTimers();
});

const card = (name) => screen.getByRole("heading", { level: 2, name }).closest("section");

async function openToday() {
  const view = renderApp("/calendar/day/2026-11-03");
  await screen.findByRole("heading", { level: 2, name: "Run / walk — Z2" });
  return view;
}

describe("the day on a desktop", () => {
  test("heads today with its place in the plan and the week's totals", async () => {
    await openToday();

    const header = screen
      .getByRole("heading", { level: 1, name: "Tuesday 3 Nov" })
      .closest("section");
    expect(
      await within(header).findByText("Today · Base · Block 1 · Load 2 · Day 2 of 7"),
    ).toBeVisible();
    // Tue 3 Nov to Sun 27 Dec is 54 days.
    expect(within(header).getByText("weeks to Autumn 10 km").previousSibling).toHaveTextContent(
      "8",
    );
    expect(within(header).getByText("sessions done today").previousSibling).toHaveTextContent(
      "1 of 4",
    );
    expect(within(header).getByText("trained today").previousSibling).toHaveTextContent(
      "1h34 of 4h08",
    );
  });

  test("marks the calendar in the bar of screens and Day in its views", async () => {
    await openToday();

    const nav = screen.getByRole("navigation", { name: "Primary" });
    expect(within(nav).getByRole("link", { name: "Calendar" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    const views = screen.getByRole("navigation", { name: "Calendar view" });
    expect(within(views).getByRole("link", { name: "Day" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(within(views).getByRole("link", { name: "Week" })).toHaveAttribute(
      "href",
      "/calendar/week/2026-11-03",
    );
    expect(screen.getByRole("link", { name: "Next day" })).toHaveAttribute(
      "href",
      "/calendar/day/2026-11-04",
    );
    expect(screen.getByRole("link", { name: "Today" })).toHaveAttribute("aria-current", "page");
  });

  test("lays the week's days side by side, each linking to its day", async () => {
    await openToday();

    const week = card(/^2 – 8 Nov/);
    expect(within(week).getByRole("heading")).toHaveTextContent("2 – 8 Nov · Load 2");
    const days = within(week).getAllByRole("link", { name: /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) / });
    expect(days).toHaveLength(7);

    const tuesday = within(week).getByRole("link", { name: /^Tue 3, today/ });
    expect(tuesday).toHaveAttribute("aria-current");
    expect(tuesday).toHaveAttribute("href", "/calendar/day/2026-11-03");
    expect(tuesday).toHaveTextContent("Done: Swim — endurance 1h08");
    expect(tuesday).toHaveTextContent("Skipped: Strength 40′");
    expect(tuesday).toHaveTextContent("Bike — threshold 3 × 12′ 1h45");

    const wednesday = within(week).getByRole("link", { name: /^Wed 4/ });
    expect(wednesday).toHaveAttribute("href", "/calendar/day/2026-11-04");
    expect(wednesday).not.toHaveAttribute("aria-current");
    expect(wednesday).toHaveTextContent("Rest");
    expect(within(week).getByRole("link", { name: /^Mon 2/ })).toHaveTextContent("Rest day kept");
  });

  test("lists the day's sessions and shows its next one", async () => {
    await openToday();

    const day = card("Tuesday 3 Nov");
    expect(day).toHaveTextContent("1 of 4 done · 4h08");
    const rows = within(within(day).getByRole("list", { name: "Sessions" })).getAllByRole("link");
    expect(rows.map((row) => row.textContent)).toEqual([
      "Swim — endurance06:32 · 3.05 km · 1:08:40✓ Done",
      "Strength40′✕ Skipped",
      "Run / walk — Z2Next · 35′",
      "Bike — threshold 3 × 12′Then · 1h45",
    ]);
    expect(rows[2]).toHaveAttribute("aria-current", "true");
    expect(rows[0]).not.toHaveAttribute("aria-current");

    const hero = card("Run / walk — Z2");
    expect(hero).toHaveTextContent("Planned today");
    expect(hero).toHaveTextContent("Easy aerobic, joints first.");
    const summary = within(hero).getByRole("group", { name: "Summary" });
    expect(summary).toHaveTextContent("35′Duration28′WorkZ2Peak zone");
  });

  test("shows the session's structure with the reason for it", async () => {
    await openToday();

    const structure = card("Structure");
    expect(
      within(structure).getByRole("img", { name: /^Workout profile: 7 × \(4′ work in Z2/ }),
    ).toBeVisible();
    const steps = within(within(structure).getByRole("list", { name: "Steps" })).getAllByRole(
      "listitem",
    );
    expect(steps[0]).toHaveTextContent("7×4′Work< 145 bpm");
    expect(steps[1]).toHaveTextContent("7×1′Recovery, Walk");
    expect(structure).toHaveTextContent("Why this session");
    expect(structure).toHaveTextContent("Run/walk keeps the load on the joints low");
  });

  test("compares with the last session like it", async () => {
    await openToday();

    const last = card("Last time");
    expect(within(last).getByRole("link", { name: "Fri 30 Oct" })).toHaveAttribute(
      "href",
      "/sessions/5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e06",
    );
    expect(last).toHaveTextContent("40:00Duration5.10 kmDistance39Training load139Avg heart rate");
  });

  test("shows a matched activity as its session", async () => {
    renderApp(`/activities/${activities.swim.id}`);

    expect(
      await screen.findByRole("heading", { level: 2, name: "Swim — endurance" }),
    ).toBeVisible();
  });

  test("shows a done session with what was recorded against the plan", async () => {
    const { router } = await openToday();

    await userEvent.click(
      within(card("Tuesday 3 Nov")).getByRole("link", { name: /Swim — endurance/ }),
    );

    const hero = await screen.findByRole("heading", { level: 2, name: "Swim — endurance" });
    expect(router.state.location.pathname).toBe(`/sessions/${sessions.swim.id}`);
    const section = hero.closest("section");
    expect(section).toHaveTextContent("Completed 06:32 · 25 m pool");
    expect(section).toHaveTextContent("✓ Done");
    expect(within(section).getByRole("group", { name: "Planned and recorded" })).toHaveTextContent(
      "1:08:40Durationplan 1h083.05 kmDistance48Training load131Avg heart rate",
    );
    expect(card("Laps")).toBeVisible();
    expect(card("Pool lengths")).toBeVisible();
    expect(screen.getByRole("heading", { level: 1, name: "Tuesday 3 Nov" })).toBeVisible();
    expect(
      within(card("Tuesday 3 Nov")).getByRole("link", { name: /Swim — endurance/ }),
    ).toHaveAttribute("aria-current");
  });

  test("shows a skipped session with the reason for it", async () => {
    await openToday();

    await userEvent.click(within(card("Tuesday 3 Nov")).getByRole("link", { name: /Strength/ }));

    const hero = (await screen.findByRole("heading", { level: 2, name: "Strength" })).closest(
      "section",
    );
    expect(hero).toHaveTextContent("Skipped · Tue 3 Nov");
    expect(hero).toHaveTextContent("✕ Skipped");
    expect(card("Why this session")).toHaveTextContent("Two strength sessions a cycle");
    expect(screen.queryByRole("heading", { level: 2, name: "Structure" })).toBeNull();
  });

  test("shows sessions still planned on an earlier day as skipped", async () => {
    vi.setSystemTime(new Date(2026, 10, 4, 9, 30));
    renderApp("/calendar/day/2026-11-03");

    const hero = (
      await screen.findByRole("heading", { level: 2, name: "Swim — endurance" })
    ).closest("section");
    expect(hero).toHaveTextContent("✓ Done");
    const rows = within(within(card("Tuesday 3 Nov")).getByRole("list", { name: "Sessions" }))
      .getAllByRole("link")
      .map((row) => row.textContent);
    expect(rows.slice(2)).toEqual([
      "Run / walk — Z235′✕ Skipped",
      "Bike — threshold 3 × 12′1h45✕ Skipped",
    ]);
    expect(screen.getByRole("link", { name: /^Tue 3/ })).toHaveTextContent(
      "Skipped: Run / walk — Z2 35′",
    );

    await userEvent.click(within(card("Tuesday 3 Nov")).getByRole("link", { name: /Run \/ walk/ }));
    expect(await screen.findByText("Skipped · Tue 3 Nov")).toBeVisible();
  });

  test("offers a retry when the day cannot be loaded", async () => {
    server.use(http.get("/api/days", () => new HttpResponse(null, { status: 500 })));
    renderApp("/calendar/day/2026-11-03");

    expect(await screen.findByRole("alert")).toHaveTextContent("The day could not be loaded.");
    expect(screen.getByRole("button", { name: "Try again" })).toBeVisible();
  });

  test("shows an activity no session is matched to", async () => {
    const { router } = await openToday();

    const unplanned = card("Tuesday 3 Nov").querySelector("[aria-labelledby=unplanned-heading]");
    expect(unplanned).toHaveTextContent("Not in the plan");
    await userEvent.click(within(unplanned).getByRole("link", { name: /Other/ }));

    const hero = await screen.findByRole("heading", { level: 2, name: "Other" });
    expect(router.state.location.pathname).toBe(`/activities/${activities.walk.id}`);
    expect(hero.closest("section")).toHaveTextContent("Recorded 17:10");
    expect(
      within(hero.closest("section")).getByRole("group", { name: "Summary" }),
    ).toHaveTextContent("25:00Duration2.40 kmDistance—Training load—Avg heart rate");
  });

  test("matches an activity to one of the day's sessions without one", async () => {
    const { router } = await openToday();

    await userEvent.click(
      screen.getByRole("button", { name: "Match the other at 17:10 to a session" }),
    );
    const menu = await screen.findByRole("menu", {
      name: "Match the other at 17:10 to a session",
    });
    expect(
      within(menu)
        .getAllByRole("menuitem")
        .map((item) => item.textContent),
    ).toEqual(["Strength", "Run / walk — Z2", "Bike — threshold 3 × 12′"]);
    await userEvent.click(within(menu).getByRole("menuitem", { name: "Run / walk — Z2" }));

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/sessions/${sessions.run.id}`),
    );
    expect(await screen.findByText("Completed 17:10")).toBeVisible();
    await waitFor(() => expect(screen.queryByText("Not in the plan")).toBeNull());
  });

  test("opens another day of the week from its link", async () => {
    const { router } = await openToday();

    await userEvent.click(screen.getByRole("link", { name: /^Thu 5/ }));

    expect(await screen.findByRole("heading", { level: 1, name: "Thursday 5 Nov" })).toBeVisible();
    expect(router.state.location.pathname).toBe("/calendar/day/2026-11-05");
    expect(
      await screen.findByRole("heading", { level: 2, name: "Bike — endurance with sprints" }),
    ).toBeVisible();
    expect(await screen.findByRole("figure", { name: "Power and heart rate" })).toBeVisible();
  });

  test("says a rest day has nothing planned, with the day's note", async () => {
    renderApp("/calendar/day/2026-11-04");

    expect(await screen.findByRole("heading", { level: 2, name: "Rest day" })).toBeVisible();
    const day = card("Wednesday 4 Nov");
    expect(day).toHaveTextContent("Rest day.");
    expect(day).toHaveTextContent("Travel day. Walk the airport, nothing more.");
  });

  test("shows a date outside the plan with what was recorded on it", async () => {
    renderApp("/calendar/day/2026-12-25");

    const header = (
      await screen.findByRole("heading", { level: 1, name: "Friday 25 Dec" })
    ).closest("section");
    expect(await within(header).findByText("Outside your plan")).toBeVisible();
    expect(await screen.findByRole("heading", { level: 2, name: "Run" })).toBeVisible();
    expect(card("Friday 25 Dec")).toHaveTextContent("Outside your plan.");
  });

  test("leaves readiness and the weight trend empty", async () => {
    await openToday();

    expect(card("Readiness")).toHaveTextContent("No readiness data yet.");
    expect(card("Weight trend")).toHaveTextContent("No weight data yet.");
  });

  test("says what is wrong with a day that is not a date", async () => {
    renderApp("/calendar/day/2026-02-30");

    expect(await screen.findByRole("heading", { level: 1, name: "Not a date" })).toBeVisible();
  });

  test("says when a session is not in the account", async () => {
    renderApp("/sessions/5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6eff");

    expect(await screen.findByRole("heading", { level: 1, name: "Not found" })).toBeVisible();
    expect(screen.getByText("There is no such session in your account.")).toBeVisible();
  });
});

describe("the week on a desktop", () => {
  test("heads the week with its place in the plan and its totals", async () => {
    renderApp("/calendar/week/2026-11-03");

    const header = (await screen.findByRole("heading", { level: 1, name: "2 – 8 Nov" })).closest(
      "section",
    );
    expect(await within(header).findByText("Base · Block 1 · Load 2")).toBeVisible();
    expect(within(header).getByText(/^sessions done/)).toHaveTextContent(
      "sessions done · 1 skipped",
    );
    expect(within(header).getByText(/^sessions done/).previousSibling).toHaveTextContent("2 of 5");
  });

  test("charts each day's hours trained against those planned", async () => {
    renderApp("/calendar/week/2026-11-03");

    expect(
      await screen.findByRole("img", { name: /^Hours trained each day against the hours planned/ }),
    ).toBeVisible();
  });

  test("lists each day with its ring, its hours and its sessions", async () => {
    renderApp("/calendar/week/2026-11-03");

    const days = within(await screen.findByRole("list", { name: "Days of the week" }));
    const day = (name) => days.getByRole("link", { name }).parentElement;
    const tuesday = day(/Tue 3, today/);
    expect(within(tuesday).getByRole("img", { name: "1 of 4 done" })).toBeVisible();
    expect(within(tuesday).getByRole("link", { name: /Tue 3, today/ })).toHaveAttribute(
      "href",
      "/calendar/day/2026-11-03",
    );
    const cards = within(tuesday)
      .getAllByRole("link")
      .filter((link) => link.getAttribute("href")?.startsWith("/sessions/"));
    expect(cards.map((link) => link.textContent)).toEqual([
      "Swim — endurance06:32 · 3.05 km · 1:08:40",
      "StrengthSkipped · 40′ planned",
      "Run / walk — Z2Next · 35′",
      "Bike — threshold 3 × 12′1h45",
    ]);
    expect(within(tuesday).getByRole("link", { name: /Other/ })).toHaveAttribute(
      "href",
      `/activities/${activities.walk.id}`,
    );
    expect(within(day(/Wed 4/)).getByText("Rest day")).toBeVisible();
    expect(within(day(/Mon 2/)).getByText("Rest day kept")).toBeVisible();
  });

  test("moves a week at a time", async () => {
    renderApp("/calendar/week/2026-11-03");

    expect(await screen.findByRole("link", { name: "Next week" })).toHaveAttribute(
      "href",
      "/calendar/week/2026-11-10",
    );
    expect(screen.getByRole("link", { name: "Previous week" })).toHaveAttribute(
      "href",
      "/calendar/week/2026-10-27",
    );
  });
});

describe("the month on a desktop", () => {
  test("lays out the month's weeks with each day's sessions and each week's hours", async () => {
    renderApp("/calendar/month/2026-11-03");

    const month = await screen.findByRole("region", { name: "November 2026" });
    const tuesday = within(month).getByRole("link", { name: /^3, today/ });
    expect(tuesday).toHaveAttribute("href", "/calendar/day/2026-11-03");
    expect(tuesday).toHaveTextContent("Done: Swim — endurance 1h08");
    expect(tuesday).toHaveTextContent("Not in the plan: Activity");
    const weeks = within(month)
      .getAllByRole("link")
      .filter((link) => link.getAttribute("href")?.startsWith("/calendar/week/"));
    expect(weeks[0]).toHaveAttribute("href", "/calendar/week/2026-10-26");
    expect(weeks[1]).toHaveTextContent("This week");
  });

  test("moves a month at a time, keeping the day of the month", async () => {
    renderApp("/calendar/month/2026-10-31");

    expect(await screen.findByRole("link", { name: "Next month" })).toHaveAttribute(
      "href",
      "/calendar/month/2026-11-30",
    );
  });
});

describe("on a phone", () => {
  beforeEach(() => {
    viewport.desktop = false;
  });

  test("puts the screens in tabs along the bottom, and the rest under More", async () => {
    renderApp("/calendar/day/2026-11-03");

    const tabs = await screen.findByRole("navigation", { name: "Primary" });
    expect(within(tabs).getByRole("link", { name: "Calendar" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await userEvent.click(within(tabs).getByRole("button", { name: "More" }));

    const more = await screen.findByRole("dialog", { name: "Ada Lovelace" });
    expect(within(more).getByText("ada@example.com")).toBeVisible();
    expect(within(more).getByRole("button", { name: "Sign out" })).toBeVisible();
  });

  test("signs out from More", async () => {
    const { router } = renderApp("/calendar/day/2026-11-03");

    await userEvent.click(await screen.findByRole("button", { name: "More" }));
    const more = await screen.findByRole("dialog", { name: "Ada Lovelace" });
    await userEvent.click(within(more).getByRole("button", { name: "Sign out" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/sign-in"));
  });

  test("shows the day as a timeline with the next session open", async () => {
    renderApp("/calendar/day/2026-11-03");

    const timeline = await screen.findByRole("list", { name: "Timeline" });
    const toggles = within(timeline)
      .getAllByRole("button", { expanded: false })
      .filter((button) => button.hasAttribute("aria-controls"));
    const open = within(timeline).getByRole("button", { expanded: true });
    expect(open).toHaveTextContent("Run / walk — Z2");
    expect(toggles.map((toggle) => toggle.textContent)).toEqual([
      "Swim — endurance3.05 km · 1:08:40",
      "Activity2.40 km · 25:00",
      "Strength40′",
      "Bike — threshold 3 × 12′1h45",
    ]);
    expect(within(timeline).getByRole("link", { name: "Open the session" })).toHaveAttribute(
      "href",
      `/sessions/${sessions.run.id}`,
    );

    await userEvent.click(open);
    expect(within(timeline).queryByRole("link", { name: "Open the session" })).toBeNull();
    await userEvent.click(toggles[0]);
    expect(within(timeline).getByRole("link", { name: "Open the session" })).toHaveAttribute(
      "href",
      `/sessions/${sessions.swim.id}`,
    );
  });

  test("rings the week's days above the day", async () => {
    renderApp("/calendar/day/2026-11-03");

    const strip = await screen.findByRole("list", { name: "Days of the week" });
    const today = within(strip).getByRole("link", { name: "Tuesday 3 Nov, today" });
    expect(today).toHaveAttribute("aria-current", "page");
    expect(within(today).getByRole("img", { name: "1 of 4 done" })).toBeVisible();
    expect(
      within(within(strip).getByRole("link", { name: "Monday 2 Nov" })).getByRole("img", {
        name: "Rest day kept",
      }),
    ).toBeVisible();
  });

  test("pulls the next day in under a drag to the left, and moves to it when let go", async () => {
    const { router } = renderApp("/calendar/day/2026-11-03");

    const timeline = await screen.findByRole("list", { name: "Timeline" });
    fireEvent.touchStart(timeline, { touches: [{ clientX: 300, clientY: 400 }] });
    fireEvent.touchMove(timeline, { touches: [{ clientX: 260, clientY: 402 }] });
    expect(
      await screen.findByRole("heading", { level: 1, name: "Wednesday 4 Nov", hidden: true }),
    ).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 1, name: "Tuesday 3 Nov" })).toBeVisible();

    fireEvent.touchMove(timeline, { touches: [{ clientX: 120, clientY: 410 }] });
    fireEvent.touchEnd(timeline, { changedTouches: [{ clientX: 120, clientY: 410 }] });

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/day/2026-11-04"));
    expect(await screen.findByRole("heading", { level: 1, name: "Wednesday 4 Nov" })).toBeVisible();
  });

  test("leaves a drag up or down to the page", async () => {
    const { router } = renderApp("/calendar/day/2026-11-03");

    const timeline = await screen.findByRole("list", { name: "Timeline" });
    fireEvent.touchStart(timeline, { touches: [{ clientX: 200, clientY: 400 }] });
    fireEvent.touchMove(timeline, { touches: [{ clientX: 180, clientY: 300 }] });
    fireEvent.touchMove(timeline, { touches: [{ clientX: 120, clientY: 200 }] });
    fireEvent.touchEnd(timeline, { changedTouches: [{ clientX: 120, clientY: 200 }] });

    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(router.state.location.pathname).toBe("/calendar/day/2026-11-03");
    expect(
      screen.queryByRole("heading", { level: 1, hidden: true, name: "Wednesday 4 Nov" }),
    ).toBeNull();
  });

  test("goes to today when the view shown is tapped in the switch above the tabs", async () => {
    const { router } = renderApp("/calendar/day/2026-11-05");

    await screen.findByRole("list", { name: "Timeline" });
    expect(screen.queryByRole("link", { name: "Today" })).toBeNull();
    const views = screen.getByRole("navigation", { name: "Calendar view" });
    expect(within(views).getByRole("link", { name: "Day" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(within(views).getByRole("link", { name: "Week" })).toHaveAttribute(
      "href",
      "/calendar/week/2026-11-05",
    );

    await userEvent.click(within(views).getByRole("link", { name: "Day" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/day/2026-11-03"));
  });

  async function viewSwitch() {
    await screen.findByRole("list", { name: "Timeline" });
    const views = screen.getByRole("navigation", { name: "Calendar view" });
    Object.defineProperty(views, "clientWidth", { value: 300 });
    return views;
  }

  const slide = (views, ...xs) => {
    fireEvent.touchStart(views, { touches: [{ clientX: xs[0], clientY: 20 }] });
    for (const x of xs.slice(1))
      fireEvent.touchMove(views, { touches: [{ clientX: x, clientY: 20 }] });
    fireEvent.touchEnd(views, { changedTouches: [{ clientX: xs.at(-1), clientY: 20 }] });
  };

  test("moves to the next view over after a short slide along the switch", async () => {
    const { router } = renderApp("/calendar/day/2026-11-05");
    const views = await viewSwitch();

    slide(views, 250, 240, 220);
    fireEvent.click(within(views).getByRole("link", { name: "Day" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/week/2026-11-05"));
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(router.state.location.pathname).toBe("/calendar/week/2026-11-05");
  });

  test("keeps a tap that wobbles a little a tap", async () => {
    const { router } = renderApp("/calendar/day/2026-11-05");
    const views = await viewSwitch();

    slide(views, 150, 156);
    expect(router.state.location.pathname).toBe("/calendar/day/2026-11-05");
    await userEvent.click(within(views).getByRole("link", { name: "Week" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/week/2026-11-05"));
  });

  test("puts the highlight on the view shown after a slide and a tap back", async () => {
    const { router } = renderApp("/calendar/day/2026-11-05");
    const views = await viewSwitch();
    const highlight = views.firstElementChild;

    slide(views, 250, 240, 220);
    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/week/2026-11-05"));
    slide(views, 250);
    await userEvent.click(within(views).getByRole("link", { name: "Day" }));
    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/day/2026-11-05"));

    expect(highlight.style.transform).toBe("translateX(calc(2 * (100% + 2px)))");
  });

  test("opens the calendar on today in the view last shown", async () => {
    const { router } = renderApp("/calendar/week/2026-11-17");

    await screen.findByRole("list", { name: "Days of the week" });
    await userEvent.click(
      within(screen.getByRole("navigation", { name: "Primary" })).getByRole("link", {
        name: "Calendar",
      }),
    );

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/week/2026-11-03"));
  });

  test("closes a sheet dragged down by its handle", async () => {
    renderApp("/calendar/day/2026-11-03");

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

  test("goes back to the day with a swipe to the right on a session's page", async () => {
    const { router } = renderApp(`/sessions/${sessions.swim.id}`);

    const heading = await screen.findByRole("heading", { level: 1, name: "Swim — endurance" });
    fireEvent.touchStart(heading, { touches: [{ clientX: 40, clientY: 300 }] });
    fireEvent.touchEnd(heading, { changedTouches: [{ clientX: 260, clientY: 310 }] });

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/day/2026-11-03"));
  });

  test("lists each day of the week with its sessions' marks", async () => {
    renderApp("/calendar/week/2026-11-03");

    const days = await screen.findByRole("list", { name: "Days of the week" });
    const tuesday = within(days).getByRole("link", { name: /^Tue, today/ });
    expect(tuesday).toHaveAttribute("href", "/calendar/day/2026-11-03");
    expect(
      within(tuesday)
        .getAllByRole("img")
        .map((mark) => mark.getAttribute("aria-label")),
    ).toEqual([
      "Swim",
      "Done",
      "Other",
      "Not in the plan",
      "Strength",
      "Skipped",
      "Run",
      "Upcoming",
      "Bike",
      "Upcoming",
    ]);
  });

  test("shows the month as dots, with the date's day listed below", async () => {
    const { router } = renderApp("/calendar/month/2026-11-03");

    const month = await screen.findByRole("list", { name: "November 2026" });
    expect(
      within(month).getByRole("link", { name: "Tuesday 3 Nov, today, 1 of 4 done, 1 skipped" }),
    ).toHaveAttribute("aria-current", "page");
    expect(card("Tuesday 3 Nov")).toHaveTextContent("Swim — endurance");

    await userEvent.click(within(month).getByRole("link", { name: /^Thursday 5 Nov/ }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/calendar/month/2026-11-05"));
    expect(await screen.findByRole("heading", { level: 2, name: "Thursday 5 Nov" })).toBeVisible();
  });

  test("opens a session as a page of its own, with a way back to its day", async () => {
    renderApp(`/sessions/${sessions.swim.id}`);

    expect(
      await screen.findByRole("heading", { level: 1, name: "Swim — endurance" }),
    ).toBeVisible();
    expect(screen.getByRole("link", { name: "Back to Tue 3 Nov" })).toHaveAttribute(
      "href",
      "/calendar/day/2026-11-03",
    );
    expect(screen.queryByRole("list", { name: "Timeline" })).toBeNull();
  });
});
