import { discipline as disciplineOf } from "../lib/disciplines.js";

const shapes = {
  swim: (
    <>
      <path d="M2 15c2 0 2-1.5 4-1.5S8 15 10 15s2-1.5 4-1.5 2 1.5 4 1.5 2-1.5 4-1.5M2 19.5c2 0 2-1.5 4-1.5s2 1.5 4 1.5 2-1.5 4-1.5 2 1.5 4 1.5 2-1.5 4-1.5" />
      <circle cx="16" cy="6" r="2" />
      <path d="M5 11l5-4 3 3" />
    </>
  ),
  bike: (
    <>
      <circle cx="5.5" cy="16.5" r="3.5" />
      <circle cx="18.5" cy="16.5" r="3.5" />
      <path d="M5.5 16.5L9 9h6l3.5 7.5M9 9l4 7.5M8 6h3" />
    </>
  ),
  run: (
    <>
      <circle cx="14" cy="4" r="2" />
      <path d="M8 21l3-6 3 2v5M6 11l4-3 4 2 3 3" />
    </>
  ),
  strength: <path d="M4 9v6M8 7v10M16 7v10M20 9v6M8 12h8" />,
  other: <path d="M3 12h4l2-5 4 10 2-5h6" />,
};

/** A discipline's line icon in its colour, named for assistive technology. */
export function DisciplineIcon({ discipline, size = 18, className = "" }) {
  const { label, text } = disciplineOf(discipline);

  return (
    <svg
      role="img"
      aria-label={label}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={`flex-none ${text} ${className}`}
    >
      {shapes[discipline] ?? shapes.other}
    </svg>
  );
}
