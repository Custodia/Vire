import { MutationCache, QueryCache, QueryClient } from "@tanstack/react-query";
import { ApiError } from "./client.js";

function retry(failureCount, error) {
  if (error instanceof ApiError && error.status >= 400 && error.status < 500) return false;
  return failureCount < 3;
}

// A request marked with `meta.authenticates` decides who is signed in and
// handles its own 401.
export function createQueryClient({ onUnauthorized, retryDelay }) {
  const onError = (error, meta) => {
    if (error instanceof ApiError && error.status === 401 && !meta?.authenticates) {
      onUnauthorized();
    }
  };

  return new QueryClient({
    queryCache: new QueryCache({ onError: (error, query) => onError(error, query.meta) }),
    mutationCache: new MutationCache({
      onError: (error, _variables, _context, mutation) => onError(error, mutation.meta),
    }),
    defaultOptions: { queries: { retry, ...(retryDelay === undefined ? {} : { retryDelay }) } },
  });
}
