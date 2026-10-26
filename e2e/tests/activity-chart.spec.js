import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";

const ride = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../test/support/fixtures/fit/ride.fit",
);

test("an uploaded ride opens with its streams drawn as a chart", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("Email").fill("e2e@example.com");
  await page.getByLabel("Password").fill("e2e-password-1234");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/today$/);

  await page.getByRole("button", { name: "Upload" }).click();
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Choose a file" }).click();
  await (await chooser).setFiles(ride);

  await expect(page.getByText("ride.fit is processed.")).toBeVisible({ timeout: 30_000 });
  await page.getByRole("link", { name: "Open the activity" }).click();

  const chart = page.getByRole("figure", { name: /^Power/ });
  await expect(chart).toBeVisible();
  await expect(chart.locator(".uplot canvas")).toBeVisible();
});
