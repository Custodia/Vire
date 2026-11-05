import { afterEach, describe, expect, test, vi } from "vitest";
import { waitFor } from "@testing-library/react";
import { forgetCsrfToken, sessionToken } from "../api/client.js";
import { mockLive, mockSession, user } from "../mocks/handlers.js";
import { connectLive } from "./connection.js";

let disconnect;

afterEach(() => disconnect?.());

const connect = (fields = {}) => {
  const onJoin = vi.fn();
  disconnect = connectLive({
    topic: `user:${user.id}`,
    csrfToken: sessionToken,
    forgetCsrfToken,
    handlers: {},
    onJoin,
    ...fields,
  });
  return onJoin;
};

describe("the live connection", () => {
  test("joins the user's topic with the session's CSRF token", async () => {
    const onJoin = connect();

    await waitFor(() => expect(onJoin).toHaveBeenCalledOnce());
    expect(mockLive.channels.size).toBe(1);
  });

  test("hands each pushed event to its handler", async () => {
    const sync = vi.fn();
    const onJoin = connect({ handlers: { sync } });
    await waitFor(() => expect(onJoin).toHaveBeenCalled());

    mockLive.push("sync", { run: null });

    await waitFor(() => expect(sync).toHaveBeenCalledWith({ run: null }));
  });

  test("fetches the token anew when the server refuses the one it had", async () => {
    await sessionToken();
    mockSession.csrfToken = "the-session-s-next-token";

    const onJoin = connect();

    await waitFor(() => expect(onJoin).toHaveBeenCalledOnce(), { timeout: 3000 });
    expect(await sessionToken()).toBe("the-session-s-next-token");
  });

  test("joins again after the connection comes back", async () => {
    const onJoin = connect();
    await waitFor(() => expect(onJoin).toHaveBeenCalledOnce());

    mockLive.drop();

    await waitFor(() => expect(onJoin).toHaveBeenCalledTimes(2), { timeout: 3000 });
  });

  test("never connects when it is closed before the token arrives", async () => {
    connect();
    disconnect();
    disconnect = null;

    await sessionToken();
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(mockLive.channels.size).toBe(0);
  });
});
