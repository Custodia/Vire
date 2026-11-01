import uPlot from "uplot";
import "uplot/dist/uPlot.min.css";
import { formatClock } from "../lib/format.js";

const minuteSteps = [60, 120, 300, 600, 900, 1200, 1800, 3600, 7200];

function token(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/** Draws a StreamChart's series into `element` at its size and answers a function that removes them. */
export function drawStreamChart(element, { seconds, series }) {
  const axis = {
    stroke: token("--color-ink-muted"),
    font: `11px ${token("--font-body")}`,
    grid: { stroke: token("--color-divider"), width: 1 },
    ticks: { show: false },
  };
  const size = () => ({ width: element.clientWidth, height: element.clientHeight });

  const plot = new uPlot(
    {
      ...size(),
      legend: { show: false },
      cursor: { y: false },
      scales: {
        x: { time: false },
        ...Object.fromEntries(series.map((line) => [line.key, { dir: line.invert ? -1 : 1 }])),
      },
      axes: [
        { ...axis, incrs: minuteSteps, values: (_, ticks) => ticks.map(formatClock) },
        ...series.map((line, index) => ({
          ...axis,
          scale: line.key,
          side: index === 0 ? 3 : 1,
          grid: { ...axis.grid, show: index === 0 },
          values: (_, ticks) => ticks.map(line.format),
        })),
      ],
      series: [
        {},
        ...series.map((line) => ({
          label: line.label,
          scale: line.key,
          stroke: token(line.colour),
          width: 1.5,
          points: { show: false },
        })),
      ],
    },
    [seconds, ...series.map((line) => line.values)],
    element,
  );

  const observer = new ResizeObserver(() => plot.setSize(size()));
  observer.observe(element);

  return () => {
    observer.disconnect();
    plot.destroy();
  };
}
