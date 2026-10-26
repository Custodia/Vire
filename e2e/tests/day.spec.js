import { expect, test } from "@playwright/test";
import { ensureUploaded, signIn } from "./helpers.js";

test.beforeAll(async ({ browser }) => {
  await ensureUploaded(browser, ["ride.fit", "run.fit", "swim.fit"]);
});

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the ride's day shows its session done with the recording", async ({ page }) => {
  await page.goto("/days/2026-07-14");

  await expect(page.getByRole("heading", { level: 1, name: "Tue 14 Jul" })).toBeVisible();
  const ride = page.getByRole("link", { name: /Saddle check ride/ });
  await expect(ride).toContainText("19:00 · 4.59 km · 9:00");
  await expect(ride).toContainText("Done");
  await expect(page.getByText("1 of 1 done", { exact: false })).toBeVisible();
});

test("the run's day shows its session done", async ({ page }) => {
  await page.goto("/days/2026-07-16");

  const run = page.getByRole("link", { name: /Shakeout run/ });
  await expect(run).toContainText("08:45 · 1.98 km · 10:00");
  await expect(run).toContainText("Done");
});

test("the swim's date is outside the plan and lists the swim unmatched", async ({ page }) => {
  await page.goto("/days/2026-01-20");

  await expect(page.getByRole("heading", { name: "Outside your plan" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Activities" })).toBeVisible();
  await expect(page.getByRole("link", { name: /^Swim/ })).toContainText("19:00 · 300 m · 6:25");
});

test("a date with no cycle and no activity is outside the plan alone", async ({ page }) => {
  await page.goto("/days/2026-03-03");

  await expect(page.getByRole("heading", { name: "Outside your plan" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Activities" })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Sessions" })).toHaveCount(0);
});
