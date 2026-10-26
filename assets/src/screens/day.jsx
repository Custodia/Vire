import { useQuery } from "@tanstack/react-query";
import { getRouteApi, Link } from "@tanstack/react-router";
import { dayQuery } from "../api/queries.js";
import { formatDay, isIsoDate } from "../lib/format.js";
import { BackLink } from "../ui/BackLink.jsx";
import { Screen } from "../ui/Screen.jsx";
import { DayContent, DayHeader, DayLinks } from "./day-view.jsx";

const route = getRouteApi("/authenticated/days/$date");

export function DayScreen() {
  const { date } = route.useParams();

  return (
    <Screen>
      <BackLink as={Link} linkProps={{ to: "/today" }}>
        Today
      </BackLink>
      {isIsoDate(date) ? <Day key={date} date={date} /> : <NotADate value={date} />}
    </Screen>
  );
}

function Day({ date }) {
  const query = useQuery(dayQuery(date));

  return (
    <>
      <DayHeader
        label={date.slice(0, 4)}
        title={formatDay(date)}
        data={query.data}
        actions={<DayLinks date={date} />}
      />
      <DayContent query={query} />
    </>
  );
}

function NotADate({ value }) {
  return (
    <>
      <h1 className="m-0 text-3xl font-bold tracking-tight">Not a date</h1>
      <p className="m-0 text-sm text-ink-soft">
        “{value}” is not a date written as year, month and day, such as 2026-11-03.
      </p>
    </>
  );
}
