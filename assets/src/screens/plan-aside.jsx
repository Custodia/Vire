import { useQuery } from "@tanstack/react-query";
import { planChangesQuery } from "../api/queries.js";
import { formatDay, localDate } from "../lib/format.js";
import { Card } from "../ui/Card.jsx";
import { Empty } from "../ui/Empty.jsx";
import { QueryContent } from "./query-content.jsx";

const verbs = { insert: "Created", update: "Updated", delete: "Deleted" };

/** What the season aims to reach. Goals are not part of the plan yet, so it holds none. */
export function SeasonTargets() {
  return (
    <Card id="targets" title="Season targets">
      <Empty>No targets yet.</Empty>
    </Card>
  );
}

/** The latest changes to the plan, each with the reason given for it. */
export function CoachLog() {
  const query = useQuery(planChangesQuery);

  return (
    <Card id="log" title="Coach log" aside="Latest plan changes">
      <QueryContent query={query} noun="coach log">
        {({ changes }) =>
          changes.length === 0 ? (
            <p className="m-0 text-sm text-ink-muted">No changes yet.</p>
          ) : (
            <ol className="m-0 flex list-none flex-col p-0">
              {changes.map((change) => (
                <li key={change.id} className="flex flex-col gap-1 border-t border-divider py-3">
                  <div className="flex justify-between gap-2">
                    <span className="text-sm font-semibold">{headline(change)}</span>
                    <span className="text-xs whitespace-nowrap text-ink-muted">
                      {formatDay(localDate(new Date(change.at)))}
                      {change.client && ` · ${change.client}`}
                    </span>
                  </div>
                  <span className="text-caption text-ink-muted">{change.rationale}</span>
                </li>
              ))}
            </ol>
          )
        }
      </QueryContent>
    </Card>
  );
}

function headline({ action, entity, subject }) {
  const verb = verbs[action];
  if (!subject) return `${verb} ${entity}`;
  if (entity === "cycle") return `${verb} ${subject} cycle`;
  if (entity === "day") return `${verb} ${formatDay(subject)}`;
  return `${verb} ${entity} · ${subject}`;
}
