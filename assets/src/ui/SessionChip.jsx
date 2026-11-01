import { discipline as disciplineOf } from "../lib/disciplines.js";
import { formatPlanned } from "../lib/format.js";

const base =
  "block truncate rounded-chip border px-1.5 py-0.5 text-label font-semibold tracking-normal";

const states = {
  done: {
    mark: "✓ ",
    name: "Done: ",
    className: "border-state-done-edge bg-state-done-tint text-state-done",
  },
  skipped: {
    mark: "✕ ",
    name: "Skipped: ",
    className: "border-state-skipped-edge bg-state-skipped-tint text-state-skipped line-through",
  },
};

/** A session in a calendar day: done and skipped in their state, upcoming in its sport. */
export function SessionChip({ session }) {
  const label = `${session.title} ${formatPlanned(session.planned_seconds)}`;
  const state = states[session.status];

  if (state) {
    return (
      <span title={label} className={`${base} ${state.className}`}>
        <span aria-hidden="true">{state.mark}</span>
        <span className="sr-only">{state.name}</span>
        {label}
      </span>
    );
  }

  const { tile, soft } = disciplineOf(session.discipline);
  return (
    <span title={label} className={`${base} border-transparent ${tile} ${soft}`}>
      {label}
    </span>
  );
}

/** A rest day in a calendar, ticked once it is `kept`. */
export function RestChip({ kept = false }) {
  return kept ? (
    <span className={`${base} border-dashed border-state-rest-kept text-state-rest-kept`}>
      <span aria-hidden="true">✓ </span>
      Rest<span className="sr-only"> day kept</span>
    </span>
  ) : (
    <span className={`${base} border-dashed border-rule text-ink-muted`}>Rest</span>
  );
}
