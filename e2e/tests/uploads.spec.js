import { expect, test } from "@playwright/test";
import { signIn, uploadFixture } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

for (const name of ["ride.fit", "run.fit", "swim.fit"]) {
  test(`${name} is processed and links to its activity`, async ({ page }) => {
    const dialog = await uploadFixture(page, name);

    await expect(dialog.getByRole("status")).toHaveText(`${name} is processed. Open the activity`);
    await expect(dialog.getByRole("link", { name: "Open the activity" })).toHaveAttribute(
      "href",
      /^\/activities\/[0-9a-f-]{36}$/,
    );
  });
}

test("a file that fails its integrity check is reported failed with the error", async ({
  page,
}) => {
  const dialog = await uploadFixture(page, "corrupt.fit");

  await expect(dialog.getByRole("status")).toHaveText(
    "corrupt.fit could not be processed: integrity check failed: " +
      "the file's size or CRC does not match its contents",
  );
  await expect(dialog.getByRole("link", { name: "Open the activity" })).toHaveCount(0);
});

test("the ride uploaded again is already processed and opens the same activity", async ({
  page,
}) => {
  let dialog = await uploadFixture(page, "ride.fit");
  const first = await dialog.getByRole("link", { name: "Open the activity" }).getAttribute("href");
  await dialog.getByRole("button", { name: "Close" }).click();

  dialog = await uploadFixture(page, "ride.fit");

  await expect(dialog.getByRole("status")).toHaveText("ride.fit is processed. Open the activity");
  const link = dialog.getByRole("link", { name: "Open the activity" });
  await expect(link).toHaveAttribute("href", first);

  const response = await page.request.get("/api/days/2026-07-14");
  expect(response.ok()).toBe(true);
  const { day, activities } = await response.json();
  const onDay = [...(day?.sessions ?? []).map((session) => session.activity), ...activities];
  expect(onDay.filter((activity) => activity?.discipline === "bike")).toHaveLength(1);

  await link.click();

  await expect(page).toHaveURL(new RegExp(`${first}$`));
  await expect(page.getByRole("heading", { level: 1, name: "Bike" })).toBeVisible();
});
