import { createQueryClient } from "./api/query-client.js";
import { createAppRouter } from "./router.jsx";

// A request answering 401 after the guard's check means the session has ended.
export function createApp({ retryDelay, ...routerOptions } = {}) {
  const queryClient = createQueryClient({
    retryDelay,
    onUnauthorized: () => {
      const { pathname, href } = router.state.location;
      if (pathname === "/sign-in") return;
      router
        .navigate({ to: "/sign-in", search: { redirect: href } })
        .then(() => queryClient.clear());
    },
  });
  const router = createAppRouter({ queryClient, ...routerOptions });
  return { queryClient, router };
}
