import { Socket } from "phoenix";

/**
 * Connects to the dashboard's WebSocket with the session's CSRF token, which
 * `csrfToken` answers, and joins `topic`. Each event the channel pushes goes to
 * its handler in `handlers`, by name, and `onJoin` runs on every join: the
 * first and each one after the connection comes back. A connection the server
 * refuses is tried again with the token fetched anew. Answers a function that
 * disconnects.
 */
export function connectLive({ topic, csrfToken, forgetCsrfToken, handlers, onJoin }) {
  let token = null;
  let closed = false;
  const socket = new Socket("/socket", { params: () => ({ _csrf_token: token }) });
  const channel = socket.channel(topic);

  for (const [event, handle] of Object.entries(handlers)) {
    channel.on(event, (payload) => handle(payload));
  }

  const refreshToken = () => {
    forgetCsrfToken();
    return csrfToken().then(
      (fresh) => {
        token = fresh;
      },
      () => {},
    );
  };

  // A refused connection closes before it opens, the same as one that drops,
  // so every close fetches the token the next attempt carries.
  socket.onClose(() => {
    if (!closed) refreshToken();
  });

  csrfToken().then(
    (fresh) => {
      if (closed) return;
      token = fresh;
      socket.connect();
      channel.join().receive("ok", () => onJoin());
    },
    () => {},
  );

  return () => {
    closed = true;
    channel.leave();
    socket.disconnect();
  };
}
