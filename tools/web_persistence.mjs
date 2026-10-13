#!/usr/bin/env node
// Whether a change made in the release Web build survives quitting Chrome
// completely, in a throwaway profile on a loopback origin (see
// web_harness.mjs: no external request, no account, no real data). Only
// synthetic tasks ("Collaudo persistenza …") are created.
//
// Usage: node tools/web_persistence.mjs [--rounds 3] [--only edit,complete] [--dir build/web]
//
// Each round and change (create, edit the title, complete): prepare the
// tasks and let them settle, make the change through the UI, quit Chrome as
// soon as the change is on screen (Browser.close, like Quit from the menu,
// or SIGKILL, like a crash), start a new Chrome on the same profile and
// check the change and a control task. Results are JSON lines; exit status
// 1 if any graceful quit lost a change.
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

import { base, openBrowser, parseArgs, startServer } from './web_harness.mjs';

const args = parseArgs(process.argv.slice(2));
const rounds = Number(args.rounds ?? 3);
const only = args.only?.split(',');
const extraWait = Number(args.wait ?? 0);
const site = await startServer(resolve(args.dir ?? 'build/web'));
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

const helpers = `
  window.__todo = {
    nodes: () => [...document.querySelectorAll('flt-semantics')],
    text: (node) => (node.getAttribute('aria-label') ?? '') + node.textContent,
    find(role, prefix) {
      return this.nodes().find((n) => (!role || n.getAttribute('role') === role) &&
        n.textContent.trim().startsWith(prefix));
    },
    exact(role, label) {
      return this.nodes().find((n) => (!role || n.getAttribute('role') === role) &&
        ((n.getAttribute('aria-label') ?? '') === label ||
         (n.childElementCount === 0 && n.textContent.trim() === label)));
    },
    // A task tile in the list: its button is labelled with the title.
    tile(title) {
      return !!this.exact('button', title);
    },
    tap(role, label) {
      const node = this.exact(role, label);
      if (!node) return false;
      node.click();
      return true;
    },
    click(role, prefix) {
      const node = this.find(role, prefix);
      if (!node) return false;
      node.click();
      return true;
    },
  };
`;

async function until(page, expression, timeout = 30_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    try {
      if (await page.evaluate(expression)) return true;
    } catch {
      // Page still loading.
    }
    await sleep(50);
  }
  return false;
}

async function open(profile) {
  const page = await openBrowser({ profile, site, chrome: args.chrome });
  await page.send('Page.addScriptToEvaluateOnNewDocument', { source: helpers });
  await page.send('Page.navigate', { url: site.origin + base });
  // Turn on the semantics tree, then wait for the Today screen.
  const ready = await until(page, `(() => {
    const placeholder = document.querySelector('flt-semantics-placeholder');
    if (placeholder) placeholder.click();
    return !!window.__todo?.find('button', 'Nuova attività');
  })()`);
  if (!ready) throw new Error('Today screen not shown');
  return page;
}

async function create(page, title) {
  await page.evaluate(`window.__todo.click('button', 'Nuova attività')`);
  if (!await until(page, `!!document.querySelector('input[aria-label="Cosa devi fare?"]')`)) {
    throw new Error('Quick add not shown');
  }
  await page.evaluate(`document.querySelector('input[aria-label="Cosa devi fare?"]').focus()`);
  await page.send('Input.insertText', { text: title });
  await sleep(200);
  await page.evaluate(`window.__todo.click('button', 'Aggiungi attività')`);
  // The sheet closes and the task is listed in Today (Inbox).
  if (!await until(page, `!document.querySelector('input[aria-label="Cosa devi fare?"]') &&
      window.__todo.tile(${JSON.stringify(title)})`)) {
    throw new Error('Created task not shown');
  }
}

async function edit(page, title, suffix) {
  await page.evaluate(`window.__todo.tap('button', ${JSON.stringify(title)})`);
  if (!await until(page, `!!window.__todo.exact('button', 'Salva')`)) {
    throw new Error('Editor not shown');
  }
  // The title field is the first text field of the editor; typing appends.
  await page.evaluate(`document.querySelector('textarea').focus()`);
  await sleep(200);
  await page.send('Input.insertText', { text: suffix });
  await sleep(200);
  await page.evaluate(`window.__todo.tap('button', 'Salva')`);
  if (!await until(page, `!window.__todo.exact('button', 'Salva') &&
      window.__todo.tile(${JSON.stringify(title + suffix)})`)) {
    throw new Error('Edited task not shown');
  }
}

async function complete(page, title) {
  await page.evaluate(`window.__todo.tap('checkbox', ${JSON.stringify('Completa ' + title)})`);
  if (!await until(page, `!window.__todo.tile(${JSON.stringify(title)})`)) {
    throw new Error('Completed task still shown');
  }
}

// Each change: tasks prepared before it, the change, then what must hold
// after reopening ([present], [absent]).
const changes = {
  create: {
    prepare: [],
    async run(page, t) { await create(page, t('nuova')); },
    present: (t) => [t('controllo'), t('nuova')],
    absent: () => [],
  },
  edit: {
    prepare: ['da modificare'],
    async run(page, t) { await edit(page, t('da modificare'), ' modificata'); },
    present: (t) => [t('controllo'), t('da modificare') + ' modificata'],
    absent: (t) => [t('da modificare')],
  },
  complete: {
    prepare: ['da completare'],
    async run(page, t) { await complete(page, t('da completare')); },
    present: (t) => [t('controllo')],
    absent: (t) => [t('da completare')],
  },
};

const results = [];
try {
  for (let round = 0; round < rounds; round++) {
    for (const [name, change] of Object.entries(changes)) {
      if (only && !only.includes(name)) continue;
      for (const quit of ['close', 'kill']) {
        const profile = mkdtempSync(join(tmpdir(), 'todo-web-persistence-'));
        const t = (what) => `Collaudo persistenza ${round} ${quit} ${what}`;
        try {
          // Prepared tasks are written, then Chrome is quit normally after
          // a pause: they are the baseline, not what is being tested.
          let page = await open(profile);
          for (const what of ['controllo', ...change.prepare]) await create(page, t(what));
          await sleep(2000);
          await page.close();
          page = await open(profile);
          for (const what of ['controllo', ...change.prepare]) {
            if (!await until(page, `window.__todo.tile(${JSON.stringify(t(what))})`, 10_000)) {
              throw new Error('Prepared task missing');
            }
          }
          const started = Date.now();
          await change.run(page, t);
          const shownMs = Date.now() - started;
          if (extraWait) await sleep(extraWait);
          await page[quit]();
          page = await open(profile);
          const present = [];
          for (const title of change.present(t)) {
            present.push(await until(page, `window.__todo.tile(${JSON.stringify(title)})`, 10_000));
          }
          const absent = [];
          for (const title of change.absent(t)) {
            absent.push(!await page.evaluate(`window.__todo.tile(${JSON.stringify(title)})`));
          }
          await page.close();
          const kept = [...present, ...absent].every(Boolean);
          const result = { round, change: name, quit, change_shown_ms: shownMs, kept, present, absent };
          results.push(result);
          console.log(JSON.stringify(result));
        } catch (error) {
          const result = { round, change: name, quit, error: error.message, kept: false };
          results.push(result);
          console.log(JSON.stringify(result));
        } finally {
          rmSync(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
        }
      }
    }
  }
} finally {
  site.server.close();
}
process.exitCode = results.some((r) => r.quit === 'close' && !r.kept) ? 1 : 0;
