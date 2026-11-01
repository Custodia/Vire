import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { signOut } from "../api/client.js";
import { Button } from "../ui/Button.jsx";

/** Signs out, forgets every cached answer and goes to the sign-in screen. */
export function useSignOut() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: signOut,
    onSuccess: () => {
      queryClient.clear();
      navigate({ to: "/sign-in" });
    },
  });
}

export function SignOutButton() {
  const mutation = useSignOut();

  return (
    <Button variant="quiet" onClick={() => mutation.mutate()} disabled={mutation.isPending}>
      Sign out
    </Button>
  );
}
