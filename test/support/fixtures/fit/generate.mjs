// Writes the synthetic .fit fixtures in this directory with Garmin's FIT SDK
// encoder, then decodes each one to check it. Run it from the decoder package:
// `npm run fixtures` in decoder/.

import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const decoderPackage = createRequire(join(here, "../../../../decoder/package.json"));
const { Decoder, Encoder, Profile, Stream, Utils } = await import(
  pathToFileURL(decoderPackage.resolve("@garmin/fitsdk")).href
);

const { MesgNum } = Profile;
const SEMICIRCLES_PER_DEGREE = 2 ** 31 / 180;

const at = (start, seconds) => new Date(start.getTime() + seconds * 1000);
const fitSeconds = (date) => Math.round((date.getTime() - Utils.FIT_EPOCH_MS) / 1000);
const wave = (t, period, amplitude) => amplitude * Math.sin((2 * Math.PI * t) / period);
const round = (value, places) => Number(value.toFixed(places));

function header(encoder, start, product) {
  encoder.onMesg(MesgNum.FILE_ID, {
    type: "activity",
    manufacturer: "development",
    product,
    serialNumber: 1000 + product,
    timeCreated: start,
  });
  encoder.onMesg(MesgNum.DEVICE_INFO, {
    timestamp: start,
    deviceIndex: "creator",
    manufacturer: "development",
    product,
    softwareVersion: 1.0,
  });
}

function timer(encoder, timestamp, eventType) {
  encoder.onMesg(MesgNum.EVENT, { timestamp, event: "timer", eventType });
}

function activity(encoder, end, timerSeconds, utcOffsetSeconds) {
  encoder.onMesg(MesgNum.ACTIVITY, {
    timestamp: end,
    localTimestamp: fitSeconds(end) + utcOffsetSeconds,
    totalTimerTime: timerSeconds,
    numSessions: 1,
    type: "manual",
    event: "activity",
    eventType: "stop",
  });
}

function mean(values) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

// A road ride of ten minutes elapsed: records every second with power, heart
// rate, cadence, speed, distance and a developer grade field, two laps, and a
// pause from 360 s to 420 s with no records.
function ride() {
  const start = new Date("2026-07-15T02:00:00Z");
  const utcOffset = -7 * 3600;
  const grade = {
    developerDataIdMesg: {
      developerDataIndex: 0,
      applicationId: Array.from({ length: 16 }, (_, i) => i + 1),
      applicationVersion: 1,
    },
    fieldDescriptionMesg: {
      developerDataIndex: 0,
      fieldDefinitionNumber: 0,
      fitBaseTypeId: 1,
      fieldName: "Grade",
      units: "%",
      nativeMesgNum: MesgNum.RECORD,
    },
  };
  const encoder = new Encoder({ fieldDescriptions: { 0: grade } });
  header(encoder, start, 1);
  encoder.onMesg(MesgNum.DEVELOPER_DATA_ID, grade.developerDataIdMesg);
  encoder.onMesg(MesgNum.FIELD_DESCRIPTION, grade.fieldDescriptionMesg);

  const pause = { from: 360, to: 420 };
  const laps = [
    { from: 0, to: 240 },
    { from: 240, to: 600 },
  ];
  const records = [];
  let distance = 0;
  for (let t = 0; t < 600; t++) {
    if (t >= pause.from && t < pause.to) continue;
    const speed = round(8.5 + wave(t, 90, 0.6), 3);
    records.push({
      t,
      timestamp: at(start, t),
      power: Math.round(215 + wave(t, 60, 35)),
      heartRate: Math.round(138 + wave(t, 240, 12) + t / 40),
      cadence: Math.round(89 + wave(t, 45, 4)),
      speed,
      distance: round(distance, 2),
      developerFields: { 0: Math.round(wave(t, 120, 4)) },
    });
    distance += speed;
  }

  timer(encoder, start, "start");
  for (const { t, ...fields } of records) {
    if (t === pause.to) timer(encoder, at(start, pause.to), "start");
    encoder.onMesg(MesgNum.RECORD, fields);
    if (t === pause.from - 1) timer(encoder, at(start, pause.from), "stopAll");
  }
  timer(encoder, at(start, 600), "stopAll");

  laps.forEach((lap, index) => {
    const inLap = records.filter((r) => r.t >= lap.from && r.t < lap.to);
    const paused = Math.max(0, Math.min(lap.to, pause.to) - Math.max(lap.from, pause.from));
    const lapDistance = inLap.reduce((sum, r) => sum + r.speed, 0);
    encoder.onMesg(MesgNum.LAP, {
      messageIndex: index,
      timestamp: at(start, lap.to),
      startTime: at(start, lap.from),
      totalElapsedTime: lap.to - lap.from,
      totalTimerTime: lap.to - lap.from - paused,
      totalDistance: round(lapDistance, 2),
      avgSpeed: round(lapDistance / (lap.to - lap.from - paused), 3),
      avgHeartRate: Math.round(mean(inLap.map((r) => r.heartRate))),
      avgPower: Math.round(mean(inLap.map((r) => r.power))),
      avgCadence: Math.round(mean(inLap.map((r) => r.cadence))),
      event: "lap",
      eventType: "stop",
      lapTrigger: index === laps.length - 1 ? "sessionEnd" : "manual",
      sport: "cycling",
    });
  });

  encoder.onMesg(MesgNum.SESSION, {
    messageIndex: 0,
    timestamp: at(start, 600),
    startTime: start,
    totalElapsedTime: 600,
    totalTimerTime: 540,
    totalDistance: round(distance, 2),
    avgSpeed: round(distance / 540, 3),
    avgHeartRate: Math.round(mean(records.map((r) => r.heartRate))),
    avgPower: Math.round(mean(records.map((r) => r.power))),
    sport: "cycling",
    subSport: "road",
    firstLapIndex: 0,
    numLaps: laps.length,
    event: "session",
    eventType: "stop",
    trigger: "activityEnd",
  });
  activity(encoder, at(start, 600), 540, utcOffset);
  return encoder.close();
}

// A run of ten minutes: records every second with heart rate, cadence with its
// fractional part, speed, altitude, distance and position, in one lap.
function run() {
  const start = new Date("2026-07-16T05:45:00Z");
  const utcOffset = 3 * 3600;
  const encoder = new Encoder();
  header(encoder, start, 2);

  const origin = { lat: 60.1699, long: 24.9384 };
  const records = [];
  let distance = 0;
  for (let t = 0; t < 600; t++) {
    const speed = round(3.3 + wave(t, 120, 0.25), 3);
    const metres = distance;
    records.push({
      timestamp: at(start, t),
      positionLat: Math.round((origin.lat + metres / 111_320) * SEMICIRCLES_PER_DEGREE),
      positionLong: Math.round((origin.long + wave(t, 600, 0.002)) * SEMICIRCLES_PER_DEGREE),
      heartRate: Math.round(148 + wave(t, 300, 8) + t / 60),
      cadence: Math.round(84 + wave(t, 90, 2)),
      fractionalCadence: 0.5,
      enhancedSpeed: speed,
      enhancedAltitude: round(20 + wave(t, 200, 6), 1),
      distance: round(metres, 2),
    });
    distance += speed;
  }

  timer(encoder, start, "start");
  records.forEach((record) => encoder.onMesg(MesgNum.RECORD, record));
  timer(encoder, at(start, 600), "stopAll");

  const totals = {
    timestamp: at(start, 600),
    startTime: start,
    totalElapsedTime: 600,
    totalTimerTime: 600,
    totalDistance: round(distance, 2),
    enhancedAvgSpeed: round(distance / 600, 3),
    avgHeartRate: Math.round(mean(records.map((r) => r.heartRate))),
    avgCadence: Math.round(mean(records.map((r) => r.cadence))),
    sport: "running",
  };
  encoder.onMesg(MesgNum.LAP, {
    ...totals,
    messageIndex: 0,
    event: "lap",
    eventType: "stop",
    lapTrigger: "sessionEnd",
  });
  encoder.onMesg(MesgNum.SESSION, {
    ...totals,
    messageIndex: 0,
    subSport: "street",
    firstLapIndex: 0,
    numLaps: 1,
    event: "session",
    eventType: "stop",
    trigger: "activityEnd",
  });
  activity(encoder, at(start, 600), 600, utcOffset);
  return encoder.close();
}

// A pool swim of 300 m in a 25 m pool: three intervals of four lengths,
// freestyle, breaststroke and freestyle, with a rest at the wall after the
// first two. Each interval and each rest is a lap. There are no records.
function swim() {
  const start = new Date("2026-01-20T17:00:00Z");
  const utcOffset = 2 * 3600;
  const encoder = new Encoder();
  header(encoder, start, 3);

  const plan = [
    { stroke: "freestyle", lengths: [24, 25, 25, 26], strokes: [16, 17, 17, 18] },
    { rest: 30 },
    { stroke: "breaststroke", lengths: [32, 33, 33, 34], strokes: [11, 12, 12, 12] },
    { rest: 20 },
    { stroke: "freestyle", lengths: [25, 25, 26, 27], strokes: [17, 17, 18, 18] },
  ];

  let t = 0;
  let lengthIndex = 0;
  const lengths = [];
  const laps = [];
  for (const interval of plan) {
    const lapStart = t;
    const firstLengthIndex = lengthIndex;
    if (interval.rest) {
      lengths.push({
        messageIndex: lengthIndex++,
        timestamp: at(start, t + interval.rest),
        startTime: at(start, t),
        totalElapsedTime: interval.rest,
        totalTimerTime: interval.rest,
        lengthType: "idle",
        event: "length",
        eventType: "stop",
      });
      t += interval.rest;
    } else {
      interval.lengths.forEach((seconds, i) => {
        lengths.push({
          messageIndex: lengthIndex++,
          timestamp: at(start, t + seconds),
          startTime: at(start, t),
          totalElapsedTime: seconds,
          totalTimerTime: seconds,
          totalStrokes: interval.strokes[i],
          avgSpeed: round(25 / seconds, 3),
          swimStroke: interval.stroke,
          lengthType: "active",
          event: "length",
          eventType: "stop",
        });
        t += seconds;
      });
    }
    const active = interval.rest ? 0 : interval.lengths.length;
    laps.push({
      messageIndex: laps.length,
      timestamp: at(start, t),
      startTime: at(start, lapStart),
      totalElapsedTime: t - lapStart,
      totalTimerTime: t - lapStart,
      totalDistance: active * 25,
      firstLengthIndex,
      numLengths: lengthIndex - firstLengthIndex,
      numActiveLengths: active,
      ...(interval.rest ? {} : { swimStroke: interval.stroke }),
      event: "lap",
      eventType: "stop",
      lapTrigger: "manual",
      sport: "swimming",
      subSport: "lapSwimming",
    });
  }

  timer(encoder, start, "start");
  lengths.forEach((length) => encoder.onMesg(MesgNum.LENGTH, length));
  timer(encoder, at(start, t), "stopAll");
  laps.forEach((lap) => encoder.onMesg(MesgNum.LAP, lap));
  const activeLengths = lengths.filter((l) => l.lengthType === "active").length;
  encoder.onMesg(MesgNum.SESSION, {
    messageIndex: 0,
    timestamp: at(start, t),
    startTime: start,
    totalElapsedTime: t,
    totalTimerTime: t,
    totalDistance: activeLengths * 25,
    poolLength: 25,
    poolLengthUnit: "metric",
    numActiveLengths: activeLengths,
    sport: "swimming",
    subSport: "lapSwimming",
    firstLapIndex: 0,
    numLaps: laps.length,
    event: "session",
    eventType: "stop",
    trigger: "activityEnd",
  });
  activity(encoder, at(start, t), t, utcOffset);
  return encoder.close();
}

// The ride with four bytes inverted in the middle of its data, so its CRC no
// longer matches.
function corrupt(rideBytes) {
  const bytes = Uint8Array.from(rideBytes);
  const middle = Math.floor(bytes.length / 2);
  for (let i = middle; i < middle + 4; i++) bytes[i] ^= 0xff;
  return bytes;
}

function check(name, bytes, { intact }) {
  const decoder = new Decoder(Stream.fromByteArray(Array.from(bytes)));
  if (!decoder.isFIT()) throw new Error(`${name} is not a FIT file`);
  if (decoder.checkIntegrity() !== intact) {
    throw new Error(`${name} ${intact ? "fails" : "passes"} the integrity check`);
  }
  if (!intact) return;
  const { errors } = decoder.read();
  if (errors.length > 0) throw new Error(`${name} decodes with errors: ${errors.join("; ")}`);
}

const rideBytes = ride();
const fixtures = {
  "ride.fit": [rideBytes, true],
  "run.fit": [run(), true],
  "swim.fit": [swim(), true],
  "corrupt.fit": [corrupt(rideBytes), false],
};

for (const [name, [bytes, intact]] of Object.entries(fixtures)) {
  check(name, bytes, { intact });
  writeFileSync(join(here, name), bytes);
  console.log(`${name}: ${bytes.length} bytes`);
}
