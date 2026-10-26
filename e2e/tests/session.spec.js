import { expect, test } from "@playwright/test";
import { ensureUploaded, signIn } from "./helpers.js";

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

test("the done ride compares plan with recording and charts power and heart rate", async ({
  page,
}) => {
  await page.goto("/days/2026-07-14");
  await page.getByRole("link", { name: /Saddle check ride/ }).click();

  await expect(page.getByRole("heading", { level: 1, name: "Saddle check ride" })).toBeVisible();
  const comparison = page.getByRole("table", { name: "Planned against actual" });
  await expect(comparison.getByRole("row", { name: /^Duration/ })).toHaveText(
    /Duration\s*10′\s*9:00/,
  );
  await expect(comparison.getByRole("row", { name: /^Distance/ })).toHaveText(
    /Distance\s*—\s*4\.59 km/,
  );

  const laps = page.getByRole("table", { name: "Laps" });
  await expect(laps.getByRole("columnheader", { name: "Power" })).toBeVisible();
  await expect(laps.getByRole("row")).toHaveCount(3);
  await expect(laps.getByRole("row").filter({ hasText: /\d+ W/ })).toHaveCount(2);

  const chart = page.getByRole("figure", { name: "Power and heart rate" });
  await expect(chart).toBeVisible();
  const canvas = chart.locator("canvas");
  await expect(canvas).toBeVisible();
  await expect.poll(() => painted(canvas), { timeout: 10_000 }).toBe(true);
});

test("the done run charts heart rate and pace", async ({ page }) => {
  await page.goto("/days/2026-07-16");
  await page.getByRole("link", { name: /Shakeout run/ }).click();

  await expect(page.getByRole("heading", { level: 1, name: "Shakeout run" })).toBeVisible();
  const chart = page.getByRole("figure", { name: "Heart rate and pace" });
  const canvas = chart.locator("canvas");
  await expect(canvas).toBeVisible();
  await expect.poll(() => painted(canvas), { timeout: 10_000 }).toBe(true);
});

test("today's planned run shows its structure, zones, steps and rationale", async ({ page }) => {
  await page.getByRole("link", { name: "Threshold intervals" }).click();

  await expect(page.getByRole("heading", { level: 1, name: "Threshold intervals" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Structure" })).toBeVisible();
  await expect(
    page.getByRole("list", { name: "Training zones" }).getByRole("listitem"),
  ).toHaveCount(5);

  const steps = page.getByRole("list", { name: "Steps" }).getByRole("listitem");
  await expect(steps).toHaveText([
    /10′\s*Warm-up/,
    /3×5′\s*Work\s*4:10 \/km/,
    /3×2′\s*Recovery/,
    /10′\s*Cool-down/,
  ]);

  await expect(page.getByRole("heading", { name: "Why this session" })).toBeVisible();
  await expect(
    page.getByText("Raises the pace that can be held for an hour, ahead of the 10 km."),
  ).toBeVisible();
});

test("the unmatched swim opens as an activity with its pool lengths", async ({ page }) => {
  await page.goto("/days/2026-01-20");
  await page.getByRole("link", { name: /^Swim/ }).click();

  await expect(page).toHaveURL(/\/activities\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { level: 1, name: "Swim" })).toBeVisible();
  const lengths = page.getByRole("table", { name: "Pool lengths" });
  await expect(lengths.getByRole("row")).toHaveCount(15);
  await expect(lengths.getByRole("row", { name: /^5 Rest/ })).toBeVisible();
});
