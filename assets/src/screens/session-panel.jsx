import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
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
import { shownStatus } from "../lib/plan.js";
import { kindLabel, sessionStats, stepRows, stepsOf, totalSeconds } from "../lib/structure.js";
import { Card } from "../ui/Card.jsx";
import { CoachNote } from "../ui/CoachNote.jsx";
import { DisciplineIcon } from "../ui/DisciplineIcon.jsx";
import { Stat } from "../ui/Stat.jsx";
import { SessionMark } from "../ui/Marks.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";
import { TrainingZoneBadge } from "../ui/TrainingZoneBadge.jsx";
import { TrainingZoneLegend } from "../ui/TrainingZoneLegend.jsx";
import { WorkoutProfile } from "../ui/WorkoutProfile.jsx";
import { ActivityRecord } from "./activity-record.jsx";
import { QueryContent } from "./query-content.jsx";

const orDash = (value, format) => (value ? format(value) : "—");

/** The session with `id`, once it loads, as `SessionView` shows it. */
export function SessionPanel({ id, today }) {
  const query = useQuery(sessionQuery(id));

  return (
    <QueryContent query={query} noun="session">
      {(session) => <SessionView session={session} today={today} />}
    </QueryContent>
  );
}

/** The activity with `id`, once it loads, as `ActivityView` shows it. */
export function ActivityPanel({ id }) {
  const query = useQuery(activityQuery(id));

  return (
    <QueryContent query={query} noun="activity">
      {(activity) => <ActivityView activity={activity} />}
    </QueryContent>
  );
}

/**
 * A session: what was planned, what was recorded against it, and the last one
 * like it. `plain` heads it without a card, for the phone's session page.
 */
export function SessionView({ session: stored, today, plain = false }) {
  const session = { ...stored, status: shownStatus(stored, stored.day.date, today) };
  const { activity, last_time: lastTime } = session;
  const steps = stepsOf(session.structure);

  return (
    <>
      <Hero
        discipline={session.discipline}
        label={sessionLabel(session, today)}
        title={session.title}
        note={session.structure?.note}
        state={session.status}
        plain={plain}
      >
        {activity ? (
          <Compare session={session} activity={activity} />
        ) : (
          <Stats stats={sessionStats(session)} />
        )}
      </Hero>
      {activity && <ActivityRecord activity={activity} />}
      {steps.length > 0 ? (
        <Structure steps={steps} rationale={session.rationale} />
      ) : (
        session.rationale && (
          <Card id="why" title="Why this session">
            <p className="m-0 text-sm leading-normal whitespace-pre-line">{session.rationale}</p>
          </Card>
        )
      )}
      {lastTime && <LastTime lastTime={lastTime} />}
    </>
  );
}

function sessionLabel(session, today) {
  const { activity } = session;
  if (activity) {
    const pool = activity.pool_length_m ? ` · ${Math.round(activity.pool_length_m)} m pool` : "";
    return `Completed ${formatStartTime(activity.started_at, activity.utc_offset_seconds)}${pool}`;
  }
  if (session.status === "skipped") return `Skipped · ${formatDay(session.day.date)}`;
  return session.day.date === today ? "Planned today" : `Planned · ${formatDay(session.day.date)}`;
}

/** An activity no session is matched to, as it was recorded. */
export function ActivityView({ activity, plain = false }) {
  return (
    <>
      <Hero
        discipline={activity.discipline}
        label={`Recorded ${formatStartTime(activity.started_at, activity.utc_offset_seconds)}`}
        title={disciplineOf(activity.discipline).label}
        state="extra"
        plain={plain}
      >
        <Stats stats={recordedStats(activity)} />
      </Hero>
      <ActivityRecord activity={activity} />
    </>
  );
}

function recordedStats(activity) {
  return [
    { label: "Duration", value: formatClock(activity.duration_seconds) },
    { label: "Distance", value: orDash(activity.distance_m, formatDistance) },
    { label: "Training load", value: orDash(activity.training_load, Math.round) },
    { label: "Avg heart rate", value: orDash(activity.avg_heart_rate, String) },
  ];
}

/**
 * The shown session or activity's heading, on a card tinted in its
 * discipline, or `plain` as the phone's page heading with its state's mark.
 */
function Hero({ discipline, label, title, note, state, plain, children }) {
  const style = disciplineOf(discipline);
  const Heading = plain ? "h1" : "h2";

  return (
    <section
      aria-labelledby="shown-heading"
      className={
        plain
          ? "flex flex-col gap-4"
          : `flex flex-col gap-5 rounded-card border p-5.5 ${style.tint} ${style.edge}`
      }
    >
      <div className="flex items-start gap-3.5">
        <span
          className={`grid flex-none place-items-center rounded-tile ${style.tile} ${plain ? "size-12" : "size-13"}`}
        >
          <DisciplineIcon discipline={discipline} size={plain ? 26 : 28} />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-1">
          <span className={`text-label font-semibold uppercase ${style.text}`}>{label}</span>
          <Heading
            id="shown-heading"
            className={`m-0 font-bold tracking-tight ${plain ? "text-[26px] leading-tight" : "text-3xl"}`}
          >
            {title}
          </Heading>
          {note && <span className="text-sm text-ink-soft">{note}</span>}
        </div>
        {plain ? (
          <SessionMark state={state} discipline={discipline} size={24} />
        ) : (
          (state === "done" || state === "skipped") && <StatusChip state={state} />
        )}
      </div>
      {children}
    </section>
  );
}

function Stats({ stats }) {
  return (
    <div
      role="group"
      aria-label="Summary"
      className="grid grid-cols-[repeat(auto-fit,minmax(6.5rem,1fr))] gap-3"
    >
      {stats.map((stat) => (
        <Stat key={stat.label} value={stat.value} label={stat.label} />
      ))}
    </div>
  );
}

function Compare({ session, activity }) {
  const rows = [
    {
      label: "Duration",
      actual: formatClock(activity.duration_seconds),
      plan: formatPlanned(session.planned_seconds),
    },
    ...recordedStats(activity)
      .slice(1)
      .map((stat) => ({ label: stat.label, actual: stat.value })),
  ];

  return (
    <div
      role="group"
      aria-label="Planned and recorded"
      className="grid grid-cols-[repeat(auto-fit,minmax(6.5rem,1fr))] gap-x-3 gap-y-4"
    >
      {rows.map((row) => (
        <div key={row.label} className="flex min-w-0 flex-col gap-1">
          <Stat value={row.actual} label={row.label} />
          {row.plan && (
            <span className="font-display text-sm text-ink-muted tabular-nums">
              plan {row.plan}
            </span>
          )}
        </div>
      ))}
    </div>
  );
}

function Structure({ steps, rationale }) {
  return (
    <Card id="structure" title="Structure" aside={formatPlanned(totalSeconds(steps))}>
      <div className="border-b border-border-strong">
        <WorkoutProfile steps={steps} />
      </div>
      <div className="flex justify-between font-display text-xs text-ink-muted tabular-nums">
        <span>0′</span>
        <span>{formatPlanned(totalSeconds(steps))}</span>
      </div>
      <TrainingZoneLegend />
      <div className="grid items-start gap-6 lg:grid-cols-2">
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
        {rationale && <CoachNote>{rationale}</CoachNote>}
      </div>
    </Card>
  );
}

function stepName(step) {
  const kind = kindLabel(step.kind);
  const name = kind[0].toUpperCase() + kind.slice(1);
  return step.note ? `${name}, ${step.note}` : name;
}

function LastTime({ lastTime }) {
  return (
    <Card
      id="last-time"
      title="Last time"
      aside={
        <Link
          to="/sessions/$id"
          params={{ id: lastTime.session_id }}
          className="text-sm font-semibold"
        >
          {formatDay(lastTime.date)}
        </Link>
      }
    >
      <div className="grid grid-cols-[repeat(auto-fit,minmax(6.5rem,1fr))] gap-3">
        {recordedStats(lastTime.activity).map((stat) => (
          <Stat key={stat.label} value={stat.value} label={stat.label} size="md" />
        ))}
      </div>
    </Card>
  );
}
