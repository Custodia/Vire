import { Link } from "@tanstack/react-router";
import { cycleName, entriesOf } from "../lib/calendar.js";
import { formatDates, formatDayInWeek, formatPlanned } from "../lib/format.js";
import { dayLink } from "../lib/links.js";
import { Card } from "../ui/Card.jsx";
import { ExtraChip, RestChip, SessionChip } from "../ui/SessionChip.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";

/** The week's days side by side, each with its sessions, linking to the day. */
export function DayStrip({ days, date, today, season }) {
  const cycles = [
    ...new Set(days.map((day) => day.day && cycleName(day.day.chain, season)).filter(Boolean)),
  ];

  return (
    <Card
      id="week"
      title={[formatDates({ first: days[0].date, last: days.at(-1).date }), ...cycles].join(" · ")}
    >
      <ol aria-label="Days of the week" className="m-0 grid list-none grid-cols-7 gap-1.5 p-0">
        {days.map((day) => (
          <li key={day.date} className="min-w-0">
            <DayCell day={day} today={today} selected={day.date === date} />
          </li>
        ))}
      </ol>
      <Legend />
    </Card>
  );
}

function DayCell({ day, today, selected }) {
  const { date } = day;
  const tone =
    date === today ? "bg-accent-tint" : date < today ? "bg-calendar-past" : "bg-calendar-planned";

  return (
    <Link
      {...dayLink(date)}
      aria-current={selected ? "date" : undefined}
      className={`focus-ring flex h-full min-h-36 min-w-0 flex-col gap-1.5 rounded-tile p-2.5 text-ink no-underline hover:brightness-125 ${tone} ${
        selected ? "ring-2 ring-accent ring-inset" : ""
      }`}
    >
      <span className="flex items-baseline justify-between gap-1.5">
        <span className={`text-sm font-bold ${date === today ? "text-accent" : ""}`}>
          {formatDayInWeek(date)}
          {date === today && <span className="sr-only">, today</span>}
        </span>
        {day.planned > 0 && (
          <span className="font-display text-sm text-ink-muted tabular-nums">
            {formatPlanned(day.planned)}
          </span>
        )}
      </span>
      {entriesOf(day, today).map(({ session, activity }) =>
        session ? (
          <SessionChip key={session.id} session={session} />
        ) : (
          <ExtraChip key={activity.id} activity={activity} />
        ),
      )}
      {day.rest && day.activities.length === 0 && <RestChip kept={day.rest === "kept"} />}
      {!day.day && <span className="text-label text-ink-faint">No plan</span>}
    </Link>
  );
}

function Legend() {
  return (
    <ul
      aria-label="Week legend"
      className="m-0 flex list-none flex-wrap items-center gap-4 p-0 text-xs text-ink-muted"
    >
      {["done", "skipped", "upcoming", "rest"].map((state) => (
        <li key={state}>
          <StatusChip state={state} />
        </li>
      ))}
      <li>
        <RestChip kept />
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="size-3.5 rounded-bar bg-accent-tint" />
        Today
      </li>
      <li className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="size-3.5 rounded-bar border-2 border-accent" />
        Shown
      </li>
    </ul>
  );
}
