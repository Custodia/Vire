import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect } from "@playwright/test";

export const email = "e2e@example.com";
export const password = "e2e-password-1234";

const fixtures = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../test/support/fixtures/fit",
);

/** The UTC date `days` after today as YYYY-MM-DD; the browser runs in UTC. */
export function isoDate(days = 0) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** A YYYY-MM-DD date the way the dashboard writes it, such as Tue 14 Jul. */
export function dayLabel(isoDate) {
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
    timeZone: "UTC",
  }).format(new Date(`${isoDate}T00:00:00Z`));
}

/** Fills the dashboard's sign-in form, which `page` is showing. */
export async function submitSignIn(page, { withPassword = password } = {}) {
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(withPassword);
  await page.getByRole("button", { name: "Sign in" }).click();
}

/** Signs in through the form and waits for Today. */
export async function signIn(page) {
  await page.goto("/sign-in");
  await submitSignIn(page);
  await expect(page).toHaveURL(/\/today$/);
}

/**
 * Uploads a fixture through Today's upload dialog and waits until the dialog
 * reports it processed or failed. Answers the open dialog.
 */
export async function uploadFixture(page, name) {
  await page.getByRole("button", { name: "Upload" }).click();
  const dialog = page.getByRole("dialog", { name: "Upload a .fit file" });
  const chooser = page.waitForEvent("filechooser");
  await dialog.getByRole("button", { name: "Choose a file" }).click();
  await (await chooser).setFiles(path.join(fixtures, name));

  await expect(dialog.getByRole("status")).toHaveText(
    new RegExp(`^${name.replace(".", "\\.")} (is processed|could not be processed)`),
    { timeout: 30_000 },
  );
  return dialog;
}

/** Signs in on a page of its own and uploads each fixture, so that its activity exists. */
export async function ensureUploaded(browser, names) {
  const page = await browser.newPage();
  await signIn(page);
  for (const name of names) {
    const dialog = await uploadFixture(page, name);
    await expect(dialog.getByRole("status")).toHaveText(
      new RegExp(`^${name.replace(".", "\\.")} is processed`),
    );
    await dialog.getByRole("button", { name: "Close" }).click();
  }
  await page.close();
}
