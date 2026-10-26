import { describeSteps, flattenSteps } from "../lib/structure.js";
import { zone as zoneOf } from "../lib/zones.js";

const heights = { 1: 40, 2: 55, 3: 70, 4: 85, 5: 100 };
const unzoned = 20;

/**
 * A session's steps as bars: each as wide as its seconds and as tall as its
 * training zone, in the zone's colour.
 */
export function WorkoutProfile({ steps, className = "h-32" }) {
  const bars = flattenSteps(steps);
  const total = bars.reduce((sum, step) => sum + step.seconds, 0);
  if (total === 0) return null;

  const gap = total * 0.006;
  const starts = bars.map((_, index) =>
    bars.slice(0, index).reduce((sum, step) => sum + step.seconds, 0),
  );

  return (
    <svg
      role="img"
      aria-label={`Workout profile: ${describeSteps(steps)}`}
      viewBox={`0 0 ${total} 100`}
      preserveAspectRatio="none"
      className={`block w-full ${className}`}
    >
      {bars.map((step, index) => {
        const height = heights[step.zone] ?? unzoned;
        return (
          <rect
            key={index}
            x={starts[index]}
            y={100 - height}
            width={Math.max(step.seconds - gap, gap)}
            height={height}
            className={zoneOf(step.zone)?.fill ?? "fill-ink-faint"}
          />
        );
      })}
    </svg>
  );
}
