import {
  getActivity,
  getActivityStreams,
  getDays,
  getMe,
  getPlanChanges,
  getSeason,
  getSeasons,
  getSession,
  getSync,
  getUpload,
} from "./client.js";

export const meQuery = {
  queryKey: ["me"],
  queryFn: getMe,
  staleTime: Infinity,
  meta: { authenticates: true },
};

export const seasonsQuery = { queryKey: ["seasons"], queryFn: getSeasons };

export const seasonQuery = (id) => ({
  queryKey: ["seasons", id],
  queryFn: () => getSeason(id),
  enabled: id != null,
});

export const planChangesQuery = { queryKey: ["plan_changes"], queryFn: getPlanChanges };

/** Every date from `from` to `to`, each with its day and the activities no session is matched to. */
export const daysQuery = (from, to) => ({
  queryKey: ["days", from, to],
  queryFn: () => getDays(from, to).then(({ days }) => days),
});

export const sessionQuery = (id) => ({
  queryKey: ["sessions", id],
  queryFn: () => getSession(id),
});

export const activityQuery = (id) => ({
  queryKey: ["activities", id],
  queryFn: () => getActivity(id),
});

export const streamsQuery = (id, channels, step) => ({
  queryKey: ["activities", id, "streams", channels, step],
  queryFn: () => getActivityStreams(id, channels, step),
  staleTime: Infinity,
});

export const syncQuery = { queryKey: ["sync"], queryFn: getSync };

export const uploadQuery = (id) => ({
  queryKey: ["uploads", id],
  queryFn: () => getUpload(id),
  enabled: id != null,
});
