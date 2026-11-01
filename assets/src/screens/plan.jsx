import { useState } from "react";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { seasonQuery, seasonsQuery } from "../api/queries.js";
import { formatDayAndMonth, localDate } from "../lib/format.js";
import { around, blocksOf, weeksTo } from "../lib/plan.js";
import { useIsDesktop } from "../ui/layout.js";
import { PageHeader } from "../ui/PageHeader.jsx";
import { Stat } from "../ui/Stat.jsx";
import { CoachLog, SeasonTargets } from "./plan-aside.jsx";
import { BlockTable } from "./plan-blocks.jsx";
import { BlockCalendar } from "./plan-calendar.jsx";
import { SeasonMap } from "./plan-map.jsx";
import { PhoneSeason } from "./plan-phone.jsx";
import { QueryContent } from "./query-content.jsx";

export function PlanScreen() {
  const today = localDate();
  const desktop = useIsDesktop();
  const { season: chosen } = useSearch({ strict: false });
  const seasons = useQuery(seasonsQuery);
  const list = seasons.data?.seasons;
  const seasonId = chosen ?? (list?.length ? around(list, today).id : null);
  const plan = useQuery(seasonQuery(seasonId));
  const switcher = list && <SeasonSwitch seasons={list} selectedId={seasonId} />;

  const content = (
    <QueryContent query={seasons} noun="plan">
      {({ seasons: all }) =>
        all.length === 0 ? (
          <NoSeasons />
        ) : (
          <QueryContent query={plan} noun="season">
            {(season) =>
              desktop ? (
                <Season key={season.id} season={season} today={today} />
              ) : (
                <PhoneSeason key={season.id} season={season} today={today} switcher={switcher} />
              )
            }
          </QueryContent>
        )
      }
    </QueryContent>
  );

  if (desktop) {
    return (
      <>
        {switcher}
        {content}
      </>
    );
  }
  return plan.data ? (
    content
  ) : (
    <div className="flex flex-col gap-3 px-4 pt-[max(1rem,env(safe-area-inset-top))]">
      {content}
    </div>
  );
}

function Season({ season, today }) {
  const phaseOf = (block) => season.phases.find((phase) => phase.blocks.includes(block));
  const [selection, setSelection] = useState(() => {
    const blocks = blocksOf(season);
    const block = blocks.length ? around(blocks, today) : null;
    const phase = block ? phaseOf(block) : around(season.phases, today);
    return { phaseId: phase?.id ?? null, blockId: block?.id ?? null };
  });

  const phase = season.phases.find((p) => p.id === selection.phaseId) ?? null;
  const block = blocksOf(season).find((b) => b.id === selection.blockId) ?? null;

  const selectPhase = (next) =>
    setSelection({
      phaseId: next.id,
      blockId: next.blocks.length ? around(next.blocks, today).id : null,
    });
  const selectBlock = (next) => setSelection({ phaseId: phaseOf(next).id, blockId: next.id });

  return (
    <>
      <Goal season={season} today={today} />
      <SeasonMap
        season={season}
        today={today}
        selection={selection}
        onPhase={selectPhase}
        onBlock={selectBlock}
      />
      <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,22rem)] items-start gap-5">
        <div className="flex min-w-0 flex-col gap-5">
          <BlockTable
            season={season}
            phase={phase}
            today={today}
            selectedId={block?.id}
            onSelect={selectBlock}
          />
          {block && <BlockCalendar season={season} block={block} today={today} />}
        </div>
        <aside className="flex min-w-0 flex-col gap-5">
          <SeasonTargets />
          <CoachLog />
        </aside>
      </div>
    </>
  );
}

function Goal({ season, today }) {
  return (
    <PageHeader
      label="Goal"
      title={season.name}
      detail={
        season.rationale ??
        `${formatDayAndMonth(season.period.first)} – ${formatDayAndMonth(season.period.last)}`
      }
    >
      <Stat value={weeksTo(today, season.period.last)} label="weeks to go" tone="accent" />
      <Stat value="—" label="trend weight" tone="muted" />
      <Stat value="—" label="chronic load (CTL)" tone="muted" />
    </PageHeader>
  );
}

function SeasonSwitch({ seasons, selectedId }) {
  const navigate = useNavigate();
  if (seasons.length < 2) return null;

  return (
    <nav aria-label="Seasons" className="no-scrollbar flex justify-end gap-1 overflow-x-auto">
      {seasons.map((season) => (
        <button
          key={season.id}
          type="button"
          aria-pressed={season.id === selectedId}
          onClick={() => navigate({ to: "/plan", search: { season: season.id } })}
          className={`focus-ring inline-flex min-h-11 items-center rounded-tile border px-3 text-sm font-semibold ${
            season.id === selectedId
              ? "border-accent bg-accent-tint text-accent"
              : "border-border bg-surface text-ink-soft hover:bg-surface-raised"
          }`}
        >
          {season.name}
        </button>
      ))}
    </nav>
  );
}

function NoSeasons() {
  return (
    <section className="flex flex-col gap-1 rounded-card border border-border bg-surface px-5.5 py-5">
      <h1 className="m-0 text-lg font-bold">No plan yet</h1>
      <p className="m-0 text-sm text-ink-soft">
        Your plan starts with a season. Ask your coach to create one.
      </p>
    </section>
  );
}
