import { describe, expect, test } from "vitest";
import { addMonths, dayOf, entriesOf, shiftDate, totalsOf, viewPeriod } from "./calendar.js";

const session = (id, fields = {}) => ({
  id,
  discipline: "run",
  title: id,
  planned_seconds: 1800,
  status: "planned",
  activity: null,
  ...fields,
});

const activity = (id, startedAt, seconds = 600) => ({
  id,
  discipline: "run",
  started_at: startedAt,
  utc_offset_seconds: 0,
  duration_seconds: seconds,
});

const answer = (date, sessions, activities = []) => ({
  date,
  day: { date, kind: sessions.length ? "training" : "rest", sessions },
  activities,
});

describe("calendar periods", () => {
  test("a week runs Monday to Sunday", () => {
    expect(viewPeriod("week", "2026-11-05")).toEqual({ first: "2026-11-02", last: "2026-11-08" });
    expect(viewPeriod("day", "2026-11-08")).toEqual({ first: "2026-11-02", last: "2026-11-08" });
  });

  test("a month holds the whole weeks it touches", () => {
    expect(viewPeriod("month", "2026-11-17")).toEqual({
      first: "2026-10-26",
      last: "2026-12-06",
    });
  });

  test("a month on keeps the day, or the next month's last when it is shorter", () => {
    expect(addMonths("2026-01-31", 1)).toBe("2026-02-28");
    expect(addMonths("2026-12-15", 1)).toBe("2027-01-15");
    expect(addMonths("2026-03-31", -1)).toBe("2026-02-28");
  });

  test("each view steps by its own period", () => {
    expect(shiftDate("day", "2026-11-03", -1)).toBe("2026-11-02");
    expect(shiftDate("week", "2026-11-03", 1)).toBe("2026-11-10");
    expect(shiftDate("month", "2026-11-03", 1)).toBe("2026-12-03");
  });
});

describe("a calendar day", () => {
  test("shows a session left planned on an earlier day as skipped", () => {
    const day = dayOf(answer("2026-11-02", [session("a")]), "2026-11-03");
    expect(day.sessions[0].status).toBe("skipped");
    expect(day.skipped).toBe(1);
  });

  test("keeps a rest day once it is past", () => {
    expect(dayOf(answer("2026-11-02", []), "2026-11-03").rest).toBe("kept");
    expect(dayOf(answer("2026-11-03", []), "2026-11-03").rest).toBe("ahead");
    expect(dayOf({ date: "2026-11-03", day: null, activities: [] }, "2026-11-03").rest).toBeNull();
  });

  test("adds up what was trained, matched or not, against what was planned", () => {
    const days = [
      dayOf(
        answer(
          "2026-11-03",
          [session("a", { status: "done", activity: activity("x", "2026-11-03T06:00:00Z", 1500) })],
          [activity("y", "2026-11-03T12:00:00Z", 900)],
        ),
        "2026-11-03",
      ),
      dayOf(answer("2026-11-04", [session("b")]), "2026-11-03"),
    ];

    expect(totalsOf(days)).toEqual({
      sessions: 2,
      done: 1,
      skipped: 0,
      trained: 2400,
      planned: 3600,
    });
  });

  test("lists what was recorded by its start, then the sessions left, marking today's next", () => {
    const day = dayOf(
      answer(
        "2026-11-03",
        [
          session("first"),
          session("late", { status: "done", activity: activity("x", "2026-11-03T18:00:00Z") }),
          session("second"),
        ],
        [activity("walk", "2026-11-03T12:00:00Z")],
      ),
      "2026-11-03",
    );

    expect(
      entriesOf(day, "2026-11-03").map((entry) => [
        entry.session?.id ?? entry.activity.id,
        entry.next,
      ]),
    ).toEqual([
      ["walk", false],
      ["late", false],
      ["first", true],
      ["second", false],
    ]);
  });
});
