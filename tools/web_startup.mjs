#!/usr/bin/env node
// Time to the first Flutter frame and to the Today screen of the release Web
// build, in a throwaway Chrome profile on a loopback origin (see
// web_harness.mjs: no external request, no account, no real data).
//
// Usage: node tools/web_startup.mjs [--runs 5] [--network fast4g] [--dir build/web]
//
// Each cold run uses a new profile (empty SQLite); the warm run reloads the
// same profile (HTTP and code cache, database already created).
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

import { base, openBrowser, parseArgs, startServer } from './web_harness.mjs';

const args = parseArgs(process.argv.slice(2));
const runs = Number(args.runs ?? 5);
const network = args.network ?? 'none';
const site = await startServer(resolve(args.dir ?? 'build/web'));

const probe = `
  window.__todoStartup = {};
  addEventListener('flutter-first-frame', () => {
    window.__todoStartup.firstFrame = performance.now();
  });
  const timer = setInterval(() => {
    const placeholder = document.querySelector('flt-semantics-placeholder');
    if (placeholder && !window.__todoStartup.semantics) {
      window.__todoStartup.semantics = true;
      placeholder.click();
    }
    const today = [...document.querySelectorAll('flt-semantics, flt-semantics *')]
      .some((node) => (node.getAttribute('aria-label') ?? node.textContent)
        .trim().startsWith('Oggi'));
    if (today) {
      window.__todoStartup.today = performance.now();
      clearInterval(timer);
    }
  }, 10);
`;

async function measure(profile, reloads) {
  const page = await openBrowser({ profile, site, chrome: args.chrome, network });
  const { send } = page;
  await send('Page.addScriptToEvaluateOnNewDocument', { source: probe });
  const results = [];
  for (let i = 0; i <= reloads; i++) {
    await send('Page.navigate', { url: site.origin + base });
    const deadline = Date.now() + 60_000;
    let value;
    while (Date.now() < deadline) {
      const { result } = await send('Runtime.evaluate', {
        expression: `JSON.stringify({...window.__todoStartup,
          main: performance.getEntriesByType('resource')
            .filter((e) => e.name.includes('main.dart'))
            .map((e) => Math.round(e.responseEnd)),
          canvaskit: performance.getEntriesByType('resource')
            .filter((e) => e.name.includes('canvaskit.wasm'))
            .map((e) => Math.round(e.responseEnd)),
          parts: performance.getEntriesByType('resource')
            .filter((e) => e.name.includes('.part.js')).length})`,
        returnByValue: true,
      });
      value = result.value ? JSON.parse(result.value) : {};
      if (value.today) break;
      await new Promise((ok) => setTimeout(ok, 50));
    }
    results.push({
      run: i === 0 ? 'cold' : 'warm',
      first_frame_ms: Math.round(value.firstFrame ?? -1),
      today_ms: Math.round(value.today ?? -1),
      main_dart_js_end_ms: value.main?.[0] ?? -1,
      canvaskit_wasm_end_ms: value.canvaskit?.[0] ?? -1,
      deferred_parts_loaded: value.parts ?? 0,
    });
  }
  await page.close();
  return { results, blocked: [...page.blocked].sort() };
}

try {
  for (let run = 0; run < runs; run++) {
    const profile = mkdtempSync(join(tmpdir(), 'todo-web-startup-'));
    try {
      const { results, blocked } = await measure(profile, 1);
      for (const result of results) {
        console.log(JSON.stringify({ sample: run, network, ...result, blocked_hosts: blocked }));
      }
    } finally {
      rmSync(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
    }
  }
} finally {
  site.server.close();
}
