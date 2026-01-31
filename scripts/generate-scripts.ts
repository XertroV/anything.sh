#!/usr/bin/env bun
/**
 * Build script to generate anything.sh artifacts for all providers
 * Outputs to dist/{provider}/{full|compact}/anything.sh
 */

import { 
  ALL_PROVIDERS, 
  PROVIDERS, 
  getScriptFull, 
  getScriptCompact,
  type ProviderId 
} from '../src/scriptGenerator';
import * as fs from 'fs';
import * as path from 'path';

const DIST_DIR = './dist';

function generateIndexPage(): string {
  const rows = ALL_PROVIDERS.map(provider => {
    const name = PROVIDERS[provider].name;
    return `
    <tr class="border-b border-zinc-800 hover:bg-zinc-900/50 transition-colors">
      <td class="py-3 px-4 text-emerald-400 font-bold">${name}</td>
      <td class="py-3 px-4">
        <a href="/${provider}/full/anything.sh" class="text-zinc-400 hover:text-emerald-400 transition-colors text-xs font-mono">/${provider}/full/anything.sh</a>
      </td>
      <td class="py-3 px-4">
        <a href="/${provider}/compact/anything.sh" class="text-zinc-400 hover:text-emerald-400 transition-colors text-xs font-mono">/${provider}/compact/anything.sh</a>
      </td>
    </tr>`;
  }).join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>anything.sh - Script Downloads</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    body {
      background-color: #050505;
      color: #a1a1aa;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }
    .scanlines {
      position: fixed;
      inset: 0;
      pointer-events: none;
      z-index: 50;
      background: linear-gradient(rgba(18,16,16,0) 50%, rgba(0,0,0,0.25) 50%),
                  linear-gradient(90deg, rgba(255,0,0,0.06), rgba(0,255,0,0.02), rgba(0,0,255,0.06));
      background-size: 100% 4px, 3px 100%;
      opacity: 0.2;
    }
  </style>
</head>
<body class="min-h-screen">
  <div class="scanlines"></div>
  
  <div class="relative z-10 max-w-5xl mx-auto p-8">
    <header class="mb-12">
      <pre class="text-xs text-emerald-600 font-bold mb-4">
┌─┐┌┐┌┬ ┬┌┬┐┬ ┬┬┌┐┌┌─┐ ┌─┐┬ ┬
├─┤│││└┬┘ │ ├─┤│││││ ┬ └─┐├─┤
┴ ┴┘└┘ ┴  ┴ ┴ ┴┴┘└┘└─┘o└─┘┴ ┴
      </pre>
      <h1 class="text-2xl font-bold text-white mb-2">anything.sh Downloads</h1>
      <p class="text-zinc-500 text-sm">Autopoietic bash scripts for every LLM provider.</p>
    </header>

    <div class="bg-[#0a0a0a] border border-zinc-800 rounded overflow-hidden">
      <table class="w-full text-left border-collapse">
        <thead>
          <tr class="border-b border-zinc-800 bg-zinc-900/50">
            <th class="py-3 px-4 text-xs uppercase tracking-wider text-zinc-500 font-bold">Provider</th>
            <th class="py-3 px-4 text-xs uppercase tracking-wider text-zinc-500 font-bold">Full Version</th>
            <th class="py-3 px-4 text-xs uppercase tracking-wider text-zinc-500 font-bold">Compact Version</th>
          </tr>
        </thead>
        <tbody class="text-sm">
          ${rows}
        </tbody>
      </table>
    </div>

    <div class="mt-12 text-xs text-zinc-600 space-y-2">
      <p class="text-emerald-600 font-bold">QUICK START:</p>
      <code class="block bg-zinc-900 border border-zinc-800 p-3 text-zinc-400 font-mono">
        wget https://xertrov.github.io/anything.sh/claude/full/anything.sh && chmod +x anything.sh && ./anything.sh
      </code>
      <p class="text-zinc-500 mt-4">
        Replace <span class="text-emerald-400">claude/full</span> with your preferred provider and version.
      </p>
    </div>

    <footer class="mt-16 pt-8 border-t border-zinc-800 text-zinc-600 text-xs">
      <p>AUTHOR: XertroV | LICENSE: Unlicense (Public Domain)</p>
      <p class="mt-1 text-zinc-700 italic">No slime molds were harmed in the making of this script.</p>
    </footer>
  </div>
</body>
</html>`;
}

async function main() {
  console.log('🔧 Generating anything.sh artifacts...\n');

  // Ensure dist directory exists
  if (!fs.existsSync(DIST_DIR)) {
    fs.mkdirSync(DIST_DIR, { recursive: true });
  }

  // Generate scripts for each provider
  for (const provider of ALL_PROVIDERS) {
    const providerDir = path.join(DIST_DIR, provider);
    const fullDir = path.join(providerDir, 'full');
    const compactDir = path.join(providerDir, 'compact');

    // Create directories
    fs.mkdirSync(fullDir, { recursive: true });
    fs.mkdirSync(compactDir, { recursive: true });

    // Generate full script
    const fullScript = getScriptFull(provider);
    const fullPath = path.join(fullDir, 'anything.sh');
    fs.writeFileSync(fullPath, fullScript, 'utf-8');
    fs.chmodSync(fullPath, 0o755);
    console.log(`  ✓ ${provider}/full/anything.sh`);

    // Generate compact script
    const compactScript = getScriptCompact(provider);
    const compactPath = path.join(compactDir, 'anything.sh');
    fs.writeFileSync(compactPath, compactScript, 'utf-8');
    fs.chmodSync(compactPath, 0o755);
    console.log(`  ✓ ${provider}/compact/anything.sh`);
  }

  // Generate index page
  const indexPath = path.join(DIST_DIR, 'scripts', 'index.html');
  fs.mkdirSync(path.dirname(indexPath), { recursive: true });
  fs.writeFileSync(indexPath, generateIndexPage(), 'utf-8');
  console.log(`  ✓ scripts/index.html`);

  // Generate JSON manifest
  const manifest = {
    generated: new Date().toISOString(),
    providers: ALL_PROVIDERS.map(provider => ({
      id: provider,
      name: PROVIDERS[provider].name,
      urls: {
        full: `/${provider}/full/anything.sh`,
        compact: `/${provider}/compact/anything.sh`,
      }
    }))
  };
  const manifestPath = path.join(DIST_DIR, 'scripts', 'manifest.json');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf-8');
  console.log(`  ✓ scripts/manifest.json`);

  console.log('\n✅ All artifacts generated successfully!');
  console.log(`\n📦 Output directory: ${path.resolve(DIST_DIR)}`);
  console.log(`\n🌐 The scripts will be available at:`);
  console.log(`   https://yourusername.github.io/anything.sh/{provider}/{full|compact}/anything.sh`);
}

main().catch(err => {
  console.error('❌ Error generating artifacts:', err);
  process.exit(1);
});
