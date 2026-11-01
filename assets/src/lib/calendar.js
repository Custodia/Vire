import { shownStatus } from "./plan.js";

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
