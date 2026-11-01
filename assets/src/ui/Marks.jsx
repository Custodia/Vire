import { discipline as disciplineOf } from "../lib/disciplines.js";

const THICK = 3.2;
const THIN = 1.5;

const arcs = {
  done: { stroke: "stroke-state-done", width: THICK },
  skipped: { stroke: "stroke-state-skipped", width: THIN },
  planned: { stroke: "stroke-ink-faint", width: THIN },
};

const sessionLabels = {
  done: "Done",
  planned: "Upcoming",
  skipped: "Skipped",
  extra: "Not in the plan",
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
 * A session's state as a ring: thick with a tick when done, thin in its
 * discipline's colour while upcoming, thin with a cross when skipped, and
 * thick with a plus for an activity outside the plan.
 */
export function SessionMark({ state, discipline, size = 18 }) {
  const centre = size / 2;
  const radius = (size - 4) / 2;
  const unit = size / 24;
  const circle = (className, width) => (
    <circle cx={centre} cy={centre} r={radius} strokeWidth={width} className={className} />
  );
  const line = (d, className, width) => (
    <path
      d={d}
      strokeWidth={width}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    />
  );
  const at = (value) => (value * unit).toFixed(1);

  return (
    <Ring size={size} label={sessionLabels[state]}>
      {state === "done" && (
        <>
          {circle("stroke-state-done", THICK)}
          {line(
            `M${at(7.5)} ${at(12.5)}l${at(3)} ${at(3)}l${at(6)} -${at(6.5)}`,
            "stroke-state-done",
            Math.max(1.6, 2.4 * unit),
          )}
        </>
      )}
      {state === "skipped" && (
        <>
          {circle("stroke-state-skipped", THIN)}
          {line(
            `M${at(9)} ${at(9)}l${at(6)} ${at(6)}M${at(15)} ${at(9)}l-${at(6)} ${at(6)}`,
            "stroke-state-skipped",
            Math.max(1.4, 2 * unit),
          )}
        </>
      )}
      {state === "extra" && (
        <>
          {circle("stroke-state-extra", THICK)}
          {line(
            `M${at(12)} ${at(8)}v${at(8)}M${at(8)} ${at(12)}h${at(8)}`,
            "stroke-state-extra",
            Math.max(1.4, 2 * unit),
          )}
        </>
      )}
      {state === "planned" && circle(disciplineOf(discipline).stroke, THIN)}
    </Ring>
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

const dotTones = {
  done: "size-1.75 rounded-pill bg-state-done",
  skipped: "h-0.75 w-2.25 rounded-bar bg-state-skipped",
};

/** A session as a dot in a month: filled when done, a dash when skipped, a ring while upcoming. */
export function SessionDot({ session }) {
  if (dotTones[session.status]) {
    return <span aria-hidden="true" className={dotTones[session.status]} />;
  }
  return (
    <span
      aria-hidden="true"
      className={`size-1.75 rounded-pill border-2 ${disciplineOf(session.discipline).border}`}
    />
  );
}

/** A past rest day as a dot in a month. */
export function RestKeptDot() {
  return (
    <span
      aria-hidden="true"
      className="size-1.75 rounded-pill border-[1.5px] border-state-rest-kept"
    />
  );
}
