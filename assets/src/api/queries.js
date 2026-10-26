import { getMe } from "./client.js";

export const meQuery = { queryKey: ["me"], queryFn: getMe, staleTime: Infinity };
