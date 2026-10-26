import { http, HttpResponse } from "msw";

// The API's shapes, as the server answers them, for the handlers below to
// serve and for tests to render.

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
    activity: {
      id: "b7a1d2c4-3e5f-4a6b-8c9d-0e1f2a3b4c01",
      discipline: "swim",
      started_at: "2026-11-03T04:32:00Z",
      utc_offset_seconds: 7200,
      duration_seconds: 4120,
      distance_m: 3050,
      training_load: 48.2,
    },
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

export const activities = {
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
  "2026-12-25": { date: "2026-12-25", day: null, activities: [activities.run] },
};

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
];
