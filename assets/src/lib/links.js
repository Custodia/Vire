import { views } from "./calendar.js";

const VIEW_KEY = "vire.calendar-view";

/** Where the calendar shows a date in one of its views. */
export function calendarLink(view, date) {
  return { to: "/calendar/$view/$date", params: { view, date } };
}

/** Where the calendar shows a date's day. */
export function dayLink(date) {
  return calendarLink("day", date);
}

/** Where a session is shown. */
export function sessionLink(id) {
  return { to: "/sessions/$id", params: { id } };
}

/** Where an activity no session is matched to is shown. */
export function activityLink(id) {
  return { to: "/activities/$id", params: { id } };
}

/** The calendar view last shown, which the calendar opens in. */
export function calendarView() {
  const view = localStorage.getItem(VIEW_KEY);
  return views.includes(view) ? view : "day";
}

/** Keeps `view` as the one the calendar opens in. */
export function rememberCalendarView(view) {
  localStorage.setItem(VIEW_KEY, view);
}
