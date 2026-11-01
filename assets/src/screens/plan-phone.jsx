import { useEffect, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import { dayOf } from "../lib/calendar.js";
import { formatDates, formatHours } from "../lib/format.js";
import { calendarLink } from "../lib/links.js";
import {
  around,
  blockNumbers,
  blocksOf,
  covers,
  cycleNames,
  daysBetween,
  periodLength,
  plannedSecondsOf,
  plannedSecondsOfDays,
  progressOf,
  weeksTo,
  withGaps,
} from "../lib/plan.js";
import { DayRing } from "../ui/Marks.jsx";
import { Stat } from "../ui/Stat.jsx";
import { CoachLog, SeasonTargets } from "./plan-aside.jsx";
import {
  BlockButton,
  Gap,
  Months,
  PhaseButton,
  placement,
  Segment,
  Track,
  WeeklyHours,
} from "./plan-map.jsx";

const DAY_PX = 2.6;

/**
 * A season on a phone: its goal, its map as a strip that scrolls through the
 * year, and the chosen phase's blocks, each opening to its cycles as rows of
 * day rings.
 */
export function PhoneSeason({ season, today, switcher }) {
  const blocks = blocksOf(season);
  const current = blocks.length ? around(blocks, today) : null;
  const phaseOf = (block) => season.phases.find((phase) => phase.blocks.includes(block));
  const [phaseId, setPhaseId] = useState(
    () => (current ? phaseOf(current) : around(season.phases, today))?.id ?? null,
  );
  const [open, setOpen] = useState(() => new Set(current ? [current.id] : []));
  const phase = season.phases.find((each) => each.id === phaseId) ?? null;

  const toggle = (block) =>
    setOpen((was) => {
      const now = new Set(was);
      if (now.has(block.id)) now.delete(block.id);
      else now.add(block.id);
      return now;
    });
  const choosePhase = (next) => setPhaseId(next.id);
  const chooseBlock = (block) => {
    setPhaseId(phaseOf(block).id);
    setOpen((was) => new Set([...was, block.id]));
  };

  return (
    <div className="flex flex-col">
      <header className="flex flex-col gap-3 border-b border-divider px-4 pt-[max(0.875rem,env(safe-area-inset-top))] pb-4">
        {switcher}
        <div className="flex flex-col gap-1">
          <span className="text-label font-semibold text-ink-muted uppercase">Goal</span>
          <h1 className="m-0 text-[26px] leading-tight font-bold tracking-tight">{season.name}</h1>
          {season.rationale && (
            <span className="text-caption text-ink-soft">{season.rationale}</span>
          )}
        </div>
        <div className="flex gap-7">
          <Stat value={weeksTo(today, season.period.last)} label="weeks to go" tone="accent" />
          <Stat value="—" label="trend kg" tone="muted" />
          <Stat value="—" label="CTL" tone="muted" />
        </div>
      </header>
      <main className="flex flex-col gap-3 px-4 pt-4 pb-6">
        <SeasonStrip
          season={season}
          today={today}
          phaseId={phaseId}
          onPhase={choosePhase}
          onBlock={chooseBlock}
        />
        {phase ? (
          <section aria-labelledby="blocks-heading" className="flex flex-col gap-2.5">
            <div className="flex flex-col gap-0.5 px-0.5 pt-2">
              <h2 id="blocks-heading" className="m-0 text-lg font-bold">
                {phase.name} · blocks
              </h2>
              {phase.rationale && (
                <span className="text-caption text-ink-muted">{phase.rationale}</span>
              )}
            </div>
            {phase.blocks.length === 0 && (
              <p className="m-0 text-sm text-ink-muted">This phase has no blocks yet.</p>
            )}
            {phase.blocks.map((block) => (
              <BlockCard
                key={block.id}
                block={block}
                number={blockNumbers(season).get(block.id)}
                today={today}
                open={open.has(block.id)}
                onToggle={() => toggle(block)}
              />
            ))}
            <RingLegend />
          </section>
        ) : (
          <p className="m-0 text-sm text-ink-muted">
            This season has no phases yet. Ask your coach to lay them out.
          </p>
        )}
        <SeasonTargets />
        <CoachLog />
      </main>
    </div>
  );
}

function SeasonStrip({ season, today, phaseId, onPhase, onBlock }) {
  const scroller = useRef(null);
  const place = placement(season.period);
  const width = periodLength(season.period) * DAY_PX;
  const numbers = blockNumbers(season);

  useEffect(() => {
    const element = scroller.current;
    if (element && covers(season.period, today)) {
      element.scrollLeft = daysBetween(season.period.first, today) * DAY_PX - 80;
    }
  }, [season.period, today]);

  return (
    <section aria-labelledby="map-heading" className="flex flex-col gap-2">
      <div className="flex items-baseline justify-between">
        <h2 id="map-heading" className="m-0 text-label font-semibold text-ink-muted uppercase">
          Season map
        </h2>
        <span className="text-xs text-ink-muted">Scroll for the year</span>
      </div>
      <div ref={scroller} data-scrolls className="no-scrollbar -mx-4 overflow-x-auto px-4">
        <div className="relative flex flex-col gap-1.5" style={{ width }}>
          <Track label="Phases" className="h-10">
            {withGaps(season.period, season.phases).map((span) =>
              span.gap ? (
                <Gap key={span.period.first} span={span} place={place} label="No phase" />
              ) : (
                <Segment key={span.id} period={span.period} place={place}>
                  <PhaseButton
                    phase={span}
                    now={covers(span.period, today)}
                    selected={span.id === phaseId}
                    onPhase={onPhase}
                  />
                </Segment>
              ),
            )}
          </Track>
          <Track label="Blocks" className="h-6.5">
            {withGaps(season.period, blocksOf(season)).map((span) =>
              span.gap ? (
                <Gap key={span.period.first} span={span} place={place} label="Not planned yet" />
              ) : (
                <Segment key={span.id} period={span.period} place={place}>
                  <BlockButton
                    block={span}
                    number={numbers.get(span.id)}
                    progress={progressOf(span.period, today)}
                    selected={false}
                    onBlock={onBlock}
                  />
                </Segment>
              ),
            )}
          </Track>
          <WeeklyHours season={season} today={today} place={place} />
          <Months period={season.period} place={place} />
          {covers(season.period, today) && (
            <div
              aria-hidden="true"
              className="pointer-events-none absolute top-19 bottom-5 w-0.5 bg-ink"
              style={{ left: place.at(today) }}
            />
          )}
        </div>
      </div>
    </section>
  );
}

function BlockCard({ block, number, today, open, onToggle }) {
  const now = covers(block.period, today);
  const panelId = `block-${block.id}`;
  const names = cycleNames(block);
  const lengths = [...new Set(block.cycles.map((cycle) => periodLength(cycle.period)))];

  return (
    <section
      className={`flex flex-col rounded-card border ${
        now ? "border-calendar-today-edge bg-calendar-today" : "border-border bg-surface"
      }`}
    >
      <button
        type="button"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={onToggle}
        className="focus-ring flex min-h-15 w-full items-center gap-3 rounded-card bg-transparent px-3.5 py-3 text-left text-ink"
      >
        <span className="flex min-w-0 flex-1 flex-col gap-0.5">
          <h3 className="m-0 text-base font-bold">
            Block {number}
            {now && " · now"}
          </h3>
          <span className="text-xs text-ink-muted">
            {[
              formatDates(block.period),
              block.focus,
              lengths.length === 1 && `${lengths[0]}-day cycles`,
            ]
              .filter(Boolean)
              .join(" · ")}
          </span>
        </span>
        <span className="font-display text-base font-semibold tabular-nums">
          {formatHours(plannedSecondsOf(block))}
        </span>
        <svg
          aria-hidden="true"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="flex-none text-ink-muted"
        >
          <path d={open ? "M6 15l6-6 6 6" : "M6 9l6 6 6-6"} />
        </svg>
      </button>
      {open && (
        <ol id={panelId} className="m-0 flex list-none flex-col gap-0.5 px-2.5 pb-2.5">
          {block.cycles.length === 0 && (
            <li className="px-1.5 py-2 text-sm text-ink-muted">This block has no cycles yet.</li>
          )}
          {block.cycles.map((cycle) => (
            <li key={cycle.id}>
              <CycleRow cycle={cycle} name={names.get(cycle.id)} today={today} />
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

function CycleRow({ cycle, name, today }) {
  const now = covers(cycle.period, today);
  const days = cycle.days.map((day) => dayOf({ date: day.date, day, activities: [] }, today));
  const dates = formatDates(cycle.period);
  const hours = `${formatHours(plannedSecondsOfDays(cycle.days))} h`;

  return (
    <Link
      {...calendarLink("week", now ? today : cycle.period.first)}
      aria-label={`${name}, ${dates}, ${hours}`}
      className={`focus-ring flex min-h-12 items-center gap-2.5 rounded-tile px-1.5 py-2 text-ink no-underline ${
        now ? "bg-accent-tint" : ""
      }`}
    >
      <span className="flex w-21 flex-none flex-col gap-px">
        <span className={`text-caption font-bold ${now ? "text-accent" : ""}`}>{name}</span>
        <span className="text-[11px] text-ink-muted">
          {dates} · {hours}
        </span>
      </span>
      <span
        className="grid flex-1 items-center gap-0.5"
        style={{ gridTemplateColumns: `repeat(${days.length}, minmax(0, 1fr))` }}
      >
        {days.map((day) => (
          <span key={day.date} className="grid place-items-center">
            <DayRing day={day} size={days.length > 7 ? 16 : 18} today={day.date === today} />
          </span>
        ))}
      </span>
      <svg
        aria-hidden="true"
        width="14"
        height="14"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="flex-none text-ink-muted"
      >
        <path d="M9 6l6 6-6 6" />
      </svg>
    </Link>
  );
}

const sample = (statuses, rest) => ({
  sessions: statuses.map((status, index) => ({ id: index, status })),
  done: statuses.filter((status) => status === "done").length,
  rest,
});

function RingLegend() {
  const items = [
    [sample(["done", "done"]), "All done"],
    [sample(["done", "skipped", "planned"]), "Done, skipped, upcoming"],
    [sample([], "kept"), "Rest kept"],
    [sample([], "ahead"), "Rest ahead"],
  ];

  return (
    <ul className="m-0 flex list-none flex-wrap gap-x-4 gap-y-2 p-0 px-0.5 text-xs text-ink-muted">
      {items.map(([day, label]) => (
        <li key={label} className="inline-flex items-center gap-1.5">
          <span aria-hidden="true">
            <DayRing day={day} size={16} />
          </span>
          {label}
        </li>
      ))}
    </ul>
  );
}
