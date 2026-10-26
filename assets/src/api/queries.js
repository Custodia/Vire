import { getActivity, getActivityStreams, getDay, getMe, getSession } from "./client.js";

export const meQuery = {
  queryKey: ["me"],
  queryFn: getMe,
  staleTime: Infinity,
  meta: { authenticates: true },
};

export const dayQuery = (date) => ({ queryKey: ["days", date], queryFn: () => getDay(date) });

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
