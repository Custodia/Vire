import { ApiError } from "../api/client.js";
import { Button } from "../ui/Button.jsx";

/** A query's data through `children` once it arrives, and what to show while it loads or fails. */
export function QueryContent({ query, noun, children }) {
  if (query.isPending) {
    return (
      <p role="status" className="m-0 text-sm text-ink-muted">
        Loading the {noun}…
      </p>
    );
  }

  if (query.error instanceof ApiError && query.error.status === 404) {
    return (
      <>
        <h1 className="m-0 text-3xl font-bold tracking-tight">Not found</h1>
        <p className="m-0 text-sm text-ink-soft">There is no such {noun} in your account.</p>
      </>
    );
  }

  if (query.isError) {
    return (
      <div className="flex flex-col items-start gap-3">
        <p role="alert" className="m-0 text-sm text-ink-soft">
          The {noun} could not be loaded.
        </p>
        <Button variant="secondary" onClick={() => query.refetch()}>
          Try again
        </Button>
      </div>
    );
  }

  return children(query.data);
}
