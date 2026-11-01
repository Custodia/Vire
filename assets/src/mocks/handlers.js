import { http, HttpResponse } from "msw";
import { addDays } from "../lib/format.js";

// The API's shapes, as the server answers them, for the handlers below to
// serve and for tests to render.

// An activity's summary, as GET /api/days/:date answers it on a session and in
// its list of unmatched activities.
export const activities = {
  swim: {
    id: "b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4c01",
    discipline: "swim",
    started_at: "2026-11-03T04:32:00Z",
    utc_offset_seconds: 7200,
    duration_seconds: 4120,
    distance_m: 3050,
    training_load: 48.2,
  },
  ride: {
    id: "b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4c04",
    discipline: "bike",
    started_at: "2026-11-05T05:15:00Z",
    utc_offset_seconds: 7200,
    duration_seconds: 3720,
    distance_m: 30500,
    training_load: 72.4,
  },
  walk: {
    id: "b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4c02",
    discipline: "other",
    started_at: "2026-11-03T15:10:00Z",
    utc_offset_seconds: 7200,
    duration_seconds: 1500,
    distance_m: 2400,
    training_load: null,
  },
  run: {
    id: "b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4c03",
    discipline: "run",
    started_at: "2026-12-25T08:05:00Z",
    utc_offset_seconds: 7200,
    duration_seconds: 1845,
    distance_m: 5120,
    training_load: 31.5,
  },
};

export const sessions = {
  swim: {
    id: "5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e01",
    position: 0,
    discipline: "swim",
    title: "Swim — endurance",
    structure: {
      title: "Swim — endurance",
      steps: [
        { kind: "warmup", seconds: 600, zone: 1 },
        { repeat: 6, steps: [{ kind: "work", seconds: 480, zone: 2, target: "2:15 /100 m" }] },
        { kind: "cooldown", seconds: 300, zone: 1 },
      ],
    },
    planned_seconds: 4080,
    status: "done",
    rationale: "Long aerobic swim to hold technique under fatigue.",
    activity: activities.swim,
  },
  strength: {
    id: "5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e02",
    position: 1,
    discipline: "strength",
    title: "Strength",
    structure: {},
    planned_seconds: 2400,
    status: "skipped",
    rationale: "Two strength sessions a cycle keep the joints ready for running.",
    activity: null,
  },
  run: {
    id: "5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e03",
    position: 2,
    discipline: "run",
    title: "Run / walk — Z2",
    structure: {
      title: "Run / walk — Z2",
      note: "Easy aerobic, joints first. Walk breaks are part of the plan.",
      steps: [
        {
          repeat: 7,
          steps: [
            { kind: "work", seconds: 240, zone: 2, target: "< 145 bpm" },
            { kind: "recovery", seconds: 60, zone: 1, note: "Walk" },
          ],
        },
      ],
    },
    planned_seconds: 2100,
    status: "planned",
    rationale: "Run/walk keeps the load on the joints low while weight comes down.",
    activity: null,
  },
  bike: {
    id: "5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e04",
    position: 3,
    discipline: "bike",
    title: "Bike — threshold 3 × 12′",
    structure: {
      title: "Bike — threshold 3 × 12′",
      steps: [
        { kind: "warmup", seconds: 600, zone: 1, target: "150–170 W" },
        { kind: "warmup", seconds: 600, zone: 2, target: "180–200 W" },
        {
          repeat: 3,
          steps: [
            { kind: "work", seconds: 720, zone: 4, target: "275–289 W" },
            { kind: "recovery", seconds: 360, zone: 1, target: "< 160 W" },
          ],
        },
        { kind: "work", seconds: 1800, zone: 2, target: "195–215 W" },
        { kind: "cooldown", seconds: 420 },
      ],
    },
    planned_seconds: 6300,
    status: "planned",
    rationale:
      "Each load cycle adds two minutes per rep at the same intensity, to lift sustainable power before Base adds volume.",
    activity: null,
  },
  ride: {
    id: "5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e05",
    position: 0,
    discipline: "bike",
    title: "Bike — endurance with sprints",
    structure: {
      title: "Bike — endurance with sprints",
      steps: [
        { kind: "warmup", seconds: 900, zone: 1 },
        {
          repeat: 4,
          steps: [
            { kind: "work", seconds: 30, zone: 5, target: "> 400 W" },
            { kind: "recovery", seconds: 270, zone: 1, note: "Spin" },
          ],
        },
        { kind: "work", seconds: 1500, zone: 2 },
      ],
    },
    planned_seconds: 3600,
    status: "done",
    rationale: "Short sprints keep the top end while the volume stays aerobic.",
    activity: activities.ride,
  },
};

// The ids of the plan GET /api/seasons/:id answers with, below, for the chain
// above each day to name.
const planIds = {
  season: "9f1c0b2a-7d4e-4a1b-9c3d-5e6f7a8b9c01",
  base: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e01",
  endurance: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e02",
  endurance1: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e03",
  endurance2: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e04",
};

const chain = (dayNumber) => ({
  season: { id: planIds.season, name: "Autumn 10 km" },
  phase: { id: planIds.base, name: "Base" },
  block: { id: planIds.endurance, focus: "Aerobic endurance" },
  cycle: { id: planIds.endurance2, kind: "load", day_number: dayNumber, length: 7 },
});

// GET /api/days/:date, by date. Any other date is the plan's day on it, or
// outside the plan, with no activities.
export const days = {
  "2026-11-03": {
    date: "2026-11-03",
    day: {
      id: "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e03",
      date: "2026-11-03",
      kind: "training",
      note: null,
      chain: chain(2),
      sessions: [sessions.swim, sessions.strength, sessions.run, sessions.bike],
    },
    activities: [activities.walk],
  },
  "2026-11-04": {
    date: "2026-11-04",
    day: {
      id: "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e04",
      date: "2026-11-04",
      kind: "rest",
      note: "Travel day. Walk the airport, nothing more.",
      chain: chain(3),
      sessions: [],
    },
    activities: [],
  },
  "2026-11-05": {
    date: "2026-11-05",
    day: {
      id: "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e05",
      date: "2026-11-05",
      kind: "training",
      note: null,
      chain: chain(4),
      sessions: [sessions.ride],
    },
    activities: [],
  },
  "2026-12-25": { date: "2026-12-25", day: null, activities: [activities.run] },
};

const lap = (lap_index, started_at, elapsed_seconds, fields) => ({
  lap_index,
  started_at,
  elapsed_seconds,
  moving_seconds: elapsed_seconds,
  distance_m: 0,
  avg_heart_rate: null,
  avg_power: null,
  avg_speed_mps: null,
  ...fields,
});

const length = (length_index, lap_index, started_at, elapsed_seconds, stroke, strokes) => ({
  length_index,
  lap_index,
  started_at,
  elapsed_seconds,
  active: stroke !== null,
  stroke,
  strokes,
});

// GET /api/activities/:id, by id: the summary with the local date, the pool
// length, the average heart rate, the laps and the pool lengths. A session's matched activity in
// GET /api/sessions/:id has the same shape.
export const activityDetails = Object.fromEntries(
  [
    {
      ...activities.swim,
      local_date: "2026-11-03",
      pool_length_m: 25,
      avg_heart_rate: 131,
      laps: [
        lap(0, "2026-11-03T04:32:00.000000Z", 130, {
          distance_m: 100,
          avg_heart_rate: 128,
          avg_speed_mps: 0.769,
        }),
        lap(1, "2026-11-03T04:34:10.000000Z", 20, { moving_seconds: 0 }),
        lap(2, "2026-11-03T04:34:30.000000Z", 140, {
          distance_m: 100,
          avg_heart_rate: 134,
          avg_speed_mps: 0.714,
        }),
      ],
      lengths: [
        length(0, 0, "2026-11-03T04:32:00.000000Z", 32.4, "freestyle", 19),
        length(1, 0, "2026-11-03T04:32:32.400000Z", 32.8, "freestyle", 20),
        length(2, 0, "2026-11-03T04:33:05.200000Z", 32.1, "freestyle", 19),
        length(3, 0, "2026-11-03T04:33:37.300000Z", 32.7, "freestyle", 20),
        length(4, 1, "2026-11-03T04:34:10.000000Z", 20, null, null),
        length(5, 2, "2026-11-03T04:34:30.000000Z", 36.2, "breaststroke", 14),
        length(6, 2, "2026-11-03T04:35:06.200000Z", 35.8, "breaststroke", 14),
        length(7, 2, "2026-11-03T04:35:42.000000Z", 34.0, "freestyle", 20),
        length(8, 2, "2026-11-03T04:36:16.000000Z", 34.0, "freestyle", 21),
      ],
    },
    {
      ...activities.ride,
      local_date: "2026-11-05",
      pool_length_m: null,
      avg_heart_rate: 145,
      laps: [
        lap(0, "2026-11-05T05:15:00.000000Z", 1800, {
          distance_m: 15000,
          avg_heart_rate: 138,
          avg_power: 212,
          avg_speed_mps: 8.333,
        }),
        lap(1, "2026-11-05T05:45:00.000000Z", 1920, {
          moving_seconds: 1890,
          distance_m: 15500,
          avg_heart_rate: 151,
          avg_power: 236,
          avg_speed_mps: 8.201,
        }),
      ],
      lengths: [],
    },
    {
      ...activities.run,
      local_date: "2026-12-25",
      pool_length_m: null,
      avg_heart_rate: 152,
      laps: [
        lap(0, "2026-12-25T08:05:00.000000Z", 1845, {
          distance_m: 5120,
          avg_heart_rate: 152,
          avg_speed_mps: 2.775,
        }),
      ],
      lengths: [],
    },
    {
      ...activities.walk,
      local_date: "2026-11-03",
      pool_length_m: null,
      avg_heart_rate: null,
      laps: [],
      lengths: [],
    },
  ].map((activity) => [activity.id, activity]),
);

// The channels each activity recorded, one value per second from the start.
const recordings = {
  [activities.ride.id]: {
    heart_rate: { unit: "bpm", at: (second) => 130 + Math.round(20 * Math.sin(second / 600)) },
    power: {
      unit: "watts",
      at: (second) => (second < 60 ? null : 200 + (second % 300 < 30 ? 220 : 20)),
    },
  },
  [activities.run.id]: {
    heart_rate: { unit: "bpm", at: (second) => 140 + Math.round(second / 120) },
    speed: { unit: "m/s", at: (second) => (second % 300 < 240 ? 3.0 : 1.4) },
  },
};

// Earlier sessions like a session, by its id, as GET /api/sessions/:id names
// them in last_time.
const lastTimes = {
  [sessions.run.id]: {
    session_id: "5a0c3c51-8f4e-4c2e-9d55-0d7f1b8a6e06",
    date: "2026-10-30",
    activity: {
      id: "b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4c05",
      discipline: "run",
      started_at: "2026-10-30T16:02:00Z",
      utc_offset_seconds: 3600,
      duration_seconds: 2400,
      distance_m: 5100,
      training_load: 38.6,
      avg_heart_rate: 139,
    },
  },
};

// Matches PUT /api/sessions/:id/activity made, activity ids by session id.
const matches = new Map();

const summaryOf = (id) => Object.values(activities).find((activity) => activity.id === id);

function withMatch(session) {
  if (!matches.has(session.id)) return session;
  return { ...session, status: "done", activity: summaryOf(matches.get(session.id)) };
}

// GET /api/sessions/:id: the session as a day lists it, with its day and the
// chain above it, its matched activity in full, and the last session like it.
function sessionDetail(session) {
  const { sessions: _sessions, ...day } = Object.values(days).find((answer) =>
    answer.day?.sessions.includes(session),
  ).day;
  const matched = withMatch(session);
  return {
    ...matched,
    day,
    activity: activityDetails[matched.activity?.id] ?? null,
    last_time: lastTimes[session.id] ?? null,
  };
}

// The plan's day on a date with the chain above it, as GET /api/days/:date
// answers a date it has no answer of its own for.
function planAnswer(date) {
  for (const phase of season.phases) {
    for (const block of phase.blocks) {
      for (const cycle of block.cycles) {
        const index = cycle.days.findIndex((day) => day.date === date);
        if (index === -1) continue;
        const chain = {
          season: { id: season.id, name: season.name },
          phase: { id: phase.id, name: phase.name },
          block: { id: block.id, focus: block.focus },
          cycle: {
            id: cycle.id,
            kind: cycle.kind,
            day_number: index + 1,
            length: cycle.days.length,
          },
        };
        return { date, day: { ...cycle.days[index], chain }, activities: [] };
      }
    }
  }
  return { date, day: null, activities: [] };
}

function nextDate(date) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + 1)).toISOString().slice(0, 10);
}

function dayAnswer(date) {
  const answer = days[date] ?? planAnswer(date);
  if (!answer.day) return answer;
  const sessions = answer.day.sessions.map(withMatch);
  const taken = new Set(sessions.map((session) => session.activity?.id));
  return {
    ...answer,
    day: { ...answer.day, sessions },
    activities: answer.activities.filter((activity) => !taken.has(activity.id)),
  };
}

export const user = {
  id: "0b6f1c9e-2d4a-4f7b-9a3c-5e8d7f6a1b20",
  email: "ada@example.com",
  name: "Ada Lovelace",
};

export const password = "correct-horse-battery";

// Whether the browser holds a signed-in session, which tests start with, and
// the session's CSRF token, which GET /api/csrf hands out and signing in and
// out end.
export const mockSession = { signedIn: true, csrfToken: null };

let tokensIssued = 0;

// The plan GET /api/seasons and GET /api/seasons/:id answer with, around the
// 3rd of November 2026 the screen tests set the clock to.
// Sessions on the days GET /api/days/:date does not answer for itself.
const plannedSessions = {
  "2026-10-26": [{ discipline: "run", title: "Easy run", planned_seconds: 2700, status: "done" }],
  "2026-10-28": [
    { discipline: "swim", title: "Technique swim", planned_seconds: 3600, status: "skipped" },
  ],
};

function planDays(first, last) {
  const planned = [];
  for (let date = first; date <= last; date = addDays(date, 1)) {
    const sessions = (plannedSessions[date] ?? []).map((session, index) => ({
      id: `session-${date}-${index}`,
      position: index,
      structure: {},
      rationale: null,
      activity: null,
      ...session,
    }));
    planned.push(
      days[date]?.day ?? {
        id: `day-${date}`,
        date,
        kind: sessions.length > 0 ? "training" : "rest",
        note: null,
        sessions,
      },
    );
  }
  return planned;
}

const planCycle = (id, kind, first, last) => ({
  id,
  kind,
  period: { first, last },
  days: planDays(first, last),
});

export const season = {
  id: planIds.season,
  name: "Autumn 10 km",
  period: { first: "2026-10-05", last: "2026-12-27" },
  rationale: "Ten kilometres in December, with the weight coming down on the way.",
  phases: [
    {
      id: planIds.base,
      name: "Base",
      rationale: "Aerobic volume first, with steady weight loss.",
      period: { first: "2026-10-05", last: "2026-11-15" },
      blocks: [
        {
          id: planIds.endurance,
          focus: "Aerobic endurance",
          period: { first: "2026-10-26", last: "2026-11-08" },
          cycles: [
            planCycle(planIds.endurance1, "load", "2026-10-26", "2026-11-01"),
            planCycle(planIds.endurance2, "load", "2026-11-02", "2026-11-08"),
          ],
        },
      ],
    },
    {
      id: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e05",
      name: "Build",
      rationale: "Threshold work towards race pace.",
      period: { first: "2026-11-16", last: "2026-12-27" },
      blocks: [
        {
          id: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e06",
          focus: "Threshold",
          period: { first: "2026-11-16", last: "2026-11-29" },
          cycles: [
            planCycle("6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e07", "load", "2026-11-16", "2026-11-25"),
            planCycle(
              "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e08",
              "recovery",
              "2026-11-26",
              "2026-11-29",
            ),
          ],
        },
      ],
    },
  ],
  activities: [
    {
      id: "c3d1e7a0-5b2f-4c8e-9a61-2f7d0e4b8a10",
      discipline: "other",
      local_date: "2026-10-31",
      started_at: "2026-10-31T09:00:00Z",
      utc_offset_seconds: 3600,
      duration_seconds: 2700,
      distance_m: 3600,
      training_load: null,
    },
  ],
};

const seasonEntry = { id: season.id, name: season.name, period: season.period };

// What GET /api/seasons lists. A test empties it to reach the screen's own
// empty state.
export const mockPlan = { seasons: [seasonEntry] };

// What GET /api/plan_changes answers. A test empties it to reach the coach
// log's own empty state.
const planChanges = [
  {
    id: "c1a2b3c4-0000-4000-8000-000000000001",
    entity: "session",
    action: "update",
    subject: "Threshold intervals",
    rationale: "HRV below its band for three nights. Thursday became an easy ride.",
    channel: "mcp",
    client: "Coach",
    at: "2026-11-02T12:00:00Z",
  },
  {
    id: "c1a2b3c4-0000-4000-8000-000000000002",
    entity: "cycle",
    action: "insert",
    subject: "recovery",
    rationale: "Four easy days before the threshold block.",
    channel: "mcp",
    client: "Coach",
    at: "2026-10-30T12:00:00Z",
  },
];

export const mockPlanChanges = { changes: planChanges };

export function resetMocks() {
  mockSession.signedIn = true;
  mockSession.csrfToken = null;
  matches.clear();
  mockPlan.seasons = [seasonEntry];
  mockPlanChanges.changes = planChanges;
}

// Answers like the :authenticated pipeline: 401 without a session.
const signedIn =
  (resolver) =>
  (...args) =>
    mockSession.signedIn
      ? resolver(...args)
      : HttpResponse.json({ errors: { detail: "Unauthorized" } }, { status: 401 });

const notFound = () => HttpResponse.json({ errors: { detail: "Not Found" } }, { status: 404 });

const safeMethods = new Set(["GET", "HEAD", "OPTIONS"]);

const refusedToken = () =>
  HttpResponse.json(
    {
      reason: "invalid_csrf_token",
      errors: { detail: "The request does not carry the session's CSRF token" },
    },
    { status: 403 },
  );

export const handlers = [
  // Answers like the :api pipeline: 403 to an unsafe request without the
  // session's token, and on to the handlers below otherwise.
  http.all("/api/*", ({ request }) => {
    if (safeMethods.has(request.method)) return undefined;
    const token = request.headers.get("x-csrf-token");
    return token && token === mockSession.csrfToken ? undefined : refusedToken();
  }),

  http.get("/api/csrf", () => {
    mockSession.csrfToken ??= `csrf-token-${++tokensIssued}`;
    return HttpResponse.json({ token: mockSession.csrfToken });
  }),

  http.get("/api/health", () => HttpResponse.json({ status: "ok" })),

  http.post("/api/session", async ({ request }) => {
    const body = await request.json();
    if (body.email?.toLowerCase() !== user.email || body.password !== password) {
      return HttpResponse.json(
        { errors: { detail: "Invalid email or password" } },
        { status: 401 },
      );
    }
    mockSession.signedIn = true;
    mockSession.csrfToken = null;
    return HttpResponse.json(user);
  }),

  http.delete("/api/session", () => {
    mockSession.signedIn = false;
    mockSession.csrfToken = null;
    return new HttpResponse(null, { status: 204 });
  }),

  http.get(
    "/api/me",
    signedIn(() => HttpResponse.json(user)),
  ),

  http.get(
    "/api/seasons",
    signedIn(() => HttpResponse.json({ seasons: mockPlan.seasons })),
  ),

  http.get(
    "/api/plan_changes",
    signedIn(() => HttpResponse.json({ changes: mockPlanChanges.changes })),
  ),

  http.get(
    "/api/seasons/:id",
    signedIn(({ params }) => (params.id === season.id ? HttpResponse.json(season) : notFound())),
  ),

  http.get(
    "/api/days",
    signedIn(({ request }) => {
      const url = new URL(request.url);
      const [from, to] = [url.searchParams.get("from"), url.searchParams.get("to")];
      const answers = [];
      for (let date = from; date <= to; date = nextDate(date)) answers.push(dayAnswer(date));
      return HttpResponse.json({ days: answers });
    }),
  ),

  http.get(
    "/api/days/:date",
    signedIn(({ params }) => HttpResponse.json(dayAnswer(params.date))),
  ),

  http.get(
    "/api/sessions/:id",
    signedIn(({ params }) => {
      const session = Object.values(sessions).find(({ id }) => id === params.id);
      return session ? HttpResponse.json(sessionDetail(session)) : notFound();
    }),
  ),

  http.put(
    "/api/sessions/:id/activity",
    signedIn(async ({ params, request }) => {
      const session = Object.values(sessions).find(({ id }) => id === params.id);
      if (!session) return notFound();
      const { activity_id: activityId } = await request.json();
      const date = sessionDetail(session).day.date;
      if (!dayAnswer(date).activities.some(({ id }) => id === activityId)) {
        return HttpResponse.json(
          { errors: { detail: "the activity is on another date" } },
          { status: 422 },
        );
      }
      matches.set(session.id, activityId);
      return HttpResponse.json(sessionDetail(session));
    }),
  ),

  http.get(
    "/api/activities/:id",
    signedIn(({ params }) =>
      activityDetails[params.id] ? HttpResponse.json(activityDetails[params.id]) : notFound(),
    ),
  ),

  // Every recorded channel unless `channels` names some, one sample per `step`
  // seconds; a channel the activity did not record is left out.
  http.get(
    "/api/activities/:id/streams",
    signedIn(({ params, request }) => {
      const activity = activityDetails[params.id];
      if (!activity) return notFound();

      const query = new URL(request.url).searchParams;
      const step = Number(query.get("step"));
      if (!Number.isInteger(step) || step < 1) {
        return HttpResponse.json(
          { errors: { detail: "step must be a whole number of seconds from 1" } },
          { status: 400 },
        );
      }

      const recorded = recordings[activity.id] ?? {};
      const channels = query.get("channels")?.split(",") ?? Object.keys(recorded);
      const count = Math.ceil(activity.duration_seconds / step);
      const streams = Object.fromEntries(
        channels
          .filter((channel) => recorded[channel])
          .map((channel) => [
            channel,
            {
              unit: recorded[channel].unit,
              samples: Array.from({ length: count }, (_, index) =>
                recorded[channel].at(index * step),
              ),
            },
          ]),
      );
      return HttpResponse.json({ activity_id: activity.id, step, streams });
    }),
  ),
];
