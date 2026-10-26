import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { activities, days, mockSession, mockSync } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
import { renderApp } from "../test/render.jsx";

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(2026, 10, 3, 9, 30));
});

afterEach(() => {
  vi.useRealTimers();
});

async function chooseFile(name, content = "fit") {
  await userEvent.click(await screen.findByRole("button", { name: "Upload" }));
  const dialog = await screen.findByRole("dialog", { name: "Upload a .fit file" });
  const input = dialog.querySelector('input[type="file"]');
  await userEvent.upload(input, new File([content], name, { type: "application/octet-stream" }));
  return dialog;
}

describe("uploading a .fit file", () => {
  test("follows the file until it is processed and refreshes the day", async () => {
    let reads = 0;
    server.use(
      http.get("/api/days/:date", ({ params }) => {
        reads += 1;
        return HttpResponse.json({
          ...days["2026-11-03"],
          date: params.date,
          activities: reads === 1 ? [] : [activities.walk],
        });
      }),
    );
    renderApp("/today");
    expect(await screen.findByText("1 of 4 done · 4h08 total")).toBeVisible();
    expect(screen.queryByRole("region", { name: "Other activities" })).toBeNull();

    const dialog = await chooseFile("ride.fit");

    expect(await within(dialog).findByText(/Processing ride\.fit/)).toBeVisible();
    expect(
      await within(dialog).findByText(/ride\.fit is processed/, {}, { timeout: 4000 }),
    ).toBeVisible();
    expect(within(dialog).getByRole("link", { name: "Open the activity" })).toHaveAttribute(
      "href",
      `/activities/${activities.ride.id}`,
    );
    await userEvent.click(within(dialog).getByRole("button", { name: "Close" }));
    expect(await screen.findByRole("region", { name: "Other activities" })).toBeVisible();
  });

  test("opens the processed activity from the dialog", async () => {
    const { router } = renderApp("/today");

    const dialog = await chooseFile("ride.fit");
    await userEvent.click(
      await within(dialog).findByRole("link", { name: "Open the activity" }, { timeout: 4000 }),
    );

    await waitFor(() =>
      expect(router.state.location.pathname).toBe(`/activities/${activities.ride.id}`),
    );
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  test("shows why a file failed", async () => {
    renderApp("/today");

    const dialog = await chooseFile("corrupt.fit", "corrupt");

    expect(
      await within(dialog).findByText(
        "corrupt.fit could not be processed: the file could not be decoded",
        {},
        { timeout: 4000 },
      ),
    ).toBeVisible();
    expect(within(dialog).queryByRole("link", { name: "Open the activity" })).toBeNull();
  });

  test("shows the server's refusal of a file", async () => {
    server.use(
      http.post("/api/uploads", () =>
        HttpResponse.json({ errors: { detail: "the file is not a FIT file" } }, { status: 422 }),
      ),
    );
    renderApp("/today");

    const dialog = await chooseFile("notes.fit");

    expect(await within(dialog).findByText("the file is not a FIT file")).toBeVisible();
  });

  test("closes with the Close button", async () => {
    renderApp("/today");

    await userEvent.click(await screen.findByRole("button", { name: "Upload" }));
    await userEvent.click(await screen.findByRole("button", { name: "Close" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});

describe("Sync now", () => {
  test("says a sync was queued", async () => {
    renderApp("/today");

    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));

    expect(await screen.findByText("A sync was queued.")).toBeVisible();
  });

  test.each([
    ["not_connected", "Sync did not start: no Garmin connection is set up."],
    ["paused", "Sync did not start: the Garmin connection is paused."],
  ])("says why a sync did not start when the answer is %s", async (answer, text) => {
    mockSync.answer = answer;
    renderApp("/today");

    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));

    expect(await screen.findByText(text)).toBeVisible();
  });

  test("says when the request itself failed", async () => {
    server.use(http.post("/api/sync", () => new HttpResponse(null, { status: 500 })));
    renderApp("/today");

    await userEvent.click(await screen.findByRole("button", { name: "Sync now" }));

    expect(await screen.findByText("Sync could not be queued.")).toBeVisible();
  });

  test("asks to sign in again when the session has ended", async () => {
    const { router } = renderApp("/today");
    const button = await screen.findByRole("button", { name: "Sync now" });

    mockSession.signedIn = false;
    await userEvent.click(button);

    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeVisible();
    expect(router.state.location.search).toEqual({ redirect: "/today" });
  });
});
