import { defineConfig, devices } from "@playwright/test";

const port = 4002;

export default defineConfig({
  testDir: "./tests",
  outputDir: "./test-results",
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "mix do ecto.create + ecto.migrate + vire.seed_e2e + phx.server",
    cwd: "..",
    env: { MIX_ENV: "test", VIRE_E2E: "true" },
    url: `http://127.0.0.1:${port}/api/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
