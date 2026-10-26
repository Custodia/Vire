import { expect, test } from "@playwright/test";
import { dayLabel, isoDate, signIn } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

test("the header shows the date and where the day sits in the plan", async ({ page }) => {
  await expect(page.getByRole("heading", { level: 1, name: "Today" })).toBeVisible();
  await expect(page.getByText(dayLabel(isoDate()), { exact: true })).toBeVisible();
  await expect(
    page.getByText(/^Base · Aerobic endurance · Load cycle · Day [1-7] of 7$/),
  ).toBeVisible();
});

test("the planned sessions appear as cards, the first marked Next", async ({ page }) => {
  const upcoming = page.getByRole("region", { name: "Upcoming sessions" });
  const run = upcoming.getByRole("article", { name: "Threshold intervals" });
  const swim = upcoming.getByRole("article", { name: "Technique swim" });

  await expect(run).toContainText("Next");
  await expect(run).toContainText("1 of 2");
  await expect(swim).toContainText("Then");
  await expect(swim).toContainText("2 of 2");
  await expect(page.getByText(/^0 of 2 done · /)).toBeVisible();
});

test("previous and next step through the days and back to Today", async ({ page }) => {
  await page.getByRole("link", { name: "Previous day" }).click();

  await expect(page).toHaveURL(new RegExp(`/days/${isoDate(-1)}$`));
  await expect(page.getByRole("heading", { level: 1, name: dayLabel(isoDate(-1)) })).toBeVisible();

  await page.getByRole("link", { name: "Next day" }).click();

  await expect(page).toHaveURL(/\/today$/);
  await expect(page.getByRole("heading", { level: 1, name: "Today" })).toBeVisible();

  await page.getByRole("link", { name: "Next day" }).click();

  await expect(page).toHaveURL(new RegExp(`/days/${isoDate(1)}$`));
  await expect(page.getByRole("heading", { level: 1, name: dayLabel(isoDate(1)) })).toBeVisible();

  await page.getByRole("link", { name: "Previous day" }).click();

  await expect(page).toHaveURL(/\/today$/);
});
