import { Link } from "@tanstack/react-router";
import { discipline as disciplineOf } from "../lib/disciplines.js";
import { formatDayAndMonth, formatHours, formatMonthName, formatPlanned } from "../lib/format.js";
import { calendarLink } from "../lib/links.js";
import {
  blockNumbers,
  blocksOf,
  covers,
  daysBetween,
  periodLength,
  progressOf,
  weeklyPlan,
  withGaps,
} from "../lib/plan.js";
import { Card } from "../ui/Card.jsx";

const blockTones = {
  done: "bg-progress-done-deep text-ink",
  now: "bg-progress-current text-ink-inverse",
  planned: "bg-border-strong text-ink",
};

const hatched =
  "bg-[repeating-linear-gradient(135deg,var(--color-progress-extra)_0_2px,transparent_2px_4px)]";

const progressWords = { done: "done", now: "current", planned: "planned" };

/** A period as the dates it runs between: 13 Jul – 26 Jul. */
export function spanLabel({ first, last }) {
  return `${formatDayAndMonth(first)} – ${formatDayAndMonth(last)}`;
}

/**
 * The season on one timeline: its phases over its blocks, the hours planned,
 * done and missed each week and the weight beneath them, with today marked
 * across them.
 */
export function SeasonMap({ season, today, selection, onPhase, onBlock }) {
  const place = placement(season.period);
  const numbers = blockNumbers(season);

  return (
    <Card
      id="map"
      title={`Season map · ${spanLabel(season.period)}`}
      aside="Phases and blocks open below"
    >
      <div className="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-3.5">
        <div className="flex flex-col gap-2 text-xs text-ink-muted">
          <span className="flex h-11 items-center">Phases</span>
          <span className="flex h-7.5 items-center">Blocks</span>
          <span className="flex h-22.5 items-end pb-1">Hours / week</span>
          <span className="flex h-22.5 items-center">Weight, kg</span>
        </div>
        <div className="relative flex min-w-0 flex-col gap-2">
          <Track label="Phases" className="h-11">
            {withGaps(season.period, season.phases).map((span) =>
              span.gap ? (
                <Gap key={span.period.first} span={span} place={place} label="No phase" />
              ) : (
                <Segment key={span.id} period={span.period} place={place}>
                  <PhaseButton
                    phase={span}
                    now={covers(span.period, today)}
                    selected={span.id === selection.phaseId}
                    onPhase={onPhase}
                  />
                </Segment>
              ),
            )}
          </Track>
          <Track label="Blocks" className="h-7.5">
            {withGaps(season.period, blocksOf(season)).map((span) =>
              span.gap ? (
                <Gap key={span.period.first} span={span} place={place} label="Not planned yet" />
              ) : (
                <Segment key={span.id} period={span.period} place={place}>
                  <BlockButton
                    block={span}
                    number={numbers.get(span.id)}
                    progress={progressOf(span.period, today)}
                    selected={span.id === selection.blockId}
                    onBlock={onBlock}
                  />
                </Segment>
              ),
            )}
          </Track>
          <WeeklyHours season={season} today={today} place={place} />
          <div className="flex h-22.5 items-center justify-center rounded-tile border border-dashed border-border-strong text-xs text-ink-muted">
            No weight data yet
          </div>
          <Months period={season.period} place={place} />
          {covers(season.period, today) && (
            <div
              aria-hidden="true"
              className="pointer-events-none absolute top-21 bottom-5 w-0.5 bg-ink"
              style={{ left: place.at(today) }}
            />
          )}
        </div>
      </div>
      <ul
        aria-label="Map legend"
        className="m-0 flex list-none flex-wrap gap-4.5 p-0 pt-1 text-xs text-ink-muted"
      >
        <LegendSwatch className="bg-progress-done">Done</LegendSwatch>
        <LegendSwatch className="border border-dashed border-progress-missed">
          Planned, not done
        </LegendSwatch>
        <LegendSwatch className={hatched}>Not in the plan</LegendSwatch>
        <LegendSwatch className="bg-progress-current">Now</LegendSwatch>
        <LegendSwatch className="bg-progress-planned">Planned</LegendSwatch>
        <li className="inline-flex items-center gap-1.5">
          <span aria-hidden="true" className="h-0.5 w-3.5 bg-ink" />
          Today
        </li>
      </ul>
    </Card>
  );
}

/** Positions on the season's timeline as percentages of its days. */
export function placement(period) {
  const total = periodLength(period);
  const fraction = (days) => `${(days / total) * 100}%`;
  return {
    at: (date) => fraction(daysBetween(period.first, date)),
    span: ({ first, last }) => ({
      left: fraction(daysBetween(period.first, first)),
      width: fraction(daysBetween(first, last) + 1),
    }),
  };
}

export function Track({ label, className, children }) {
  return (
    <ol aria-label={label} className={`relative m-0 list-none p-0 ${className}`}>
      {children}
    </ol>
  );
}

export function Segment({ period, place, children }) {
  return (
    <li className="absolute inset-y-0 min-w-0 pr-1" style={place.span(period)}>
      {children}
    </li>
  );
}

export function Gap({ span, place, label }) {
  return (
    <Segment period={span.period} place={place}>
      <span
        title={`${label} · ${spanLabel(span.period)}`}
        className="flex h-full items-center overflow-hidden rounded-chip border border-dashed border-border-strong px-2 text-xs whitespace-nowrap text-ink-muted"
      >
        {label}
      </span>
    </Segment>
  );
}

export function PhaseButton({ phase, now, selected, onPhase }) {
  const tone = now ? "bg-accent text-ink-inverse" : "bg-phase text-phase-ink";

  return (
    <button
      type="button"
      aria-pressed={selected}
      title={`${phase.name} · ${spanLabel(phase.period)}`}
      onClick={() => onPhase(phase)}
      className={`focus-ring flex h-full w-full flex-col justify-center overflow-hidden rounded-chip px-2.5 text-left whitespace-nowrap ${tone} ${
        selected ? "ring-2 ring-ink ring-inset" : ""
      }`}
    >
      <span className="truncate text-caption font-bold">{phase.name}</span>
      <span className="truncate text-label opacity-80">{spanLabel(phase.period)}</span>
      {now && <span className="sr-only">Current</span>}
    </button>
  );
}

export function BlockButton({ block, number, progress, selected, onBlock }) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      aria-label={`Block ${number} · ${block.focus}, ${progressWords[progress]}`}
      title={`Block ${number} · ${block.focus} · ${spanLabel(block.period)}`}
      onClick={() => onBlock(block)}
      className={`focus-ring flex h-full w-full items-center overflow-hidden rounded-chip px-2 text-xs font-semibold whitespace-nowrap ${blockTones[progress]} ${
        selected ? "ring-2 ring-ink ring-inset" : ""
      }`}
    >
      <span className="truncate">B{number}</span>
    </button>
  );
}

export function WeeklyHours({ season, today, place }) {
  const weeks = weeklyPlan(season, today);
  const most = Math.max(
    ...weeks.map(({ seconds }) =>
      Math.max(seconds.planned, seconds.done + seconds.extra + seconds.upcoming),
    ),
    3600,
  );

  return (
    <ol
      aria-label="Hours per week"
      className="relative m-0 h-22.5 list-none border-b border-border-strong p-0"
    >
      {weeks.map((week, index) => (
        <li
          key={week.period.first}
          className="group absolute bottom-0 h-full px-px"
          style={place.span(week.period)}
        >
          <Link
            {...calendarLink("week", covers(week.period, today) ? today : week.period.first)}
            aria-describedby={`week-${week.period.first}`}
            className="focus-ring relative block h-full"
          >
            <span className="sr-only">Week of {formatDayAndMonth(week.period.first)}</span>
            <WeekBar week={week} progress={progressOf(week.period, today)} most={most} />
          </Link>
          <WeekCard week={week} today={today} end={index >= weeks.length / 2} />
        </li>
      ))}
    </ol>
  );
}

function WeekBar({ week, progress, most }) {
  const now = progress === "now";
  const height = (seconds) => `${(seconds / most) * 94}%`;
  const layers = [
    [week.seconds.done, now ? "bg-progress-current" : "bg-progress-done"],
    [week.seconds.extra, `${hatched} shadow-[inset_0_0_0_1px_var(--color-progress-extra)]`],
    [week.seconds.upcoming, now ? "bg-progress-current-planned" : "bg-progress-planned"],
  ].filter(([seconds]) => seconds > 0);

  let bottom = 0;
  return (
    <>
      {week.seconds.planned > 0 && (
        <span
          className="absolute inset-x-0 bottom-0 rounded-t-bar border border-b-0 border-dashed border-progress-missed"
          style={{ height: height(week.seconds.planned) }}
        />
      )}
      {layers.map(([seconds, tone], index) => {
        const style = { bottom: height(bottom), height: height(seconds) };
        bottom += seconds;
        return (
          <span
            key={tone}
            className={`absolute inset-x-0 ${tone} ${index === layers.length - 1 ? "rounded-t-bar" : ""}`}
            style={style}
          />
        );
      })}
    </>
  );
}

function WeekCard({ week, today, end }) {
  const { sessions, activities, seconds } = week;
  const done = sessions.filter((session) => session.status === "done").length;
  const missed = sessions.filter((session) => session.status === "skipped");
  const summary = !week.planned
    ? "Not planned yet"
    : week.period.first > today
      ? `${formatHours(seconds.planned)} h planned · ${sessions.length} ${plural(sessions.length)}`
      : `${formatHours(seconds.done)} of ${formatHours(seconds.planned)} h · ${done} of ${sessions.length} ${plural(sessions.length)}`;

  return (
    <div
      id={`week-${week.period.first}`}
      role="tooltip"
      className={`pointer-events-none absolute top-full z-10 mt-2 hidden w-64 flex-col gap-2 rounded-tile border border-border-strong bg-surface-raised px-3.5 py-3 shadow-[0_10px_28px_rgb(0_0_0/0.5)] group-focus-within:flex group-hover:flex ${
        end ? "right-0" : "left-0"
      }`}
    >
      <p className="m-0 text-sm font-bold">Week of {formatDayAndMonth(week.period.first)}</p>
      <p className="m-0 text-caption text-ink-soft">{summary}.</p>
      {missed.length > 0 && (
        <WeekList
          label="Not done"
          swatch="border border-dashed border-progress-missed"
          items={missed.map((session) => [
            session.id,
            session.title,
            formatPlanned(session.planned_seconds),
          ])}
        />
      )}
      {activities.length > 0 && (
        <WeekList
          label="Not in the plan"
          swatch={hatched}
          items={activities.map((activity) => [
            activity.id,
            disciplineOf(activity.discipline).label,
            `+${formatPlanned(activity.duration_seconds)}`,
          ])}
        />
      )}
    </div>
  );
}

const plural = (count) => (count === 1 ? "session" : "sessions");

function WeekList({ label, swatch, items }) {
  return (
    <div className="flex flex-col gap-1.5 border-t border-divider pt-2">
      <p className="m-0 flex items-center gap-1.5 text-label font-semibold text-ink-muted uppercase">
        <span aria-hidden="true" className={`size-2.5 rounded-bar ${swatch}`} />
        {label}:
      </p>
      {items.map(([key, name, time]) => (
        <p key={key} className="m-0 flex items-baseline justify-between gap-3 text-caption">
          <span>{name}</span>{" "}
          <span className="font-display text-ink-muted tabular-nums">{time}</span>
        </p>
      ))}
    </div>
  );
}

export function Months({ period, place }) {
  const [year, month, day] = period.first.split("-").map(Number);
  // The season's first month is labelled at its start unless the next month's label would crowd it.
  const months = day <= 20 ? [period.first] : [];
  for (let index = 1; ; index += 1) {
    const date = new Date(Date.UTC(year, month - 1 + index, 1)).toISOString().slice(0, 10);
    if (date > period.last) break;
    months.push(date);
  }

  return (
    <div aria-hidden="true" className="relative h-4 text-label text-ink-muted">
      {months.map((date) => (
        <span key={date} className="absolute top-0" style={{ left: place.at(date) }}>
          {formatMonthName(date)}
        </span>
      ))}
    </div>
  );
}

function LegendSwatch({ className, children }) {
  return (
    <li className="inline-flex items-center gap-1.5">
      <span aria-hidden="true" className={`size-2.5 rounded-bar ${className}`} />
      {children}
    </li>
  );
}
