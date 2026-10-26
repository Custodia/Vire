import { zone as zoneOf } from "../lib/zones.js";

/** A training zone as a coloured badge, Z1 to Z5. */
export function TrainingZoneBadge({ zone }) {
  const { name, bg } = zoneOf(zone);

  return (
    <span
      className={`inline-block w-7.5 flex-none rounded-chip py-0.5 text-center text-label font-bold text-ink-inverse ${bg}`}
    >
      Z{zone}
      <span className="sr-only"> {name}</span>
    </span>
  );
}
