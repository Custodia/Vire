import { zone as zoneOf } from "../lib/zones.js";

/** The five training zones, each as its colour beside its number and name. */
export function TrainingZoneLegend() {
  return (
    <ul aria-label="Training zones" className="m-0 flex list-none flex-wrap gap-3 p-0">
      {[1, 2, 3, 4, 5].map((number) => {
        const { name, bg } = zoneOf(number);
        return (
          <li key={number} className="inline-flex items-center gap-1.5 text-xs text-ink-muted">
            <span aria-hidden="true" className={`size-2.5 rounded-bar ${bg}`} />Z{number} {name}
          </li>
        );
      })}
    </ul>
  );
}
