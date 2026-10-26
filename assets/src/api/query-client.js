import { QueryClient } from "@tanstack/react-query";
import { ApiError } from "./client.js";

function retry(failureCount, error) {
  if (error instanceof ApiError && error.status >= 400 && error.status < 500) return false;
  return failureCount < 3;
}

export function createQueryClient({ retryDelay } = {}) {
  return new QueryClient({
    defaultOptions: { queries: { retry, ...(retryDelay === undefined ? {} : { retryDelay }) } },
  });
}
