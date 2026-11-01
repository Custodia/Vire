import { useSyncExternalStore } from "react";

const DESKTOP = "(min-width: 64rem)";

function subscribe(onChange) {
  const query = window.matchMedia(DESKTOP);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

/** Whether the window is wide enough for the desktop layout, following it as it resizes. */
export function useIsDesktop() {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(DESKTOP).matches,
    () => true,
  );
}
