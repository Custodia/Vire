import { expect, test } from "@playwright/test";

test("a signed-out visitor is asked to sign in", async ({ page }) => {
  await page.goto("/");

  await expect(page).toHaveURL(/\/sign-in\?redirect=%2Ftoday$/);
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
});

test("the seeded user signs in and sees Today", async ({ page }) => {
  await page.goto("/");

  await page.getByLabel("Email").fill("e2e@example.com");
  await page.getByLabel("Password").fill("e2e-password-1234");
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page).toHaveURL(/\/today$/);
  await expect(page.getByRole("heading", { level: 1, name: "Today" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Upload" })).toBeVisible();
});
