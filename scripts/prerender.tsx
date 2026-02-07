#!/usr/bin/env bun
/**
 * Build-time pre-rendering: renders the React app to static HTML
 * and injects it into dist/index.html for SEO.
 */

import { renderToString } from "react-dom/server";
import { StrictMode } from "react";
import { App } from "../src/App";
import * as fs from "fs";

const DIST_HTML = "./dist/index.html";

const html = renderToString(
  <StrictMode>
    <App />
  </StrictMode>
);

const indexHtml = fs.readFileSync(DIST_HTML, "utf-8");
const prerendered = indexHtml.replace(
  '<div id="root"></div>',
  `<div id="root">${html}</div>`
);

fs.writeFileSync(DIST_HTML, prerendered, "utf-8");

console.log(`✅ Pre-rendered ${html.length} chars of HTML into ${DIST_HTML}`);
