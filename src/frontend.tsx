/**
 * This file is the entry point for the React app, it sets up the root
 * element and renders the App component to the DOM.
 *
 * It is included in `src/index.html`.
 */

import { StrictMode } from "react";
import { hydrateRoot, createRoot } from "react-dom/client";
import { App } from "./App";

const elem = document.getElementById("root")!;
const app = (
  <StrictMode>
    <App />
  </StrictMode>
);

if (import.meta.hot) {
  // With hot module reloading, `import.meta.hot.data` is persisted.
  const root = (import.meta.hot.data.root ??= createRoot(elem));
  root.render(app);
} else if (elem.hasChildNodes()) {
  // Pre-rendered HTML present — hydrate to attach event handlers.
  hydrateRoot(elem, app);
} else {
  // No pre-rendered HTML — full client-side render.
  createRoot(elem).render(app);
}
