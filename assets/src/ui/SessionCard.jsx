import { useId } from "react";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import { sessionStats, stepsOf } from "../lib/structure.js";
import { DisciplineIcon } from "./DisciplineIcon.jsx";
import { Stat } from "./Stat.jsx";
import { WorkoutProfile } from "./WorkoutProfile.jsx";

/**
 * The large card of an upcoming session: its discipline and place in the day,
 * title, note, up to three stats and its workout profile. The title links to
 * the session through `as` and `linkProps`, and the link covers the card.
 */
export function SessionCard({ session, lead, place, as: LinkComponent = "a", linkProps }) {
  const titleId = useId();
  const style = disciplineOf(session.discipline);
  const steps = stepsOf(session.structure);
  const note = typeof session.structure?.note === "string" ? session.structure.note : null;

  return (
    <article
      aria-labelledby={titleId}
      className={`relative flex w-79 flex-none snap-start flex-col gap-4 rounded-card border p-5 ${style.tint} ${style.edge}`}
    >
      <div className="flex items-center justify-between gap-2">
        <span
          className={`inline-flex items-center gap-2 text-xs font-bold tracking-wider uppercase ${style.text}`}
        >
          <DisciplineIcon discipline={session.discipline} />
          {lead}
        </span>
        {place && <span className="text-xs text-ink-muted">{place}</span>}
      </div>
      <div className="flex flex-col gap-1">
        <h3 id={titleId} className="m-0 text-title font-bold tracking-tight">
          <LinkComponent
            className="focus-ring rounded-chip text-ink no-underline after:absolute after:inset-0"
            {...linkProps}
          >
            {session.title}
          </LinkComponent>
        </h3>
        {note && <p className="m-0 text-sm text-ink-soft">{note}</p>}
      </div>
      <div className="grid grid-cols-3 gap-2">
        {sessionStats(session).map((stat) => (
          <Stat key={stat.label} value={stat.value} label={stat.label} />
        ))}
      </div>
      {steps.length > 0 && <WorkoutProfile steps={steps} className="h-10" />}
    </article>
  );
}
