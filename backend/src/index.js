import { toCsv } from './format.js';
import { PAGE } from './page.js';

// Routes (all except /health need the token as "Authorization: Bearer <token>" or ?key=<token>)
//   GET  /health
//   POST /events          {events:[{id,start,end,first,l,r,dev}]} -> {ok:[ids accepted or already known]}
//   POST /events/delete   {id}  (only if not yet imported)
//   GET  /pending         -> {count, events:[...]}
//   POST /batch           -> {batch, count}   freezes all un-imported events into a batch (batch null if none)
//   GET  /batch/<id>.csv  -> My Baby import CSV
//   POST /ack             {batch} -> marks the batch's events imported
//   POST /unack           {batch} -> undo an ack (import failed after all)

const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });

function safeEq(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

function authed(req, url, env) {
  const h = req.headers.get('authorization') || '';
  const cookie = (req.headers.get('cookie') || '').match(/(?:^|;\s*)k=([^;]+)/);
  const tok = h.startsWith('Bearer ') ? h.slice(7) : (url.searchParams.get('key') || (cookie && cookie[1]));
  return safeEq(tok || '', env.API_TOKEN || '');
}

const now = () => Math.floor(Date.now() / 1000);
const isInt = (v) => Number.isInteger(v);

function validate(e) {
  if (!e || typeof e.id !== 'string' || e.id.length < 4 || e.id.length > 64) return 'bad id';
  if (!isInt(e.start) || !isInt(e.end) || e.end < e.start) return 'bad times';
  if (e.start < 1577836800 || e.start > now() + 86400) return 'start out of range';
  if (e.first !== 'L' && e.first !== 'R') return 'bad side';
  const l = e.l ?? 0, r = e.r ?? 0;
  if (!isInt(l) || !isInt(r) || l < 0 || r < 0 || l + r <= 0) return 'bad durations';
  if (l + r > 4 * 3600) return 'too long';
  return null;
}

async function postEvents(req, env) {
  const body = await req.json().catch(() => null);
  const list = Array.isArray(body?.events) ? body.events.slice(0, 50) : [];
  const ok = [], rejected = [];
  const t = now();
  const stmts = [];
  for (const e of list) {
    const err = validate(e);
    if (err) { rejected.push({ id: e?.id, err }); continue; }
    stmts.push(env.DB.prepare(
      `INSERT OR IGNORE INTO events (id,start_ts,end_ts,first_side,left_s,right_s,device,created_at)
       VALUES (?1,?2,?3,?4,?5,?6,?7,?8)`
    ).bind(e.id, e.start, e.end, e.first, e.l ?? 0, e.r ?? 0, String(e.dev || '').slice(0, 32), t));
    ok.push(e.id);
  }
  for (const e of list) {
    if (!validate(e)) {
      stmts.push(env.DB.prepare('DELETE FROM active WHERE device = ?1 AND start_ts = ?2')
        .bind(String(e.dev || '').slice(0, 32), e.start));
    }
  }
  if (stmts.length) await env.DB.batch(stmts);
  // Rejected events are also reported as "ok" to the watch so a malformed entry can't block the queue forever.
  return json({ ok: ok.concat(rejected.map((x) => x.id).filter(Boolean)), rejected });
}

// POST /active {dev, s:{start,first,side,l,r,run,pausedAt} | null}
async function postActive(req, env) {
  const b = await req.json().catch(() => null);
  const dev = String(b?.dev || '').slice(0, 32);
  if (!dev) return json({ error: 'no dev' }, 400);
  const s = b?.s;
  if (!s) {
    await env.DB.prepare('DELETE FROM active WHERE device = ?1').bind(dev).run();
    return json({ ok: true, active: false });
  }
  const ints = ['start', 'l', 'r', 'run', 'pausedAt'];
  if (ints.some((k) => !isInt(s[k])) || !['L', 'R'].includes(s.first) || !['L', 'R'].includes(s.side)) {
    return json({ error: 'bad session' }, 400);
  }
  await env.DB.prepare(
    `INSERT INTO active (device,start_ts,first_side,side,left_s,right_s,run_ts,paused_at,updated_at)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
     ON CONFLICT(device) DO UPDATE SET start_ts=?2, first_side=?3, side=?4, left_s=?5, right_s=?6,
       run_ts=?7, paused_at=?8, updated_at=?9`
  ).bind(dev, s.start, s.first, s.side, s.l, s.r, s.run, s.pausedAt, now()).run();
  return json({ ok: true, active: true });
}

async function activeFeeds(env) {
  const t = now();
  const { results } = await env.DB.prepare(
    'SELECT * FROM active WHERE updated_at > ?1 ORDER BY start_ts').bind(t - 12 * 3600).all();
  return results.map((a) => {
    const running = a.run_ts >= 0;
    const live = running ? Math.max(0, t - a.run_ts) : 0;
    const l = a.left_s + (running && a.side === 'L' ? live : 0);
    const r = a.right_s + (running && a.side === 'R' ? live : 0);
    return { device: a.device, start_ts: a.start_ts, first_side: a.first_side, side: a.side,
             running, left_s: l, right_s: r, paused_at: a.paused_at, updated_at: a.updated_at, now: t };
  });
}

async function pendingEvents(env) {
  const { results } = await env.DB.prepare(
    'SELECT * FROM events WHERE imported_at IS NULL AND deleted = 0 ORDER BY start_ts'
  ).all();
  return results;
}

async function makeBatch(env) {
  const evs = await pendingEvents(env);
  if (!evs.length) return json({ batch: null, count: 0 });
  const id = 'b' + now().toString(36) + Math.random().toString(36).slice(2, 6);
  await env.DB.prepare('INSERT INTO batches (id,created_at,event_ids) VALUES (?1,?2,?3)')
    .bind(id, now(), JSON.stringify(evs.map((e) => e.id))).run();
  return json({ batch: id, count: evs.length });
}

async function batchCsv(id, env) {
  const b = await env.DB.prepare('SELECT event_ids FROM batches WHERE id=?1').bind(id).first();
  if (!b) return json({ error: 'no such batch' }, 404);
  const { results } = await env.DB.prepare(
    `SELECT * FROM events WHERE deleted = 0 AND id IN (SELECT value FROM json_each(?1)) ORDER BY start_ts`
  ).bind(b.event_ids).all();
  const csv = toCsv(results, env.TZ || 'UTC', {
    ...(env.NARA_PROFILE_NAME ? { profileName: env.NARA_PROFILE_NAME } : {}),
    ...(env.NARA_CAREGIVER ? { caregiver: env.NARA_CAREGIVER } : {}),
    ...(env.NARA_SEX !== undefined ? { sex: env.NARA_SEX } : {}),
  });
  return new Response(csv, {
    headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': `attachment; filename="garmin-feeds-${id}.csv"`,
    },
  });
}

async function setAck(req, env, ack) {
  const body = await req.json().catch(() => null);
  const id = body?.batch;
  const b = id && (await env.DB.prepare('SELECT event_ids FROM batches WHERE id=?1').bind(id).first());
  if (!b) return json({ error: 'no such batch' }, 404);
  const t = ack ? now() : null;
  const r = await env.DB.prepare(
    `UPDATE events SET imported_at = ?1 WHERE id IN (SELECT value FROM json_each(?2))`
  ).bind(t, b.event_ids).run();
  await env.DB.prepare('UPDATE batches SET acked_at = ?1 WHERE id = ?2').bind(t, id).run();
  return json({ batch: id, updated: r.meta?.changes ?? null, acked: ack });
}

async function deleteEvent(req, env) {
  const body = await req.json().catch(() => null);
  const r = await env.DB.prepare('UPDATE events SET deleted = 1 WHERE id = ?1 AND imported_at IS NULL')
    .bind(String(body?.id || '')).run();
  return json({ deleted: (r.meta?.changes ?? 0) > 0 });
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const p = url.pathname;
    if (p === '/health') return json({ ok: true });
    if (p === '/' || p === '/app') {
      const key = url.searchParams.get('key');
      if (key && safeEq(key, env.API_TOKEN || '')) {
        // one-time setup link: remember the key in a cookie, then drop it from the address bar
        return new Response(null, { status: 302, headers: {
          location: '/app',
          'set-cookie': `k=${key}; Path=/; Max-Age=31536000; HttpOnly; Secure; SameSite=Lax`,
        } });
      }
      return new Response(PAGE, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
    }
    if (!authed(req, url, env)) return json({ error: 'unauthorized' }, 401);
    try {
      if (req.method === 'POST' && p === '/events') return await postEvents(req, env);
      if (req.method === 'POST' && p === '/events/delete') return await deleteEvent(req, env);
      if (req.method === 'POST' && p === '/active') return await postActive(req, env);
      if (req.method === 'GET' && p === '/pending') {
        const evs = await pendingEvents(env);
        return json({ count: evs.length, events: evs, active: await activeFeeds(env) });
      }
      if (req.method === 'POST' && p === '/batch') return await makeBatch(env);
      const m = p.match(/^\/batch\/([a-z0-9]+)\.csv$/);
      if (req.method === 'GET' && m) return await batchCsv(m[1], env);
      if (req.method === 'POST' && p === '/ack') return await setAck(req, env, true);
      if (req.method === 'POST' && p === '/unack') return await setAck(req, env, false);
    } catch (e) {
      return json({ error: String(e?.message || e) }, 500);
    }
    return json({ error: 'not found' }, 404);
  },
};
