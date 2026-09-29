import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/caveat/cyrillic-400.css";
import "@fontsource/caveat/cyrillic-600.css";
import "@fontsource/caveat/cyrillic-700.css";
import "@fontsource/caveat/latin-400.css";
import "@fontsource/caveat/latin-600.css";
import "@fontsource/caveat/latin-700.css";
import "./index.css";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
