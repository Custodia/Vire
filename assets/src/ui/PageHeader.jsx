/** A screen's heading: a label over the title and a line under it, with its figures beside. */
export function PageHeader({ label, title, detail, children }) {
  return (
    <header className="flex flex-wrap items-end justify-between gap-x-10 gap-y-5">
      <div className="flex min-w-0 flex-col gap-1.5">
        {label && (
          <span className="text-label font-semibold text-ink-muted uppercase">{label}</span>
        )}
        <h1 className="m-0 text-4xl font-bold tracking-tight">{title}</h1>
        {detail && <span className="text-sm text-ink-muted">{detail}</span>}
      </div>
      {children && <div className="flex flex-wrap gap-7">{children}</div>}
    </header>
  );
}
