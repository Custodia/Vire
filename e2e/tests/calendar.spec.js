import { expect, test } from "@playwright/test";
import { dayPath, ensureUploaded, isoDate, longDayLabel, signIn } from "./helpers.js";

test.beforeAll(async ({ browser }) => {
  await ensureUploaded(browser, ["ride.fit", "run.fit", "swim.fit"]);
});

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

/** Whether any pixel of the chart's canvas has been painted. */
function painted(canvas) {
  return canvas.evaluate((element) => {
    const { data } = element.getContext("2d").getImageData(0, 0, element.width, element.height);
    return data.some((value, index) => index % 4 === 3 && value > 0);
  });
}

const card = (page, name) =>
  page.locator("section").filter({ has: page.getByRole("heading", { level: 2, name }) });

test("today's day heads with its place in the plan", async ({ page }) => {
  const header = page.locator("section").filter({ has: page.getByRole("heading", { level: 1 }) });

  await expect(
    header.getByRole("heading", { level: 1, name: longDayLabel(isoDate()) }),
  ).toBeVisible();
  await expect(
    header.getByText(/^Today · Base · Block 1 · Load \d+ · Day [1-7] of 7$/),
  ).toBeVisible();
  await expect(header.getByText("weeks to Autumn 10 km")).toBeVisible();
});

test("the week lays out seven days with today's sessions", async ({ page }) => {
  const days = page.getByRole("list", { name: "Days of the week" }).getByRole("link");

  await expect(days).toHaveCount(7);
  const today = page
    .getByRole("list", { name: "Days of the week" })
    .getByRole("link", { name: /, today/ });
  await expect(today).toHaveAttribute("href", dayPath(isoDate()));
  await expect(today).toContainText("Threshold intervals");
  await expect(today).toContainText("Technique swim");
});

test("the day lists the run as next and shows its structure", async ({ page }) => {
  const sessions = page.getByRole("list", { name: "Sessions" }).getByRole("link");
  await expect(sessions.first()).toContainText("Threshold intervals");
  await expect(sessions.first()).toContainText("Next ·");
  await expect(sessions.nth(1)).toContainText("Then ·");

  await expect(page.getByRole("heading", { level: 2, name: "Threshold intervals" })).toBeVisible();
  const structure = card(page, "Structure");
  await expect(
    structure.getByRole("list", { name: "Training zones" }).getByRole("listitem"),
  ).toHaveCount(5);
  await expect(structure.getByRole("list", { name: "Steps" }).getByRole("listitem")).toHaveText([
    /10′\s*Warm-up/,
    /3×5′\s*Work\s*4:10 \/km/,
    /3×2′\s*Recovery/,
    /10′\s*Cool-down/,
  ]);
  await expect(
    structure.getByText("Raises the pace that can be held for an hour, ahead of the 10 km."),
  ).toBeVisible();

  await sessions.nth(1).click();

  await expect(page).toHaveURL(/\/sessions\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { level: 2, name: "Technique swim" })).toBeVisible();
  await expect(
    page.getByRole("heading", { level: 1, name: longDayLabel(isoDate()) }),
  ).toBeVisible();
});

test("the day steps a day either way, and Today comes back", async ({ page }) => {
  await page.getByRole("link", { name: "Next day" }).click();

  await expect(page).toHaveURL(dayPath(isoDate(1)));
  await expect(
    page.getByRole("heading", { level: 1, name: longDayLabel(isoDate(1)) }),
  ).toBeVisible();

  await page.getByRole("link", { name: "Today" }).click();

  await expect(page).toHaveURL(dayPath(isoDate()));
});

test("the week lists each day with its sessions, and the month each week", async ({ page }) => {
  await page
    .getByRole("navigation", { name: "Calendar view" })
    .getByRole("link", { name: "Week" })
    .click();

  await expect(page).toHaveURL(`/calendar/week/${isoDate()}`);
  await expect(
    page.getByRole("heading", { level: 2, name: "Hours, done of planned" }),
  ).toBeVisible();
  const today = page
    .getByRole("list", { name: "Days of the week" })
    .getByRole("link", { name: /, today/ });
  await expect(today).toHaveAttribute("href", dayPath(isoDate()));
  await expect(page.getByRole("link", { name: /Threshold intervals Next/ })).toBeVisible();

  await page
    .getByRole("navigation", { name: "Calendar view" })
    .getByRole("link", { name: "Month" })
    .click();

  await expect(page).toHaveURL(`/calendar/month/${isoDate()}`);
  const month = page.getByRole("region", {
    name: new Intl.DateTimeFormat("en-GB", {
      month: "long",
      year: "numeric",
      timeZone: "UTC",
    }).format(new Date()),
  });
  await expect(month.getByRole("link", { name: /, today/ })).toContainText("Threshold intervals");
});

test("the ride's day compares plan with recording and charts power and heart rate", async ({
  page,
}) => {
  await page.goto(dayPath("2026-07-14"));

  await expect(page.getByRole("heading", { level: 1, name: "Tuesday 14 Jul" })).toBeVisible();
  const ride = page.getByRole("list", { name: "Sessions" }).getByRole("link");
  await expect(ride).toContainText("Saddle check ride");
  await expect(ride).toContainText("19:00 · 4.59 km · 9:00");
  await expect(ride).toContainText("Done");

  await expect(page.getByRole("group", { name: "Planned and recorded" })).toContainText(
    "9:00Durationplan 10′4.59 kmDistance",
  );
  const laps = page.getByRole("table", { name: "Laps" });
  await expect(laps.getByRole("columnheader", { name: "Power" })).toBeVisible();
  await expect(laps.getByRole("row")).toHaveCount(3);

  const canvas = page.getByRole("figure", { name: "Power and heart rate" }).locator("canvas");
  await expect(canvas).toBeVisible();
  await expect.poll(() => painted(canvas), { timeout: 10_000 }).toBe(true);
});

test("the run's day charts heart rate and pace", async ({ page }) => {
  await page.goto(dayPath("2026-07-16"));

  await expect(page.getByRole("list", { name: "Sessions" }).getByRole("link")).toContainText(
    "08:45 · 1.98 km · 10:00",
  );
  const canvas = page.getByRole("figure", { name: "Heart rate and pace" }).locator("canvas");
  await expect(canvas).toBeVisible();
  await expect.poll(() => painted(canvas), { timeout: 10_000 }).toBe(true);
});

test("the swim outside the plan shows as an activity with its pool lengths", async ({ page }) => {
  await page.goto(dayPath("2026-01-20"));

  await expect(page.getByText("Outside your plan", { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { level: 2, name: "Swim" })).toBeVisible();
  const lengths = page.getByRole("table", { name: "Pool lengths" });
  await expect(lengths.getByRole("row")).toHaveCount(15);
  await expect(lengths.getByRole("row", { name: /^5 Rest/ })).toBeVisible();
});

test("a date with no cycle and no activity is outside the plan alone", async ({ page }) => {
  await page.goto(dayPath("2026-03-03"));

  await expect(page.getByRole("heading", { level: 2, name: "Outside your plan" })).toBeVisible();
  await expect(page.getByRole("heading", { level: 3, name: "Not in the plan" })).toHaveCount(0);
});
