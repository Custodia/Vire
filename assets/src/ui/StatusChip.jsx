const states = {
  done: {
    label: "Done",
    mark: "✓ ",
    className: "border-solid border-state-done-edge bg-state-done-tint text-state-done",
  },
  skipped: {
    label: "Skipped",
    mark: "✕ ",
    className: "border-solid border-state-skipped-edge bg-state-skipped-tint text-state-skipped",
  },
  upcoming: {
    label: "Upcoming",
    mark: "",
    className: "border-solid border-state-upcoming-edge bg-state-upcoming-tint text-state-upcoming",
  },
  rest: {
    label: "Rest",
    mark: "",
    className: "border-dashed border-state-rest-edge bg-state-rest-tint text-state-rest",
  },
};

/** A session's state as a small chip: done, skipped, upcoming or rest. */
export function StatusChip({ state }) {
  const { label, mark, className } = states[state];

  return (
    <span
      className={`inline-flex flex-none items-center rounded-chip border px-1.5 py-0.5 text-label font-semibold ${className}`}
    >
      {mark && <span aria-hidden="true">{mark}</span>}
      {label}
    </span>
  );
}
