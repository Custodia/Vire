export class ApiError extends Error {
  constructor(status, body) {
    super(`API request failed with status ${status}`);
    this.status = status;
    this.body = body;
  }
}

const safeMethods = new Set(["GET", "HEAD", "OPTIONS"]);

// The session's CSRF token, fetched when an unsafe request first needs it.
let csrfToken = null;

/** Forgets the session's CSRF token, which signing in and signing out end. */
export function forgetCsrfToken() {
  csrfToken = null;
}

/** The session's CSRF token, fetched once and kept until it is forgotten. */
export function sessionToken() {
  csrfToken ??= send("/csrf").then(
    ({ token }) => token,
    (error) => {
      csrfToken = null;
      throw error;
    },
  );
  return csrfToken;
}

const refusedToken = (error) =>
  error instanceof ApiError && error.status === 403 && error.body?.reason === "invalid_csrf_token";

/**
 * Sends a request to the API and answers its decoded body. A request other
 * than a GET, HEAD or OPTIONS carries the session's CSRF token, and is sent
 * once more with a fresh token when the server refuses the one it carried.
 */
export async function api(path, options = {}) {
  if (safeMethods.has((options.method ?? "GET").toUpperCase())) return send(path, options);

  const withToken = async () =>
    send(path, {
      ...options,
      headers: { ...options.headers, "x-csrf-token": await sessionToken() },
    });

  try {
    return await withToken();
  } catch (error) {
    if (!refusedToken(error)) throw error;
    forgetCsrfToken();
    return withToken();
  }
}

async function send(path, options = {}) {
  const response = await fetch(`/api${path}`, {
    credentials: "same-origin",
    ...options,
    headers: { accept: "application/json", ...options.headers },
  });

  const body = await decode(response);

  if (!response.ok) {
    throw new ApiError(response.status, body);
  }

  return body;
}

async function decode(response) {
  if (response.status === 204) return null;
  if (response.headers.get("content-type")?.includes("application/json")) {
    return response.json();
  }
  return (await response.text()) || null;
}

export const getMe = () => api("/me");

export async function signIn({ email, password }) {
  const user = await api("/session", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  forgetCsrfToken();
  return user;
}

export async function signOut() {
  await api("/session", { method: "DELETE" });
  forgetCsrfToken();
}

export const getSeasons = () => api("/seasons");

export const getSeason = (id) => api(`/seasons/${encodeURIComponent(id)}`);

export const getPlanChanges = () => api("/plan_changes");

export const getDays = (from, to) => api(`/days?from=${from}&to=${to}`);

export const getSession = (id) => api(`/sessions/${encodeURIComponent(id)}`);

export const matchSession = (sessionId, activityId) =>
  api(`/sessions/${encodeURIComponent(sessionId)}/activity`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ activity_id: activityId }),
  });

export const getActivity = (id) => api(`/activities/${encodeURIComponent(id)}`);

export const getActivityStreams = (id, channels, step) =>
  api(
    `/activities/${encodeURIComponent(id)}/streams?${new URLSearchParams({ channels: channels.join(","), step })}`,
  );

export const getSync = () => api("/sync");

export const postSync = () => api("/sync", { method: "POST" });

export const uploadFitFile = (file) => {
  const body = new FormData();
  body.append("file", file);
  return api("/uploads", { method: "POST", body });
};

export const getUpload = (id) => api(`/uploads/${encodeURIComponent(id)}`);
