import { useQuery } from "@tanstack/react-query";
import { api } from "../api/client.js";
import { Card } from "../ui/Card.jsx";
import { PageHeader } from "../ui/PageHeader.jsx";

export function TodayScreen() {
  const health = useQuery({ queryKey: ["health"], queryFn: () => api("/health") });

  return (
    <>
      <PageHeader title="Today" />
      <Card id="server" title="Server">
        <p className="m-0 text-lg" role="status">
          {health.isPending && "Checking…"}
          {health.isError && "Unreachable"}
          {health.isSuccess && "Connected"}
        </p>
      </Card>
    </>
  );
}
