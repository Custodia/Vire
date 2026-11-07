import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import {
  activities,
  days,
  finishUpload,
  mockLive,
  mockSession,
  mockSync,
  sessions,
  syncRun,
  syncStatus,
} from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
import { renderApp } from "../test/render.jsx";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(2026, 10, 3, 9, 30));
});

afterEach(() => {
  vi.useRealTimers();
});

const today = "/calendar/day/2026-11-03";

// Renders a page and waits until the user's channel is joined.
async function renderLive(path) {
  const view = renderApp(path);
  await waitFor(() => expect(mockLive.channels.size).toBe(1));
  return view;
}

async function openUpload() {
  await userEvent.click(await screen.findByRole("button", { name: "Upload .fit" }));
  return screen.findByRole("dialog", { name: "Upload a .fit file" });
}

async function chooseFile(name, content = "fit") {
  const dialog = await openUpload();
  const input = dialog.querySelector('input[type="file"]');
  await userEvent.upload(input, new File([content], name, { type: "application/octet-stream" }));
  return dialog;
}

const uploaded = () => screen.findByRole("dialog", { name: "Uploaded" });

describe("uploading a .fit file", () => {
  test("follows the file until it is read, then shows its activity and session", async () => {
    await renderLive(today);

    const dialog = await chooseFile("ride.fit");

    const progress = await within(dialog).findByRole("status", { name: "Progress" });
    expect(within(progress).getByText("Uploaded")).toBeVisible();
    expect(within(progress).getByText("Reading the file")).toBeVisible();
    expect(within(dialog).getByText("ride.fit")).toBeVisible();
    expect(within(dialog).getByText("1 KB")).toBeVisible();

    finishUpload();

    const done = await uploaded();
    expect(await within(done).findByText("Thu 5 Nov · 07:15")).toBeVisible();
    expect(within(done).getByText("Ride")).toBeVisible();
    expect(within(done).getByText("1:02:00")).toBeVisible();
    expect(within(done).getByText("30.50 km")).toBeVisible();
    expect(within(done).getByText("145")).toBeVisible();
    expect(within(done).getByText(sessions.ride.title)).toBeVisible();
    expect(within(done).getByRole("link", { name: "Open the session" })).toHaveAttribute(
      "href",
      `/sessions/${sessions.ride.id}`,
    );
  });

  test("reads the day again once the file is processed", async () => {
    const recorded = days["2026-11-03"];
    days["2026-11-03"] = { ...recorded, activities: [] };
    try {
      await renderLive(today);
      expect(await screen.findByText("1 of 4 done · 4h08")).toBeVisible();
      expect(screen.queryByText("Not in the plan")).toBeNull();

      await chooseFile("walk.fit");
      days["2026-11-03"] = recorded;
      finishUpload({ activityId: activities.walk.id });
      await userEvent.click(await within(await uploaded()).findByRole("button", { name: "Close" }));

      expect(await screen.findByText("Not in the plan")).toBeVisible();
    } finally {
      days["2026-11-03"] = recorded;
    }
  });

  test("opens the matched session from the dialog", async () => {
    const { router } = await renderLive(today);

    await chooseFile("ride.fit");
    finishUpload();
    await userEvent.click(
      await within(await uploaded()).findByRole("link", { name: "Open the session" }),
    );

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/sessions/${sessions.ride.id}`),
    );
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  test("offers the activity when it matched no session", async () => {
    await renderLive(today);

    await chooseFile("walk.fit");
    finishUpload({ activityId: activities.walk.id });

    const done = await uploaded();
    expect(await within(done).findByText("Not in the plan")).toBeVisible();
    expect(within(done).getByRole("link", { name: "Open the activity" })).toHaveAttribute(
      "href",
      `/activities/${activities.walk.id}`,
    );
  });

  test("shows a file processed before its upload answered as done", async () => {
    server.use(
      http.get("/api/uploads/:id", ({ params }) =>
        HttpResponse.json({
          id: params.id,
          status: "processed",
          processor_version: 1,
          error: null,
          activity_id: activities.ride.id,
        }),
      ),
    );
    await renderLive(today);

    await chooseFile("ride.fit");

    expect(await within(await uploaded()).findByText(sessions.ride.title)).toBeVisible();
  });

  test("starts over with Upload another", async () => {
    await renderLive(today);

    await chooseFile("ride.fit");
    finishUpload();
    await userEvent.click(
      await within(await uploaded()).findByRole("button", { name: "Upload another" }),
    );

    const dialog = await screen.findByRole("dialog", { name: "Upload a .fit file" });
    expect(within(dialog).getByText("Drop a .fit file here")).toBeVisible();
  });

  test("says why a file could not be read and offers another", async () => {
    await renderLive(today);

    const dialog = await chooseFile("corrupt.fit", "corrupt");
    finishUpload();

    expect(await within(dialog).findByRole("alert")).toHaveTextContent(
      "This file could not be read: the file could not be decoded. Try exporting it again from the device.",
    );
    expect(within(dialog).getByRole("button", { name: "Choose another file" })).toBeVisible();
  });

  test("says why the server refused a file", async () => {
    server.use(
      http.post("/api/uploads", () =>
        HttpResponse.json({ errors: { detail: "the file is not a FIT file" } }, { status: 422 }),
      ),
    );
    await renderLive(today);

    const dialog = await chooseFile("notes.fit");

    expect(await within(dialog).findByRole("alert")).toHaveTextContent(
      "This file could not be uploaded: the file is not a FIT file.",
    );
  });

  test("takes a file dropped on the drop zone", async () => {
    await renderLive(today);
    const dialog = await openUpload();
    const zone = within(dialog).getByText("Drop a .fit file here").closest("[data-rac]");
    const file = new File(["fit"], "dropped.fit", { type: "application/octet-stream" });
    const dataTransfer = {
      dropEffect: "none",
      effectAllowed: "all",
      types: ["Files"],
      files: [file],
      items: [{ kind: "file", type: file.type, getAsFile: () => file }],
      getData: () => "",
    };

    fireEvent.dragEnter(zone, { dataTransfer, clientX: 1, clientY: 1 });
    fireEvent.dragOver(zone, { dataTransfer, clientX: 1, clientY: 1 });
    fireEvent.drop(zone, { dataTransfer, clientX: 1, clientY: 1 });

    expect(await within(dialog).findByText("dropped.fit")).toBeVisible();
  });

  test("closes with the Close button", async () => {
    await renderLive(today);

    await openUpload();
    await userEvent.click(await screen.findByRole("button", { name: "Close" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});

describe("Sync now", () => {
  const notifications = () => screen.getByRole("region", { name: "Notifications" });

  test("follows a sync from the press to what it brought in", async () => {
    let dayReads = 0;
    server.events.on("request:start", ({ request }) => {
      if (new URL(request.url).pathname === "/api/days") dayReads++;
    });
    await renderLive(today);
    expect(await screen.findByText("Garmin 06:05")).toBeVisible();

    await userEvent.click(screen.getByRole("button", { name: "Sync now" }));

    expect(await screen.findByRole("button", { name: "Syncing…" })).toBeDisabled();
    expect(screen.getByText("Garmin syncing")).toBeVisible();
    expect(within(notifications()).getByRole("status")).toHaveTextContent(
      "Syncing with GarminWaiting to start.",
    );

    const found = [
      {
        ...activities.ride,
        local_date: "2026-11-05",
        session: { id: sessions.ride.id, title: sessions.ride.title },
      },
      { ...activities.walk, local_date: "2026-11-03", session: null },
    ];
    const running = syncRun({
      state: "fetching",
      files: { total: 2, fetched: 1, parsed: 1, failed: 0 },
      activities: found,
    });
    mockLive.push("sync", syncStatus({ run: running }));

    expect(
      await within(notifications()).findByText(/2 new activities found · fetching files,/),
    ).toHaveTextContent("1 of 2");
    expect(
      within(notifications()).getByRole("progressbar", { name: "Files fetched" }),
    ).toHaveAttribute("aria-valuenow", "1");

    const readsBefore = dayReads;
    mockLive.push(
      "sync",
      syncStatus({
        last_synced_at: new Date(2026, 10, 3, 9, 31).toISOString(),
        run: {
          ...running,
          state: "finished",
          files: { total: 2, fetched: 2, parsed: 2, failed: 0 },
        },
      }),
    );

    const card = await within(notifications()).findByRole("status");
    await waitFor(() => expect(card).toHaveTextContent("Garmin synced"));
    expect(card).toHaveTextContent("2 new activities, 1 matched to sessions.");
    const rows = within(card).getAllByRole("listitem");
    expect(rows[0]).toHaveTextContent(`Thu · Ride 1:02✓ ${sessions.ride.title}`);
    expect(rows[1]).toHaveTextContent("Tue · Activity 0:25Not in the plan");
    expect(within(card).getByRole("link", { name: "Open today" })).toHaveAttribute(
      "href",
      "/calendar",
    );
    expect(await screen.findByRole("button", { name: "Sync now" })).toBeEnabled();
    expect(screen.getByText("Garmin 09:31")).toBeVisible();
    await waitFor(() => expect(dayReads).toBeGreaterThan(readsBefore));
    server.events.removeAllListeners();
  });

  test("says when a sync found nothing new", async () => {
    await renderLive(today);

    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));
    await screen.findByRole("button", { name: "Syncing…" });
    mockLive.push("sync", syncStatus({ run: syncRun({ state: "finished" }) }));

    await waitFor(() =>
      expect(within(notifications()).getByRole("status")).toHaveTextContent(
        "Garmin syncedNothing new since 06:05.",
      ),
    );
  });

  test("shows a scheduled sync on the button, and a card only once it brings activities", async () => {
    await renderLive(today);
    await screen.findByRole("button", { name: "Sync now" });

    mockLive.push("sync", syncStatus({ run: syncRun({ trigger: "scheduled" }) }));
    expect(await screen.findByRole("button", { name: "Syncing…" })).toBeDisabled();
    expect(screen.queryByRole("status")).toBeNull();

    mockLive.push(
      "sync",
      syncStatus({ run: syncRun({ trigger: "scheduled", state: "finished" }) }),
    );
    expect(await screen.findByRole("button", { name: "Sync now" })).toBeEnabled();
    expect(screen.queryByRole("status")).toBeNull();

    const next = { id: "5c7e0a1b-2d3f-4a5b-8c6d-7e8f9a0b1c02", trigger: "scheduled" };
    mockLive.push("sync", syncStatus({ run: syncRun({ ...next, state: "searching" }) }));
    await screen.findByRole("button", { name: "Syncing…" });
    mockLive.push(
      "sync",
      syncStatus({
        run: syncRun({
          ...next,
          state: "finished",
          activities: [{ ...activities.walk, local_date: "2026-11-03", session: null }],
        }),
      }),
    );

    expect(await within(notifications()).findByRole("status")).toHaveTextContent(
      "1 new activity, 0 matched to sessions.",
    );
  });

  test("picks up a sync that is already running when the page opens", async () => {
    mockSync.status = syncStatus({ run: syncRun({ state: "searching" }) });
    await renderLive(today);

    expect(await screen.findByRole("button", { name: "Syncing…" })).toBeDisabled();
    expect(within(notifications()).getByRole("status")).toHaveTextContent(
      "Looking for new activities.",
    );
  });

  test("keeps a card for a sync that did not finish, with a retry", async () => {
    await renderLive(today);
    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));
    await screen.findByRole("button", { name: "Syncing…" });

    mockLive.push(
      "sync",
      syncStatus({
        run: syncRun({
          state: "failed",
          error: "3 of 3 searches failed",
          activities: [{ ...activities.walk, local_date: "2026-11-03", session: null }],
        }),
      }),
    );

    const alert = await within(notifications()).findByRole("alert");
    expect(alert).toHaveTextContent(
      "The sync did not finishGarmin did not answer. The 1 activity found is in.",
    );

    await userEvent.click(within(alert).getByRole("button", { name: "Try again" }));

    expect(await screen.findByRole("button", { name: "Syncing…" })).toBeDisabled();
    expect(within(notifications()).queryByRole("alert")).toBeNull();
  });

  test("says the connection is paused when a sync paused it", async () => {
    await renderLive(today);
    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));
    await screen.findByRole("button", { name: "Syncing…" });

    mockLive.push(
      "sync",
      syncStatus({ connection: "paused", run: syncRun({ state: "failed", error: "paused" }) }),
    );

    expect(await within(notifications()).findByRole("alert")).toHaveTextContent(
      "The Garmin connection is pausedActivities sync again once it is resumed.",
    );
    expect(screen.getByText("Garmin paused")).toBeVisible();
  });

  test.each([
    ["not_connected", "No Garmin connection is set up"],
    ["paused", "The Garmin connection is paused"],
  ])("says why a sync did not start when the answer is %s", async (refusal, text) => {
    mockSync.refusal = refusal;
    await renderLive(today);

    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));

    expect(await within(notifications()).findByRole("alert")).toHaveTextContent(text);
  });

  test("says when the request itself failed", async () => {
    server.use(http.post("/api/sync", () => new HttpResponse(null, { status: 500 })));
    await renderLive(today);

    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));

    expect(await within(notifications()).findByRole("alert")).toHaveTextContent(
      "The sync did not startVire did not answer. Try again in a moment.",
    );
  });

  test("hides a card with its Hide button", async () => {
    mockSync.refusal = "paused";
    await renderLive(today);
    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));

    await userEvent.click(await within(notifications()).findByRole("button", { name: "Hide" }));

    expect(within(notifications()).queryByRole("alert")).toBeNull();
  });

  test("catches up on a sync that finished while the connection was down", async () => {
    mockSync.status = syncStatus({ run: syncRun({ state: "searching" }) });
    await renderLive(today);
    expect(await screen.findByRole("button", { name: "Syncing…" })).toBeDisabled();

    mockSync.status = syncStatus({ run: syncRun({ state: "finished" }) });
    mockLive.drop();

    expect(
      await screen.findByRole("button", { name: "Sync now" }, { timeout: 3000 }),
    ).toBeEnabled();
    expect(mockLive.joins).toBe(2);
  });

  test("asks to sign in again when the session has ended", async () => {
    const { router } = await renderLive(today);
    const button = await screen.findByRole("button", { name: "Sync now" });

    mockSession.signedIn = false;
    await userEvent.click(button);

    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeVisible();
    expect(router.state.location.search).toEqual({ redirect: today });
  });
});
