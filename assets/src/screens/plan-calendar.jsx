import { formatDay, formatHours } from "../lib/format.js";
import {
  blockNumbers,
  calendarWeeks,
  covers,
  cycleNames,
  plannedSecondsOfDays,
  shownStatus,
} from "../lib/plan.js";
import { Card } from "../ui/Card.jsx";
import { Empty } from "../ui/Empty.jsx";
import { RestChip, SessionChip } from "../ui/SessionChip.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";
import { spanLabel } from "./plan-map.jsx";

const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** A block's days as a calendar of weeks, each day with the sessions planned on it. */
export function BlockCalendar({ season, block, today }) {
  const names = cycleNames(block);
  const weeks = calendarWeeks(block);

  return (
    <Card
      id="calendar"
      title={`Block ${blockNumbers(season).get(block.id)} · cycles × days`}
      aside={`${block.focus} · ${spanLabel(block.period)}`}
    >
      {block.cycles.length === 0 ? (
        <Empty>This block has no cycles yet.</Empty>
      ) : (
        <div role="table" aria-label="Block calendar" className="flex flex-col gap-1">
          <div role="row" className="grid grid-cols-[6rem_repeat(7,minmax(0,1fr))] gap-1">
            <span role="columnheader">
              <span className="sr-only">Week</span>
            </span>
            {weekdays.map((weekday) => (
              <span
                key={weekday}
                role="columnheader"
                className="px-1.5 text-xs font-semibold text-ink-muted"
              >
                {weekday}
              </span>
            ))}
          </div>
          {weeks.map((week) => (
            <Week key={week.start} week={week} names={names} today={today} />
          ))}
        </div>
      )}
      <Legend />
    </Card>
  );
}

function Week({ week, names, today }) {
  const days = week.cells.map((cell) => cell.day).filter(Boolean);

  return (
    <div role="row" className="grid grid-cols-[6rem_repeat(7,minmax(0,1fr))] gap-1">
      <div role="rowheader" className="flex flex-col justify-center gap-0.5 pr-1.5">
        {week.cycles.map((cycle) => (
          <span
            key={cycle.id}
            className={`text-caption font-bold ${covers(cycle.period, today) ? "text-accent" : "text-ink"}`}
          >
            {names.get(cycle.id)}
          </span>
        ))}
        <span className="font-display text-caption text-ink-muted">
          {formatHours(plannedSecondsOfDays(days))} h
        </span>
      </div>
      {week.cells.map((cell, index) => (
        <div role="cell" key={cell.date} className="min-w-0">
          {cell.day && (
            <DayCell
              cell={cell}
              name={cell.starts && index > 0 ? names.get(cell.cycle.id) : null}
              today={today}
            />
          )}
        </div>
      ))}
    </div>
  );
}

function DayCell({ cell, name, today }) {
  const { day, cycle } = cell;
  const isToday = day.date === today;
  const tone = isToday
    ? "bg-accent-tint ring-2 ring-accent ring-inset"
    : cycle.kind === "recovery"
      ? "bg-calendar-recovery"
      : day.date < today
        ? "bg-calendar-past"
        : "bg-calendar-planned";

  return (
    <div
      role="group"
      aria-label={formatDay(day.date)}
      className={`flex h-full min-h-14.5 min-w-0 flex-col gap-1 rounded-chip p-1.5 ${tone} ${
        name ? "border-l-2 border-rule" : ""
      }`}
    >
      <span className="flex items-baseline gap-1.5 text-label text-ink-muted">
        <span>{Number(day.date.slice(8))}</span>
        {name && <span className="min-w-0 truncate font-semibold text-ink-soft">{name}</span>}
        {isToday && <span className="ml-auto font-semibold text-accent">Today</span>}
      </span>
      {day.sessions.length === 0
        ? day.kind === "rest" && <RestChip kept={day.date < today} />
        : day.sessions.map((session) => (
            <SessionChip
              key={session.id}
              session={{ ...session, status: shownStatus(session, day.date, today) }}
            />
          ))}
    </div>
  );
}

function Legend() {
  return (
    <ul
      aria-label="Calendar legend"
      className="m-0 flex list-none flex-wrap items-center gap-4 p-0 text-xs text-ink-muted"
    >
      {["done", "skipped", "upcoming", "rest"].map((state) => (
        <li key={state}>
          <StatusChip state={state} />
        </li>
      ))}
      <li className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="size-3.5 rounded-bar border-2 border-accent" />
        Today
      </li>
    </ul>
  );
}
