// Phone page: list new watch feeds, download the My Baby CSV, mark the batch imported.
export const PAGE = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Garmin Feeds">
<meta name="theme-color" content="#16171b">
<meta name="color-scheme" content="dark">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Garmin Feeds</title>
<style>
  :root { color-scheme:dark; --ink:#f1ecea; --muted:#9d99a3; --accent:#ef8a80; --bg:#16171b; --card:#212329; --ok:#6fcb93; --line:#2e3037; --btn2:#2c2e35; }
  * { box-sizing:border-box; }
  body { margin:0; font:17px/1.4 -apple-system, system-ui, sans-serif; color:var(--ink); background:var(--bg);
         padding:max(20px, env(safe-area-inset-top)) 18px 40px; }
  h1 { font-size:26px; margin:6px 0 2px; }
  .sub { color:var(--muted); margin:0 0 18px; font-size:15px; }
  .card { background:var(--card); border-radius:16px; padding:14px 16px; border:1px solid var(--line); margin-bottom:14px; }
  .row { display:flex; justify-content:space-between; padding:9px 0; border-bottom:1px solid var(--line); font-variant-numeric:tabular-nums; }
  .row:last-child { border-bottom:0; }
  .row { align-items:center; }
  .t { font-weight:600; font-variant-numeric:tabular-nums; }
  .d { color:var(--muted); font-size:14px; }
  .big { font-size:20px; font-weight:700; color:var(--ink) !important; }
  .live-card:empty { display:none; }
  .live-card { border-color:var(--accent); }
  .hint { color:var(--muted); font-size:13px; margin:8px 0 0; }
  .row .right { color:var(--muted); display:flex; align-items:center; gap:10px; }
  .del { width:auto; margin:0; padding:6px 10px; font:600 14px -apple-system, system-ui; background:transparent; color:#ef6b6b; border:1px solid #4a2f33; border-radius:10px; }
  button { width:100%; border:0; border-radius:14px; padding:16px; font:600 17px -apple-system, system-ui; margin:6px 0; }
  .primary { background:var(--accent); color:#1b1214; }
  .secondary { background:var(--btn2); color:var(--ink); }
  button:disabled { opacity:.45; }
  .step { font-size:14px; color:var(--muted); margin:4px 2px 12px; }
  .msg { text-align:center; color:var(--ok); font-weight:600; min-height:1.4em; }
  .empty { text-align:center; color:var(--muted); padding:18px 0; }
  a { color:var(--muted); font-size:14px; }
  .overlay { position:fixed; inset:0; background:rgba(0,0,0,.6); display:flex; align-items:flex-end; justify-content:center; padding:16px; padding-bottom:max(16px, env(safe-area-inset-bottom)); z-index:10; }
  .overlay[hidden] { display:none; }
  .sheet { background:var(--card); border:1px solid var(--line); border-radius:18px; padding:18px 16px 10px; width:100%; max-width:420px; }
  .mt { font-weight:700; font-size:19px; margin-bottom:6px; }
  .mb { color:var(--muted); margin-bottom:12px; white-space:pre-line; }
  .danger { background:#e5534b; color:#fff; }
  .head { display:flex; align-items:center; justify-content:space-between; }
  .icon { width:auto; margin:0; padding:8px 14px; font-size:20px; background:var(--btn2); color:var(--ink); border-radius:12px; }
  #ptr { height:0; overflow:hidden; text-align:center; color:var(--muted); font-size:14px; line-height:40px; transition:height .15s; }
  #ptr.show { height:40px; }
</style></head><body>
<div id="ptr">Pull to refresh</div>
<div class="head"><h1>Garmin Feeds</h1><button id="rf" class="icon" aria-label="Refresh">↻</button></div>
<p class="sub" id="sub">Loading…</p>
<div class="card live-card" id="live"></div>
<div class="card" id="list"></div>
<button class="primary" id="dl" disabled>1 · Download for My Baby</button>
<p class="step">Then in My Baby: Settings → Import data → pick the downloaded file.</p>
<button class="secondary" id="ack" disabled>2 · I imported it, mark as done</button>
<p class="msg" id="msg"></p>
<div id="modal" class="overlay" hidden><div class="sheet" role="dialog" aria-modal="true"><div class="mt" id="mTitle"></div><div class="mb" id="mBody"></div><button class="danger" id="mOk">Delete</button><button class="secondary" id="mNo">Cancel</button></div></div>
<p style="text-align:center"><a href="#" id="undo" hidden>Undo last “mark as done”</a></p>
<script>
const $ = (id) => document.getElementById(id);
const pad = (n) => String(n).padStart(2, '0');
const dur = (s) => { const m = Math.floor(s/60), x = s%60; return m ? m + 'm' + (x ? ' ' + x + 's' : '') : x + 's'; };
const when = (t) => { const d = new Date(t*1000); return d.toLocaleDateString(undefined,{weekday:'short', day:'numeric', month:'short'}) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()); };
const store = { get:(k)=>{ try { return localStorage.getItem(k); } catch(e) { return null; } },
                set:(k,v)=>{ try { localStorage.setItem(k,v); } catch(e) {} } };
let batch = store.get('batch');

async function api(path, opts) {
  const r = await fetch(path, Object.assign({ credentials:'same-origin' }, opts || {}));
  if (r.status === 401) { $('sub').textContent = 'Not signed in. Open the setup link again.'; throw new Error('401'); }
  return r;
}

const hm = (t) => { const d = new Date(t*1000); return pad(d.getHours()) + ':' + pad(d.getMinutes()); };
const day = (t) => new Date(t*1000).toLocaleDateString(undefined, { weekday:'short', day:'numeric', month:'short' });
const sideTxt = (first, l, r) => l && r ? (first === 'L' ? 'Left → Right' : 'Right → Left') : (l ? 'Left' : 'Right');
const esc = (x) => encodeURIComponent(x);
let live = [], liveAt = 0;

function renderLive() {
  const el = $('live'); if (!live.length) { el.innerHTML = ''; return; }
  const drift = Math.floor(Date.now()/1000) - liveAt;
  el.innerHTML = live.map(a => {
    const extra = a.running ? drift : 0;
    const l = a.left_s + (a.running && a.side === 'L' ? extra : 0);
    const r = a.right_s + (a.running && a.side === 'R' ? extra : 0);
    const state = a.running ? 'Feeding now · ' + (a.side === 'L' ? 'Left' : 'Right') : 'Paused · ' + (a.side === 'L' ? 'Left' : 'Right');
    const split = (l && r) ? ' · L ' + dur(l) + ' / R ' + dur(r) : '';
    return '<div class="row live"><div><div class="t">' + hm(a.start_ts) + ' – now</div><div class="d">' + state + split + '</div></div>'
      + '<span class="right big">' + dur(l + r) + '</span></div>';
  }).join('') + '<p class="hint">In progress on the watch. Stop it there (or use “Stop – ended earlier”).</p>';
}

async function load() {
  const d = await (await api('/pending')).json();
  live = d.active || []; liveAt = live.length ? live[0].now : 0;
  renderLive();
  const parts = [];
  if (live.length) parts.push('feeding now');
  parts.push(d.count ? d.count + ' new feed' + (d.count > 1 ? 's' : '') + ' to import' : 'nothing new to import');
  $('sub').textContent = parts.join(' · ');
  $('list').innerHTML = d.count ? d.events.map(e => {
    const total = e.left_s + e.right_s;
    const label = day(e.start_ts) + ' ' + hm(e.start_ts) + '–' + hm(e.end_ts) + ' · ' + sideTxt(e.first_side, e.left_s, e.right_s) + ' · ' + dur(total);
    const split = (e.left_s && e.right_s) ? ' · L ' + dur(e.left_s) + ' / R ' + dur(e.right_s) : '';
    return '<div class="row"><div><div class="t">' + hm(e.start_ts) + ' – ' + hm(e.end_ts) + '</div>'
      + '<div class="d">' + day(e.start_ts) + ' · ' + sideTxt(e.first_side, e.left_s, e.right_s) + split + '</div></div>'
      + '<span class="right">' + dur(total)
      + '<button class="del" data-id="' + esc(e.id) + '" data-label="' + esc(label) + '">Delete</button></span></div>';
  }).join('') : '<div class="empty">No finished feeds waiting 🎉</div>';
  $('dl').disabled = !d.count;
  $('ack').disabled = !batch;
  $('undo').hidden = !store.get('lastAcked');
}
setInterval(renderLive, 1000);
setInterval(() => load().catch(() => {}), 30000);

$('dl').onclick = async () => {
  const b = await (await api('/batch', { method:'POST' })).json();
  if (!b.batch) return load();
  batch = b.batch; store.set('batch', batch);
  const blob = await (await api('/batch/' + batch + '.csv')).blob();
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([blob], { type:'text/csv' }));
  a.download = 'garmin-feeds-' + new Date().toISOString().slice(0,16).replace(/[-:T]/g,'') + '.csv';
  document.body.appendChild(a); a.click(); a.remove();
  $('ack').disabled = false;
  $('msg').textContent = b.count + ' feed' + (b.count > 1 ? 's' : '') + ' downloaded. Import it in My Baby.';
};

$('ack').onclick = async () => {
  if (!batch) return;
  await api('/ack', { method:'POST', body: JSON.stringify({ batch }) });
  store.set('lastAcked', batch); batch = null; store.set('batch', '');
  $('msg').textContent = 'Done. These feeds won’t be downloaded again.';
  load();
};

function ask(title, body, okLabel) {
  return new Promise((resolve) => {
    $('mTitle').textContent = title; $('mBody').textContent = body; $('mOk').textContent = okLabel;
    const m = $('modal'); m.hidden = false;
    const done = (v) => { m.hidden = true; $('mOk').onclick = $('mNo').onclick = m.onclick = null; resolve(v); };
    $('mOk').onclick = () => done(true);
    $('mNo').onclick = () => done(false);
    m.onclick = (e) => { if (e.target === m) done(false); };   // tap outside = cancel
  });
}

$('list').onclick = async (ev) => {
  const b = ev.target.closest('.del'); if (!b) return;
  const label = decodeURIComponent(b.dataset.label);
  if (!(await ask('Are you sure you want to delete this feed?', label + ' · It will not be sent to My Baby. This cannot be undone.', 'Delete feed'))) return;
  b.disabled = true;
  const r = await (await api('/events/delete', { method:'POST', body: JSON.stringify({ id: decodeURIComponent(b.dataset.id) }) })).json();
  $('msg').textContent = r.deleted ? 'Feed deleted.' : 'Could not delete (already imported?)';
  if (r.deleted && batch) { batch = null; store.set('batch', ''); $('msg').textContent += ' Download again before importing.'; }
  load();
};

$('undo').onclick = async (ev) => {
  ev.preventDefault();
  const b = store.get('lastAcked'); if (!b) return;
  await api('/unack', { method:'POST', body: JSON.stringify({ batch: b }) });
  store.set('lastAcked', ''); $('msg').textContent = 'Undone. Those feeds are back in the list.';
  load();
};

async function refresh() {
  const p = $('ptr'); p.textContent = 'Refreshing…'; p.classList.add('show'); p.style.height = '';
  try { await load(); } catch (e) {}
  setTimeout(() => { p.classList.remove('show'); p.textContent = 'Pull to refresh'; }, 350);
}
$('rf').onclick = refresh;

// Home Screen apps have no native pull-to-refresh: do it ourselves.
let y0 = null, pulled = 0;
window.addEventListener('touchstart', (e) => { y0 = window.scrollY <= 0 ? e.touches[0].clientY : null; pulled = 0; }, { passive: true });
window.addEventListener('touchmove', (e) => {
  if (y0 === null) return;
  pulled = e.touches[0].clientY - y0;
  if (pulled > 10) {
    const p = $('ptr'); p.classList.add('show');
    p.style.height = Math.min(pulled / 2, 60) + 'px';
    p.textContent = pulled > 110 ? 'Release to refresh' : 'Pull to refresh';
  }
}, { passive: true });
window.addEventListener('touchend', () => {
  if (y0 === null) return;
  y0 = null;
  if (pulled > 110) { refresh(); } else { const p = $('ptr'); p.classList.remove('show'); p.style.height = ''; }
  pulled = 0;
});

// iOS pauses Home Screen apps in the background: reload whenever it comes back.
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load().catch(() => {}); });
window.addEventListener('pageshow', (e) => { if (e.persisted) load().catch(() => {}); });

load().catch(() => {});
</script>
</body></html>`;
