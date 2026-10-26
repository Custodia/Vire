import { Link } from "@tanstack/react-router";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import { formatClock, formatDistance, formatPlanned, formatStartTime } from "../lib/format.js";
import { Button } from "../ui/Button.jsx";
import { CoachNote } from "../ui/CoachNote.jsx";
import { SessionCard } from "../ui/SessionCard.jsx";
import { SessionRow } from "../ui/SessionRow.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";

const cycleKinds = { load: "Load cycle", recovery: "Recovery cycle" };

/** The plan above a day in one line: phase, block, cycle and the day's place in it. */
function chainLine(day) {
  const { phase, block, cycle } = day.chain;
  return [
    phase.name,
    block.focus,
    cycleKinds[cycle.kind],
    `Day ${cycle.day_number} of ${cycle.length}`,
  ].join(" · ");
}

/** A day's sessions, its rest or out-of-plan state, and its unmatched activities. */
function DayView({ data }) {
  const { day, activities } = data;

  return (
    <>
      {day ? <DayPlan day={day} /> : <OutsidePlan />}
      {day?.note && <CoachNote label="Day note">{day.note}</CoachNote>}
      <Activities activities={activities} heading={day ? "Other activities" : "Activities"} />
    </>
  );
}

function DayPlan({ day }) {
  const { sessions } = day;
  if (sessions.length === 0) return <NoSessions rest={day.kind === "rest"} />;

  const done = sessions.filter((session) => session.status === "done").length;
  const planned = sessions.reduce((sum, session) => sum + (session.planned_seconds ?? 0), 0);
  const upcoming = sessions.filter((session) => session.status === "planned");
  const finished = sessions.filter((session) => session.status !== "planned");

  return (
    <section aria-labelledby="sessions-heading" className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between gap-2">
        <h2 id="sessions-heading" className="m-0 text-label font-semibold text-ink-muted uppercase">
          Sessions
        </h2>
        <span className="text-xs text-ink-muted">
          {done} of {sessions.length} done · {formatPlanned(planned)} total
        </span>
      </div>
      {upcoming.length > 0 && (
        <div
          role="region"
          aria-label="Upcoming sessions"
          tabIndex={0}
          className="no-scrollbar focus-ring -mx-5 flex snap-x snap-mandatory scroll-px-5 gap-2.5 overflow-x-auto px-5"
        >
          {upcoming.map((session, index) => (
            <SessionCard
              key={session.id}
              session={session}
              lead={index === 0 ? "Next" : "Then"}
              place={`${sessions.indexOf(session) + 1} of ${sessions.length}`}
              as={Link}
              linkProps={{ to: "/sessions/$id", params: { id: session.id } }}
            />
          ))}
        </div>
      )}
      {finished.map((session) => (
        <SessionRow
          key={session.id}
          discipline={session.discipline}
          title={session.title}
          detail={sessionDetail(session)}
          state={session.status}
          as={Link}
          linkProps={{ to: "/sessions/$id", params: { id: session.id } }}
        />
      ))}
    </section>
  );
}

function NoSessions({ rest }) {
  return (
    <section className="flex items-center gap-3 rounded-card border border-dashed border-state-rest-edge bg-state-rest-tint px-4 py-3.5">
      {rest && <StatusChip state="rest" />}
      <p className="m-0 text-sm text-ink-soft">
        {rest ? "Rest day. Nothing is planned." : "No sessions are planned for this day."}
      </p>
    </section>
  );
}

function OutsidePlan() {
  return (
    <section className="flex flex-col gap-1 rounded-card border border-border bg-surface px-4 py-3.5">
      <h2 className="m-0 text-row font-semibold">Outside your plan</h2>
      <p className="m-0 text-sm text-ink-soft">This date is not in any cycle of your plan.</p>
    </section>
  );
}

function Activities({ activities, heading }) {
  if (activities.length === 0) return null;

  return (
    <section aria-labelledby="activities-heading" className="flex flex-col gap-2.5">
      <h2 id="activities-heading" className="m-0 text-label font-semibold text-ink-muted uppercase">
        {heading}
      </h2>
      {activities.map((activity) => (
        <SessionRow
          key={activity.id}
          discipline={activity.discipline}
          title={disciplineOf(activity.discipline).label}
          detail={activityDetail(activity)}
          as={Link}
          linkProps={{ to: "/activities/$id", params: { id: activity.id } }}
        />
      ))}
    </section>
  );
}

function sessionDetail(session) {
  return session.activity
    ? activityDetail(session.activity)
    : `Planned ${formatPlanned(session.planned_seconds)}`;
}

function activityDetail(activity) {
  return [
    formatStartTime(activity.started_at, activity.utc_offset_seconds),
    activity.distance_m && formatDistance(activity.distance_m),
    activity.duration_seconds && formatClock(activity.duration_seconds),
  ]
    .filter(Boolean)
    .join(" · ");
}

/** A day screen's header: the date over the title, the plan line, and actions. */
export function DayHeader({ label, title, data, actions }) {
  return (
    <header className="flex items-start justify-between gap-3 pt-3">
      <div className="flex min-w-0 flex-col gap-1">
        <span className="text-label font-semibold text-ink-muted uppercase">{label}</span>
        <h1 className="m-0 text-3xl font-bold tracking-tight">{title}</h1>
        {data?.day && <span className="text-caption text-ink-muted">{chainLine(data.day)}</span>}
      </div>
      <div className="flex flex-none items-center gap-1">{actions}</div>
    </header>
  );
}

/** A day's data while it loads, when it fails, and once it arrives. */
export function DayContent({ query }) {
  if (query.isPending) {
    return (
      <p role="status" className="m-0 text-sm text-ink-muted">
        Loading the day…
      </p>
    );
  }

  if (query.isError) {
    return (
      <div className="flex flex-col items-start gap-3">
        <p role="alert" className="m-0 text-sm text-ink-soft">
          The day could not be loaded.
        </p>
        <Button variant="secondary" onClick={() => query.refetch()}>
          Try again
        </Button>
      </div>
    );
  }

  return <DayView data={query.data} />;
}
