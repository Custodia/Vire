import { Spinner } from "./Spinner.jsx";

const tones = {
  busy: { tile: "bg-accent-tint", icon: <Spinner size={18} /> },
  success: {
    tile: "bg-state-done-tint text-state-done",
    icon: (
      <svg
        aria-hidden="true"
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M5 12.5l4.5 4.5L19 7.5" />
      </svg>
    ),
  },
  caution: {
    tile: "bg-caution-tint text-caution",
    icon: (
      <svg
        aria-hidden="true"
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
      >
        <path d="M12 7v6M12 16.5v.5" />
      </svg>
    ),
  },
};

/**
 * A card over the page: a tile of its tone, a title, whatever `children` holds
 * and a Hide button. A caution card is an alert; the others are a status.
 */
export function Toast({ tone, title, children, onHide, ...props }) {
  const { tile, icon } = tones[tone];

  return (
    <div
      role={tone === "caution" ? "alert" : "status"}
      className="flex items-start gap-3 rounded-card border border-border-strong bg-surface-raised py-3.5 pr-3 pl-3.5 shadow-[0_12px_30px_rgba(0,0,0,0.5)]"
      {...props}
    >
      <span className={`grid size-9 flex-none place-items-center rounded-tile ${tile}`}>
        {icon}
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <span className="text-sm font-bold">{title}</span>
        {children}
      </div>
      <button
        type="button"
        aria-label="Hide"
        onClick={onHide}
        className="focus-ring -my-2.5 -mr-1.5 grid size-11 flex-none place-items-center rounded-tile text-ink-muted hover:text-ink"
      >
        <svg
          aria-hidden="true"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        >
          <path d="M6 6l12 12M18 6L6 18" />
        </svg>
      </button>
    </div>
  );
}
