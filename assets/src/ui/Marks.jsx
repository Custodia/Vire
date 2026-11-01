const THICK = 3.2;
const THIN = 1.5;

const arcs = {
  done: { stroke: "stroke-state-done", width: THICK },
  skipped: { stroke: "stroke-state-skipped", width: THIN },
  planned: { stroke: "stroke-ink-faint", width: THIN },
};

function Ring({ size, label, children }) {
  return (
    <svg
      role="img"
      aria-label={label}
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      fill="none"
      className="block flex-none"
    >
      {children}
    </svg>
  );
}

/**
 * A day as one ring split evenly between its sessions, each arc thick when
 * done and thin while upcoming or skipped. A day without sessions is a dashed
 * ring, green once it is past. `today` circles it in the accent.
 */
export function DayRing({ day, size = 16, today = false }) {
  const centre = size / 2;
  const radius = (size - 4) / 2;
  const around = 2 * Math.PI * radius;
  const { sessions } = day;
  const each = around / sessions.length;

  const ring =
    sessions.length === 0 ? (
      <Ring size={size} label={day.rest === "kept" ? "Rest day kept" : "Rest day"}>
        <circle
          cx={centre}
          cy={centre}
          r={radius}
          strokeWidth={day.rest === "kept" ? 2.2 : THIN}
          strokeDasharray="2.2 2.4"
          className={day.rest === "kept" ? "stroke-state-rest-kept" : "stroke-rule"}
        />
      </Ring>
    ) : (
      <Ring size={size} label={`${day.done} of ${sessions.length} done`}>
        {sessions.map((session, index) => {
          const { stroke, width } = arcs[session.status] ?? arcs.planned;
          return (
            <circle
              key={session.id}
              cx={centre}
              cy={centre}
              r={radius}
              strokeWidth={width}
              strokeDasharray={`${each} ${around - each}`}
              strokeDashoffset={around / 4 - index * each}
              className={stroke}
            />
          );
        })}
      </Ring>
    );

  return today ? (
    <span className="inline-grid place-items-center rounded-pill p-0.5 ring-2 ring-accent">
      {ring}
    </span>
  ) : (
    ring
  );
}
