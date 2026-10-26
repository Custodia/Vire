import { render } from "@testing-library/react";
import { createMemoryHistory } from "@tanstack/react-router";
import { App } from "../app.jsx";
import { createApp } from "../create-app.js";

// Renders the whole application at a path, the way the browser would, with
// retries that do not wait.
export function renderApp(path = "/") {
  const { queryClient, router } = createApp({
    retryDelay: 0,
    history: createMemoryHistory({ initialEntries: [path] }),
  });
  const view = render(<App router={router} queryClient={queryClient} />);
  return { ...view, router, queryClient };
}
