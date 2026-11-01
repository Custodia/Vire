import { Link } from "@tanstack/react-router";
import {
  activityLine,
  chunk,
  cycleName,
  entriesOf,
  placeOf,
  sessionLine,
  totalsOf,
} from "../lib/calendar.js";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import {
  formatDayAndMonth,
  formatHours,
  formatLongDay,
  formatMonthAndYear,
} from "../lib/format.js";
import { activityLink, calendarLink, dayLink, sessionLink } from "../lib/links.js";
import { blockNumbers } from "../lib/plan.js";
import { DisciplineIcon } from "../ui/DisciplineIcon.jsx";
import { RestKeptDot, SessionDot } from "../ui/Marks.jsx";
import { ExtraChip, RestChip, SessionChip } from "../ui/SessionChip.jsx";
import { Stat } from "../ui/Stat.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";
import { DesktopHeading, DesktopToolbar, PhonePage, WeeksToGo } from "./calendar.jsx";

const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const inMonth = (day, date) => day.date.slice(0, 7) === date.slice(0, 7);

/** A month on a desktop: a row for each week, each day with its sessions and each week's hours. */
export function DesktopMonth({ view, date, today, season, days }) {
  const month = days.filter((day) => inMonth(day, date));
  const totals = totalsOf(month);

  return (
    <>
      <DesktopToolbar view={view} date={date} today={today} />
      <DesktopHeading
        label={placeOf(month, season, { cycles: false })}
        title={formatMonthAndYear(date)}
      >
        <Stat value={totals.done} of={totals.sessions} label="sessions done this month" />
        <Stat
          value={formatHours(totals.trained)}
          of={`${formatHours(totals.planned)} h`}
          label="trained this month"
        />
        <WeeksToGo season={season} today={today} />
      </DesktopHeading>
      <section
        aria-label={formatMonthAndYear(date)}
        className="flex flex-col gap-1.5 rounded-card border border-border bg-surface px-4.5 pt-4 pb-4.5"
      >
        <div
          aria-hidden="true"
          className="grid grid-cols-[repeat(7,minmax(0,1fr))_8rem] gap-1.5 px-0.5 pb-1 text-xs font-semibold text-ink-muted"
        >
          {weekdays.map((weekday) => (
            <span key={weekday}>{weekday}</span>
          ))}
          <span className="pl-2">Week</span>
        </div>
        {chunk(days, 7).map((week) => (
          <div key={week[0].date} className="grid grid-cols-[repeat(7,minmax(0,1fr))_8rem] gap-1.5">
            {week.map((day) => (
              <MonthDay key={day.date} day={day} today={today} outside={!inMonth(day, date)} />
            ))}
            <WeekTotal week={week} today={today} season={season} />
          </div>
        ))}
        <MonthLegend />
      </section>
    </>
  );
}

function MonthDay({ day, today, outside }) {
  const isToday = day.date === today;
  const tone = isToday
    ? "bg-accent-tint outline-2 -outline-offset-2 outline-accent"
    : outside
      ? "border border-divider bg-ground opacity-70"
      : day.date < today
        ? "bg-calendar-past"
        : "bg-calendar-planned";

  return (
    <Link
      {...dayLink(day.date)}
      aria-current={isToday ? "date" : undefined}
      className={`focus-ring flex min-h-31.5 min-w-0 flex-col gap-1 rounded-tile p-2 text-ink no-underline hover:brightness-115 ${tone}`}
    >
      <span
        className={`px-0.5 pb-0.5 font-display text-base leading-tight font-semibold ${
          isToday ? "text-accent" : outside ? "text-ink-faint" : ""
        }`}
      >
        {day.date.endsWith("-01") ? formatDayAndMonth(day.date) : Number(day.date.slice(8))}
        {isToday && <span className="sr-only">, today</span>}
      </span>
      {entriesOf(day, today).map(({ session, activity }) =>
        session ? (
          <SessionChip key={session.id} session={session} />
        ) : (
          <ExtraChip key={activity.id} activity={activity} />
        ),
      )}
      {day.rest && day.activities.length === 0 && <RestChip kept={day.rest === "kept"} />}
    </Link>
  );
}

function WeekTotal({ week, today, season }) {
  const totals = totalsOf(week);
  const now = week.some((day) => day.date === today);
  const past = week.at(-1).date < today;
  const note = now
    ? "This week"
    : totals.skipped > 0
      ? `${totals.skipped} skipped`
      : past
        ? totals.sessions > 0
          ? "All done"
          : ""
        : "Planned";

  return (
    <Link
      {...calendarLink("week", week[0].date)}
      className="focus-ring flex flex-col justify-center gap-0.75 rounded-tile border border-divider p-2 text-ink no-underline hover:bg-surface-raised"
    >
      <span className={`text-xs font-bold ${now ? "text-accent" : ""}`}>
        {weekName(week, season)}
      </span>
      <span className="font-display text-base font-semibold tabular-nums">
        {past || now
          ? `${formatHours(totals.trained)} of ${formatHours(totals.planned)} h`
          : `${formatHours(totals.planned)} h`}
      </span>
      <span className="text-[11px] text-ink-muted">{note}</span>
    </Link>
  );
}

function weekName(week, season) {
  const numbers = season ? blockNumbers(season) : new Map();
  const chains = week.map((day) => day.day?.chain).filter(Boolean);
  const names = chains.map((chain) => {
    const number = numbers.get(chain.block.id);
    return `${number ? `B${number}` : chain.block.focus} · ${cycleName(chain, season)}`;
  });
  return [...new Set(names)].join(" / ") || "Outside your plan";
}

function MonthLegend() {
  const chip = "rounded-[5px] border px-1.5 py-px text-[11px] font-semibold";

  return (
    <ul className="m-0 flex list-none flex-wrap items-center gap-4 p-0 pt-2 text-xs text-ink-muted">
      <li className="inline-flex items-center gap-1.5">
        <span
          aria-hidden="true"
          className={`${chip} border-state-done-edge bg-state-done-tint text-state-done`}
        >
          ✓
        </span>
        Done
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span
          aria-hidden="true"
          className={`${chip} border-state-skipped-edge bg-state-skipped-tint text-state-skipped`}
        >
          ✕
        </span>
        Skipped
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span
          aria-hidden="true"
          className={`${chip} border-transparent bg-discipline-bike-tile text-discipline-bike-soft`}
        >
          Bike
        </span>
        Upcoming, in its sport’s colour
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span
          aria-hidden="true"
          className={`${chip} border-border-strong bg-surface-raised text-ink-soft`}
        >
          +
        </span>
        Not in the plan
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="size-3.5 rounded-[4px] border-2 border-accent" />
        Today
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span
          aria-hidden="true"
          className={`${chip} border-dashed border-state-rest-kept text-state-rest-kept`}
        >
          ✓ Rest
        </span>
        Rest kept
      </li>
      <li className="ml-auto">A day opens it in Day · a week total opens Week</li>
    </ul>
  );
}

/** A month on a phone: its days as dots under their dates, and the date's day listed below. */
export function PhoneMonth({ date, today, season, days }) {
  const selected = days.find((day) => day.date === date);

  return (
    <PhonePage
      label={placeOf(
        days.filter((day) => inMonth(day, date)),
        season,
        { cycles: false },
      )}
      title={formatMonthAndYear(date)}
    >
      <div className="flex flex-col gap-1">
        <div
          aria-hidden="true"
          className="grid grid-cols-7 gap-0.75 text-center text-[11px] font-semibold text-ink-muted"
        >
          {weekdays.map((weekday) => (
            <span key={weekday}>{weekday[0]}</span>
          ))}
        </div>
        <ol
          aria-label={formatMonthAndYear(date)}
          className="m-0 grid list-none grid-cols-7 gap-0.75 p-0"
        >
          {days.map((day) => (
            <li key={day.date}>
              <PhoneMonthDay
                day={day}
                today={today}
                selected={day.date === date}
                outside={!inMonth(day, date)}
              />
            </li>
          ))}
        </ol>
        <PhoneLegend />
      </div>
      {selected && <SelectedDay day={selected} today={today} />}
    </PhonePage>
  );
}

function PhoneMonthDay({ day, today, selected, outside }) {
  const isToday = day.date === today;
  const summary = day.day
    ? day.sessions.length === 0
      ? "rest day"
      : `${day.done} of ${day.sessions.length} done${day.skipped ? `, ${day.skipped} skipped` : ""}`
    : "outside your plan";

  return (
    <Link
      {...calendarLink("month", day.date)}
      replace
      aria-label={`${formatLongDay(day.date)}${isToday ? ", today" : ""}, ${summary}`}
      aria-current={selected ? "date" : undefined}
      className={`focus-ring flex min-h-13.5 flex-col items-center justify-between gap-1 rounded-[10px] pt-1.5 pb-2 text-ink no-underline ${
        selected
          ? "bg-accent-tint outline-2 -outline-offset-2 outline-accent"
          : outside
            ? "bg-transparent"
            : "bg-calendar-month"
      }`}
    >
      <span
        className={`font-display text-[17px] leading-none font-semibold ${
          isToday ? "text-accent" : outside ? "text-ink-faint" : ""
        }`}
      >
        {Number(day.date.slice(8))}
      </span>
      <span className="flex h-2 items-center gap-0.75">
        {day.rest === "kept" ? (
          <RestKeptDot />
        ) : (
          day.sessions.map((session) => <SessionDot key={session.id} session={session} />)
        )}
      </span>
    </Link>
  );
}

function PhoneLegend() {
  return (
    <ul className="m-0 flex list-none flex-wrap gap-3.5 p-0 px-0.5 pt-2 text-xs text-ink-muted">
      <li className="inline-flex items-center gap-1.5">
        <SessionDot session={{ status: "done" }} />
        Done
      </li>
      <li className="inline-flex items-center gap-1.5">
        <SessionDot session={{ status: "planned", discipline: "bike" }} />
        Planned, in its sport’s colour
      </li>
      <li className="inline-flex items-center gap-1.5">
        <SessionDot session={{ status: "skipped" }} />
        Skipped
      </li>
      <li className="inline-flex items-center gap-1.5">
        <RestKeptDot />
        Rest kept
      </li>
    </ul>
  );
}

function SelectedDay({ day, today }) {
  const entries = entriesOf(day, today);

  return (
    <section
      aria-labelledby="selected-heading"
      className="flex flex-col rounded-card border border-border bg-surface px-3.5 pt-3.5 pb-1.5"
    >
      <div className="flex items-baseline justify-between gap-2 px-1 pb-2.5">
        <h2 id="selected-heading" className="m-0 text-[17px] font-bold">
          {formatLongDay(day.date)}
        </h2>
        <Link {...dayLink(day.date)} className="text-caption font-semibold">
          Open the day
        </Link>
      </div>
      {entries.length > 0 ? (
        <ul className="m-0 flex list-none flex-col p-0">
          {entries.map((entry) => (
            <li key={entry.session?.id ?? entry.activity.id}>
              <SelectedEntry entry={entry} />
            </li>
          ))}
        </ul>
      ) : (
        <p className="m-0 border-t border-divider px-1 py-3 text-sm text-ink-muted">
          {!day.day ? "Outside your plan." : day.rest === "kept" ? "Rest day kept." : "Rest day."}
        </p>
      )}
    </section>
  );
}

function SelectedEntry({ entry }) {
  const { session, activity, next } = entry;
  const item = session ?? activity;
  const style = disciplineOf(item.discipline);
  const state = session ? session.status : null;

  return (
    <Link
      {...(session ? sessionLink(session.id) : activityLink(activity.id))}
      className="focus-ring flex items-center gap-3 border-t border-divider px-1 py-2.5 text-ink no-underline"
    >
      <span className={`grid size-9 flex-none place-items-center rounded-[10px] ${style.tile}`}>
        <DisciplineIcon discipline={item.discipline} size={20} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="truncate text-sm font-semibold">
          {session ? session.title : style.activity}
        </span>
        <span className="truncate text-xs text-ink-muted">
          {session ? sessionLine(session, next) : `${activityLine(activity)} · not in the plan`}
        </span>
      </span>
      {(state === "done" || state === "skipped") && <StatusChip state={state} />}
    </Link>
  );
}
