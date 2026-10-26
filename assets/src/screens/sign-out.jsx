import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { signOut } from "../api/client.js";
import { Button } from "../ui/Button.jsx";

export function SignOutButton() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const mutation = useMutation({
    mutationFn: signOut,
    onSuccess: () => {
      queryClient.clear();
      navigate({ to: "/sign-in" });
    },
  });

  return (
    <Button variant="quiet" onClick={() => mutation.mutate()} disabled={mutation.isPending}>
      Sign out
    </Button>
  );
}
