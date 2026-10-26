import { useRouter } from "@tanstack/react-router";
import { Button } from "../ui/Button.jsx";
import { Screen } from "../ui/Screen.jsx";

export function ErrorScreen() {
  const router = useRouter();

  return (
    <Screen>
      <h1 className="m-0 pt-3 text-3xl font-bold tracking-tight">Something went wrong</h1>
      <p role="alert" className="m-0 text-sm text-ink-soft">
        Vire could not load this page. Check your connection and try again.
      </p>
      <Button className="self-start" onClick={() => router.invalidate()}>
        Try again
      </Button>
    </Screen>
  );
}
