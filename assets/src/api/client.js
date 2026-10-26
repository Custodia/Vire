export class ApiError extends Error {
  constructor(status, body) {
    super(`API request failed with status ${status}`);
    this.status = status;
    this.body = body;
  }
}

export async function api(path, options = {}) {
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

export const signIn = ({ email, password }) =>
  api("/session", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password }),
  });

export const signOut = () => api("/session", { method: "DELETE" });

export const getDay = (date) => api(`/days/${date}`);
