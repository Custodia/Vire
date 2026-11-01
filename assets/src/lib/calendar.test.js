import { describe, expect, test } from "vitest";
import { dayOf } from "./calendar.js";

const session = (id, fields = {}) => ({
  id,
  discipline: "run",
  title: id,
  planned_seconds: 1800,
  status: "planned",
  activity: null,
  ...fields,
});

const answer = (date, sessions, activities = []) => ({
  date,
  day: { date, kind: sessions.length ? "training" : "rest", sessions },
  activities,
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
});
