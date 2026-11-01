import { addDays } from "./format.js";

const DAY_MS = 86_400_000;

/** The days from one ISO date to another, negative when the second is earlier. */
export function daysBetween(first, last) {
  return Math.round((Date.parse(last) - Date.parse(first)) / DAY_MS);
}

/** How many days a period covers, both ends counted. */
export function periodLength({ first, last }) {
  return daysBetween(first, last) + 1;
}

/** The whole weeks from a date to a period's last day, rounded up, and none once it is past. */
export function weeksTo(date, last) {
  return Math.max(0, Math.ceil(daysBetween(date, last) / 7));
}

/** Whether a period holds an ISO date. */
export function covers(period, date) {
  return date >= period.first && date <= period.last;
}

/** Whether a period lies before, around or after an ISO date: done, now or planned. */
export function progressOf(period, date) {
  if (period.last < date) return "done";
  return period.first > date ? "planned" : "now";
}

/** The Monday of the week an ISO date falls in. */
export function weekStart(date) {
  const weekday = new Date(Date.parse(date)).getUTCDay();
  return addDays(date, -((weekday + 6) % 7));
}

/** Every block of a season, in the order its phases hold them. */
export function blocksOf(season) {
  return season.phases.flatMap((phase) => phase.blocks);
}

/** Every day of a block, in date order. */
function daysOf(block) {
  return block.cycles.flatMap((cycle) => cycle.days);
}

/** The seconds every session on some days is planned to take. */
export function plannedSecondsOfDays(days) {
  return days.reduce(
    (total, day) =>
      total + day.sessions.reduce((sum, session) => sum + (session.planned_seconds ?? 0), 0),
    0,
  );
}

/** The seconds every session in a block is planned to take. */
export function plannedSecondsOf(block) {
  return plannedSecondsOfDays(daysOf(block));
}

/** The entry of `items` whose period holds `date`, or the first one. */
export function around(items, date) {
  return items.find((item) => covers(item.period, date)) ?? items[0];
}

/** Each block's number in the season, counted from 1 across its phases. */
export function blockNumbers(season) {
  return new Map(blocksOf(season).map((block, index) => [block.id, index + 1]));
}

/** Each cycle's name in its block: loads counted as Load 1, Load 2, recoveries likewise. */
export function cycleNames(block) {
  const counts = { load: 0, recovery: 0 };
  const totals = { load: 0, recovery: 0 };
  for (const cycle of block.cycles) totals[cycle.kind] += 1;

  return new Map(
    block.cycles.map((cycle) => {
      counts[cycle.kind] += 1;
      const base = cycle.kind === "load" ? "Load" : "Recovery";
      const numbered = cycle.kind === "load" || totals.recovery > 1;
      return [cycle.id, numbered ? `${base} ${counts[cycle.kind]}` : base];
    }),
  );
}

/** A block's cycles as their lengths, repeats folded: 3 × 7d + 7d recovery. */
export function cyclePattern(block) {
  const parts = [];
  for (const cycle of block.cycles) {
    const label = `${periodLength(cycle.period)}d${cycle.kind === "recovery" ? " recovery" : ""}`;
    const last = parts.at(-1);
    if (last?.label === label) last.count += 1;
    else parts.push({ label, count: 1 });
  }
  return parts.map(({ label, count }) => (count > 1 ? `${count} × ${label}` : label)).join(" + ");
}

/**
 * A block's weeks that hold days, each from Monday to Sunday. Each cell is a
 * date with its day and cycle, or neither where no cycle covers it; `starts`
 * marks the first day of a cycle. Each week names the cycles it holds.
 */
export function calendarWeeks(block) {
  const days = new Map();
  for (const cycle of block.cycles) {
    for (const day of cycle.days) days.set(day.date, { day, cycle });
  }

  const weeks = [];
  for (
    let start = weekStart(block.period.first);
    start <= block.period.last;
    start = addDays(start, 7)
  ) {
    const cells = Array.from({ length: 7 }, (_, offset) => {
      const date = addDays(start, offset);
      const entry = days.get(date);
      return {
        date,
        day: entry?.day ?? null,
        cycle: entry?.cycle ?? null,
        starts: entry != null && entry.cycle.period.first === date,
      };
    });
    const cycles = [...new Set(cells.map((cell) => cell.cycle).filter(Boolean))];
    if (cycles.length > 0) weeks.push({ start, cells, cycles });
  }
  return weeks;
}

/** A session's status as the screens show it: one still planned on a day before `today` shows as skipped. */
export function shownStatus(session, date, today) {
  return session.status === "planned" && date < today ? "skipped" : session.status;
}

/**
 * A season as weeks from Monday. Each week holds whether it has days, its
 * sessions with the status they show as of `today`, the season's activities
 * no session is matched to that fall in it, and its seconds: planned, done,
 * still planned and in those activities.
 */
export function weeklyPlan(season, today) {
  const days = new Map(
    blocksOf(season)
      .flatMap(daysOf)
      .map((day) => [day.date, day]),
  );

  const weeks = [];
  for (
    let start = weekStart(season.period.first);
    start <= season.period.last;
    start = addDays(start, 7)
  ) {
    const period = { first: start, last: addDays(start, 6) };
    const held = Array.from({ length: 7 }, (_, offset) => days.get(addDays(start, offset))).filter(
      Boolean,
    );
    const sessions = held.flatMap((day) =>
      day.sessions.map((session) => ({
        ...session,
        status: shownStatus(session, day.date, today),
      })),
    );
    const activities = season.activities.filter((activity) => covers(period, activity.local_date));
    const plannedIn = (status) =>
      sessions
        .filter((session) => session.status === status)
        .reduce((sum, session) => sum + (session.planned_seconds ?? 0), 0);

    weeks.push({
      period,
      planned: held.length > 0,
      sessions,
      activities,
      seconds: {
        planned: plannedSecondsOfDays(held),
        done: plannedIn("done"),
        upcoming: plannedIn("planned"),
        extra: activities.reduce((sum, activity) => sum + (activity.duration_seconds ?? 0), 0),
      },
    });
  }
  return weeks;
}

/**
 * The spans of a period that `items` cover and the gaps between them, in
 * date order. A gap is `{ gap: true, period }`.
 */
export function withGaps(period, items) {
  const spans = [];
  let next = period.first;
  for (const item of items) {
    if (item.period.first > next) {
      spans.push({ gap: true, period: { first: next, last: addDays(item.period.first, -1) } });
    }
    spans.push(item);
    if (item.period.last >= next) next = addDays(item.period.last, 1);
  }
  if (next <= period.last) spans.push({ gap: true, period: { first: next, last: period.last } });
  return spans;
}
