const dayLabel = new Intl.DateTimeFormat("en-GB", {
  weekday: "short",
  day: "numeric",
  month: "short",
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

const dayAndMonth = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  timeZone: "UTC",
});

const monthName = new Intl.DateTimeFormat("en-GB", { month: "short", timeZone: "UTC" });

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

/** An ISO date as its day and month: 23 Oct. */
export function formatDayAndMonth(isoDate) {
  return dayAndMonth.format(asDate(isoDate));
}

/** An ISO date as its month alone: Oct. */
export function formatMonthName(isoDate) {
  return monthName.format(asDate(isoDate));
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

/** The browser's local date as YYYY-MM-DD. */
export function localDate(now = new Date()) {
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}
