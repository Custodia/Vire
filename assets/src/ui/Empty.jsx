/** A card's placeholder for what it has nothing of yet. */
export function Empty({ children }) {
  return (
    <p className="m-0 rounded-tile border border-dashed border-border-strong px-4 py-3.5 text-sm text-ink-muted">
      {children}
    </p>
  );
}
