import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import {
  Button as AriaButton,
  Dialog,
  DialogTrigger,
  FileTrigger,
  Heading,
  Modal,
  ModalOverlay,
} from "react-aria-components";
import { ApiError, uploadFitFile } from "../api/client.js";
import { uploadQuery } from "../api/queries.js";
import { buttonClass } from "../ui/Button.jsx";

const POLL_MS = 750;

function errorDetail(error) {
  return error instanceof ApiError && error.body?.errors?.detail
    ? error.body.errors.detail
    : "The file could not be uploaded.";
}

/** The Upload action: a dialog that takes a .fit file and follows it until it is processed or failed. */
export function UploadDialog() {
  return (
    <DialogTrigger>
      <AriaButton className={buttonClass("secondary")}>Upload</AriaButton>
      <ModalOverlay
        isDismissable
        className="fixed inset-0 z-50 flex items-end justify-center bg-ground/80 sm:items-center"
      >
        <Modal className="w-full max-w-md">
          <Dialog
            aria-label="Upload a .fit file"
            className="screen-insets flex flex-col gap-4 rounded-t-card border border-border bg-surface p-5 outline-none sm:rounded-card"
          >
            {({ close }) => <UploadForm close={close} />}
          </Dialog>
        </Modal>
      </ModalOverlay>
    </DialogTrigger>
  );
}

function UploadForm({ close }) {
  const queryClient = useQueryClient();
  const [fileName, setFileName] = useState(null);

  const upload = useMutation({ mutationFn: uploadFitFile });
  const uploadId = upload.data?.id;
  const status = useQuery({ ...uploadQuery(uploadId, POLL_MS), enabled: Boolean(uploadId) });
  const result = status.data?.status;

  useEffect(() => {
    if (result === "processed") {
      queryClient.invalidateQueries({ queryKey: ["days"] });
      queryClient.invalidateQueries({ queryKey: ["sessions"] });
      queryClient.invalidateQueries({ queryKey: ["activities"] });
    }
  }, [result, queryClient]);

  const busy = upload.isPending || (uploadId && (!result || result === "pending"));

  const choose = (files) => {
    const file = files?.[0];
    if (!file) return;
    setFileName(file.name);
    upload.mutate(file);
  };

  return (
    <>
      <Heading slot="title" className="m-0 text-xl font-bold">
        Upload a .fit file
      </Heading>
      <FileTrigger acceptedFileTypes={[".fit"]} onSelect={choose}>
        <AriaButton isDisabled={busy} className={buttonClass("primary", "self-start")}>
          Choose a file
        </AriaButton>
      </FileTrigger>
      <div role="status" className="flex flex-col gap-2 text-sm text-ink-soft">
        {upload.isPending && <p className="m-0">Uploading {fileName}…</p>}
        {upload.isError && <p className="m-0 text-state-skipped">{errorDetail(upload.error)}</p>}
        {busy && !upload.isPending && <p className="m-0">Processing {fileName}…</p>}
        {result === "processed" && (
          <p className="m-0 text-state-done">
            {fileName} is processed.
            {status.data.activity_id && (
              <>
                {" "}
                <Link
                  to="/activities/$id"
                  params={{ id: status.data.activity_id }}
                  className="text-accent"
                  onClick={close}
                >
                  Open the activity
                </Link>
              </>
            )}
          </p>
        )}
        {result === "failed" && (
          <p className="m-0 text-state-skipped">
            {fileName} could not be processed{status.data.error ? `: ${status.data.error}` : "."}
          </p>
        )}
        {status.isError && (
          <p className="m-0 text-state-skipped">The upload could not be followed.</p>
        )}
      </div>
      <AriaButton onPress={close} className={buttonClass("quiet", "self-end")}>
        Close
      </AriaButton>
    </>
  );
}
