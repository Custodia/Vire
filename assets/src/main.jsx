import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient } from "@tanstack/react-query";
import { App } from "./app.jsx";
import { createAppRouter } from "./router.jsx";
import "./styles/app.css";

const router = createAppRouter();
const queryClient = new QueryClient();

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App router={router} queryClient={queryClient} />
  </StrictMode>,
);
