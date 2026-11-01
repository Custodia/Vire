import { expect, test } from "@playwright/test";
import { dayPath, isoDate, longDayLabel, signIn } from "./helpers.js";

test.beforeEach(async ({ page }) => {
  await signIn(page);
});

/** Drags a finger across `locator` by `dx` pixels, sideways. */
async function swipe(page, locator, dx) {
  const box = await locator.boundingBox();
  const y = box.y + box.height / 2;
  const x = dx < 0 ? box.x + box.width - 20 : box.x + 20;
  const at = (offset) => [{ identifier: 0, clientX: x + offset, clientY: y }];
  await locator.dispatchEvent("touchstart", { touches: at(0) });
  await locator.dispatchEvent("touchmove", { touches: at(dx / 2) });
  await locator.dispatchEvent("touchmove", { touches: at(dx) });
  await locator.dispatchEvent("touchend", { changedTouches: at(dx) });
}

test("today's day is a timeline with the next session open", async ({ page }) => {
  await expect(
    page.getByRole("heading", { level: 1, name: longDayLabel(isoDate()) }),
  ).toBeVisible();
  const timeline = page.getByRole("list", { name: "Timeline" });
  await expect(timeline.getByRole("button", { expanded: true })).toContainText(
    "Threshold intervals",
  );

  await timeline.getByRole("link", { name: "Open the session" }).click();

  await expect(page).toHaveURL(/\/sessions\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { level: 1, name: "Threshold intervals" })).toBeVisible();
  await page.getByRole("link", { name: /^Back to / }).click();
  await expect(page).toHaveURL(dayPath(isoDate()));
});

test("a swipe moves the day, and the tabs lead to the plan", async ({ page }) => {
  await swipe(page, page.getByRole("list", { name: "Timeline" }), -200);

  await expect(page).toHaveURL(dayPath(isoDate(1)));

  await page
    .getByRole("navigation", { name: "Primary" })
    .getByRole("link", { name: "Plan" })
    .click();

  await expect(page.getByRole("heading", { level: 2, name: "Base · blocks" })).toBeVisible();
  await expect(page.getByRole("button", { name: /^Block 1 · now/ })).toHaveAttribute(
    "aria-expanded",
    "true",
  );
});

test("More holds the upload and signing out", async ({ page }) => {
  await page
    .getByRole("navigation", { name: "Primary" })
    .getByRole("button", { name: "More" })
    .click();
  const more = page.getByRole("dialog");
  await expect(more.getByText("e2e@example.com")).toBeVisible();

  await more.getByRole("button", { name: /Upload .fit/ }).click();
  await expect(page.getByRole("dialog", { name: "Upload a .fit file" })).toBeVisible();
  await page.getByRole("button", { name: "Close" }).click();

  await page.getByRole("button", { name: "More" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/sign-in$/);
});
