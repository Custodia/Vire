import { useRef } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { getRouteApi, Link, useCanGoBack, useNavigate, useRouter } from "@tanstack/react-router";
import { activityQuery, sessionQuery } from "../api/queries.js";
import { formatDay, localDate } from "../lib/format.js";
import { dayLink } from "../lib/links.js";
import { useSwipe } from "../ui/gestures.js";
import { useIsDesktop } from "../ui/layout.js";
import { Calendar } from "./calendar.jsx";
import { QueryContent } from "./query-content.jsx";
import { ActivityView, SessionView } from "./session-panel.jsx";

const sessionRoute = getRouteApi("/authenticated/sessions/$id");
const activityRoute = getRouteApi("/authenticated/activities/$id");

/** A session: beside its day on a desktop, and a page of its own on a phone. */
export function SessionScreen() {
  const { id } = sessionRoute.useParams();
  const desktop = useIsDesktop();
  const query = useQuery({ ...sessionQuery(id), placeholderData: keepPreviousData });

  return (
    <QueryContent query={query} noun="session">
      {(session) =>
        desktop ? (
          <Calendar view="day" date={session.day.date} selected={{ session: id }} />
        ) : (
          <Page date={session.day.date}>
            <SessionView session={session} today={localDate()} plain />
          </Page>
        )
      }
    </QueryContent>
  );
}

/** An activity no session is matched to: beside its day on a desktop, a page on a phone. */
export function ActivityScreen() {
  const { id } = activityRoute.useParams();
  const desktop = useIsDesktop();
  const query = useQuery({ ...activityQuery(id), placeholderData: keepPreviousData });

  return (
    <QueryContent query={query} noun="activity">
      {(activity) =>
        desktop ? (
          <Calendar view="day" date={activity.local_date} selected={{ activity: id }} />
        ) : (
          <Page date={activity.local_date}>
            <ActivityView activity={activity} plain />
          </Page>
        )
      }
    </QueryContent>
  );
}

/** A phone page under a link back to its day, which a swipe to the right also follows. */
function Page({ date, children }) {
  const page = useRef(null);
  const router = useRouter();
  const navigate = useNavigate();
  const canGoBack = useCanGoBack();
  useSwipe(page, {
    onRight: () => (canGoBack ? router.history.back() : navigate(dayLink(date))),
  });

  return (
    <div ref={page} className="flex min-h-[calc(100dvh-4.5rem)] flex-col">
      <div className="flex items-center px-2 pt-[max(0.5rem,env(safe-area-inset-top))]">
        <Link
          {...dayLink(date)}
          aria-label={`Back to ${formatDay(date)}`}
          className="focus-ring inline-flex min-h-11 items-center gap-1 rounded-tile pr-2.5 pl-1 text-sm font-semibold text-accent no-underline"
        >
          <svg
            aria-hidden="true"
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M15 6l-6 6 6 6" />
          </svg>
          {formatDay(date)}
        </Link>
      </div>
      <main className="flex flex-col gap-3.5 px-4 pt-2 pb-6">{children}</main>
    </div>
  );
}
