import { expect, test } from "@playwright/test";
import { signIn, uploadFixture } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

for (const [name, session] of [
  ["ride.fit", "Saddle check ride"],
  ["run.fit", "Shakeout run"],
]) {
  test(`${name} is processed and matched to ${session}`, async ({ page }) => {
    const dialog = await uploadFixture(page, name);

    await expect(dialog.getByRole("heading", { name: "Uploaded" })).toBeVisible();
    await expect(dialog.getByText(`Matched to ${session}`)).toBeVisible();
    await expect(dialog.getByRole("link", { name: "Open the session" })).toHaveAttribute(
      "href",
      /^\/sessions\/[0-9a-f-]{36}$/,
    );
  });
}

test("swim.fit, on a day with nothing planned, is processed and opens its activity", async ({
  page,
}) => {
  const dialog = await uploadFixture(page, "swim.fit");

  await expect(dialog.getByText("Not in the plan")).toBeVisible();
  await expect(dialog.getByRole("link", { name: "Open the activity" })).toHaveAttribute(
    "href",
    /^\/activities\/[0-9a-f-]{36}$/,
  );
});

test("a file that fails its integrity check says why it could not be read", async ({ page }) => {
  const dialog = await uploadFixture(page, "corrupt.fit");

  await expect(dialog.getByRole("alert")).toHaveText(
    "This file could not be read: integrity check failed: " +
      "the file's size or CRC does not match its contents. " +
      "Try exporting it again from the device.",
  );
  await expect(dialog.getByRole("button", { name: "Choose another file" })).toBeVisible();
});

test("the ride uploaded again is already processed and opens the same session", async ({
  page,
}) => {
  let dialog = await uploadFixture(page, "ride.fit");
  const first = await dialog.getByRole("link", { name: "Open the session" }).getAttribute("href");
  await dialog.getByRole("button", { name: "Close" }).click();

  dialog = await uploadFixture(page, "ride.fit");

  const link = dialog.getByRole("link", { name: "Open the session" });
  await expect(link).toHaveAttribute("href", first);

  const response = await page.request.get("/api/days/2026-07-14");
  expect(response.ok()).toBe(true);
  const { day, activities } = await response.json();
  const onDay = [...(day?.sessions ?? []).map((session) => session.activity), ...activities];
  expect(onDay.filter((activity) => activity?.discipline === "bike")).toHaveLength(1);

  await link.click();

  await expect(page).toHaveURL(new RegExp(`${first}$`));
  await expect(page.getByRole("heading", { level: 2, name: "Saddle check ride" })).toBeVisible();
});
