import { useQuery } from "@tanstack/react-query";
import { api } from "../api/client.js";

export function TodayScreen() {
  const health = useQuery({ queryKey: ["health"], queryFn: () => api("/health") });

  return (
    <main className="mx-auto max-w-xl px-4 py-10">
      <h1 className="font-display text-5xl font-semibold uppercase tracking-tight">Vire</h1>
      <p className="mt-2 text-ink-muted">Today</p>
      <section className="mt-8 rounded-card bg-surface p-5">
        <h2 className="text-sm uppercase tracking-wide text-ink-muted">Server</h2>
        <p className="mt-1 text-lg" role="status">
          {health.isPending && "Checking…"}
          {health.isError && "Unreachable"}
          {health.isSuccess && "Connected"}
        </p>
      </section>
    </main>
  );
}
