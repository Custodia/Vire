/** A link back to the screen a page belongs to, linking through `as` and `linkProps`. */
export function BackLink({ children, as: LinkComponent = "a", linkProps }) {
  return (
    <LinkComponent
      aria-label={`Back to ${children}`}
      className="focus-ring inline-flex min-h-11 items-center gap-1 self-start rounded-chip text-sm font-semibold text-ink-muted no-underline hover:text-ink"
      {...linkProps}
    >
      <svg
        aria-hidden="true"
        width="20"
        height="20"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M15 6l-6 6 6 6" />
      </svg>
      {children}
    </LinkComponent>
  );
}
