const sizes = {
  lg: "text-3xl",
  md: "text-2xl",
};

/** A large tabular number over its label. */
export function Stat({ value, label, size = "lg" }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span
        className={`font-display leading-none font-semibold tracking-wide tabular-nums ${sizes[size]}`}
      >
        {value}
      </span>
      <span className="text-xs text-ink-muted">{label}</span>
    </div>
  );
}
