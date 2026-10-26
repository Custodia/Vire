import { useId } from "react";
import { useQuery } from "@tanstack/react-query";
import { getRouteApi } from "@tanstack/react-router";
import { activityQuery, sessionQuery } from "../api/queries.js";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import {
  formatClock,
  formatDay,
  formatDistance,
  formatPlanned,
  formatStartTime,
  formatStepDuration,
} from "../lib/format.js";
import { kindLabel, sessionStats, stepRows, stepsOf, totalSeconds } from "../lib/structure.js";
import { CoachNote } from "../ui/CoachNote.jsx";
import { DisciplineIcon } from "../ui/DisciplineIcon.jsx";
import { Screen } from "../ui/Screen.jsx";
import { Stat } from "../ui/Stat.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";
import { TrainingZoneBadge } from "../ui/TrainingZoneBadge.jsx";
import { TrainingZoneLegend } from "../ui/TrainingZoneLegend.jsx";
import { WorkoutProfile } from "../ui/WorkoutProfile.jsx";
import { ActivityRecord } from "./activity-record.jsx";
import { DayBackLink } from "./day-view.jsx";
import { QueryContent } from "./query-content.jsx";

const sessionRoute = getRouteApi("/authenticated/sessions/$id");
const activityRoute = getRouteApi("/authenticated/activities/$id");

const statusLabels = { planned: "Planned", done: "Done", skipped: "Skipped" };

export function SessionScreen() {
  const { id } = sessionRoute.useParams();
  const query = useQuery(sessionQuery(id));

  return (
    <Screen>
      <DayBackLink date={query.data?.day.date} />
      <QueryContent query={query} noun="session">
        {(session) => <SessionView session={session} />}
      </QueryContent>
    </Screen>
  );
}

export function ActivityScreen() {
  const { id } = activityRoute.useParams();
  const query = useQuery(activityQuery(id));

  return (
    <Screen>
      <DayBackLink date={query.data?.local_date} />
      <QueryContent query={query} noun="activity">
        {(activity) => <ActivityView activity={activity} />}
      </QueryContent>
    </Screen>
  );
}

function SessionView({ session }) {
  const { activity } = session;
  const steps = stepsOf(session.structure);
  const status = activity
    ? `Completed ${formatStartTime(activity.started_at, activity.utc_offset_seconds)}`
    : statusLabels[session.status];

  return (
    <>
      <Header
        discipline={session.discipline}
        label={`${formatDay(session.day.date)} · ${status}`}
        title={session.title}
        state={session.status === "planned" ? null : session.status}
      />
      {activity ? (
        <>
          <PlannedAgainstActual session={session} activity={activity} />
          <ActivityRecord activity={activity} />
        </>
      ) : (
        <StatCards stats={sessionStats(session)} />
      )}
      {steps.length > 0 && <Structure steps={steps} />}
      {session.rationale && <CoachNote>{session.rationale}</CoachNote>}
    </>
  );
}

function ActivityView({ activity }) {
  const stats = [
    { label: "Duration", value: formatClock(activity.duration_seconds) },
    activity.distance_m && { label: "Distance", value: formatDistance(activity.distance_m) },
    activity.training_load && {
      label: "Training load",
      value: Math.round(activity.training_load),
    },
  ].filter(Boolean);

  return (
    <>
      <Header
        discipline={activity.discipline}
        label={`${formatDay(activity.local_date)} · ${formatStartTime(activity.started_at, activity.utc_offset_seconds)}`}
        title={disciplineOf(activity.discipline).label}
      />
      <StatCards stats={stats} />
      <ActivityRecord activity={activity} />
    </>
  );
}

function Header({ discipline, label, title, state }) {
  return (
    <header className="flex items-center gap-3.5">
      <span
        className={`grid size-12 flex-none place-items-center rounded-tile ${disciplineOf(discipline).tile}`}
      >
        <DisciplineIcon discipline={discipline} size={26} />
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-label font-semibold text-ink-muted uppercase">{label}</span>
        <h1 className="m-0 text-2xl font-bold tracking-tight">{title}</h1>
      </div>
      {state && <StatusChip state={state} />}
    </header>
  );
}

function StatCards({ stats }) {
  return (
    <div role="group" aria-label="Summary" className="grid grid-cols-3 gap-2">
      {stats.map((stat) => (
        <div key={stat.label} className="rounded-card border border-border bg-surface p-3">
          <Stat value={stat.value} label={stat.label} size="md" />
        </div>
      ))}
    </div>
  );
}

function PlannedAgainstActual({ session, activity }) {
  const rows = [
    ["Duration", formatPlanned(session.planned_seconds), formatClock(activity.duration_seconds)],
    ["Distance", "—", activity.distance_m ? formatDistance(activity.distance_m) : "—"],
  ];

  return (
    <section className="overflow-hidden rounded-card border border-border bg-surface">
      <table className="w-full border-collapse">
        <caption className="sr-only">Planned against actual</caption>
        <thead>
          <tr className="text-xs text-ink-muted">
            <td className="px-4.5 pt-3 pb-2" />
            <th scope="col" className="w-20 pt-3 pb-2 text-right font-normal">
              Planned
            </th>
            <th scope="col" className="w-24 pt-3 pr-4.5 pb-2 text-right font-normal">
              Actual
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map(([name, planned, actual]) => (
            <tr key={name} className="border-t border-divider">
              <th scope="row" className="px-4.5 py-2.5 text-left text-sm font-normal">
                {name}
              </th>
              <td className="py-2.5 text-right font-display text-lg text-ink-muted tabular-nums">
                {planned}
              </td>
              <td className="py-2.5 pr-4.5 text-right font-display text-lg tabular-nums">
                {actual}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

function Structure({ steps }) {
  const titleId = useId();

  return (
    <section
      aria-labelledby={titleId}
      className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4.5"
    >
      <h2 id={titleId} className="m-0 text-label font-semibold text-ink-muted uppercase">
        Structure
      </h2>
      <div className="border-b border-border-strong">
        <WorkoutProfile steps={steps} />
      </div>
      <div className="flex justify-between font-display text-xs text-ink-muted tabular-nums">
        <span>0′</span>
        <span>{formatPlanned(totalSeconds(steps))}</span>
      </div>
      <TrainingZoneLegend />
      <ol aria-label="Steps" className="m-0 flex list-none flex-col p-0">
        {stepRows(steps).map((step, index) => (
          <li key={index} className="flex items-center gap-2.5 border-t border-divider py-2.25">
            {step.zone ? (
              <TrainingZoneBadge zone={step.zone} />
            ) : (
              <span aria-hidden="true" className="w-7.5 flex-none" />
            )}
            <span className="min-w-14 flex-none font-display text-base text-ink-muted tabular-nums">
              {step.times}
              {formatStepDuration(step.seconds)}
            </span>
            <span className="flex-1 text-sm">{stepName(step)}</span>
            {step.target && (
              <span className="font-display text-base tabular-nums">{step.target}</span>
            )}
          </li>
        ))}
      </ol>
    </section>
  );
}

function stepName(step) {
  const kind = kindLabel(step.kind);
  const name = kind[0].toUpperCase() + kind.slice(1);
  return step.note ? `${name}, ${step.note}` : name;
}
