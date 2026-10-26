import { useId } from "react";

/** A labelled input at least 44 px tall, with an error line under it. */
export function TextField({ label, error, type = "text", ...props }) {
  const id = useId();
  const errorId = `${id}-error`;

  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-label font-semibold text-ink-muted uppercase">
        {label}
      </label>
      <input
        id={id}
        type={type}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errorId : undefined}
        className="focus-ring min-h-11 rounded-tile border border-border bg-surface px-3.5 text-base text-ink placeholder:text-ink-muted aria-invalid:border-state-skipped-edge"
        {...props}
      />
      {error && (
        <p id={errorId} className="m-0 text-caption text-state-skipped">
          {error}
        </p>
      )}
    </div>
  );
}
