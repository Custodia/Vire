import {
  createRootRouteWithContext,
  createRoute,
  createRouter,
  Outlet,
  redirect,
} from "@tanstack/react-router";
import { ApiError } from "./api/client.js";
import { meQuery } from "./api/queries.js";
import { ErrorScreen } from "./screens/error.jsx";
import { AppFrame } from "./screens/frame.jsx";
import { PlanScreen } from "./screens/plan.jsx";
import { SignInScreen } from "./screens/sign-in.jsx";
import { CalendarScreen } from "./screens/calendar.jsx";
import { ActivityScreen, SessionScreen } from "./screens/session-page.jsx";
import { localDate } from "./lib/format.js";
import { calendarView } from "./lib/links.js";

const rootRoute = createRootRouteWithContext()({
  component: Outlet,
  errorComponent: ErrorScreen,
});

const signInRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/sign-in",
  validateSearch: (search) => ({ redirect: safeRedirect(search.redirect) }),
  component: SignInScreen,
});

const authenticatedRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: "authenticated",
  beforeLoad: async ({ context, location }) => {
    try {
      return { me: await context.queryClient.ensureQueryData(meQuery) };
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        throw redirect({ to: "/sign-in", search: { redirect: location.href } });
      }
      throw error;
    }
  },
  component: AppFrame,
});

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  beforeLoad: () => {
    throw redirect({ to: "/calendar" });
  },
});

const calendarIndexRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/calendar",
  beforeLoad: () => {
    throw redirect({
      to: "/calendar/$view/$date",
      params: { view: calendarView(), date: localDate() },
    });
  },
});

const calendarRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/calendar/$view/$date",
  component: CalendarScreen,
});

const planRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/plan",
  validateSearch: (search) => ({
    season: typeof search.season === "string" ? search.season : undefined,
  }),
  component: PlanScreen,
});

const sessionRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/sessions/$id",
  component: SessionScreen,
});

const activityRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/activities/$id",
  component: ActivityScreen,
});

export const routeTree = rootRoute.addChildren([
  indexRoute,
  signInRoute,
  authenticatedRoute.addChildren([
    calendarIndexRoute,
    calendarRoute,
    planRoute,
    sessionRoute,
    activityRoute,
  ]),
]);

export function createAppRouter({ queryClient, ...options }) {
  return createRouter({ routeTree, context: { queryClient }, ...options });
}

// Only a path on this origin is a place to return to after signing in.
function safeRedirect(value) {
  return typeof value === "string" && /^\/(?![/\\])/.test(value) ? value : undefined;
}
