import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { mockPlan, mockPlanChanges, season } from "../mocks/handlers.js";
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

describe("the plan", () => {
  test("leads with the season as the goal and the weeks left to it", async () => {
    renderApp("/plan");

    expect(await screen.findByRole("heading", { level: 1, name: "Autumn 10 km" })).toBeVisible();
    expect(
      screen.getByText("Ten kilometres in December, with the weight coming down on the way."),
    ).toBeVisible();
    // Tue 3 Nov to Sun 27 Dec is 54 days.
    expect(screen.getByText("weeks to go").previousSibling).toHaveTextContent("8");
    expect(screen.getByText("trend weight").previousSibling).toHaveTextContent("—");
    expect(screen.getByText("chronic load (CTL)").previousSibling).toHaveTextContent("—");
  });

  test("marks the plan in the bar of screens", async () => {
    renderApp("/plan");

    const nav = await screen.findByRole("navigation", { name: "Primary" });
    expect(within(nav).getByRole("link", { name: "Plan" })).toHaveAttribute("aria-current", "page");
    expect(within(nav).getByRole("link", { name: "Calendar" })).not.toHaveAttribute("aria-current");
  });

  test("lays the phases and blocks along the season, with the spans nothing covers", async () => {
    renderApp("/plan");

    const phases = await screen.findByRole("list", { name: "Phases" });
    const [base, build] = within(phases).getAllByRole("listitem");
    // Base runs 5 Oct to 15 Nov, Build 16 Nov to 27 Dec: 42 of the season's 84 days each.
    expect(base).toHaveStyle({ left: "0%", width: "50%" });
    expect(build).toHaveStyle({ left: "50%", width: "50%" });
    expect(within(base).getByRole("button")).toHaveTextContent("Current");
    expect(within(build).getByRole("button")).not.toHaveTextContent("Current");

    const blocks = within(screen.getByRole("list", { name: "Blocks" }));
    expect(blocks.getAllByText("Not planned yet")).toHaveLength(3);
    expect(
      blocks.getByRole("button", { name: "Block 1 · Aerobic endurance, current" }),
    ).toHaveAttribute("aria-pressed", "true");
    expect(blocks.getByRole("button", { name: "Block 2 · Threshold, planned" })).toHaveAttribute(
      "aria-pressed",
      "false",
    );
  });

  test("charts each week's hours planned, done and outside the plan", async () => {
    renderApp("/plan");

    const weeks = await screen.findByRole("list", { name: "Hours per week" });
    const past = within(weeks).getByRole("link", { name: "Week of 26 Oct" });
    expect(past).toHaveAttribute("href", "/calendar/week/2026-10-26");
    expect(past).toHaveAccessibleDescription(
      "Week of 26 Oct 0.8 of 1.8 h · 1 of 2 sessions. Not done: Technique swim 1h Not in the plan: Other +45′",
    );
    // The strength session skipped today is missed; the rest of the week is still to come.
    const now = within(weeks).getByRole("link", { name: "Week of 2 Nov" });
    expect(now).toHaveAttribute("href", "/calendar/week/2026-11-03");
    expect(now).toHaveAccessibleDescription(
      "Week of 2 Nov 2.1 of 5.1 h · 2 of 5 sessions. Not done: Strength 40′",
    );
    expect(within(weeks).getByRole("link", { name: "Week of 9 Nov" })).toHaveAccessibleDescription(
      "Week of 9 Nov Not planned yet.",
    );
    expect(within(weeks).getByRole("link", { name: "Week of 16 Nov" })).toHaveAccessibleDescription(
      "Week of 16 Nov 0.0 h planned · 0 sessions.",
    );
  });

  test("tabulates the current phase's blocks with their dates, cycles and hours", async () => {
    renderApp("/plan");

    await screen.findByRole("heading", { level: 2, name: "Base · blocks" });
    const blocks = card("Base · blocks");
    expect(blocks).toHaveTextContent("Aerobic volume first, with steady weight loss.");

    const [row] = within(blocks).getAllByRole("row").slice(1);
    expect(within(row).getByRole("button", { name: "Block 1, current" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    expect(row).toHaveTextContent("26 Oct – 8 Nov");
    expect(row).toHaveTextContent("2 × 7d");
    expect(row).toHaveTextContent("Aerobic endurance");
    // 45′ + 1h + 1h + 45′ + 1h30.
    expect(row).toHaveTextContent("6.9");
  });

  test("opens on the block today falls in, as weeks of its days", async () => {
    renderApp("/plan");

    await screen.findByRole("heading", { level: 2, name: "Block 1 · cycles × days" });
    const calendar = screen.getByRole("table", { name: "Block calendar" });
    const [, first, second] = within(calendar).getAllByRole("row");

    expect(within(first).getByRole("rowheader")).toHaveTextContent("Load 1");
    expect(within(second).getByRole("rowheader")).toHaveTextContent("Load 2");

    const today = within(second).getByRole("link", { name: "Tue 3 Nov" });
    expect(today).toHaveTextContent("Today");
    expect(today).toHaveTextContent("Done: Swim — endurance 1h08");
    expect(today).toHaveTextContent("Run / walk — Z2 35′");
    expect(within(second).getByRole("link", { name: "Wed 4 Nov" })).toHaveTextContent("Rest");
  });

  test("marks sessions that are done and skipped", async () => {
    renderApp("/plan");

    expect(await screen.findByRole("link", { name: "Mon 26 Oct" })).toHaveTextContent(
      "Done: Easy run 45′",
    );
    expect(screen.getByRole("link", { name: "Wed 28 Oct" })).toHaveTextContent(
      "Skipped: Technique swim 1h",
    );
  });

  test("shows a session still planned on an earlier day as skipped", async () => {
    vi.setSystemTime(new Date(2026, 10, 4, 9, 30));
    renderApp("/plan");

    const tuesday = await screen.findByRole("link", { name: "Tue 3 Nov" });
    expect(tuesday).toHaveTextContent("Skipped: Run / walk — Z2 35′");
    expect(tuesday).toHaveTextContent("Done: Swim — endurance 1h08");
  });

  test("splits a cycle longer than a week over rows, sharing a week with the next", async () => {
    renderApp("/plan");

    const build = within(await screen.findByRole("list", { name: "Phases" })).getByRole("button", {
      name: /Build/,
    });
    await userEvent.click(build);

    const blocks = card("Build · blocks");
    expect(blocks).toHaveTextContent("10d + 4d recovery");
    expect(blocks).toHaveTextContent("—");

    const calendar = screen.getByRole("table", { name: "Block calendar" });
    const [, first, second] = within(calendar).getAllByRole("row");
    expect(within(first).getByRole("rowheader")).toHaveTextContent("Load 1");
    expect(within(second).getByRole("rowheader")).toHaveTextContent("Load 1Recovery");
    expect(within(second).getByRole("link", { name: "Thu 26 Nov" })).toHaveTextContent("Recovery");
  });

  test("choosing a block on the map redraws the table and calendar", async () => {
    renderApp("/plan");

    await userEvent.click(
      await screen.findByRole("button", { name: "Block 2 · Threshold, planned" }),
    );

    expect(screen.getByRole("heading", { level: 2, name: "Build · blocks" })).toBeVisible();
    expect(
      screen.getByRole("heading", { level: 2, name: "Block 2 · cycles × days" }),
    ).toBeVisible();
  });

  test("choosing a block in the table opens its calendar", async () => {
    renderApp("/plan");

    await userEvent.click(await screen.findByRole("button", { name: /^Build/ }));
    await userEvent.click(await screen.findByRole("button", { name: "Block 2" }));

    expect(
      screen.getByRole("heading", { level: 2, name: "Block 2 · cycles × days" }),
    ).toBeVisible();
    expect(screen.getByRole("button", { name: "Block 2" })).toHaveAttribute("aria-pressed", "true");
  });

  test("switches between seasons", async () => {
    const spring = {
      ...season,
      id: "9f1c0b2a-7d4e-4a1b-9c3d-5e6f7a8b9c02",
      name: "Spring 5 km",
      period: { first: "2027-03-01", last: "2027-05-30" },
      rationale: null,
      phases: [],
    };
    mockPlan.seasons = [
      ...mockPlan.seasons,
      { id: spring.id, name: spring.name, period: spring.period },
    ];
    server.use(http.get(`/api/seasons/${spring.id}`, () => HttpResponse.json(spring)));
    const { router } = renderApp("/plan");

    const seasons = await screen.findByRole("navigation", { name: "Seasons" });
    expect(within(seasons).getByRole("button", { name: "Autumn 10 km" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await userEvent.click(within(seasons).getByRole("button", { name: "Spring 5 km" }));

    expect(await screen.findByRole("heading", { level: 1, name: "Spring 5 km" })).toBeVisible();
    expect(router.state.location.search).toEqual({ season: spring.id });
    expect(screen.getByText("1 Mar – 30 May")).toBeVisible();
  });

  test("a day leads to its day in the calendar", async () => {
    const { router } = renderApp("/plan");

    await userEvent.click(await screen.findByRole("link", { name: "Thu 5 Nov" }));
    expect(router.state.location.pathname).toBe("/calendar/day/2026-11-05");
  });

  test("lists the latest plan changes with the reasons behind them", async () => {
    renderApp("/plan");

    await screen.findByText("Updated session · Threshold intervals");
    const log = card("Coach log");
    const [update, insert] = within(log).getAllByRole("listitem");

    expect(update).toHaveTextContent("Mon 2 Nov · Coach");
    expect(update).toHaveTextContent("HRV below its band for three nights.");
    expect(insert).toHaveTextContent("Created recovery cycle");
  });

  test("says so when the plan has not changed yet", async () => {
    mockPlanChanges.changes = [];
    renderApp("/plan");

    expect(await screen.findByText("No changes yet.")).toBeVisible();
  });

  test("keeps the weight and targets boards empty until their data exists", async () => {
    renderApp("/plan");

    expect(await screen.findByText("No weight data yet")).toBeVisible();
    expect(within(card("Season targets")).getByText("No targets yet.")).toBeVisible();
  });

  test("the calendar links to the plan", async () => {
    const { router } = renderApp("/calendar");

    await userEvent.click(await screen.findByRole("link", { name: "Plan" }));

    expect(router.state.location.pathname).toBe("/plan");
  });

  test("says so when there is no season yet", async () => {
    mockPlan.seasons = [];
    renderApp("/plan");

    expect(await screen.findByRole("heading", { level: 1, name: "No plan yet" })).toBeVisible();
    expect(screen.queryByRole("list", { name: "Phases" })).toBeNull();
  });
});

describe("the plan on a phone", () => {
  beforeEach(() => {
    viewport.desktop = false;
  });

  test("leads with the goal over a season map that scrolls", async () => {
    renderApp("/plan");

    expect(await screen.findByRole("heading", { level: 1, name: "Autumn 10 km" })).toBeVisible();
    expect(screen.getByText("weeks to go").previousSibling).toHaveTextContent("8");
    const map = screen.getByRole("region", { name: "Season map" });
    expect(within(map).getByRole("list", { name: "Phases" })).toBeVisible();
    expect(within(map).getByRole("list", { name: "Hours per week" })).toBeVisible();
  });

  test("opens the current block to its cycles, each a row of day rings leading to its week", async () => {
    renderApp("/plan");

    expect(await screen.findByRole("heading", { level: 2, name: "Base · blocks" })).toBeVisible();
    const block = screen.getByRole("button", { name: /^Block 1 · now/ });
    expect(block).toHaveAttribute("aria-expanded", "true");
    const now = screen.getByRole("link", { name: "Load 2, 2 – 8 Nov, 5.1 h" });
    expect(now).toHaveAttribute("href", "/calendar/week/2026-11-03");
    expect(within(now).getAllByRole("img")).toHaveLength(7);
    expect(within(now).getByRole("img", { name: "1 of 4 done" })).toBeVisible();
    expect(screen.getByRole("link", { name: /^Load 1, 26 Oct – 1 Nov/ })).toHaveAttribute(
      "href",
      "/calendar/week/2026-10-26",
    );

    await userEvent.click(block);
    expect(block).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("link", { name: /^Load 2/ })).toBeNull();
  });

  test("shows another phase's blocks from the map", async () => {
    renderApp("/plan");

    await userEvent.click(await screen.findByRole("button", { name: /^Build/ }));
    expect(screen.getByRole("heading", { level: 2, name: "Build · blocks" })).toBeVisible();
    const block = screen.getByRole("button", { expanded: false, name: /^Block 2/ });
    expect(block).toHaveAttribute("aria-expanded", "false");

    await userEvent.click(screen.getByRole("button", { name: "Block 2 · Threshold, planned" }));
    expect(block).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("link", { name: /^Load 1, 16 – 25 Nov/ })).toBeVisible();
    expect(screen.getByRole("link", { name: /^Recovery, 26 – 29 Nov/ })).toBeVisible();
  });

  test("keeps the targets and the coach log under the blocks", async () => {
    renderApp("/plan");

    expect(await screen.findByText("Updated session · Threshold intervals")).toBeVisible();
    expect(within(card("Season targets")).getByText("No targets yet.")).toBeVisible();
  });
});
