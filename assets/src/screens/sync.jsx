import { useEffect, useRef } from "react";
import { useIsMutating, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { ApiError, postSync } from "../api/client.js";
import { syncQuery } from "../api/queries.js";
import { discipline } from "../lib/disciplines.js";
import { formatHoursMinutes, formatMoment, formatWeekday } from "../lib/format.js";
import { Button } from "../ui/Button.jsx";
import { Spinner } from "../ui/Spinner.jsx";
import { useToasts } from "../ui/Toasts.jsx";

const DONE_MS = 8000;
const NOTHING_NEW_MS = 5000;

const inFlight = (run) => ["queued", "searching", "fetching"].includes(run?.state);

const plural = (count, one, many) => `${count} ${count === 1 ? one : many}`;

// Every Sync now shares one mutation key, so the button is busy whichever card
// or button sent it.
const syncMutation = ["sync"];

/** Sends Sync now, and shows why when the sync is refused. */
export function useSyncNow() {
  const queryClient = useQueryClient();
  const toasts = useToasts();

  return useMutation({
    mutationKey: syncMutation,
    mutationFn: postSync,
    onSuccess: (status) => {
      toasts.dismiss("sync-refused");
      queryClient.setQueryData(syncQuery.queryKey, status);
    },
    onError: (error) => {
      if (!(error instanceof ApiError && error.status === 401)) toasts.show(refusedToast(error));
    },
  });
}

function refusedToast(error) {
  const reason = error instanceof ApiError && error.status === 409 ? error.body?.reason : null;
  if (reason === "paused") return pausedToast("sync-refused");
  if (reason === "not_connected") {
    return {
      id: "sync-refused",
      tone: "caution",
      title: "No Garmin connection is set up",
      body: <Body>Activities sync once one is set up.</Body>,
    };
  }
  return {
    id: "sync-refused",
    tone: "caution",
    title: "The sync did not start",
    body: <Body>Vire did not answer. Try again in a moment.</Body>,
  };
}

const pausedToast = (id) => ({
  id,
  tone: "caution",
  title: "The Garmin connection is paused",
  body: <Body>Activities sync again once it is resumed.</Body>,
});

const Body = ({ children }) => <p className="m-0 text-caption text-ink-soft">{children}</p>;

/** The sync status, and whether a sync is being sent or runs. */
export function useSyncing() {
  const status = useQuery(syncQuery).data;
  const sending = useIsMutating({ mutationKey: syncMutation }) > 0;
  return { status, busy: sending || inFlight(status?.run) };
}

/** The Sync now action, busy while a sync is sent or runs. */
export function SyncButton() {
  const { busy } = useSyncing();
  const mutation = useSyncNow();

  return (
    <Button
      variant="secondary"
      onClick={() => mutation.mutate()}
      disabled={busy}
      aria-busy={busy || undefined}
    >
      {busy && <Spinner />}
      {busy ? "Syncing…" : "Sync now"}
    </Button>
  );
}

/**
 * Where Garmin syncing stands: `{ state: "paused" }`, `{ state: "syncing" }`
 * or `{ state: "synced", at }` with the time it last synced, or `null`
 * without a connection or a sync yet.
 */
export function syncStanding(status, busy) {
  if (!status || status.connection === "none") return null;
  if (status.connection === "paused") return { state: "paused" };
  if (busy) return { state: "syncing" };
  return status.last_synced_at
    ? { state: "synced", at: formatMoment(status.last_synced_at) }
    : null;
}

/** When Garmin last synced, or that it is syncing or paused. */
export function SyncStamp() {
  const { status, busy } = useSyncing();
  const standing = syncStanding(status, busy);
  if (!standing) return null;
  return (
    <span className="mr-4 text-xs text-ink-muted">
      Garmin {standing.state === "synced" ? standing.at : standing.state}
    </span>
  );
}

/**
 * The cards that follow a sync: one while a sync someone asked for runs, and
 * one once a sync finishes or fails. A sync the schedule or the plan started
 * shows its card only once it brings activities or fails.
 */
export function SyncToasts() {
  const status = useQuery(syncQuery).data;
  const toasts = useToasts();
  const mutation = useSyncNow();
  const seen = useRef(null);

  useEffect(() => {
    const run = status?.run;
    const before = seen.current;
    if (!run) return;

    if (inFlight(run)) {
      seen.current = {
        id: run.id,
        inFlight: true,
        syncedAt: before?.id === run.id ? before.syncedAt : status.last_synced_at,
      };
      if (run.trigger === "manual") toasts.show(progressToast(run));
      return;
    }

    seen.current = { id: run.id, inFlight: false };
    if (before?.id !== run.id || !before.inFlight) return;

    const id = `sync-${run.id}`;
    if (run.state === "failed") {
      toasts.show(
        status.connection === "paused"
          ? pausedToast(id)
          : unfinishedToast(id, run, () => {
              toasts.dismiss(id);
              mutation.mutate();
            }),
      );
    } else if (run.activities.length > 0) {
      toasts.show(syncedToast(id, run));
    } else if (run.trigger === "manual") {
      toasts.show(nothingNewToast(id, before.syncedAt));
    } else {
      toasts.dismiss(id);
    }
  }, [status, toasts, mutation]);

  return null;
}

function progressToast(run) {
  const { total, fetched, failed } = run.files;
  const done = fetched + failed;
  const found = plural(run.activities.length, "new activity", "new activities");

  return {
    id: `sync-${run.id}`,
    tone: "busy",
    title: "Syncing with Garmin",
    body:
      total > 0 ? (
        <>
          <Body>
            {found} found · fetching files,{" "}
            <span className="font-display text-row font-semibold text-ink">
              {done} of {total}
            </span>
          </Body>
          <div
            role="progressbar"
            aria-label="Files fetched"
            aria-valuemin={0}
            aria-valuemax={total}
            aria-valuenow={done}
            className="h-1 rounded-pill bg-track"
          >
            <div
              className="h-1 rounded-pill bg-accent"
              style={{ width: `${(100 * done) / total}%` }}
            />
          </div>
        </>
      ) : (
        <Body>{run.state === "queued" ? "Waiting to start." : "Looking for new activities."}</Body>
      ),
  };
}

function syncedToast(id, run) {
  const matched = run.activities.filter((activity) => activity.session).length;

  return {
    id,
    tone: "success",
    title: "Garmin synced",
    timeout: DONE_MS,
    body: (
      <>
        <Body>
          {plural(run.activities.length, "new activity", "new activities")}, {matched} matched to
          sessions.
        </Body>
        <ul className="m-0 flex list-none flex-col p-0">
          {run.activities.map((activity) => (
            <li
              key={activity.id}
              className="flex justify-between gap-3 border-t border-border py-1.5 text-caption"
            >
              <span>
                {formatWeekday(activity.local_date)} · {discipline(activity.discipline).activity}{" "}
                <span className="font-display font-semibold text-ink-muted">
                  {formatHoursMinutes(activity.duration_seconds)}
                </span>
              </span>
              {activity.session ? (
                <span className="text-state-done">
                  <span aria-hidden="true">✓ </span>
                  {activity.session.title}
                </span>
              ) : (
                <span className="text-ink-muted">Not in the plan</span>
              )}
            </li>
          ))}
        </ul>
        <Link
          to="/calendar"
          className="focus-ring self-start pt-0.5 text-caption font-semibold text-accent hover:text-accent-hover"
        >
          Open today
        </Link>
      </>
    ),
  };
}

function nothingNewToast(id, syncedAt) {
  return {
    id,
    tone: "success",
    title: "Garmin synced",
    timeout: NOTHING_NEW_MS,
    body: <Body>{syncedAt ? `Nothing new since ${formatMoment(syncedAt)}.` : "Nothing new."}</Body>,
  };
}

function unfinishedToast(id, run, retry) {
  const found = run.activities.length;

  return {
    id,
    tone: "caution",
    title: "The sync did not finish",
    body: (
      <>
        <Body>
          Garmin did not answer.
          {found > 0 &&
            ` The ${plural(found, "activity", "activities")} found ${found === 1 ? "is" : "are"} in.`}
        </Body>
        <Button variant="secondary" className="min-h-9 self-start text-caption" onClick={retry}>
          Try again
        </Button>
      </>
    ),
  };
}
