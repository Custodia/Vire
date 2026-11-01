import { http, HttpResponse } from "msw";
import { addDays } from "../lib/format.js";

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
const plannedSessions = {
  "2026-10-26": [{ discipline: "run", title: "Easy run", planned_seconds: 2700, status: "done" }],
  "2026-10-28": [
    { discipline: "swim", title: "Technique swim", planned_seconds: 3600, status: "skipped" },
  ],
  "2026-11-03": [
    { discipline: "run", title: "Threshold intervals", planned_seconds: 3600, status: "planned" },
    { discipline: "swim", title: "Technique swim", planned_seconds: 2700, status: "skipped" },
  ],
  "2026-11-05": [
    { discipline: "bike", title: "Endurance ride", planned_seconds: 5400, status: "planned" },
  ],
};

function planDays(first, last) {
  const days = [];
  for (let date = first; date <= last; date = addDays(date, 1)) {
    const planned = plannedSessions[date] ?? [];
    days.push({
      id: `day-${date}`,
      date,
      kind: planned.length > 0 ? "training" : "rest",
      note: null,
      sessions: planned.map((session, index) => ({
        id: `session-${date}-${index}`,
        position: index,
        ...session,
      })),
    });
  }
  return days;
}

const planCycle = (id, kind, first, last) => ({
  id,
  kind,
  period: { first, last },
  days: planDays(first, last),
});

export const season = {
  id: "9f1c0b2a-7d4e-4a1b-9c3d-5e6f7a8b9c01",
  name: "Autumn 10 km",
  period: { first: "2026-10-05", last: "2026-12-27" },
  rationale: "Ten kilometres in December, with the weight coming down on the way.",
  phases: [
    {
      id: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e01",
      name: "Base",
      rationale: "Aerobic volume first, with steady weight loss.",
      period: { first: "2026-10-05", last: "2026-11-15" },
      blocks: [
        {
          id: "6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e02",
          focus: "Aerobic endurance",
          period: { first: "2026-10-26", last: "2026-11-08" },
          cycles: [
            planCycle("6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e03", "load", "2026-10-26", "2026-11-01"),
            planCycle("6b2e1f30-1c44-4f2a-8b7d-0a1b2c3d4e04", "load", "2026-11-02", "2026-11-08"),
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
];
