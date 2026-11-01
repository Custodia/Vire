import { getMe, getPlanChanges, getSeason, getSeasons } from "./client.js";

export const meQuery = { queryKey: ["me"], queryFn: getMe, staleTime: Infinity };

export const seasonsQuery = { queryKey: ["seasons"], queryFn: getSeasons };

export const seasonQuery = (id) => ({
  queryKey: ["seasons", id],
  queryFn: () => getSeason(id),
  enabled: id != null,
});

export const planChangesQuery = { queryKey: ["plan_changes"], queryFn: getPlanChanges };
