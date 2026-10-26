import { discipline as disciplineOf } from "../lib/disciplines.js";
import { DisciplineIcon } from "./DisciplineIcon.jsx";
import { StatusChip } from "./StatusChip.jsx";

/**
 * The compact row of a session or activity: its discipline, title, a detail
 * line and its state, linking through `as` and `linkProps`.
 */
export function SessionRow({
  discipline,
  title,
  detail,
  state,
  as: LinkComponent = "a",
  linkProps,
}) {
  const style = disciplineOf(discipline);

  return (
    <LinkComponent
      className="focus-ring flex min-h-11 items-center gap-3 rounded-card border border-border bg-surface px-4 py-3.5 text-ink no-underline hover:bg-surface-raised"
      {...linkProps}
    >
      <span className={`grid size-10 flex-none place-items-center rounded-tile ${style.tile}`}>
        <DisciplineIcon discipline={discipline} size={22} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="truncate text-row font-semibold">{title}</span>
        {detail && <span className="text-caption text-ink-muted">{detail}</span>}
      </span>
      {state && <StatusChip state={state} />}
    </LinkComponent>
  );
}
