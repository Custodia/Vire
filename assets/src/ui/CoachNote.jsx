/** The coach's reasoning on a card, under its label. */
export function CoachNote({ children, label = "Why this session" }) {
  return (
    <div className="flex flex-col gap-2 rounded-tile bg-surface-raised p-3.5">
      <span className="text-label font-semibold text-ink-muted uppercase">{label}</span>
      <p className="m-0 text-sm leading-normal whitespace-pre-line">{children}</p>
    </div>
  );
}
