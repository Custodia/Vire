import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate } from "@tanstack/react-router";
import { Button as AriaButton, Menu, MenuItem, MenuTrigger, Popover } from "react-aria-components";
import { matchSession } from "../api/client.js";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import { activityLine, entriesOf } from "../lib/calendar.js";
import { formatLongDay, formatPlanned, formatStartTime } from "../lib/format.js";
import { activityLink, sessionLink } from "../lib/links.js";
import { buttonClass } from "../ui/Button.jsx";
import { Card } from "../ui/Card.jsx";
import { CoachNote } from "../ui/CoachNote.jsx";
import { SessionRow } from "../ui/SessionRow.jsx";

/**
 * A day's sessions, what was recorded first by its start time, and the
 * activities recorded on it that no session is matched to.
 */
export function DayCard({ day, today, shown }) {
  const { date, activities } = day;
  const sessions = entriesOf(day, today)
    .filter((entry) => entry.session)
    .map((entry) => entry.session);
  const upcoming = sessions.filter((session) => session.status === "planned");
  const lead = (session) => {
    if (date !== today || session.status !== "planned") return null;
    return session === upcoming[0] ? "Next" : "Then";
  };

  return (
    <Card
      id="day"
      title={formatLongDay(date)}
      aside={
        sessions.length > 0 &&
        `${day.done} of ${sessions.length} done · ${formatPlanned(day.planned)}`
      }
      className="gap-1.5"
    >
      {sessions.length > 0 ? (
        <ul aria-label="Sessions" className="m-0 flex list-none flex-col gap-1 p-0">
          {sessions.map((session) => (
            <li key={session.id}>
              <SessionRow
                discipline={session.discipline}
                title={session.title}
                detail={sessionDetail(session, lead(session))}
                state={session.status === "planned" ? null : session.status}
                selected={shown?.session === session.id}
                as={Link}
                linkProps={sessionLink(session.id)}
              />
            </li>
          ))}
        </ul>
      ) : (
        <p className="m-0 px-1 py-2 text-sm text-ink-muted">
          {!day.day ? "Outside your plan." : day.rest === "kept" ? "Rest day kept." : "Rest day."}
        </p>
      )}
      {day.day?.note && <CoachNote label="Day note">{day.day.note}</CoachNote>}
      {activities.length > 0 && (
        <Unplanned
          activities={activities}
          sessions={day.sessions.filter((session) => !session.activity)}
          shown={shown}
        />
      )}
    </Card>
  );
}

function Unplanned({ activities, sessions, shown }) {
  return (
    <section
      aria-labelledby="unplanned-heading"
      className="mt-1.5 flex flex-col gap-1 border-t border-divider pt-3"
    >
      <h3
        id="unplanned-heading"
        className="m-0 px-1 text-label font-semibold text-ink-muted uppercase"
      >
        Not in the plan
      </h3>
      <ul className="m-0 flex list-none flex-col gap-1 p-0">
        {activities.map((activity) => (
          <li key={activity.id} className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <div className="min-w-0 flex-1">
              <SessionRow
                discipline={activity.discipline}
                title={disciplineOf(activity.discipline).label}
                detail={activityLine(activity)}
                selected={shown?.activity === activity.id}
                as={Link}
                linkProps={activityLink(activity.id)}
              />
            </div>
            {sessions.length > 0 && <MatchMenu activity={activity} sessions={sessions} />}
          </li>
        ))}
      </ul>
    </section>
  );
}

/** Matches an activity to one of the day's sessions without one, and shows that session. */
export function MatchMenu({ activity, sessions }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const mutation = useMutation({
    mutationFn: (sessionId) => matchSession(sessionId, activity.id),
    onSuccess: (session) => {
      queryClient.setQueryData(["sessions", session.id], session);
      queryClient.invalidateQueries({ queryKey: ["days"] });
      queryClient.invalidateQueries({ queryKey: ["seasons"] });
      navigate(sessionLink(session.id));
    },
  });
  const name = `${disciplineOf(activity.discipline).label} at ${formatStartTime(activity.started_at, activity.utc_offset_seconds)}`;

  return (
    <>
      <MenuTrigger>
        <AriaButton
          aria-label={`Match the ${name.toLowerCase()} to a session`}
          isDisabled={mutation.isPending}
          className={buttonClass("secondary", "flex-none")}
        >
          Match
        </AriaButton>
        <Popover
          placement="bottom end"
          className="min-w-56 rounded-tile border border-border bg-surface-raised p-1 shadow-lg"
        >
          <Menu onAction={(id) => mutation.mutate(id)} className="outline-none">
            {sessions.map((session) => (
              <MenuItem
                key={session.id}
                id={session.id}
                className="flex min-h-11 cursor-pointer items-center rounded-chip px-3 text-sm outline-none data-focused:bg-surface"
              >
                {session.title}
              </MenuItem>
            ))}
          </Menu>
        </Popover>
      </MenuTrigger>
      {mutation.isError && (
        <p role="alert" className="m-0 w-full px-1 text-xs text-state-skipped">
          The {name.toLowerCase()} could not be matched.
        </p>
      )}
    </>
  );
}

function sessionDetail(session, lead) {
  if (session.activity) return activityLine(session.activity);
  return [lead, formatPlanned(session.planned_seconds)].filter(Boolean).join(" · ");
}
