import { http, HttpResponse } from "msw";

// One handler per API endpoint, shaped like the server's response.
export const handlers = [http.get("/api/health", () => HttpResponse.json({ status: "ok" }))];
