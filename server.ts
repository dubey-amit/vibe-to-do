#!/usr/bin/env bun
/**
 * Vibe-To-Do — tiny local server.
 *
 *   bun server.ts                # default port 7788
 *   PORT=9000 bun server.ts      # override
 *
 * Stores data under ./data/{tasks,settings,completions}.json
 * Atomic writes via tempfile + rename. Rotating snapshot backups in ./data/backups.
 *
 * Endpoints:
 *   GET  /                  → serves index.html
 *   GET  /api/health        → {ok:true, version, port}
 *   GET  /api/state         → {tasks, settings, completions, revs}
 *   PUT  /api/tasks         → body: array   (rev-checked, see revs below)
 *   PUT  /api/settings      → body: object
 *   PUT  /api/completions   → body: object
 */

import { resolve, dirname } from 'node:path';
import {
  mkdir, readFile, writeFile, rename, readdir, unlink,
} from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA = resolve(__dirname, 'data');
const BACKUPS = resolve(DATA, 'backups');
const PORT = Number(process.env.PORT ?? 7788);
const KEEP_BACKUPS = 50;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,PUT,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

await mkdir(DATA, { recursive: true });
await mkdir(BACKUPS, { recursive: true });

type Json = unknown;

async function readJson<T extends Json>(name: string, fallback: T): Promise<T> {
  try {
    const txt = await readFile(resolve(DATA, name), 'utf8');
    return JSON.parse(txt) as T;
  } catch {
    return fallback;
  }
}

async function writeJsonAtomic(name: string, value: Json): Promise<void> {
  const target = resolve(DATA, name);
  const tmp = `${target}.tmp`;
  await writeFile(tmp, JSON.stringify(value, null, 2), 'utf8');
  await rename(tmp, target);
}

async function snapshot(name: string, current: Json): Promise<void> {
  const base = name.replace(/\.json$/, '');
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const path = resolve(BACKUPS, `${base}-${ts}.json`);
  await writeFile(path, JSON.stringify(current, null, 2), 'utf8');

  // Trim to most recent KEEP_BACKUPS per base name
  const files = (await readdir(BACKUPS))
    .filter((f) => f.startsWith(`${base}-`))
    .sort(); // ISO timestamps sort lexically by time
  while (files.length > KEEP_BACKUPS) {
    const old = files.shift()!;
    await unlink(resolve(BACKUPS, old)).catch(() => {});
  }
}

const ALLOWED = new Set(['tasks', 'settings', 'completions']);

// Per-file revision counters for optimistic concurrency. Clients send back the
// rev they last saw (x-base-rev header or ?baseRev=); a mismatch means another
// tab/window wrote first → 409 with the current value so the client can adopt
// it instead of silently clobbering. Counters reset on restart; clients pick
// up fresh values from GET /api/state at bootstrap.
const revs: Record<string, number> = { tasks: 1, settings: 1, completions: 1 };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...cors },
  });
}

const server = Bun.serve({
  port: PORT,
  hostname: '127.0.0.1',
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    const method = req.method;

    if (method === 'OPTIONS') return new Response(null, { headers: cors });

    if (method === 'GET' && (path === '/' || path === '/index.html')) {
      try {
        const html = await readFile(resolve(__dirname, 'index.html'), 'utf8');
        return new Response(html, {
          headers: { 'Content-Type': 'text/html; charset=utf-8', ...cors },
        });
      } catch (e) {
        return new Response(`index.html missing: ${(e as Error).message}`, { status: 500 });
      }
    }

    if (method === 'GET' && path === '/api/health') {
      return json({ ok: true, version: 1, port: PORT });
    }

    if (method === 'GET' && path === '/api/state') {
      const [tasks, settings, completions] = await Promise.all([
        readJson('tasks.json', [] as unknown),
        readJson('settings.json', {} as unknown),
        readJson('completions.json', {} as unknown),
      ]);
      return json({ tasks, settings, completions, revs });
    }

    if ((method === 'PUT' || method === 'POST') && path.startsWith('/api/')) {
      const name = path.slice('/api/'.length);
      if (!ALLOWED.has(name)) return new Response('Not found', { status: 404, headers: cors });

      let body: unknown;
      try {
        body = await req.json();
      } catch {
        return json({ error: 'Invalid JSON body' }, 400);
      }

      // Shape sanity
      if (name === 'tasks' && !Array.isArray(body)) {
        return json({ error: 'tasks must be an array' }, 400);
      }
      if ((name === 'settings' || name === 'completions') && (typeof body !== 'object' || body === null || Array.isArray(body))) {
        return json({ error: `${name} must be an object` }, 400);
      }

      const file = `${name}.json`;
      const current = await readJson(file, null);

      // Optimistic concurrency: reject stale writers so two tabs can't
      // silently clobber each other. Absent baseRev (older clients) → accept.
      const baseRevRaw = req.headers.get('x-base-rev') ?? url.searchParams.get('baseRev');
      if (baseRevRaw !== null && Number(baseRevRaw) !== revs[name]) {
        return json({ error: 'conflict', rev: revs[name], value: current }, 409);
      }

      if (current !== null) {
        await snapshot(file, current).catch((e) => console.error('snapshot fail:', e));
      }
      await writeJsonAtomic(file, body);
      revs[name] += 1;
      return json({ ok: true, savedAt: Date.now(), rev: revs[name] });
    }

    return new Response('Not found', { status: 404, headers: cors });
  },
});

console.log(`Vibe-To-Do → http://localhost:${server.port}`);
console.log(`Data dir   → ${DATA}`);
console.log(`Backups    → ${BACKUPS} (last ${KEEP_BACKUPS} per file)`);
