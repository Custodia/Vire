import { expect, test } from "@playwright/test";

test("the Today screen shows a connected server", async ({ page }) => {
  await page.goto("/");

  await expect(page).toHaveURL(/\/today$/);
  await expect(page.getByText("Today", { exact: true })).toBeVisible();
  await expect(page.getByRole("status")).toHaveText("Connected");
});
