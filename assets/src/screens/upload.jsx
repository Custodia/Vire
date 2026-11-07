import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { Button as AriaButton, DropZone, FileTrigger, Heading } from "react-aria-components";
import { ApiError, uploadFitFile } from "../api/client.js";
import { activityQuery, uploadQuery } from "../api/queries.js";
import { discipline } from "../lib/disciplines.js";
import {
  formatClock,
  formatDay,
  formatDistance,
  formatFileSize,
  formatStartTime,
} from "../lib/format.js";
import { buttonClass } from "../ui/Button.jsx";
import { DisciplineIcon } from "../ui/DisciplineIcon.jsx";
import { Sheet } from "../ui/Sheet.jsx";
import { Spinner } from "../ui/Spinner.jsx";
import { StatusChip } from "../ui/StatusChip.jsx";

/** The Upload action: a button that opens the upload sheet. */
export function UploadDialog() {
  const [open, setOpen] = useState(false);

  return (
    <>
      <AriaButton onPress={() => setOpen(true)} className={buttonClass("secondary")}>
        Upload .fit
      </AriaButton>
      <UploadSheet isOpen={open} onOpenChange={setOpen} />
    </>
  );
}

/**
 * A sheet that takes a .fit file, chosen or dropped, follows it through
 * reading and matching, and shows the activity it became with the session it
 * was matched to.
 */
export function UploadSheet({ isOpen, onOpenChange }) {
  return (
    <Sheet isOpen={isOpen} onOpenChange={onOpenChange} className="lg:min-h-105">
      {({ close }) => <Upload close={close} />}
    </Sheet>
  );
}

function Upload({ close }) {
  const [file, setFile] = useState(null);
  const upload = useMutation({ mutationFn: uploadFitFile });
  const status = useQuery(uploadQuery(upload.data?.id)).data ?? upload.data;

  const choose = (chosen) => {
    if (!chosen) return;
    setFile({ name: chosen.name, size: chosen.size });
    upload.mutate(chosen);
  };

  const again = () => {
    upload.reset();
    setFile(null);
  };

  if (!file) return <Choose close={close} onChoose={choose} />;
  if (upload.isError) {
    return <Unread close={close} file={file} message={refusal(upload.error)} onChoose={choose} />;
  }
  if (status?.status === "failed") {
    const message = `This file could not be read: ${status.error}. Try exporting it again from the device.`;
    return <Unread close={close} file={file} message={message} onChoose={choose} />;
  }
  if (status?.status === "processed") {
    return <Processed close={close} activityId={status.activity_id} onAgain={again} />;
  }
  return <Following close={close} file={file} uploaded={upload.isSuccess} />;
}

function refusal(error) {
  return error instanceof ApiError && error.body?.errors?.detail
    ? `This file could not be uploaded: ${error.body.errors.detail}.`
    : "This file could not be uploaded. Try again in a moment.";
}

function Head({ title, close }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <Heading slot="title" className="m-0 text-xl font-bold">
        {title}
      </Heading>
      <AriaButton
        aria-label="Close"
        onPress={close}
        className="focus-ring -my-2.5 -mr-2.5 grid size-11 place-items-center rounded-tile text-ink-muted hover:text-ink"
      >
        <svg
          aria-hidden="true"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        >
          <path d="M6 6l12 12M18 6L6 18" />
        </svg>
      </AriaButton>
    </div>
  );
}

function ChooseButton({ label, onChoose }) {
  return (
    <FileTrigger acceptedFileTypes={[".fit"]} onSelect={(files) => onChoose(files?.[0])}>
      <AriaButton className={buttonClass("primary")}>{label}</AriaButton>
    </FileTrigger>
  );
}

function Choose({ close, onChoose }) {
  const drop = async (event) => {
    const item = event.items.find((dropped) => dropped.kind === "file");
    if (item) onChoose(await item.getFile());
  };

  return (
    <>
      <Head title="Upload a .fit file" close={close} />
      <DropZone
        aria-label="Drop a .fit file here"
        onDrop={drop}
        className="flex flex-1 flex-col items-center justify-center gap-3 rounded-tile border-[1.5px] border-dashed border-rule bg-surface-sunken px-4 py-7 text-center data-[drop-target]:border-accent data-[drop-target]:bg-accent-tint"
      >
        <span className="grid size-12 place-items-center rounded-tile bg-accent-tint text-accent">
          <svg
            aria-hidden="true"
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M12 16V4M7 9l5-5 5 5M5 20h14" />
          </svg>
        </span>
        <span className="text-row font-semibold">Drop a .fit file here</span>
        <span className="text-caption text-ink-muted">
          From a watch or bike computer. It is matched to that day&rsquo;s sessions.
        </span>
        <ChooseButton label="Choose a file" onChoose={onChoose} />
      </DropZone>
    </>
  );
}

function FileRow({ file, caution = false }) {
  return (
    <div className="flex items-center gap-3 rounded-tile border border-divider bg-surface-sunken p-3">
      <span
        className={`grid size-9 flex-none place-items-center rounded-tile ${caution ? "bg-caution-tint text-caution" : "bg-calendar-planned text-ink-muted"}`}
      >
        <svg
          aria-hidden="true"
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          {caution ? (
            <path d="M12 7v6M12 16.5v.5" />
          ) : (
            <>
              <path d="M6 3h8l4 4v14H6z" />
              <path d="M14 3v4h4" />
            </>
          )}
        </svg>
      </span>
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="truncate text-sm font-semibold">{file.name}</span>
        <span className="font-display text-caption font-semibold text-ink-muted">
          {formatFileSize(file.size)}
        </span>
      </div>
    </div>
  );
}

function Step({ state, children }) {
  return (
    <li
      className={`flex min-h-6 items-center gap-2.5 text-caption ${state === "waiting" ? "text-ink-muted" : ""}`}
    >
      {state === "working" ? (
        <Spinner />
      ) : (
        <span
          aria-hidden="true"
          className={`w-4 text-center ${state === "done" ? "text-accent" : ""}`}
        >
          {state === "done" ? "✓" : "·"}
        </span>
      )}
      {children}
    </li>
  );
}

function Following({ close, file, uploaded }) {
  return (
    <>
      <Head title="Upload a .fit file" close={close} />
      <FileRow file={file} />
      <ol
        role="status"
        aria-label="Progress"
        className="m-0 flex list-none flex-col gap-2.5 px-0.5 py-1"
      >
        <Step state={uploaded ? "done" : "working"}>{uploaded ? "Uploaded" : "Uploading"}</Step>
        <Step state={uploaded ? "working" : "waiting"}>Reading the file</Step>
        <Step state="waiting">Matching it to your plan</Step>
      </ol>
      <span className="flex-1" />
      <AriaButton onPress={close} className={buttonClass("quiet", "self-end")}>
        Close · it keeps going
      </AriaButton>
    </>
  );
}

function Unread({ close, file, message, onChoose }) {
  return (
    <>
      <Head title="Upload a .fit file" close={close} />
      <FileRow file={file} caution />
      <p role="alert" className="m-0 text-sm leading-relaxed text-ink-soft">
        {message}
      </p>
      <span className="flex-1" />
      <div className="flex justify-end gap-2">
        <AriaButton onPress={close} className={buttonClass("quiet")}>
          Close
        </AriaButton>
        <ChooseButton label="Choose another file" onChoose={onChoose} />
      </div>
    </>
  );
}

function Processed({ close, activityId, onAgain }) {
  const activity = useQuery({ ...activityQuery(activityId), enabled: activityId != null }).data;
  const session = activity?.session;

  return (
    <>
      <Head title="Uploaded" close={close} />
      {activity && <ActivityCard activity={activity} />}
      {activity && (
        <p className="m-0 flex items-center gap-2 text-caption">
          {session ? (
            <>
              <StatusChip state="done" /> Matched to <strong>{session.title}</strong>
            </>
          ) : (
            "Not in the plan"
          )}
        </p>
      )}
      <span className="flex-1" />
      <div className="flex justify-end gap-2">
        <AriaButton onPress={onAgain} className={buttonClass("quiet")}>
          Upload another
        </AriaButton>
        {activity &&
          (session ? (
            <Link
              to="/sessions/$id"
              params={{ id: session.id }}
              onClick={close}
              className={buttonClass("primary")}
            >
              Open the session
            </Link>
          ) : (
            <Link
              to="/activities/$id"
              params={{ id: activity.id }}
              onClick={close}
              className={buttonClass("primary")}
            >
              Open the activity
            </Link>
          ))}
      </div>
    </>
  );
}

function ActivityCard({ activity }) {
  const { activity: name, text, tint, edge, tile } = discipline(activity.discipline);
  const figures = [
    ["Duration", formatClock(activity.duration_seconds)],
    ["Distance", activity.distance_m == null ? "—" : formatDistance(activity.distance_m)],
    ["Avg HR", activity.avg_heart_rate ?? "—"],
  ];

  return (
    <div className={`flex flex-col gap-3.5 rounded-tile border p-4 ${tint} ${edge}`}>
      <div className="flex items-center gap-3">
        <span className={`grid size-10 flex-none place-items-center rounded-tile ${tile}`}>
          <DisciplineIcon discipline={activity.discipline} size={22} />
        </span>
        <div className="flex flex-col gap-0.5">
          <span className={`text-label font-semibold uppercase ${text}`}>
            {formatDay(activity.local_date)} ·{" "}
            {formatStartTime(activity.started_at, activity.utc_offset_seconds)}
          </span>
          <span className="text-[17px] font-bold">{name}</span>
        </div>
      </div>
      <dl className="m-0 grid grid-cols-3 gap-2">
        {figures.map(([label, value]) => (
          <div key={label} className="flex flex-col-reverse">
            <dt className="text-xs text-ink-muted">{label}</dt>
            <dd className="m-0 font-display text-[22px] font-semibold">{value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
