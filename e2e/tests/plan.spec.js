import { expect, test } from "@playwright/test";
import { dayLabel, dayPath, isoDate, longDayLabel, signIn } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("Today leads to the plan, which leads with the season", async ({ page }) => {
  await page.getByRole("link", { name: "Plan", exact: true }).click();

  await expect(page).toHaveURL(/\/plan$/);
  await expect(page.getByRole("heading", { level: 1, name: "Autumn 10 km" })).toBeVisible();
  await expect(
    page.getByRole("navigation", { name: "Primary" }).getByRole("link", { name: "Plan" }),
  ).toHaveAttribute("aria-current", "page");
});

test("the season map carries the phases over the blocks", async ({ page }) => {
  await page.goto("/plan");

  const phases = page.getByRole("list", { name: "Phases" });
  await expect(phases.getByRole("button", { name: /Base/ })).toContainText("Current");

  const blocks = page.getByRole("list", { name: "Blocks" });
  await expect(
    blocks.getByRole("button", { name: "Block 1 · Aerobic endurance, current" }),
  ).toHaveAttribute("aria-pressed", "true");
});

test("the block today falls in fills the table and the calendar", async ({ page }) => {
  await page.goto("/plan");

  const table = page.getByRole("heading", { level: 2, name: "Base · blocks" }).locator("../..");
  await expect(table.getByRole("button", { name: "Block 1, current" })).toBeVisible();
  await expect(table).toContainText("Aerobic endurance");

  await expect(
    page.getByRole("heading", { level: 2, name: "Block 1 · cycles × days" }),
  ).toBeVisible();
});

test("the calendar marks today and leads to the day behind it", async ({ page }) => {
  await page.goto("/plan");

  const today = page.getByRole("link", { name: dayLabel(isoDate()) });
  await expect(today).toContainText("Today");

  await today.click();

  await expect(page).toHaveURL(dayPath(isoDate()));
});

test("another day in the cycle leads to its own screen", async ({ page }) => {
  await page.goto("/plan");

  await page.getByRole("link", { name: dayLabel(isoDate(2)) }).click();

  await expect(page).toHaveURL(dayPath(isoDate(2)));
  await expect(
    page.getByRole("heading", { level: 1, name: longDayLabel(isoDate(2)) }),
  ).toBeVisible();
});

test("the coach log lists the changes behind the plan", async ({ page }) => {
  await page.goto("/plan");

  const log = page.getByRole("heading", { level: 2, name: "Coach log" }).locator("../..");
  await expect(log.getByRole("listitem").first()).toBeVisible();
});
