// What the channel's events change in the cached queries. The pushes carry the
// API's own JSON, so each one replaces the query that GETs the same resource.

const planQueries = ["days", "seasons", "sessions", "activities"];

function refreshPlan(queryClient) {
  for (const key of planQueries) queryClient.invalidateQueries({ queryKey: [key] });
}

/**
 * Takes the sync's state from a `sync` push. A run that has just finished may
 * have brought activities and marked sessions skipped, so the plan is read again.
 */
export function receiveSync(queryClient, status) {
  const before = queryClient.getQueryData(["sync"])?.run;
  queryClient.setQueryData(["sync"], status);

  const run = status.run;
  if (run?.state === "finished" && !(before?.id === run.id && before.state === "finished")) {
    refreshPlan(queryClient);
  }
}

/** Takes a file's status from an `upload` push; a processed file changes the plan. */
export function receiveUpload(queryClient, upload) {
  queryClient.setQueryData(["uploads", upload.id], upload);
  if (upload.status === "processed") refreshPlan(queryClient);
}

/** Reads again what a push may have changed while the connection was down. */
export function catchUp(queryClient) {
  queryClient.invalidateQueries({ queryKey: ["sync"] });
  queryClient.invalidateQueries({ queryKey: ["uploads"] });
}
