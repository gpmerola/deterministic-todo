// Shared by web_startup.mjs and web_persistence.mjs: the release Web build on
// a loopback origin and Chrome driven over the DevTools protocol, in a
// throwaway profile. Only 127.0.0.1 is reachable: CanvasKit requests to
// gstatic are redirected to the copy in the build, every other request
// (Supabase, fonts, GitHub) is refused, so no account or real data is touched.
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';
import { gzipSync } from 'node:zlib';

export const base = '/deterministic-todo/';
export const chromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.bin': 'application/octet-stream',
  '.symbols': 'text/plain',
};

export function parseArgs(argv) {
  return Object.fromEntries(
    argv.reduce((pairs, value, i, all) =>
      value.startsWith('--') ? [...pairs, [value.slice(2), all[i + 1]]] : pairs, []),
  );
}

/// Serves [dir] like GitHub Pages: gzip, ETag and a short max-age, so a
/// warm reload revalidates instead of downloading again. A fixed [port]
/// keeps the same origin, and so the same storage, across browser restarts.
export async function startServer(dir, port = 0) {
  function local(pathname) {
    const relative = decodeURIComponent(pathname).slice(base.length) || 'index.html';
    const file = join(dir, relative);
    if (!file.startsWith(dir) || !existsSync(file) || statSync(file).isDirectory()) {
      return null;
    }
    return file;
  }
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
  await new Promise((done) => server.listen(port, '127.0.0.1', done));
  return { server, dir, origin: `http://127.0.0.1:${server.address().port}` };
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
    this.socket.onclose = () => {
      for (const { reject } of this.pending.values()) reject(new Error('closed'));
      this.pending.clear();
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

/// Chrome on [profile] with one page attached; `send` talks to the page.
/// `network: 'fast4g'` applies the DevTools "Fast 4G" profile.
/// [site] may also be `{ origin }` alone, a published site: then CanvasKit
/// is fetched from gstatic and only that origin and gstatic are reachable.
export async function openBrowser({ profile, site, chrome = chromePath, network = 'none' }) {
  const browser = spawn(chrome, [
    '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--window-size=1280,800', 'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  const exited = new Promise((ok) => browser.on('exit', ok));
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
    try {
      if (url.origin === site.origin) {
        await send('Fetch.continueRequest', { requestId });
        return;
      }
      if (!site.dir && url.hostname === 'www.gstatic.com' &&
          url.pathname.startsWith('/flutter-canvaskit/')) {
        await send('Fetch.continueRequest', { requestId });
        return;
      }
      if (url.hostname === 'www.gstatic.com' &&
          url.pathname.startsWith('/flutter-canvaskit/')) {
        const rest = url.pathname.split('/').slice(3).join('/');
        if (existsSync(join(site.dir, 'canvaskit', rest))) {
          await send('Fetch.fulfillRequest', {
            requestId, responseCode: 302,
            responseHeaders: [{ name: 'location', value: `${site.origin}/__canvaskit/${rest}` },
              { name: 'access-control-allow-origin', value: '*' }],
          });
          return;
        }
      }
      blocked.add(url.hostname);
      await send('Fetch.failRequest', { requestId, errorReason: 'BlockedByClient' });
    } catch {
      // The browser is closing.
    }
  });
  await send('Fetch.enable', { patterns: [{ urlPattern: '*' }] });
  await send('Network.enable');
  if (network === 'fast4g') {
    await send('Network.emulateNetworkConditions', {
      offline: false, latency: 150, downloadThroughput: 9_000_000 / 8,
      uploadThroughput: 1_500_000 / 8,
    });
  }
  await send('Page.enable');
  return {
    send,
    blocked,
    async evaluate(expression) {
      const { result, exceptionDetails } = await send('Runtime.evaluate', {
        expression, returnByValue: true, awaitPromise: true,
      });
      if (exceptionDetails) throw new Error(exceptionDetails.text);
      return result.value;
    },
    /// Like quitting Chrome from its menu: every window, the whole process.
    async close() {
      await cdp.send('Browser.close').catch(() => {});
      await exited;
    },
    /// Like a crash or a forced quit: no shutdown work at all.
    async kill() {
      browser.kill('SIGKILL');
      await exited;
    },
  };
}
