import { useQuery } from "@tanstack/react-query";
import { dayQuery } from "../api/queries.js";
import { formatDay, localDate } from "../lib/format.js";
import { Screen } from "../ui/Screen.jsx";
import { DayContent, DayHeader } from "./day-view.jsx";
import { SignOutButton } from "./sign-out.jsx";

export function TodayScreen() {
  const date = localDate();
  const query = useQuery(dayQuery(date));

  return (
    <Screen>
      <DayHeader
        label={formatDay(date)}
        title="Today"
        data={query.data}
        actions={<SignOutButton />}
      />
      <DayContent query={query} />
    </Screen>
  );
}
