import { useQuery } from "@tanstack/react-query";
import { Button as AriaButton, Heading } from "react-aria-components";
import { meQuery } from "../api/queries.js";
import { buttonClass } from "../ui/Button.jsx";
import { Sheet } from "../ui/Sheet.jsx";
import { Spinner } from "../ui/Spinner.jsx";
import { useSignOut } from "./sign-out.jsx";
import { syncStanding, useSyncNow, useSyncing } from "./sync.jsx";

const icon = (d) => (
  <svg
    aria-hidden="true"
    width="20"
    height="20"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
  >
    <path d={d} />
  </svg>
);

const row = "flex min-h-14 items-center gap-3 border-t border-divider px-1 py-3";
const tile = "grid size-10 flex-none place-items-center rounded-tile";

/**
 * The phone's More sheet: who is signed in, Garmin syncing with Sync now,
 * Upload .fit, which calls `onUpload`, and Sign out.
 */
export function MoreSheet({ isOpen, onOpenChange, onUpload }) {
  return (
    <Sheet isOpen={isOpen} onOpenChange={onOpenChange} className="gap-0">
      {() => <More onUpload={onUpload} />}
    </Sheet>
  );
}

function More({ onUpload }) {
  const me = useQuery(meQuery).data;
  const signOut = useSignOut();

  return (
    <>
      <div className="flex items-center gap-3 px-1 pt-3 pb-3.5">
        <span
          aria-hidden="true"
          className="grid size-11 flex-none place-items-center rounded-pill bg-phase font-bold text-phase-ink"
        >
          {(me?.name || me?.email || "?")[0].toUpperCase()}
        </span>
        <div className="flex min-w-0 flex-col">
          <Heading slot="title" className="m-0 truncate text-[17px] font-bold">
            {me?.name || me?.email}
          </Heading>
          {me?.name && <span className="truncate text-caption text-ink-muted">{me.email}</span>}
        </div>
      </div>
      <Garmin />
      <AriaButton onPress={onUpload} className={`focus-ring ${row} w-full text-left`}>
        <span className={`${tile} bg-surface-raised text-ink-soft`}>
          {icon("M12 16V4M7 9l5-5 5 5M5 20h14")}
        </span>
        <span className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="text-row font-semibold">Upload .fit</span>
          <span className="text-caption text-ink-muted">From Files, a watch or bike computer</span>
        </span>
        {icon("M9 6l6 6-6 6")}
      </AriaButton>
      <AriaButton
        onPress={() => signOut.mutate()}
        isDisabled={signOut.isPending}
        className={`focus-ring ${row} w-full text-left text-ink-muted`}
      >
        <span className={`${tile} bg-surface-raised`}>
          {icon("M10 8l-4 4 4 4M6 12h9M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4")}
        </span>
        <span className="text-row font-semibold">Sign out</span>
      </AriaButton>
    </>
  );
}

const lines = {
  paused: "Paused",
  syncing: "Syncing…",
};

function Garmin() {
  const { status, busy } = useSyncing();
  const syncNow = useSyncNow();
  const standing = syncStanding(status, busy);
  if (!status || status.connection === "none") return null;

  return (
    <div className={row}>
      <span className={`${tile} bg-accent-tint text-accent`}>
        {busy ? (
          <Spinner size={18} />
        ) : (
          icon("M20 11a8 8 0 0 0-14.3-4.9L4 8M4 4v4h4M4 13a8 8 0 0 0 14.3 4.9L20 16M20 20v-4h-4")
        )}
      </span>
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-row font-semibold">Garmin</span>
        <span className="text-caption text-ink-muted">
          {standing?.state === "synced"
            ? `Synced ${standing.at}`
            : (lines[standing?.state] ?? "Not synced yet")}
        </span>
      </span>
      <AriaButton
        onPress={() => syncNow.mutate()}
        isDisabled={busy || status.connection === "paused"}
        className={buttonClass("secondary", "flex-none")}
      >
        Sync now
      </AriaButton>
    </div>
  );
}
