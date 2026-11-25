/** A spinning arc on a faint ring, for work under way; its label comes from beside it. */
export function Spinner({ size = 16 }) {
  return (
    <svg
      aria-hidden="true"
      width={size}
      height={size}
      viewBox="0 0 16 16"
      className="flex-none motion-safe:animate-spin"
    >
      <circle cx="8" cy="8" r="6" fill="none" stroke="var(--color-border-strong)" strokeWidth="2" />
      <path
        d="M8 2a6 6 0 0 1 6 6"
        fill="none"
        stroke="var(--color-accent)"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}
