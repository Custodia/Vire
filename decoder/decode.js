// Decodes FIT files for Vire. Requests and responses are JSON, each framed by
// a 4-byte big-endian length, on stdin and stdout. stdout carries nothing else.
//
// Request:  {"op": "decode", "data": "<the file's bytes in base64>"}
// Response: {"ok": true, "messages": {...}, "units": {...}}
//           {"ok": false, "error": "<what failed>"}

import { Decoder, Profile, Stream } from "@garmin/fitsdk";

// The SDK logs warnings to the console, which would break the framing.
console.log = console.info = console.debug = console.error;

const recordUnits = Object.fromEntries(
  Object.values(Profile.messages[Profile.MesgNum.RECORD].fields)
    .map((field) => [field.name, [field.units].flat()[0]])
    .filter(([, units]) => units),
);

function decode(bytes) {
  const decoder = new Decoder(Stream.fromBuffer(bytes));

  if (!decoder.isFIT()) return failure("not a FIT file");
  if (!decoder.checkIntegrity()) {
    return failure("integrity check failed: the file's size or CRC does not match its contents");
  }

  const descriptions = {};
  const { messages, errors } = decoder.read({
    fieldDescriptionListener: (key, _developerDataId, description) => {
      descriptions[key] = description;
    },
  });

  if (errors.length > 0) {
    return failure(`decoding failed: ${errors.map((error) => error.message).join("; ")}`);
  }

  for (const group of Object.values(messages)) {
    for (const message of group) {
      if (message.developerFields) {
        message.developerFields = named(message.developerFields, descriptions);
      }
    }
  }

  const developerUnits = Object.fromEntries(
    Object.values(descriptions)
      .filter((description) => description.fieldName && description.units)
      .map((description) => [description.fieldName, description.units]),
  );

  return {
    ok: true,
    messages,
    units: { recordMesgs: recordUnits, developerFields: developerUnits },
  };
}

function named(developerFields, descriptions) {
  return Object.fromEntries(
    Object.entries(developerFields).map(([key, value]) => [
      descriptions[key]?.fieldName ?? key,
      value,
    ]),
  );
}

function failure(error) {
  return { ok: false, error };
}

function handle(frame) {
  let request;
  try {
    request = JSON.parse(frame.toString("utf8"));
  } catch {
    return failure("the request is not JSON");
  }

  if (request?.op !== "decode" || typeof request.data !== "string") {
    return failure("the request is not a decode request with base64 data");
  }

  try {
    return decode(Buffer.from(request.data, "base64"));
  } catch (error) {
    return failure(`decoding failed: ${error.message}`);
  }
}

function toJSON(_key, value) {
  if (typeof value === "bigint") return Number(value);
  if (ArrayBuffer.isView(value)) return Array.from(value);
  return value;
}

function respond(response) {
  const body = Buffer.from(JSON.stringify(response, toJSON), "utf8");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(body.length);
  process.stdout.write(Buffer.concat([length, body]));
}

function serve() {
  let pending = Buffer.alloc(0);

  process.stdin.on("data", (chunk) => {
    pending = Buffer.concat([pending, chunk]);

    while (pending.length >= 4) {
      const length = pending.readUInt32BE(0);
      if (pending.length < 4 + length) break;

      const frame = pending.subarray(4, 4 + length);
      pending = pending.subarray(4 + length);
      respond(handle(frame));
    }
  });

  process.stdin.on("end", () => process.exit(0));
  process.stdout.on("error", () => process.exit(0));
}

serve();
