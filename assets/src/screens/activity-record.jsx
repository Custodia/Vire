import { useId, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { streamsQuery } from "../api/queries.js";
import { formatClock, formatDistance, formatPace } from "../lib/format.js";
import { StreamChart } from "../ui/StreamChart.jsx";

const charts = {
  bike: ["power", "heart_rate"],
  run: ["heart_rate", "speed"],
};

const mean = (values) => {
  const recorded = values.filter((value) => value != null);
  return recorded.reduce((sum, value) => sum + value, 0) / recorded.length;
};

const channels = {
  power: {
    label: "Power",
    colour: "--color-chart-power",
    swatch: "bg-chart-power",
    values: (samples) => samples,
    format: (watts) => `${Math.round(watts)}`,
    summary: (samples) => `avg ${Math.round(mean(samples))} W`,
  },
  heart_rate: {
    label: "Heart rate",
    colour: "--color-chart-heart-rate",
    swatch: "bg-chart-heart-rate",
    values: (samples) => samples,
    format: (bpm) => `${Math.round(bpm)}`,
    summary: (samples) => `avg ${Math.round(mean(samples))} bpm`,
  },
  speed: {
    label: "Pace",
    colour: "--color-chart-pace",
    swatch: "bg-chart-pace",
    invert: true,
    values: (samples) => samples.map((speed) => (speed >= 1 ? 1000 / speed : null)),
    format: formatClock,
    summary: (samples) => `avg ${formatPace(mean(samples), 1000)} /km`,
  },
};

const paceDistances = { run: [1000, "/km"], swim: [100, "/100 m"] };

const orDash = (value, format) => (value ? format(value) : "—");

/** One sample per two pixels of the widest chart the screen can hold. */
function streamStep(durationSeconds) {
  const samples = Math.min(window.innerWidth, 576) / 2;
  return Math.max(1, Math.ceil(durationSeconds / samples));
}

/** An activity's recording: its streams as a chart, its laps and its pool lengths. */
export function ActivityRecord({ activity }) {
  return (
    <>
      {charts[activity.discipline] && <Streams activity={activity} />}
      {activity.laps.length > 0 && <Laps activity={activity} />}
      {activity.lengths.length > 0 && <Lengths lengths={activity.lengths} />}
    </>
  );
}

function Streams({ activity }) {
  const wanted = charts[activity.discipline];
  const query = useQuery(streamsQuery(activity.id, wanted, streamStep(activity.duration_seconds)));

  const chart = useMemo(() => {
    if (!query.data) return null;
    const { step, streams } = query.data;
    const series = wanted
      .filter((key) => streams[key]?.samples.some((value) => value != null))
      .map((key) => {
        const { values, summary, ...line } = channels[key];
        const { samples } = streams[key];
        return { key, ...line, values: values(samples), summary: summary(samples) };
      });
    if (series.length === 0) return null;

    const length = streams[series[0].key].samples.length;
    return {
      label: series
        .map((line, index) => (index ? line.label.toLowerCase() : line.label))
        .join(" and "),
      seconds: Array.from({ length }, (_, index) => index * step),
      series,
    };
  }, [query.data, wanted]);

  if (query.isError) {
    return <p className="m-0 text-sm text-ink-soft">The recording could not be loaded.</p>;
  }
  return chart && <StreamChart {...chart} />;
}

function Laps({ activity }) {
  const { laps, discipline } = activity;
  const pace = paceDistances[discipline];
  const columns = [
    { label: "Lap", value: (lap) => lap.lap_index + 1 },
    { label: "Time", value: (lap) => formatClock(lap.elapsed_seconds) },
    { label: "Distance", value: (lap) => orDash(lap.distance_m, formatDistance) },
    pace && {
      label: `Pace ${pace[1]}`,
      value: (lap) => formatPace(lap.avg_speed_mps, pace[0]),
    },
    laps.some((lap) => lap.avg_power) && {
      label: "Power",
      value: (lap) => orDash(lap.avg_power, (watts) => `${watts} W`),
    },
    laps.some((lap) => lap.avg_heart_rate) && {
      label: "Heart rate",
      value: (lap) => orDash(lap.avg_heart_rate, String),
    },
  ].filter(Boolean);

  return <RecordTable title="Laps" columns={columns} rows={laps} rowKey={(lap) => lap.lap_index} />;
}

function Lengths({ lengths }) {
  const columns = [
    { label: "Length", value: (length) => length.length_index + 1 },
    {
      label: "Stroke",
      value: (length) =>
        length.active ? length.stroke[0].toUpperCase() + length.stroke.slice(1) : "Rest",
    },
    { label: "Time", value: (length) => formatClock(length.elapsed_seconds) },
    { label: "Strokes", value: (length) => orDash(length.strokes, String) },
  ];

  return (
    <RecordTable
      title="Pool lengths"
      columns={columns}
      rows={lengths}
      rowKey={(length) => length.length_index}
    />
  );
}

function RecordTable({ title, columns, rows, rowKey }) {
  const titleId = useId();

  return (
    <section
      aria-labelledby={titleId}
      className="flex flex-col gap-2 overflow-x-auto rounded-card border border-border bg-surface p-4.5"
    >
      <h2 id={titleId} className="m-0 text-label font-semibold text-ink-muted uppercase">
        {title}
      </h2>
      <table aria-labelledby={titleId} className="w-full border-collapse text-sm">
        <thead>
          <tr>
            {columns.map((column) => (
              <th
                key={column.label}
                scope="col"
                className="pb-1.5 text-right text-xs font-normal text-ink-muted first:text-left"
              >
                {column.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={rowKey(row)} className="border-t border-divider">
              {columns.map((column) => (
                <td
                  key={column.label}
                  className="py-2 text-right font-display text-base tabular-nums first:text-left first:text-ink-muted"
                >
                  {column.value(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
