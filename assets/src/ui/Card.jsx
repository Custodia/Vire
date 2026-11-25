/** A board's card: a surface with a heading, an optional note beside it, and its content. */
export function Card({ id, title, aside, className = "", children }) {
  const headingId = `${id}-heading`;

  return (
    <section
      aria-labelledby={headingId}
      className={`flex min-w-0 flex-col gap-3 rounded-card border border-border bg-surface px-5.5 py-5 ${className}`}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 id={headingId} className="m-0 text-lg font-bold">
          {title}
        </h2>
        {aside && <div className="text-xs text-ink-muted">{aside}</div>}
      </div>
      {children}
    </section>
  );
}
