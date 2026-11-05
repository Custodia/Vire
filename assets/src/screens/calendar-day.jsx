import { useState } from "react";
import { Link } from "@tanstack/react-router";
import { blockName, dayInCycle, entriesOf, recordedLine } from "../lib/calendar.js";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import {
  formatClock,
  formatDistance,
  formatLongDay,
  formatPlanned,
  formatStartTime,
  formatWeekday,
} from "../lib/format.js";
import { activityLink, dayLink, sessionLink } from "../lib/links.js";
import { sessionStats, stepsOf } from "../lib/structure.js";
import { buttonClass } from "../ui/Button.jsx";
import { Card } from "../ui/Card.jsx";
import { CoachNote } from "../ui/CoachNote.jsx";
import { DisciplineIcon } from "../ui/DisciplineIcon.jsx";
import { Empty } from "../ui/Empty.jsx";
import { DayRing, SessionMark } from "../ui/Marks.jsx";
import { Stat } from "../ui/Stat.jsx";
import { WorkoutProfile } from "../ui/WorkoutProfile.jsx";
import { DesktopHeading, DesktopToolbar, PhonePage, WeeksToGo } from "./calendar.jsx";
import { DayCard, MatchMenu } from "./day-card.jsx";
import { DayStrip } from "./day-strip.jsx";
import { ActivityPanel, SessionPanel } from "./session-panel.jsx";

/** What a day shows first: its next session, or its first session or activity. */
function firstShown(day, today) {
  const entries = entriesOf(day, today);
  const entry = entries.find((each) => each.next) ?? entries[0];
  if (!entry) return null;
  return entry.session ? { session: entry.session.id } : { activity: entry.activity.id };
}

/**
 * A day on a desktop: its week across the top, its sessions on the left, and
 * the session or activity `selected` from it, or the day's first, beside them.
 * An activity matched to a session shows as its session.
 */
export function DesktopDay({ view, date, today, season, days, selected }) {
  const day = days.find((each) => each.date === date);
  const chain = day.day?.chain;
  const matched =
    selected?.activity && day.sessions.find(({ activity }) => activity?.id === selected.activity);
  const shown = matched ? { session: matched.id } : (selected ?? firstShown(day, today));
  const isToday = date === today;

  return (
    <>
      <DesktopToolbar view={view} date={date} today={today} />
      <DesktopHeading
        label={[
          isToday && "Today",
          chain
            ? `${chain.phase.name} · ${blockName(chain, season)} · ${dayInCycle(chain, season)}`
            : "Outside your plan",
        ]
          .filter(Boolean)
          .join(" · ")}
        title={formatLongDay(date)}
      >
        <Stat
          value={day.done}
          of={day.sessions.length}
          label={isToday ? "sessions done today" : "sessions done"}
        />
        <Stat
          value={formatPlanned(day.trained)}
          of={formatPlanned(day.planned)}
          label={isToday ? "trained today" : "trained"}
        />
        <WeeksToGo season={season} today={today} />
      </DesktopHeading>
      <DayStrip days={days} date={date} today={today} season={season} />
      <div className="grid grid-cols-[minmax(0,24rem)_minmax(0,1fr)] items-start gap-5">
        <aside className="flex min-w-0 flex-col gap-5">
          <DayCard day={day} today={today} shown={shown} />
          <Card id="readiness" title="Readiness">
            <Empty>No readiness data yet.</Empty>
          </Card>
          <Card id="weight" title="Weight trend">
            <Empty>No weight data yet.</Empty>
          </Card>
        </aside>
        <div className="flex min-w-0 flex-col gap-5">
          {shown?.session && <SessionPanel key={shown.session} id={shown.session} today={today} />}
          {shown?.activity && <ActivityPanel key={shown.activity} id={shown.activity} />}
          {!shown && <NothingOnTheDay day={day} />}
        </div>
      </div>
    </>
  );
}

function NothingOnTheDay({ day }) {
  const [title, text] = !day.day
    ? ["Outside your plan", "This date is not in any cycle of your plan."]
    : day.rest === "kept"
      ? ["Rest day kept", "Nothing was planned, and the plan was kept."]
      : ["Rest day", "Nothing is planned."];

  return (
    <Card id="nothing" title={title}>
      <p className="m-0 text-sm text-ink-soft">{text}</p>
    </Card>
  );
}

/**
 * A day on a phone: its week as a strip of rings, how much of it is done,
 * and its sessions and activities along a timeline, each a card that opens.
 */
export function PhoneDay({ date, today, season, days }) {
  const day = days.find((each) => each.date === date);
  const chain = day.day?.chain;

  return (
    <PhonePage
      label={[date === today && "Today", chain ? dayInCycle(chain, season) : "Outside your plan"]
        .filter(Boolean)
        .join(" · ")}
      title={formatLongDay(date)}
      header={<WeekRings days={days} date={date} today={today} />}
    >
      {day.sessions.length > 0 && <Progress day={day} />}
      {day.day?.note && <CoachNote label="Day note">{day.day.note}</CoachNote>}
      <Timeline key={date} day={day} today={today} />
      {day.sessions.length === 0 && day.activities.length === 0 && <RestCard day={day} />}
    </PhonePage>
  );
}

function WeekRings({ days, date, today }) {
  return (
    <ol aria-label="Days of the week" className="m-0 grid list-none grid-cols-7 gap-0.5 p-0">
      {days.map((day) => (
        <li key={day.date}>
          <Link
            {...dayLink(day.date)}
            replace
            aria-label={`${formatLongDay(day.date)}${day.date === today ? ", today" : ""}`}
            aria-current={day.date === date ? "date" : undefined}
            className={`focus-ring flex min-h-15.5 flex-col items-center gap-1.25 rounded-tile pt-1.5 pb-2 text-ink no-underline ${
              day.date === date ? "bg-surface-raised" : ""
            }`}
          >
            <span
              className={`text-[11px] font-semibold ${day.date === today ? "text-accent" : "text-ink-muted"}`}
            >
              {formatWeekday(day.date)[0]}
            </span>
            <span className="font-display text-[19px] leading-none font-semibold">
              {Number(day.date.slice(8))}
            </span>
            {day.day ? (
              <DayRing day={day} size={14} today={day.date === today} />
            ) : (
              <span className="h-3.5" />
            )}
          </Link>
        </li>
      ))}
    </ol>
  );
}

function Progress({ day }) {
  const share = day.planned > 0 ? Math.min(1, day.trained / day.planned) : 0;

  return (
    <div className="flex flex-col gap-2 px-0.5">
      <div className="flex items-baseline justify-between text-caption">
        <span>
          <span className="font-display text-lg font-semibold">{day.done}</span>{" "}
          <span className="text-ink-muted">of {day.sessions.length} done</span>
        </span>
        <span>
          <span className="font-display text-lg font-semibold">{formatPlanned(day.trained)}</span>{" "}
          <span className="text-ink-muted">of {formatPlanned(day.planned)}</span>
        </span>
      </div>
      <div className="h-1 rounded-bar bg-track">
        <div className="h-1 rounded-bar bg-accent" style={{ width: `${share * 100}%` }} />
      </div>
    </div>
  );
}

function RestCard({ day }) {
  return (
    <section className="flex items-center gap-3 rounded-card border border-border bg-surface p-4">
      {day.day && <DayRing day={day} size={22} />}
      <span className="flex flex-col gap-0.5">
        <span className="text-row font-semibold">
          {!day.day ? "Outside your plan" : day.rest === "kept" ? "Rest day kept" : "Rest day"}
        </span>
        <span className="text-caption text-ink-muted">
          {!day.day ? "This date is not in any cycle of your plan." : "Nothing is planned."}
        </span>
      </span>
    </section>
  );
}

function Timeline({ day, today }) {
  const entries = entriesOf(day, today);
  const [open, setOpen] = useState(
    () => new Set(entries.filter((entry) => entry.next).map((entry) => entry.session.id)),
  );
  const toggle = (id) =>
    setOpen((was) => {
      const now = new Set(was);
      if (now.has(id)) now.delete(id);
      else now.add(id);
      return now;
    });
  const free = day.sessions.filter((session) => !session.activity);

  return (
    entries.length > 0 && (
      <ol aria-label="Timeline" className="m-0 flex list-none flex-col gap-3.5 p-0">
        {entries.map((entry, index) => {
          const id = entry.session?.id ?? entry.activity.id;
          return (
            <TimelineEntry
              key={id}
              entry={entry}
              last={index === entries.length - 1}
              open={open.has(id)}
              onToggle={() => toggle(id)}
              free={free}
            />
          );
        })}
      </ol>
    )
  );
}

function TimelineEntry({ entry, last, open, onToggle, free }) {
  const { session, activity, next } = entry;
  const item = session ?? activity;
  const style = disciplineOf(item.discipline);
  const recorded = session?.activity ?? activity;
  const time = recorded && formatStartTime(recorded.started_at, recorded.utc_offset_seconds);
  const panelId = `entry-${item.id}`;
  const labelled = Boolean(time || next);

  return (
    <li className="relative flex items-start gap-3">
      {!last && (
        <span
          aria-hidden="true"
          className={`absolute -bottom-3.5 left-2 w-0.5 bg-border ${labelled ? "top-14.5" : "top-9.5"}`}
        />
      )}
      <span className={labelled ? "pt-10" : "pt-5"}>
        <SessionMark state={session ? session.status : "extra"} discipline={item.discipline} />
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        {labelled && (
          <span
            className={`pt-0.5 font-display text-[13px] font-semibold ${next ? style.text : "text-ink-muted"}`}
          >
            {time ?? "Next"}
          </span>
        )}
        <section
          className={`overflow-hidden rounded-[14px] border ${
            next ? `${style.tint} ${style.edge}` : "border-border bg-surface"
          }`}
        >
          <button
            type="button"
            aria-expanded={open}
            aria-controls={panelId}
            onClick={onToggle}
            className="focus-ring flex min-h-14 w-full items-center gap-2.5 bg-transparent px-3 py-2.5 text-left text-ink"
          >
            <span
              className={`grid size-8 flex-none place-items-center rounded-[10px] ${style.tile}`}
            >
              <DisciplineIcon discipline={item.discipline} size={18} />
            </span>
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="truncate text-row font-semibold">
                {session ? session.title : style.activity}
              </span>
              <span className="truncate text-xs text-ink-muted">
                {recorded ? recordedLine(recorded) : formatPlanned(session.planned_seconds)}
              </span>
            </span>
            <svg
              aria-hidden="true"
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="flex-none text-ink-muted"
            >
              <path d={open ? "M6 15l6-6 6 6" : "M6 9l6 6 6-6"} />
            </svg>
          </button>
          {open && (
            <div id={panelId} className="flex flex-col gap-3 px-3 pb-3">
              {recorded ? <Recorded activity={recorded} /> : <Planned session={session} />}
              <Link
                {...(session ? sessionLink(session.id) : activityLink(activity.id))}
                className={buttonClass("secondary", "w-full")}
              >
                {session ? "Open the session" : "Open the activity"}
              </Link>
            </div>
          )}
          {activity && (
            <div className="flex flex-wrap items-center gap-2.5 px-3 pb-3">
              <span className="flex-1 text-xs text-ink-muted">Not in the plan</span>
              {free.length > 0 && <MatchMenu activity={activity} sessions={free} />}
            </div>
          )}
        </section>
      </div>
    </li>
  );
}

function Figures({ figures }) {
  return (
    <div className="grid grid-cols-[repeat(auto-fit,minmax(4.5rem,1fr))] gap-2">
      {figures.map((figure) => (
        <Stat key={figure.label} value={figure.value} label={figure.label} size="md" />
      ))}
    </div>
  );
}

function Recorded({ activity }) {
  return (
    <Figures
      figures={[
        { label: "Duration", value: formatClock(activity.duration_seconds) },
        {
          label: "Distance",
          value: activity.distance_m ? formatDistance(activity.distance_m) : "—",
        },
        { label: "Load", value: activity.training_load ? Math.round(activity.training_load) : "—" },
      ]}
    />
  );
}

function Planned({ session }) {
  const steps = stepsOf(session.structure);

  return (
    <>
      <Figures figures={sessionStats(session)} />
      {steps.length > 0 && (
        <div className="border-b border-border-strong">
          <WorkoutProfile steps={steps} className="h-18" />
        </div>
      )}
      {(session.structure?.note ?? session.rationale) && (
        <p className="m-0 text-sm leading-normal text-ink-soft">
          {session.structure?.note ?? session.rationale}
        </p>
      )}
    </>
  );
}
