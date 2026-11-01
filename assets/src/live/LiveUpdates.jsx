import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { forgetCsrfToken, sessionToken } from "../api/client.js";
import { meQuery } from "../api/queries.js";
import { connectLive } from "./connection.js";
import { catchUp, receiveSync, receiveUpload } from "./updates.js";

/** Keeps the signed-in user's cached queries current with the pushes of their channel. */
export function LiveUpdates() {
  const queryClient = useQueryClient();
  const userId = useQuery(meQuery).data?.id;

  useEffect(() => {
    if (!userId) return undefined;
    return connectLive({
      topic: `user:${userId}`,
      csrfToken: sessionToken,
      forgetCsrfToken,
      handlers: {
        sync: (status) => receiveSync(queryClient, status),
        upload: (upload) => receiveUpload(queryClient, upload),
      },
      onJoin: () => catchUp(queryClient),
    });
  }, [userId, queryClient]);

  return null;
}
