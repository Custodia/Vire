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

/** An ISO date such as 2026-10-23 as Fri 23 Oct. */
export function formatDay(isoDate) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return dayLabel.format(new Date(Date.UTC(year, month - 1, day)));
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
