import { execFileSync } from "node:child_process";
import { expect, test } from "@playwright/test";
import { signIn } from "./helpers.js";

// Nothing answers for Garmin here, so a queued sync waits for good; seeding
// again drops it before the next spec.
test.afterAll(() => {
  execFileSync("mix", ["vire.seed_e2e"], {
    cwd: "..",
    env: { ...process.env, MIX_ENV: "test", VIRE_E2E: "true" },
    stdio: "ignore",
  });
});

test("Sync now shows the sync under way, here and in another tab", async ({ page, context }) => {
  await signIn(page);
  const other = await context.newPage();
  await other.goto("/calendar");
  await expect(other.getByRole("button", { name: "Sync now" })).toBeEnabled();

  await page.getByRole("button", { name: "Sync now" }).click();

  await expect(page.getByRole("button", { name: "Syncing…" })).toBeDisabled();
  await expect(page.getByRole("region", { name: "Notifications" }).getByRole("status")).toHaveText(
    /^Syncing with Garmin\s*Waiting to start\.$/,
  );
  await expect(other.getByRole("button", { name: "Syncing…" })).toBeDisabled();

  await page.reload();

  await expect(page.getByRole("button", { name: "Syncing…" })).toBeDisabled();
});
