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

export const handlers = [http.get("/api/health", () => HttpResponse.json({ status: "ok" }))];
