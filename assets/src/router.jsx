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
import { PlaceholderScreen } from "./screens/placeholder.jsx";
import { SignInScreen } from "./screens/sign-in.jsx";
import { TodayScreen } from "./screens/today.jsx";

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
  component: Outlet,
});

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  beforeLoad: () => {
    throw redirect({ to: "/today" });
  },
});

const todayRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/today",
  component: TodayScreen,
});

const sessionRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/sessions/$id",
  component: () => <PlaceholderScreen title="Session" />,
});

const activityRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/activities/$id",
  component: () => <PlaceholderScreen title="Activity" />,
});

export const routeTree = rootRoute.addChildren([
  indexRoute,
  signInRoute,
  authenticatedRoute.addChildren([todayRoute, sessionRoute, activityRoute]),
]);

export function createAppRouter({ queryClient, ...options }) {
  return createRouter({ routeTree, context: { queryClient }, ...options });
}

// Only a path on this origin is a place to return to after signing in.
function safeRedirect(value) {
  return typeof value === "string" && /^\/(?![/\\])/.test(value) ? value : undefined;
}
