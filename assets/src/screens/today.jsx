import { useQuery } from "@tanstack/react-query";
import { dayQuery } from "../api/queries.js";
import { formatDay, localDate } from "../lib/format.js";
import { Screen } from "../ui/Screen.jsx";
import { DayContent, DayHeader, DayLinks } from "./day-view.jsx";
import { SignOutButton } from "./sign-out.jsx";
import { SyncButton } from "./sync.jsx";
import { UploadDialog } from "./upload.jsx";

export function TodayScreen() {
  const date = localDate();
  const query = useQuery(dayQuery(date));

  return (
    <Screen>
      <DayHeader
        label={formatDay(date)}
        title="Today"
        data={query.data}
        actions={
          <>
            <DayLinks date={date} />
            <SignOutButton />
          </>
        }
      />
      <div className="flex flex-wrap items-center gap-2">
        <UploadDialog />
        <SyncButton />
      </div>
      <DayContent query={query} />
    </Screen>
  );
}
