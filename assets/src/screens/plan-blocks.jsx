import { formatHours } from "../lib/format.js";
import {
  blockNumbers,
  covers,
  cyclePattern,
  periodLength,
  plannedSecondsOf,
  progressOf,
} from "../lib/plan.js";
import { Card } from "../ui/Card.jsx";
import { Empty } from "../ui/Empty.jsx";
import { spanLabel } from "./plan-map.jsx";

const dotTones = {
  done: "bg-progress-done",
  now: "bg-progress-current",
  planned: "bg-progress-planned",
};

/** A phase's blocks as rows of their dates, cycles, focus and planned hours. */
export function BlockTable({ season, phase, today, selectedId, onSelect }) {
  if (!phase) {
    return (
      <Card id="blocks" title="Blocks">
        <Empty>This season has no phases yet. Ask your coach to lay them out.</Empty>
      </Card>
    );
  }

  const numbers = blockNumbers(season);

  return (
    <Card id="blocks" title={`${phase.name} · blocks`} aside={phase.rationale}>
      {phase.blocks.length === 0 ? (
        <Empty>This phase has no blocks yet.</Empty>
      ) : (
        <table className="w-full border-collapse text-caption">
          <thead>
            <tr className="text-left text-xs text-ink-muted">
              <th scope="col" className="py-2 pr-2.5 font-semibold">
                Block
              </th>
              <th scope="col" className="px-2.5 py-2 font-semibold">
                Dates
              </th>
              <th scope="col" className="px-2.5 py-2 font-semibold">
                Cycles
              </th>
              <th scope="col" className="px-2.5 py-2 font-semibold">
                Focus
              </th>
              <th scope="col" className="py-2 pl-2.5 text-right font-semibold">
                Hours
              </th>
            </tr>
          </thead>
          <tbody>
            {phase.blocks.map((block) => (
              <BlockRow
                key={block.id}
                block={block}
                number={numbers.get(block.id)}
                today={today}
                selected={block.id === selectedId}
                onSelect={onSelect}
              />
            ))}
          </tbody>
        </table>
      )}
    </Card>
  );
}

function BlockRow({ block, number, today, selected, onSelect }) {
  const now = covers(block.period, today);
  const planned = plannedSecondsOf(block);
  const tone = now ? "bg-accent-tint" : selected ? "bg-surface-raised" : "hover:bg-surface-raised";

  return (
    <tr
      onClick={() => onSelect(block)}
      className={`cursor-pointer border-t border-divider ${tone}`}
    >
      <td className="py-1 pr-2.5">
        <button
          type="button"
          aria-pressed={selected}
          aria-label={`Block ${number}${now ? ", current" : ""}`}
          onClick={(event) => {
            event.stopPropagation();
            onSelect(block);
          }}
          className={`focus-ring inline-flex min-h-11 items-center gap-2 rounded-chip font-semibold whitespace-nowrap ${
            selected ? "text-accent" : "text-ink"
          }`}
        >
          Block {number}
        </button>
      </td>
      <td className="px-2.5 py-1 whitespace-nowrap text-ink-muted">{spanLabel(block.period)}</td>
      <td className="px-2.5 py-1">
        <span className="flex items-center gap-0.75">
          {block.cycles.map((cycle) => (
            <span
              key={cycle.id}
              aria-hidden="true"
              className={`h-2.5 rounded-bar ${
                cycle.kind === "recovery"
                  ? "bg-progress-recovery"
                  : dotTones[progressOf(cycle.period, today)]
              }`}
              style={{
                width: `${Math.max(6, Math.round((periodLength(cycle.period) * 10) / 7))}px`,
              }}
            />
          ))}
          <span className="ml-2 whitespace-nowrap text-ink-muted">
            {block.cycles.length ? cyclePattern(block) : "No cycles yet"}
          </span>
        </span>
      </td>
      <td className="px-2.5 py-1">{block.focus}</td>
      <td className="py-1 pl-2.5 text-right font-display text-base font-semibold">
        {planned === 0 ? "—" : formatHours(planned)}
      </td>
    </tr>
  );
}
