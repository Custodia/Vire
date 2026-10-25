import { render } from "@testing-library/react";
import { QueryClient } from "@tanstack/react-query";
import { createMemoryHistory } from "@tanstack/react-router";
import { App } from "../app.jsx";
import { createAppRouter } from "../router.jsx";

// Renders the whole application at a path, the way the browser would.
export function renderApp(path = "/") {
  const router = createAppRouter({ history: createMemoryHistory({ initialEntries: [path] }) });
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, refetchOnWindowFocus: false } },
  });
  const view = render(<App router={router} queryClient={queryClient} />);
  return { ...view, router };
}
