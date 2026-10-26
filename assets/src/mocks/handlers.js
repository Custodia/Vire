import { http, HttpResponse } from "msw";

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

const chain = (dayNumber) => ({
  season: { id: "9d1e2f30-4a5b-4c6d-8e7f-a0b1c2d3e401", name: "Winter base" },
  phase: { id: "9d1e2f30-4a5b-4c6d-8e7f-a0b1c2d3e402", name: "Base" },
  block: { id: "9d1e2f30-4a5b-4c6d-8e7f-a0b1c2d3e403", focus: "Aerobic endurance" },
  cycle: {
    id: "9d1e2f30-4a5b-4c6d-8e7f-a0b1c2d3e404",
    kind: "load",
    day_number: dayNumber,
    length: 7,
  },
});

// GET /api/days/:date, by date. Any other date lies outside the plan with no
// activities.
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
// length, the laps and the pool lengths. A session's matched activity in
// GET /api/sessions/:id has the same shape.
export const activityDetails = Object.fromEntries(
  [
    {
      ...activities.swim,
      local_date: "2026-11-03",
      pool_length_m: 25,
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
      laps: [
        lap(0, "2026-12-25T08:05:00.000000Z", 1845, {
          distance_m: 5120,
          avg_heart_rate: 152,
          avg_speed_mps: 2.775,
        }),
      ],
      lengths: [],
    },
    { ...activities.walk, local_date: "2026-11-03", pool_length_m: null, laps: [], lengths: [] },
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

// GET /api/sessions/:id: the session as a day lists it, with its day and the
// chain above it, and its matched activity in full.
function sessionDetail(session) {
  const { sessions: _sessions, ...day } = Object.values(days).find((answer) =>
    answer.day?.sessions.includes(session),
  ).day;
  return { ...session, day, activity: activityDetails[session.activity?.id] ?? null };
}

export const user = {
  id: "0b6f1c9e-2d4a-4f7b-9a3c-5e8d7f6a1b20",
  email: "ada@example.com",
  name: "Ada Lovelace",
};

export const password = "correct-horse-battery";

// Whether the browser holds a signed-in session. Tests start signed in.
export const mockSession = { signedIn: true };

export function resetMocks() {
  mockSession.signedIn = true;
}

// Answers like the :authenticated pipeline: 401 without a session.
const signedIn =
  (resolver) =>
  (...args) =>
    mockSession.signedIn
      ? resolver(...args)
      : HttpResponse.json({ errors: { detail: "Unauthorized" } }, { status: 401 });

const notFound = () => HttpResponse.json({ errors: { detail: "Not Found" } }, { status: 404 });

export const handlers = [
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
    return HttpResponse.json(user);
  }),

  http.delete("/api/session", () => {
    mockSession.signedIn = false;
    return new HttpResponse(null, { status: 204 });
  }),

  http.get(
    "/api/me",
    signedIn(() => HttpResponse.json(user)),
  ),

  http.get(
    "/api/days/:date",
    signedIn(({ params }) =>
      HttpResponse.json(days[params.date] ?? { date: params.date, day: null, activities: [] }),
    ),
  ),

  http.get(
    "/api/sessions/:id",
    signedIn(({ params }) => {
      const session = Object.values(sessions).find(({ id }) => id === params.id);
      return session ? HttpResponse.json(sessionDetail(session)) : notFound();
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
