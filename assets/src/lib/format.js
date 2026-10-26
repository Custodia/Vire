/** A planned duration the way the boards write it: 35′, 1h45, 2h. */
export function formatPlanned(seconds) {
  if (seconds == null) return "—";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}′`;
  const rest = minutes % 60;
  return `${Math.floor(minutes / 60)}h${rest === 0 ? "" : String(rest).padStart(2, "0")}`;
}
