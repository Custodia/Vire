import { describe, expect, test } from "vitest";
import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { mockSession, password, user } from "../mocks/handlers.js";
import { server } from "../mocks/server.js";
import { renderApp } from "../test/render.jsx";

async function signInWith(email, secret) {
  await userEvent.type(await screen.findByLabelText("Email"), email);
  await userEvent.type(screen.getByLabelText("Password"), secret);
  await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
}

describe("signing in", () => {
  test("sends a signed-out visitor to sign in and back to where they were going", async () => {
    mockSession.signedIn = false;
    const { router } = renderApp("/today");

    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe("/sign-in");
    expect(router.state.location.search).toEqual({ redirect: "/today" });

    await signInWith("Ada@Example.com", password);

    await waitFor(() => expect(router.state.location.pathname).toBe("/today"));
    expect(await screen.findByRole("button", { name: "Sign out" })).toBeInTheDocument();
  });

  test("keeps the query string of the page the visitor was going to", async () => {
    mockSession.signedIn = false;
    const { router } = renderApp("/today?tab=sessions");

    await signInWith(user.email, password);

    await waitFor(() => expect(router.state.location.href).toBe("/today?tab=sessions"));
  });

  test("goes to Today after signing in without a page to return to", async () => {
    mockSession.signedIn = false;
    const { router } = renderApp("/sign-in?redirect=//example.com");

    await signInWith(user.email, password);

    await waitFor(() => expect(router.state.location.pathname).toBe("/today"));
  });

  test("says so when the email and password do not match", async () => {
    mockSession.signedIn = false;
    const { router } = renderApp("/sign-in");

    await signInWith(user.email, "wrong-password");

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "That email and password do not match an account.",
    );
    expect(router.state.location.pathname).toBe("/sign-in");
    expect(screen.getByRole("button", { name: "Sign in" })).toBeEnabled();
  });

  test("says so when the server fails", async () => {
    server.use(http.post("/api/session", () => HttpResponse.json({}, { status: 500 })));
    renderApp("/sign-in");

    await signInWith(user.email, password);

    expect(await screen.findByRole("alert")).toHaveTextContent("Signing in failed. Try again.");
  });
});

describe("signing out", () => {
  test("ends the session and returns to sign in", async () => {
    const { router } = renderApp("/today");

    await userEvent.click(await screen.findByRole("button", { name: "Sign out" }));

    expect(await screen.findByRole("heading", { name: "Sign in" })).toBeInTheDocument();
    expect(mockSession.signedIn).toBe(false);

    await router.navigate({ to: "/today" });

    await waitFor(() => expect(router.state.location.pathname).toBe("/sign-in"));
  });
});

describe("checking the session", () => {
  test("shows an error with a retry when the server cannot say who is signed in", async () => {
    let failing = true;
    server.use(
      http.get("/api/me", () =>
        failing ? HttpResponse.json({}, { status: 500 }) : HttpResponse.json(user),
      ),
    );
    renderApp("/today");

    expect(await screen.findByRole("alert")).toHaveTextContent("Vire could not load this page.");

    failing = false;
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));

    expect(await screen.findByRole("button", { name: "Sign out" })).toBeInTheDocument();
  });

  test("asks the server who is signed in once", async () => {
    let calls = 0;
    server.events.on("request:start", ({ request }) => {
      if (new URL(request.url).pathname === "/api/me") calls++;
    });
    const { router } = renderApp("/today");
    await screen.findByRole("button", { name: "Sign out" });

    await router.navigate({ to: "/" });
    await waitFor(() => expect(router.state.location.pathname).toBe("/today"));

    expect(calls).toBe(1);
    server.events.removeAllListeners();
  });
});
