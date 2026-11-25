import { Link } from "@tanstack/react-router";
import { activityLine, entriesOf, placeOf, sessionLine, totalsOf } from "../lib/calendar.js";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import {
  formatDates,
  formatDayInWeek,
  formatHours,
  formatPlanned,
  formatWeekday,
} from "../lib/format.js";
import { activityLink, dayLink, sessionLink } from "../lib/links.js";
import { DisciplineIcon } from "../ui/DisciplineIcon.jsx";
import { DayRing, SessionMark } from "../ui/Marks.jsx";
import { Stat } from "../ui/Stat.jsx";
import { DesktopHeading, DesktopToolbar, PhonePage, WeeksToGo } from "./calendar.jsx";

const chevron = (size = 18) => (
  <svg
    aria-hidden="true"
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className="flex-none text-ink-muted"
  >
    <path d="M9 6l6 6-6 6" />
  </svg>
);

const title = (days) => formatDates({ first: days[0].date, last: days.at(-1).date });

/** A week on a desktop: its hours day by day, then a row for each day with its sessions. */
export function DesktopWeek({ view, date, today, season, days }) {
  const totals = totalsOf(days);

  return (
    <>
      <DesktopToolbar view={view} date={date} today={today} />
      <DesktopHeading label={placeOf(days, season)} title={title(days)}>
        <Stat
          value={totals.done}
          of={totals.sessions}
          label={`sessions done${totals.skipped ? ` · ${totals.skipped} skipped` : ""}`}
        />
        <Stat
          value={formatHours(totals.trained)}
          of={`${formatHours(totals.planned)} h`}
          label="trained this week"
        />
        <WeeksToGo season={season} today={today} />
      </DesktopHeading>
      <section
        aria-labelledby="load-heading"
        className="flex flex-col gap-3 rounded-card border border-border bg-surface px-5 py-4.5"
      >
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="load-heading" className="m-0 text-lg font-bold">
            Hours, done of planned
          </h2>
          <LoadLegend />
        </div>
        <LoadBars days={days} today={today} height={120} barWidth="w-16" long />
      </section>
      <ol aria-label="Days of the week" className="m-0 flex list-none flex-col gap-2 p-0">
        {days.map((day) => (
          <li key={day.date}>
            <DesktopDayRow day={day} today={today} />
          </li>
        ))}
      </ol>
    </>
  );
}

function DesktopDayRow({ day, today }) {
  const isToday = day.date === today;
  const entries = entriesOf(day, today);

  return (
    <div
      className={`flex items-center gap-4 rounded-[16px] border px-4 py-3 ${
        isToday ? "border-calendar-today-edge bg-calendar-today" : "border-border bg-surface"
      }`}
    >
      <Link
        {...dayLink(day.date)}
        className="focus-ring flex w-37.5 flex-none items-center gap-2.5 rounded-tile text-ink no-underline"
      >
        {day.day && <DayRing day={day} size={20} today={isToday} />}
        <span className="flex flex-col gap-0.5">
          <span className={`text-row font-bold ${isToday ? "text-accent" : ""}`}>
            {formatDayInWeek(day.date)}
            {isToday && <span className="sr-only">, today</span>}
          </span>
          <span className="font-display text-sm text-ink-muted tabular-nums">
            {day.day
              ? `${formatPlanned(day.trained)} of ${formatPlanned(day.planned)}`
              : "Outside your plan"}
          </span>
        </span>
      </Link>
      <ul className="m-0 flex min-w-0 flex-1 list-none flex-wrap gap-2.5 p-0">
        {entries.map((entry) => (
          <li key={entry.session?.id ?? entry.activity.id} className="w-72.5 max-w-full">
            <EntryCard entry={entry} />
          </li>
        ))}
        {entries.length === 0 && day.rest && (
          <li className="text-sm text-ink-muted">
            {day.rest === "kept" ? "Rest day kept" : "Rest day"}
          </li>
        )}
      </ul>
      <Link
        {...dayLink(day.date)}
        tabIndex={-1}
        aria-hidden="true"
        className="grid size-11 flex-none place-items-center rounded-tile hover:bg-surface-raised"
      >
        {chevron()}
      </Link>
    </div>
  );
}

const cardLooks = {
  done: (style) => `${style.tint} ${style.edge}`,
  planned: (style) => `bg-surface-raised ${style.edge}`,
  skipped: () => "border-dashed border-rule bg-transparent text-ink-muted",
};

function EntryCard({ entry }) {
  const { session, activity, next } = entry;
  const item = session ?? activity;
  const style = disciplineOf(item.discipline);
  const look = session
    ? (cardLooks[session.status] ?? cardLooks.planned)(style)
    : "border-border-strong bg-surface-raised";

  return (
    <Link
      {...(session ? sessionLink(session.id) : activityLink(activity.id))}
      className={`focus-ring flex items-center gap-2.5 rounded-[14px] border p-3 text-ink no-underline hover:brightness-110 ${look}`}
    >
      <span className={`grid size-8 flex-none place-items-center rounded-[10px] ${style.tile}`}>
        <DisciplineIcon discipline={item.discipline} size={18} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="truncate text-sm font-semibold">
          {session ? session.title : style.activity}
        </span>
        <span className={`truncate text-xs ${next ? style.text : "text-ink-muted"}`}>
          {session ? sessionLine(session, next) : activityLine(activity)}
        </span>
      </span>
      <SessionMark
        state={session ? session.status : "extra"}
        discipline={item.discipline}
        size={18}
      />
    </Link>
  );
}

/** A week on a phone: its hours day by day, then a row for each day linking to it. */
export function PhoneWeek({ today, season, days }) {
  const totals = totalsOf(days);

  return (
    <PhonePage label={placeOf(days, season)} title={title(days)}>
      <section
        aria-labelledby="load-heading"
        className="flex flex-col gap-2.5 rounded-card border border-border bg-surface p-3.5"
      >
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="load-heading" className="m-0 text-label font-semibold text-ink-muted uppercase">
            Hours, done of planned
          </h2>
          <span className="font-display text-[15px] font-semibold tabular-nums">
            {formatHours(totals.trained)}{" "}
            <span className="text-ink-muted">
              of {formatHours(totals.planned)} h · {totals.done} of {totals.sessions} done
            </span>
          </span>
        </div>
        <LoadBars days={days} today={today} height={110} barWidth="w-6.5" />
        <LoadLegend />
      </section>
      <ol aria-label="Days of the week" className="m-0 flex list-none flex-col gap-2 p-0">
        {days.map((day) => (
          <li key={day.date}>
            <PhoneDayRow day={day} today={today} />
          </li>
        ))}
      </ol>
    </PhonePage>
  );
}

function PhoneDayRow({ day, today }) {
  const isToday = day.date === today;
  const entries = entriesOf(day, today);

  return (
    <Link
      {...dayLink(day.date)}
      className={`focus-ring flex min-h-14 items-center gap-3 rounded-[14px] border px-3 py-2.5 text-ink no-underline ${
        isToday ? "border-calendar-today-edge bg-calendar-today" : "border-border bg-surface"
      }`}
    >
      <span className="flex w-12.5 flex-none flex-col">
        <span className={`text-xs font-bold ${isToday ? "text-accent" : "text-ink-muted"}`}>
          {formatWeekday(day.date)}
          {isToday && <span className="sr-only">, today</span>}
        </span>
        <span className="font-display text-xl leading-none font-semibold">
          {Number(day.date.slice(8))}
        </span>
      </span>
      <span className="flex min-w-0 flex-1 flex-wrap items-center gap-3">
        {entries.map(({ session, activity }) => {
          const item = session ?? activity;
          return (
            <span key={item.id} className="relative inline-flex">
              <span
                className={`grid size-7.5 place-items-center rounded-[9px] ${disciplineOf(item.discipline).tile}`}
              >
                <DisciplineIcon discipline={item.discipline} size={16} />
              </span>
              <span className="absolute -right-1.25 -bottom-1.25 rounded-pill bg-surface p-px">
                <SessionMark
                  state={session ? session.status : "extra"}
                  discipline={item.discipline}
                  size={14}
                />
              </span>
            </span>
          );
        })}
        {entries.length === 0 && day.rest && (
          <span className="flex items-center gap-2 text-caption text-ink-muted">
            <DayRing day={day} size={16} />
            Rest
          </span>
        )}
      </span>
      {day.day && (
        <span className="font-display text-sm text-ink-muted tabular-nums">
          {formatPlanned(day.trained)} / {formatPlanned(day.planned)}
        </span>
      )}
      {chevron(14)}
    </Link>
  );
}

/**
 * Each day's hours as a bar: an outline as tall as its planned hours and a
 * fill as tall as the hours trained, both against the week's longest day.
 */
function LoadBars({ days, today, height, barWidth, long = false }) {
  const top = Math.max(1, ...days.map((day) => Math.max(day.planned, day.trained)));
  const px = (seconds) => Math.round((seconds / top) * height);
  const totals = totalsOf(days);

  return (
    <div
      role="img"
      aria-label={`Hours trained each day against the hours planned; ${formatHours(totals.trained)} of ${formatHours(totals.planned)} hours`}
      className="flex gap-1"
    >
      {days.map((day) => (
        <div key={day.date} className="flex min-w-0 flex-1 flex-col items-center gap-1.5">
          <div className={`relative ${barWidth}`} style={{ height }}>
            {day.planned > 0 && (
              <span
                className="absolute inset-x-0 bottom-0 rounded-[6px] border-[1.5px] border-rule"
                style={{ height: px(day.planned) }}
              />
            )}
            {day.trained > 0 && (
              <span
                className="absolute inset-x-0 bottom-0 rounded-[6px] bg-accent"
                style={{ height: px(day.trained) }}
              />
            )}
          </div>
          <span
            className={`font-semibold ${long ? "text-xs" : "text-[11px]"} ${
              day.date === today ? "text-accent" : "text-ink-muted"
            }`}
          >
            {long
              ? formatDayInWeek(day.date)
              : `${formatWeekday(day.date)[0]} ${Number(day.date.slice(8))}`}
          </span>
        </div>
      ))}
    </div>
  );
}

function LoadLegend() {
  return (
    <ul className="m-0 flex list-none gap-3.5 p-0 text-xs text-ink-muted">
      <li className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="size-3 rounded-[3px] bg-accent" />
        Done
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="size-3 rounded-[3px] border-[1.5px] border-rule" />
        Planned
      </li>
    </ul>
  );
}
