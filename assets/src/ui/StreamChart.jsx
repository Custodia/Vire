import { useEffect, useRef } from "react";

/**
 * Recorded channels over the elapsed seconds, each series with its own scale,
 * under a legend of their names and summaries. uPlot draws the lines on a
 * canvas and is loaded only where the browser can draw 2D paths, so without
 * that only the frame and the legend render.
 *
 * Each series has a `key`, a `label`, a `summary`, the custom property of its
 * `colour` and the class of its `swatch`, its `values` aligned with `seconds`,
 * a `format` for its axis and, for a scale where lower is better, `invert`.
 */
export function StreamChart({ label, seconds, series }) {
  const plot = useRef(null);

  useEffect(() => {
    if (typeof window.Path2D !== "function") return undefined;

    let cancelled = false;
    let remove;
    import("./stream-plot.js").then(({ drawStreamChart }) => {
      if (!cancelled) remove = drawStreamChart(plot.current, { seconds, series });
    });
    return () => {
      cancelled = true;
      remove?.();
    };
  }, [seconds, series]);

  return (
    <figure
      aria-label={label}
      className="m-0 flex flex-col gap-3 rounded-card border border-border bg-surface p-4.5"
    >
      <figcaption className="flex flex-wrap gap-x-4 gap-y-1">
        {series.map((line) => (
          <span key={line.key} className="inline-flex items-center gap-1.5 text-xs text-ink-muted">
            <span aria-hidden="true" className={`h-0.5 w-3 rounded-pill ${line.swatch}`} />
            <span className="font-semibold text-ink">{line.label}</span>
            {line.summary}
          </span>
        ))}
      </figcaption>
      <div ref={plot} className="h-48 w-full" />
    </figure>
  );
}
