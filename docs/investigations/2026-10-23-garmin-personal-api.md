---
title: Garmin Connect Personal API
lifecycle: point-in-time
date: 2026-10-23
---

# Garmin Connect Personal API

Garmin's Personal API gives one person read-only access to their own Garmin
Connect data. This records what the API offered on the date above, from two
sources, checked against a live account.

- **Swagger page** —
  <https://developer.garmin.com/gc-developer-program/personal/swagger-docs/>.
  Lists the endpoints and response schemas. Authentication is not described.
- **Python client** — <https://github.com/garmin/connect-personal-api-python>.
  Garmin's reference client. The only description of authentication.

[2026-10-23-garmin-personal-api.openapi.json](2026-10-23-garmin-personal-api.openapi.json)
is the Swagger spec with the client's authentication added. Elements taken from
the client carry `x-source`.

## Authentication

1. Create a personal API key at
   <https://connect.garmin.com/app/settings/personalApiToken>.
2. `POST https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token`
   with `Authorization: ApiKey <key>`. The response body is a bare JWT.
3. Send `Authorization: Bearer <jwt>` on every other request.

The token lives 24 hours. Its scopes are `CONNECT_READ` and
`PERSONAL_API_{FITNESS,NUTRITION,USER,WELLNESS}_READ`. The client replaces a
cached token once less than an hour of its life remains.

The server refuses the TLS versions offered by LibreSSL 2.8.3, the library
behind macOS's bundled Python 3.9. macOS `curl` connects.

Rate limits are not published.

## Endpoints

All are `GET` on `https://personal.connectapi.garmin.com`.

| Data | Path |
| --- | --- |
| Activity search | `/activitylist-service/activities/search/activities` |
| Activity summary | `/activity-service/activity/{activityId}` |
| Activity workouts | `/activity-service/activity/{activityId}/workouts` |
| Activity file | `/download-service/files/activity/{activityId}` |
| HRV, one night | `/hrv-service/hrv/{calendarDate}` |
| HRV, range | `/hrv-service/hrv/daily/{fromDate}/{toDate}` |
| Sleep | `/sleep-service/sleep/dailySleep`, `/sleep-service/sleep/dailySleepSummariesByDate` |
| Body Battery | `/wellness-service/wellness/bodyBattery/reports/daily` |
| Heart rate | `/wellness-service/wellness/dailyHeartRate` |
| SpO2 | `/wellness-service/wellness/daily/spo2acclimation/{calendarDate}` |
| Heart rate zones | `/biometric-service/heartRateZones/v2` |
| Daily summary | `/usersummary-service/usersummary/daily`, `/usersummary-service/v2/dailysummaries` |
| Steps, stress, hydration | `/usersummary-service/stats/{steps,stress,hydration}/daily/{startDate}/{endDate}` |
| Wellness activities | `/wellnessactivity-service/activity/summary/range/{fromDate}/{untilDate}` |
| Weight | `/weight-service/weight/range/{startDate}/{endDate}`, `/weight-service/weight/all/{startDate}/{endDate}` |
| Weight goals | `/goal-service/goal/user/effective/weightgoal/{startDate}/{endDate}` |
| Food logs | `/nutrition-service/food/logs/{date}` |
| Fitness age | `/fitnessage-service/fitnessage/v2/{calendarDate}` |
| Menstrual cycle | `/periodichealth-service/menstrualcycle/{summary,dayview}/{calendarDate}` |
| Profile settings | `/userprofile-service/userprofile/settings` |

Activity search filters on dates, sport type and subtype, event type, distance,
duration, elevation, average power, a start-location bounding box, free text, and
`requiredField` (fields that must be non-null). Page size defaults to 99. The
date filters apply to the activity's local start time.

## Observations

**Activity files are the originals.** The ZIP from the download endpoint holds
the `.fit` exactly as recorded, byte-identical to a manual export from Garmin
Connect, undocumented Garmin messages included. This held for a Forerunner 955
run and a ride recorded by Rouvy.

**HRV.** The range endpoint returns one summary per night: last-night average,
5-minute high, weekly average, baseline bands and status. The single-night
endpoint adds the 5-minute readings. A night without readings returns an empty
`200` body from the single-night endpoint and null averages from the range
endpoint.

**FTP.** No endpoint returns the current FTP. An activity summary carries
`functionalThresholdPower`, populated on rides recorded by a Garmin device and
absent on rides uploaded by Rouvy. The schema also lists
`directFunctionalThresholdPower`, which neither had. The
activity search schema lists `maxFtp`; no activity on the account had it set.
Profile settings and heart rate zones hold no power threshold. Heart rate zones
carry `lactateThresholdHeartRateUsed`.
