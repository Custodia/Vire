const variants = {
  primary: "bg-accent text-ink-inverse hover:bg-accent-hover",
  secondary: "border border-border bg-surface text-ink hover:bg-surface-raised",
  quiet: "text-ink-muted hover:text-ink",
};

/** A button at least 44 px tall with a visible focus ring. */
export function Button({ variant = "primary", type = "button", className = "", ...props }) {
  return (
    <button
      type={type}
      className={`focus-ring inline-flex min-h-11 min-w-11 items-center justify-center gap-2 rounded-tile px-4 text-sm font-semibold disabled:opacity-60 ${variants[variant]} ${className}`}
      {...props}
    />
  );
}
