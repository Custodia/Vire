import {
  createRootRoute,
  createRoute,
  createRouter,
  Outlet,
  redirect,
} from "@tanstack/react-router";
import { TodayScreen } from "./screens/today.jsx";

const rootRoute = createRootRoute({ component: Outlet });

const indexRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  beforeLoad: () => {
    throw redirect({ to: "/today" });
  },
});

const todayRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/today",
  component: TodayScreen,
});

export const routeTree = rootRoute.addChildren([indexRoute, todayRoute]);

export function createAppRouter(options = {}) {
  return createRouter({ routeTree, ...options });
}
