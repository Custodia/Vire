import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { createQueryClient } from "./api/query-client.js";
import { App } from "./app.jsx";
import { createAppRouter } from "./router.jsx";
import "./styles/app.css";

const queryClient = createQueryClient();
const router = createAppRouter({ queryClient });

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App router={router} queryClient={queryClient} />
  </StrictMode>,
);
