import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { getRouteApi, useNavigate } from "@tanstack/react-router";
import { signIn } from "../api/client.js";
import { meQuery } from "../api/queries.js";
import { Button } from "../ui/Button.jsx";
import { Screen } from "../ui/Screen.jsx";
import { TextField } from "../ui/TextField.jsx";

const route = getRouteApi("/sign-in");

export function SignInScreen() {
  const { redirect } = route.useSearch();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const mutation = useMutation({
    mutationFn: signIn,
    onSuccess: (user) => {
      queryClient.setQueryData(meQuery.queryKey, user);
      navigate({ href: redirect ?? "/today", replace: true });
    },
  });

  const submit = (event) => {
    event.preventDefault();
    mutation.mutate({ email, password });
  };

  return (
    <Screen>
      <header className="flex flex-col gap-1 pt-3">
        <span className="font-display text-4xl font-bold tracking-wide text-accent uppercase">
          Vire
        </span>
        <h1 className="m-0 text-3xl font-bold tracking-tight">Sign in</h1>
      </header>
      <form className="flex flex-col gap-4" onSubmit={submit} noValidate>
        <TextField
          label="Email"
          type="email"
          name="email"
          autoComplete="username"
          required
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
        <TextField
          label="Password"
          type="password"
          name="password"
          autoComplete="current-password"
          required
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
        {mutation.isError && (
          <p role="alert" className="m-0 text-sm text-state-skipped">
            {errorMessage(mutation.error)}
          </p>
        )}
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? "Signing in…" : "Sign in"}
        </Button>
      </form>
    </Screen>
  );
}

function errorMessage(error) {
  return error.status === 401
    ? "That email and password do not match an account."
    : "Signing in failed. Try again.";
}
