# FIT fixtures

Synthetic activity files for the decoder and parsing tests, written by
`generate.mjs` with the encoder of Garmin's FIT JavaScript SDK at the version
pinned in `decoder/package.json`. No real recording is in this directory.

| File | Contents |
| --- | --- |
| `ride.fit` | Road ride starting 2026-07-15 02:00 UTC at UTC−7, so on 2026-07-14 local time. 600 s elapsed, 540 s of timer time. A record every second with power, heart rate, cadence, speed, distance and a developer field `Grade` in `%`. A pause from 360 s to 420 s with timer stop and start events and no records. Two laps: 0–240 s, and 240–600 s with the pause inside it. One session and one activity. |
| `run.fit` | Street run starting 2026-07-16 05:45 UTC at UTC+3. 600 s. A record every second with heart rate, cadence with its fractional part, enhanced speed, enhanced altitude, distance and position. One lap, one session, one activity. |
| `swim.fit` | Pool swim in a 25 m pool starting 2026-01-20 17:00 UTC at UTC+2. 300 m in 385 s: four lengths freestyle, a 30 s rest, four lengths breaststroke, a 20 s rest, four lengths freestyle. Active lengths carry the stroke and the stroke count; each rest is an idle length. Every interval and every rest is a lap. The session carries the pool length. There are no records. |
| `corrupt.fit` | `ride.fit` with four bytes in the middle of its data inverted, so the file CRC no longer matches. |

The generator is deterministic: running it again writes the same bytes. It
decodes every file it writes and stops with an error if an intact file fails
the SDK's integrity check or decodes with errors, or if `corrupt.fit` passes the
check.

To regenerate:

```sh
cd decoder
npm ci
npm run fixtures
```
