import { render } from "@testing-library/react";
import { createMemoryHistory } from "@tanstack/react-router";
import { createQueryClient } from "../api/query-client.js";
import { App } from "../app.jsx";
import { createAppRouter } from "../router.jsx";

// Renders the whole application at a path, the way the browser would, with
// retries that do not wait.
export function renderApp(path = "/") {
  const queryClient = createQueryClient({ retryDelay: 0 });
  const router = createAppRouter({
    queryClient,
    history: createMemoryHistory({ initialEntries: [path] }),
  });
  const view = render(<App router={router} queryClient={queryClient} />);
  return { ...view, router, queryClient };
}
