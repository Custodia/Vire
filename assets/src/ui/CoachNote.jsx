/** The reasoning behind a session, as the coach wrote it. */
export function CoachNote({ children, label = "Why this session" }) {
  return (
    <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4.5">
      <h2 className="m-0 text-label font-semibold text-ink-muted uppercase">{label}</h2>
      <p className="m-0 text-sm leading-normal whitespace-pre-line">{children}</p>
    </section>
  );
}
