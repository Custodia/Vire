import { getDay, getMe } from "./client.js";

export const meQuery = {
  queryKey: ["me"],
  queryFn: getMe,
  staleTime: Infinity,
  meta: { authenticates: true },
};

export const dayQuery = (date) => ({ queryKey: ["days", date], queryFn: () => getDay(date) });
