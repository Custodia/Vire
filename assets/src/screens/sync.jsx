import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ApiError, postSync } from "../api/client.js";
import { Button } from "../ui/Button.jsx";

const reasons = {
  not_connected: "Sync did not start: no Garmin connection is set up.",
  paused: "Sync did not start: the Garmin connection is paused.",
};

function message(mutation) {
  if (mutation.isSuccess) return "A sync was queued.";
  if (mutation.error instanceof ApiError && mutation.error.status === 409) {
    return reasons[mutation.error.body?.reason] ?? "Sync did not start.";
  }
  if (mutation.isError) return "Sync could not be queued.";
  return null;
}

/** The Sync now action and the line saying what happened to it. */
export function SyncButton() {
  const queryClient = useQueryClient();
  const mutation = useMutation({
    mutationFn: postSync,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["days"] }),
  });

  return (
    <>
      <Button variant="secondary" onClick={() => mutation.mutate()} disabled={mutation.isPending}>
        Sync now
      </Button>
      <p role="status" className="m-0 w-full text-caption text-ink-soft empty:hidden">
        {message(mutation)}
      </p>
    </>
  );
}
