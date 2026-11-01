const sizes = {
  lg: "text-3xl",
  md: "text-2xl",
};

const tones = {
  ink: "",
  accent: "text-accent",
  muted: "text-ink-faint",
};

/** A large tabular number over its label, with what it counts towards in `of`. */
export function Stat({ value, of, label, size = "lg", tone = "ink" }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span
        className={`font-display leading-none font-semibold tracking-wide tabular-nums ${sizes[size]} ${tones[tone]}`}
      >
        {value}
        {of != null && <span className="text-lg text-ink-muted"> of {of}</span>}
      </span>
      <span className="text-xs text-ink-muted">{label}</span>
    </div>
  );
}
