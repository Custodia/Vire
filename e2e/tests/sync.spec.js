import { expect, test } from "@playwright/test";
import { signIn } from "./helpers.js";

test("Sync now reports that a sync was queued", async ({ page }) => {
  await signIn(page);

  await page.getByRole("button", { name: "Sync now" }).click();

  await expect(page.getByText("A sync was queued.")).toBeVisible();
});
