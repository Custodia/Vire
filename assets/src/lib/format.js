const dayLabel = new Intl.DateTimeFormat("en-GB", {
  weekday: "short",
  day: "numeric",
  month: "short",
  timeZone: "UTC",
});

const timeOfDay = new Intl.DateTimeFormat("en-GB", {
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
  timeZone: "UTC",
});

/** A planned duration the way the boards write it: 35′, 1h45, 2h. */
export function formatPlanned(seconds) {
  if (seconds == null) return "—";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}′`;
  const rest = minutes % 60;
  return `${Math.floor(minutes / 60)}h${rest === 0 ? "" : String(rest).padStart(2, "0")}`;
}

/** A step's duration: whole minutes as 12′, anything else with its seconds, as 30″ or 1′30″. */
export function formatStepDuration(seconds) {
  if (seconds % 60 === 0) return formatPlanned(seconds);
  const minutes = Math.floor(seconds / 60);
  const secs = `${seconds % 60}″`;
  return minutes > 0 ? `${minutes}′${secs.padStart(3, "0")}` : secs;
}

/** The time a speed in metres per second takes to cover `metres`, as 5:12, or a dash. */
export function formatPace(speed, metres) {
  return speed > 0 ? formatClock(metres / speed) : "—";
}

/** A recorded duration on a clock: 9:05 or 1:08:40. */
export function formatClock(seconds) {
  const total = Math.round(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = String(total % 60).padStart(2, "0");
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}:${secs}` : `${minutes}:${secs}`;
}

/** A distance in metres below a kilometre, in kilometres from there. */
export function formatDistance(metres) {
  return metres < 1000 ? `${Math.round(metres)} m` : `${(metres / 1000).toFixed(2)} km`;
}

const dayInWeek = new Intl.DateTimeFormat("en-GB", {
  weekday: "short",
  day: "numeric",
  timeZone: "UTC",
});

const dayAndMonth = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  timeZone: "UTC",
});

const monthName = new Intl.DateTimeFormat("en-GB", { month: "short", timeZone: "UTC" });

const weekdayName = new Intl.DateTimeFormat("en-GB", { weekday: "short", timeZone: "UTC" });

const longDay = new Intl.DateTimeFormat("en-GB", {
  weekday: "long",
  day: "numeric",
  month: "short",
  timeZone: "UTC",
});

const monthAndYear = new Intl.DateTimeFormat("en-GB", {
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

/** An ISO date such as 2026-10-23 as Friday 23 Oct. */
export function formatLongDay(isoDate) {
  return longDay.format(asDate(isoDate));
}

/** An ISO date's month and year: October 2026. */
export function formatMonthAndYear(isoDate) {
  return monthAndYear.format(asDate(isoDate));
}

/** The dates a period runs between, its month written once when both share it: 19 – 25 Oct. */
export function formatDates({ first, last }) {
  const day = (date) => Number(date.slice(8));
  return first.slice(0, 7) === last.slice(0, 7)
    ? `${day(first)} – ${formatDayAndMonth(last)}`
    : `${formatDayAndMonth(first)} – ${formatDayAndMonth(last)}`;
}

/** An ISO date such as 2026-10-23 as Fri 23 Oct. */
export function formatDay(isoDate) {
  return dayLabel.format(asDate(isoDate));
}

function asDate(isoDate) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

/** An ISO date as its weekday and day of the month: Fri 23. */
export function formatDayInWeek(isoDate) {
  return dayInWeek.format(asDate(isoDate));
}

/** An ISO date as its day and month: 23 Oct. */
export function formatDayAndMonth(isoDate) {
  return dayAndMonth.format(asDate(isoDate));
}

/** An ISO date as its month alone: Oct. */
export function formatMonthName(isoDate) {
  return monthName.format(asDate(isoDate));
}

/** An ISO date as its weekday alone: Fri. */
export function formatWeekday(isoDate) {
  return weekdayName.format(asDate(isoDate));
}

/** Seconds as hours to one decimal: 8.5. */
export function formatHours(seconds) {
  return (seconds / 3600).toFixed(1);
}

/** The ISO date a number of days after an ISO date, or before it when negative. */
export function addDays(isoDate, days) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

/** Whether a string is a calendar date written as YYYY-MM-DD. */
export function isIsoDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && addDays(value, 0) === value;
}

/** The wall-clock time an activity started where it was recorded, such as 06:32. */
export function formatStartTime(startedAt, utcOffsetSeconds) {
  return timeOfDay.format(new Date(Date.parse(startedAt) + (utcOffsetSeconds ?? 0) * 1000));
}

/** The browser's local date as YYYY-MM-DD. */
export function localDate(now = new Date()) {
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}
