import { addDays, formatClock, formatDistance, formatPlanned, formatStartTime } from "./format.js";
import { blockNumbers, blocksOf, cycleNames, shownStatus, weekStart } from "./plan.js";

const cycleKinds = { load: "Load", recovery: "Recovery" };

/** The calendar's views, each showing the dates around the date in its URL. */
export const views = ["month", "week", "day"];

/** The first day of an ISO date's month. */
export function monthStart(date) {
  return `${date.slice(0, 8)}01`;
}

function monthLength(date) {
  const [year, month] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** The last day of an ISO date's month. */
export function monthEnd(date) {
  return `${date.slice(0, 8)}${monthLength(date)}`;
}

/** The same day of the month `months` later, or that month's last day when it is shorter. */
export function addMonths(date, months) {
  const [year, month, day] = date.split("-").map(Number);
  const first = new Date(Date.UTC(year, month - 1 + months, 1)).toISOString().slice(0, 10);
  return `${first.slice(0, 8)}${String(Math.min(day, monthLength(first))).padStart(2, "0")}`;
}

/** The dates a view loads around a date: a week from Monday, or the whole weeks a month touches. */
export function viewPeriod(view, date) {
  if (view === "month") {
    return { first: weekStart(monthStart(date)), last: addDays(weekStart(monthEnd(date)), 6) };
  }
  const monday = weekStart(date);
  return { first: monday, last: addDays(monday, 6) };
}

/** The date a view shows `steps` days, weeks or months on. */
export function shiftDate(view, date, steps) {
  if (view === "month") return addMonths(date, steps);
  return addDays(date, view === "week" ? 7 * steps : steps);
}

/** An array cut into runs of `size`. */
export function chunk(items, size) {
  return Array.from({ length: Math.ceil(items.length / size) }, (_, index) =>
    items.slice(index * size, index * size + size),
  );
}

const startOf = (activity) => Date.parse(activity.started_at);

/**
 * A day as the screens draw it, from its date, its day and the activities on
 * it no session is matched to: its sessions with the status they show as of
 * `today`, those activities, and its totals. `rest` is "kept" for a day
 * without sessions before today and "ahead" for one from today on; a date
 * outside the plan has neither.
 */
export function dayOf(answer, today) {
  const { date, day, activities } = answer;
  const sessions = (day?.sessions ?? []).map((session) => ({
    ...session,
    status: shownStatus(session, date, today),
  }));
  const recorded = [...sessions.map((session) => session.activity).filter(Boolean), ...activities];

  return {
    date,
    day,
    sessions,
    activities,
    done: sessions.filter((session) => session.status === "done").length,
    skipped: sessions.filter((session) => session.status === "skipped").length,
    trained: recorded.reduce((sum, activity) => sum + (activity.duration_seconds ?? 0), 0),
    planned: sessions.reduce((sum, session) => sum + (session.planned_seconds ?? 0), 0),
    rest: day && sessions.length === 0 ? (date < today ? "kept" : "ahead") : null,
  };
}

/** Days' sessions done, skipped and planned, and their seconds trained and planned. */
export function totalsOf(days) {
  const sum = (key) => days.reduce((total, day) => total + day[key], 0);
  return {
    sessions: days.reduce((total, day) => total + day.sessions.length, 0),
    done: sum("done"),
    skipped: sum("skipped"),
    trained: sum("trained"),
    planned: sum("planned"),
  };
}

/**
 * A day's sessions and unmatched activities in the order they are listed:
 * what was recorded by its start time, then the sessions left in plan order.
 * Each entry is `{ session }` or `{ activity }`, and the first session still
 * planned today is `next`.
 */
export function entriesOf(day, today) {
  const recorded = [
    ...day.sessions
      .filter((session) => session.activity)
      .map((session) => ({ session, at: startOf(session.activity) })),
    ...day.activities.map((activity) => ({ activity, at: startOf(activity) })),
  ].sort((first, second) => first.at - second.at);
  const left = day.sessions.filter((session) => !session.activity).map((session) => ({ session }));
  const next = day.date === today ? left.find(({ session }) => session.status === "planned") : null;

  return [...recorded, ...left].map((entry) => ({ ...entry, next: entry === next }));
}

/** The name of a day's cycle as its block counts it, or its kind without the season. */
export function cycleName(chain, season) {
  const block = season && blocksOf(season).find(({ id }) => id === chain.block.id);
  return (block && cycleNames(block).get(chain.cycle.id)) ?? cycleKinds[chain.cycle.kind];
}

/** A block's name in its season, Block 2, or its focus without the season. */
export function blockName(chain, season) {
  const number = season && blockNumbers(season).get(chain.block.id);
  return number ? `Block ${number}` : chain.block.focus;
}

/** A day's cycle and its place in it: Load 2 · Day 5 of 7. */
export function dayInCycle(chain, season) {
  return `${cycleName(chain, season)} · Day ${chain.cycle.day_number} of ${chain.cycle.length}`;
}

/** Where some days sit in the plan: the phases, blocks and cycles they hold, each named once. */
export function placeOf(days, season, { cycles = true } = {}) {
  const chains = days.map((day) => day.day?.chain).filter(Boolean);
  const names = (name) => [...new Set(chains.map(name))];
  const blocks = names((chain) => blockName(chain, season));
  const numbered = blocks.length > 1 && blocks.every((name) => name.startsWith("Block "));
  return [
    ...names((chain) => chain.phase.name),
    numbered ? `Blocks ${blocks[0].slice(6)} – ${blocks.at(-1).slice(6)}` : blocks.join(" · "),
    ...(cycles ? names((chain) => cycleName(chain, season)) : []),
  ]
    .filter(Boolean)
    .join(" · ");
}

/** How far and how long an activity went, in a line. */
export function recordedLine(activity) {
  return [
    activity.distance_m && formatDistance(activity.distance_m),
    activity.duration_seconds && formatClock(activity.duration_seconds),
  ]
    .filter(Boolean)
    .join(" · ");
}

/** An activity in a line: when it started, how far and how long. */
export function activityLine(activity) {
  return [formatStartTime(activity.started_at, activity.utc_offset_seconds), recordedLine(activity)]
    .filter(Boolean)
    .join(" · ");
}

/** A session in a line: its activity's, or Next and how long it is planned to take. */
export function sessionLine(session, next = false) {
  if (session.activity) return activityLine(session.activity);
  if (session.status === "skipped")
    return `Skipped · ${formatPlanned(session.planned_seconds)} planned`;
  return [next && "Next", formatPlanned(session.planned_seconds)].filter(Boolean).join(" · ");
}
