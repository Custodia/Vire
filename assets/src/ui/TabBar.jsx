import { Link } from "@tanstack/react-router";
import { Button as AriaButton } from "react-aria-components";

/** Places a bar fixed to the bottom of the screen just above the tab bar. */
export const aboveTabs = "bottom-[calc(3.5rem+1px+max(0.5rem,env(safe-area-inset-bottom)))]";

const tab =
  "focus-ring flex min-h-12.5 flex-col items-center justify-center gap-1 rounded-tile text-[11px] font-semibold no-underline";

/**
 * The tab bar of every signed-in screen on a phone: the screens in `links`,
 * each `{ to, label, icon, current }` with the icon's SVG shapes, and a More
 * tab that calls `onMore`.
 */
export function TabBar({ links, moreOpen, onMore }) {
  return (
    <nav
      aria-label="Primary"
      className="fixed inset-x-0 bottom-0 z-30 grid grid-cols-3 border-t border-divider bg-ground px-3 pt-1.5 pb-[max(0.5rem,env(safe-area-inset-bottom))]"
    >
      {links.map(({ to, label, icon, current }) => (
        <Link
          key={to}
          to={to}
          aria-current={current ? "page" : undefined}
          className={`${tab} ${current ? "text-accent" : "text-ink-muted"}`}
        >
          <svg
            aria-hidden="true"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            {icon}
          </svg>
          {label}
        </Link>
      ))}
      <AriaButton
        onPress={onMore}
        aria-expanded={moreOpen}
        className={`${tab} ${moreOpen ? "text-accent" : "text-ink-muted"}`}
      >
        <svg aria-hidden="true" width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
          <circle cx="5.5" cy="12" r="1.8" />
          <circle cx="12" cy="12" r="1.8" />
          <circle cx="18.5" cy="12" r="1.8" />
        </svg>
        More
      </AriaButton>
    </nav>
  );
}
