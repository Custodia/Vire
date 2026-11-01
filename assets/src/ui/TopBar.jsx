import { Link } from "@tanstack/react-router";

/**
 * The bar of every signed-in screen on a desktop: the wordmark, the screens in
 * `links`, each `{ to, label, current }`, and whatever `actions` holds.
 */
export function TopBar({ links, actions }) {
  return (
    <header className="border-b border-divider">
      <div className="mx-auto flex max-w-board items-center gap-6 px-8 py-3.5">
        <span className="text-xl font-bold tracking-tight">vire</span>
        <nav aria-label="Primary" className="flex flex-1 gap-0.5">
          {links.map(({ to, label, current }) => (
            <Link
              key={to}
              to={to}
              aria-current={current ? "page" : undefined}
              className={`focus-ring inline-flex min-h-11 items-center rounded-tile px-3.5 text-sm font-semibold no-underline hover:bg-surface ${
                current ? "bg-surface text-accent" : "text-ink-muted hover:text-ink"
              }`}
            >
              {label}
            </Link>
          ))}
        </nav>
        <div className="flex items-center gap-2">{actions}</div>
      </div>
    </header>
  );
}
