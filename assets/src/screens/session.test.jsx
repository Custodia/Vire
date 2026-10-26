import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { activities, sessions } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
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

function rows(table) {
  return within(table)
    .getAllByRole("row")
    .map((row) => row.textContent);
}

function stat(label) {
  return within(screen.getByRole("group", { name: "Summary" })).getByText(label).parentElement;
}

describe("A planned session", () => {
  test("shows its stats, its structure step by step and why it is planned", async () => {
    renderApp(`/sessions/${sessions.bike.id}`);

    expect(await heading("Bike — threshold 3 × 12′")).toBeVisible();
    expect(screen.getByText("Tue 3 Nov · Planned")).toBeVisible();
    expect(stat("Duration")).toHaveTextContent("1h45Duration");
    expect(stat("Work")).toHaveTextContent("1h06Work");
    expect(stat("Peak zone")).toHaveTextContent("Z4Peak zone");

    const structure = screen.getByRole("region", { name: "Structure" });
    expect(
      within(structure).getByRole("img", { name: /^Workout profile: 10′ warm-up/ }),
    ).toBeVisible();
    expect(structure).toHaveTextContent("0′1h51");

    const legend = within(structure).getByRole("list", { name: "Training zones" });
    expect(
      within(legend)
        .getAllByRole("listitem")
        .map((zone) => zone.textContent),
    ).toEqual(["Z1 Recovery", "Z2 Endurance", "Z3 Tempo", "Z4 Threshold", "Z5 VO2 max"]);

    const steps = within(structure).getByRole("list", { name: "Steps" });
    expect(
      within(steps)
        .getAllByRole("listitem")
        .map((step) => step.textContent),
    ).toEqual([
      "Z1 Recovery10′Warm-up150–170 W",
      "Z2 Endurance10′Warm-up180–200 W",
      "Z4 Threshold3×12′Work275–289 W",
      "Z1 Recovery3×6′Recovery< 160 W",
      "Z2 Endurance30′Work195–215 W",
      "7′Cool-down",
    ]);

    expect(screen.getByRole("heading", { name: "Why this session" })).toBeVisible();
    expect(screen.getByText(/Each load cycle adds two minutes per rep/)).toBeVisible();
    expect(screen.queryByRole("table", { name: "Planned against actual" })).toBeNull();
  });

  test("leads back to the day it belongs to", async () => {
    const { router } = renderApp(`/sessions/${sessions.run.id}`);

    await heading("Run / walk — Z2");
    const steps = screen.getByRole("list", { name: "Steps" });
    expect(
      within(steps)
        .getAllByRole("listitem")
        .map((step) => step.textContent),
    ).toEqual(["Z2 Endurance7×4′Work< 145 bpm", "Z1 Recovery7×1′Recovery, Walk"]);

    await userEvent.click(screen.getByRole("link", { name: "Back to Today" }));

    expect(await heading("Today")).toBeVisible();
    expect(router.state.location.pathname).toBe("/today");
  });
});

describe("A done session", () => {
  test("compares the plan with the ride, lists its laps and charts its streams", async () => {
    const { router } = renderApp(`/sessions/${sessions.ride.id}`);

    expect(await heading("Bike — endurance with sprints")).toBeVisible();
    expect(screen.getByText("Thu 5 Nov · Completed 07:15")).toBeVisible();
    expect(screen.getByText("Done")).toBeVisible();

    expect(rows(screen.getByRole("table", { name: "Planned against actual" }))).toEqual([
      "PlannedActual",
      "Duration1h1:02:00",
      "Distance—30.50 km",
    ]);

    expect(rows(screen.getByRole("table", { name: "Laps" }))).toEqual([
      "LapTimeDistancePowerHeart rate",
      "130:0015.00 km212 W138",
      "232:0015.50 km236 W151",
    ]);

    const chart = await screen.findByRole("figure", { name: "Power and heart rate" });
    expect(chart).toHaveTextContent(/^Poweravg \d+ WHeart rateavg \d+ bpm$/);

    const steps = screen.getByRole("list", { name: "Steps" });
    expect(
      within(steps)
        .getAllByRole("listitem")
        .map((step) => step.textContent),
    ).toEqual([
      "Z1 Recovery15′Warm-up",
      "Z5 VO2 max4×30″Work> 400 W",
      "Z1 Recovery4×4′30″Recovery, Spin",
      "Z2 Endurance25′Work",
    ]);
    expect(screen.getByText(/Short sprints keep the top end/)).toBeVisible();

    await userEvent.click(screen.getByRole("link", { name: "Back to Thu 5 Nov" }));

    await waitFor(() => expect(router.state.location.pathname).toBe("/days/2026-11-05"));
    expect(await heading("Thu 5 Nov")).toBeVisible();
  });

  test("lists a swim's laps with their pace and its pool lengths", async () => {
    renderApp(`/sessions/${sessions.swim.id}`);

    expect(await heading("Swim — endurance")).toBeVisible();
    expect(screen.getByText("Tue 3 Nov · Completed 06:32")).toBeVisible();
    expect(rows(screen.getByRole("table", { name: "Planned against actual" }))).toContain(
      "Duration1h081:08:40",
    );

    expect(rows(screen.getByRole("table", { name: "Laps" }))).toEqual([
      "LapTimeDistancePace /100 mHeart rate",
      "12:10100 m2:10128",
      "20:20———",
      "32:20100 m2:20134",
    ]);

    const lengths = rows(screen.getByRole("table", { name: "Pool lengths" }));
    expect(lengths).toHaveLength(1 + 9);
    expect(lengths.slice(0, 2)).toEqual(["LengthStrokeTimeStrokes", "1Freestyle0:3219"]);
    expect(lengths[5]).toBe("5Rest0:20—");
    expect(lengths[6]).toBe("6Breaststroke0:3614");

    expect(screen.queryByRole("figure")).toBeNull();
  });

  test("leaves the chart out when the recording has no streams to draw", async () => {
    server.use(
      http.get("/api/activities/:id/streams", ({ params }) =>
        HttpResponse.json({
          activity_id: params.id,
          step: 13,
          streams: { power: { unit: "watts", samples: [null, null] } },
        }),
      ),
    );
    renderApp(`/sessions/${sessions.ride.id}`);

    expect(await screen.findByRole("table", { name: "Laps" })).toBeVisible();
    await waitFor(() => expect(screen.queryByRole("status")).toBeNull());
    expect(screen.queryByRole("figure")).toBeNull();
  });

  test("says when the recording cannot be loaded", async () => {
    server.use(
      http.get("/api/activities/:id/streams", () => HttpResponse.json({}, { status: 500 })),
    );
    renderApp(`/sessions/${sessions.ride.id}`);

    expect(await screen.findByText("The recording could not be loaded.")).toBeVisible();
    expect(screen.getByRole("table", { name: "Laps" })).toBeVisible();
  });
});

describe("A skipped session", () => {
  test("shows that it was skipped with what was planned", async () => {
    renderApp(`/sessions/${sessions.strength.id}`);

    expect(await heading("Strength")).toBeVisible();
    expect(screen.getByText("Tue 3 Nov · Skipped")).toBeVisible();
    expect(screen.getByText("Skipped")).toBeVisible();
    expect(stat("Duration")).toHaveTextContent("40′Duration");
    expect(screen.queryByRole("region", { name: "Structure" })).toBeNull();
    expect(screen.getByText(/Two strength sessions a cycle/)).toBeVisible();
  });
});

describe("An activity without a session", () => {
  test("shows a run with its lap and its heart rate and pace", async () => {
    renderApp(`/activities/${activities.run.id}`);

    expect(await heading("Run")).toBeVisible();
    expect(screen.getByText("Fri 25 Dec · 10:05")).toBeVisible();
    expect(stat("Duration")).toHaveTextContent("30:45Duration");
    expect(stat("Distance")).toHaveTextContent("5.12 kmDistance");
    expect(stat("Training load")).toHaveTextContent("32Training load");
    expect(screen.getByRole("link", { name: "Back to Fri 25 Dec" })).toBeVisible();

    expect(rows(screen.getByRole("table", { name: "Laps" }))).toEqual([
      "LapTimeDistancePace /kmHeart rate",
      "130:455.12 km6:00152",
    ]);

    const chart = await screen.findByRole("figure", { name: "Heart rate and pace" });
    expect(chart).toHaveTextContent(/^Heart rateavg \d+ bpmPaceavg \d+:\d\d \/km$/);
  });

  test("opens from the day and shows a walk without laps or streams", async () => {
    const { router } = renderApp("/today");

    const section = await screen.findByRole("region", { name: "Other activities" });
    await userEvent.click(within(section).getByRole("link", { name: /Other/ }));

    expect(await heading("Other")).toBeVisible();
    expect(router.state.location.pathname).toBe(`/activities/${activities.walk.id}`);
    expect(screen.getByText("Tue 3 Nov · 17:10")).toBeVisible();
    expect(stat("Distance")).toHaveTextContent("2.40 kmDistance");
    expect(screen.queryByText("Training load")).toBeNull();
    expect(screen.queryByRole("table")).toBeNull();
    expect(screen.queryByRole("figure")).toBeNull();
  });

  test("says when there is no such activity", async () => {
    renderApp("/activities/b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4cff");

    expect(await heading("Not found")).toBeVisible();
    expect(screen.getByText("There is no such activity in your account.")).toBeVisible();
    expect(screen.getByRole("link", { name: "Back to Today" })).toBeVisible();
  });
});

describe("A session that cannot be shown", () => {
  test("says when there is no such session", async () => {
    renderApp("/sessions/5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6eff");

    expect(await screen.findByRole("status")).toHaveTextContent("Loading the session…");
    expect(await heading("Not found")).toBeVisible();
    expect(screen.getByText("There is no such session in your account.")).toBeVisible();
  });
});
