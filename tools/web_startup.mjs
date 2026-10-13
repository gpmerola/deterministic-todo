#!/usr/bin/env node
// Time to the first Flutter frame and to the Today screen of the release Web
// build, in a throwaway Chrome profile on a loopback origin.
//
// Usage: node tools/web_startup.mjs [--runs 5] [--network fast4g] [--dir build/web]
//
// Only 127.0.0.1 is reachable: CanvasKit requests to gstatic are redirected
// to the copy in the build, served by the same throttled loopback server;
// every other request (Supabase, fonts, GitHub) is refused, so no account
// or real data is touched.
// Each cold run uses a new profile (empty SQLite); the warm run reloads the
// same profile (HTTP and code cache, database already created).
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdtempSync, readFileSync, rmSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname, resolve } from 'node:path';
import { gzipSync } from 'node:zlib';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((pairs, value, i, all) =>
    value.startsWith('--') ? [...pairs, [value.slice(2), all[i + 1]]] : pairs, []),
);
const runs = Number(args.runs ?? 5);
const dir = resolve(args.dir ?? 'build/web');
const network = args.network ?? 'none';
const chrome = args.chrome ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const base = '/deterministic-todo/';
const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.bin': 'application/octet-stream',
  '.symbols': 'text/plain',
};

function local(pathname) {
  const relative = decodeURIComponent(pathname).slice(base.length) || 'index.html';
  const file = join(dir, relative);
  if (!file.startsWith(dir) || !existsSync(file) || statSync(file).isDirectory()) {
    return null;
  }
  return file;
}

// Like GitHub Pages: gzip, ETag and a short max-age, so a warm reload
// revalidates instead of downloading again.
const bodies = new Map();
function body(file) {
  if (!bodies.has(file)) {
    const raw = readFileSync(file);
    bodies.set(file, {
      raw, gzip: gzipSync(raw),
      etag: '"' + createHash('sha256').update(raw).digest('hex').slice(0, 16) + '"',
    });
  }
  return bodies.get(file);
}

const server = createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  const file = url.pathname.startsWith(base) ? local(url.pathname)
    : url.pathname.startsWith('/__canvaskit/')
      ? local(base + 'canvaskit/' + url.pathname.slice('/__canvaskit/'.length))
      : null;
  if (file == null) {
    response.writeHead(404).end();
    return;
  }
  const { raw, gzip, etag } = body(file);
  const headers = {
    'content-type': types[extname(file)] ?? 'application/octet-stream',
    'cache-control': 'max-age=600', etag,
    'access-control-allow-origin': '*',
  };
  if (request.headers['if-none-match'] === etag) {
    response.writeHead(304, headers).end();
    return;
  }
  const zipped = /\bgzip\b/.test(request.headers['accept-encoding'] ?? '');
  if (zipped) headers['content-encoding'] = 'gzip';
  response.writeHead(200, headers);
  response.end(zipped ? gzip : raw);
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${server.address().port}`;

// gstatic paths of the engine assets, mapped to the copies in the build.
function mapped(url) {
  const parsed = new URL(url);
  if (parsed.hostname === 'www.gstatic.com' &&
      parsed.pathname.startsWith('/flutter-canvaskit/')) {
    return parsed.pathname.split('/').slice(3).join('/');
  }
  return null;
}

class Cdp {
  constructor(url) {
    this.socket = new WebSocket(url);
    this.id = 0;
    this.pending = new Map();
    this.handlers = [];
    this.socket.onmessage = ({ data }) => {
      const message = JSON.parse(data);
      if (message.id && this.pending.has(message.id)) {
        const { resolve: ok, reject } = this.pending.get(message.id);
        this.pending.delete(message.id);
        message.error ? reject(new Error(message.error.message)) : ok(message.result);
      } else if (message.method) {
        for (const handler of this.handlers) handler(message);
      }
    };
  }
  ready() {
    return new Promise((ok) => this.socket.addEventListener('open', ok, { once: true }));
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    this.socket.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((ok, reject) => this.pending.set(id, { resolve: ok, reject }));
  }
}

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
  const browser = spawn(chrome, [
    '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--window-size=1280,800', 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  const endpoint = await new Promise((ok, reject) => {
    let text = '';
    browser.stderr.on('data', (chunk) => {
      text += chunk;
      const match = text.match(/DevTools listening on (ws:\/\/\S+)/);
      if (match) ok(match[1]);
    });
    browser.on('exit', () => reject(new Error('Chrome exited')));
  });
  const cdp = new Cdp(endpoint);
  await cdp.ready();
  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
  const send = (method, params) => cdp.send(method, params, sessionId);
  const blocked = new Set();
  cdp.handlers.push(async (message) => {
    if (message.method !== 'Fetch.requestPaused' || message.sessionId !== sessionId) return;
    const { requestId, request } = message.params;
    const url = new URL(request.url);
    if (url.origin === origin) {
      await send('Fetch.continueRequest', { requestId });
      return;
    }
    const rest = mapped(request.url);
    if (rest && existsSync(join(dir, 'canvaskit', rest))) {
      await send('Fetch.fulfillRequest', {
        requestId, responseCode: 302,
        responseHeaders: [{ name: 'location', value: `${origin}/__canvaskit/${rest}` },
          { name: 'access-control-allow-origin', value: '*' }],
      });
      return;
    }
    blocked.add(url.hostname);
    await send('Fetch.failRequest', { requestId, errorReason: 'BlockedByClient' });
  });
  await send('Fetch.enable', { patterns: [{ urlPattern: '*' }] });
  await send('Network.enable');
  if (network === 'fast4g') {
    // Same as Chrome DevTools "Fast 4G".
    await send('Network.emulateNetworkConditions', {
      offline: false, latency: 150, downloadThroughput: 9_000_000 / 8,
      uploadThroughput: 1_500_000 / 8,
    });
  }
  await send('Page.enable');
  await send('Page.addScriptToEvaluateOnNewDocument', { source: probe });
  const results = [];
  for (let i = 0; i <= reloads; i++) {
    await send('Page.navigate', { url: origin + base });
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
  browser.kill();
  await new Promise((ok) => browser.on('exit', ok));
  return { results, blocked: [...blocked].sort() };
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
  server.close();
}
