import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app.jsx";
import { createApp } from "./create-app.js";
import "./styles/app.css";

const { queryClient, router } = createApp();

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App router={router} queryClient={queryClient} />
  </StrictMode>,
);
