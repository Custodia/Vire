import { expect, test } from "@playwright/test";
import { dayPath, isoDate, longDayLabel, submitSignIn } from "./helpers.js";

test("a visitor is sent to sign in and lands on today's day once signed in", async ({ page }) => {
  await page.goto("/");

  await expect(page).toHaveURL(/\/sign-in\?redirect=%2Fcalendar$/);
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();

  await submitSignIn(page);

  await expect(page).toHaveURL(dayPath(isoDate()));
  await expect(
    page.getByRole("heading", { level: 1, name: longDayLabel(isoDate()) }),
  ).toBeVisible();
});

test("a wrong password shows the error and stays on sign-in", async ({ page }) => {
  await page.goto("/sign-in");

  await submitSignIn(page, { withPassword: "not-the-password" });

  await expect(page.getByRole("alert")).toHaveText(
    "That email and password do not match an account.",
  );
  await expect(page).toHaveURL(/\/sign-in$/);
});

test("signing out returns to sign-in and the screens ask to sign in again", async ({ page }) => {
  await page.goto("/");
  await submitSignIn(page);
  await expect(page).toHaveURL(dayPath(isoDate()));

  await page.getByRole("button", { name: "Sign out" }).click();

  await expect(page).toHaveURL(/\/sign-in$/);
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();

  await page.goto("/calendar/day/2026-07-14");

  await expect(page).toHaveURL(/\/sign-in\?redirect=%2Fcalendar%2Fday%2F2026-07-14$/);
  await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
});
