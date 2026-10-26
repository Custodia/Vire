import { Link } from "@tanstack/react-router";
import { Screen } from "../ui/Screen.jsx";

export function PlaceholderScreen({ title }) {
  return (
    <Screen>
      <Link
        to="/today"
        className="focus-ring inline-flex min-h-11 items-center self-start rounded-chip text-sm font-semibold text-ink-muted no-underline hover:text-ink"
      >
        ‹ Today
      </Link>
      <h1 className="m-0 text-3xl font-bold tracking-tight">{title}</h1>
      <p className="m-0 text-sm text-ink-soft">This screen is not built yet.</p>
    </Screen>
  );
}
