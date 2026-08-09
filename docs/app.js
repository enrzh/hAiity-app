/* hAiity — GitHub-style habit tracker.
   Storage: localStorage always; optionally mirrored to the user's own GitHub
   repo (haiity-data/data.json) via the Contents API. No server of ours. */
'use strict';

const LS_DATA = 'haiity-data-v1';
const LS_SYNC = 'haiity-sync-v1'; // {token, login, repo}
const API = 'https://api.github.com';
const DATA_REPO = 'haiity-data';
const DATA_PATH = 'data.json';

/* ---------- state ---------- */

let state = load();
let sync = loadSync();
let remoteSha = null;      // sha of data.json at last read/write
let pushTimer = null;
let pushing = false;
let pushQueued = false;

function load() {
  try {
    const raw = localStorage.getItem(LS_DATA);
    if (raw) {
      const d = JSON.parse(raw);
      if (d && Array.isArray(d.habits)) return d;
    }
  } catch (e) { /* corrupted -> start fresh, keep raw around */ }
  return { version: 1, updatedAt: 0, habits: [] };
}
function loadSync() {
  try { return JSON.parse(localStorage.getItem(LS_SYNC)) || null; }
  catch (e) { return null; }
}
function persist() {
  state.updatedAt = Date.now();
  localStorage.setItem(LS_DATA, JSON.stringify(state));
  schedulePush();
  render();
}

/* ---------- dates (LOCAL days — a habit day is the user's day) ---------- */

function dkey(d) {
  const y = d.getFullYear(), m = d.getMonth() + 1, day = d.getDate();
  return `${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}
function today() { return dkey(new Date()); }
function addDays(d, n) { const c = new Date(d); c.setDate(c.getDate() + n); return c; }

/* ---------- habit logic ---------- */

function newHabit(name, emoji) {
  return { id: crypto.randomUUID(), name, emoji: emoji || '', createdAt: today(), log: {} };
}
function isDone(h, key) { return !!h.log[key]; }
function toggle(h, key) {
  if (h.log[key]) delete h.log[key]; else h.log[key] = 1;
  persist();
}
function streak(h) {
  // current streak: consecutive days ending today (or yesterday if today unchecked)
  let d = new Date();
  if (!isDone(h, dkey(d))) d = addDays(d, -1);
  let n = 0;
  while (isDone(h, dkey(d))) { n++; d = addDays(d, -1); }
  return n;
}
function bestStreak(h) {
  const keys = Object.keys(h.log).sort();
  let best = 0, run = 0, prev = null;
  for (const k of keys) {
    if (prev !== null && dkey(addDays(parseKey(prev), 1)) === k) run++;
    else run = 1;
    prev = k;
    if (run > best) best = run;
  }
  return best;
}
function parseKey(k) {
  const [y, m, d] = k.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/* ---------- rendering ---------- */

const $ = (s) => document.querySelector(s);
const habitsEl = $('#habits');
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

function render() {
  habitsEl.textContent = '';
  $('#empty').hidden = state.habits.length > 0;
  for (const h of state.habits) habitsEl.appendChild(renderHabit(h));
  renderSyncStatus();
}

function renderHabit(h) {
  const card = document.createElement('section');
  card.className = 'habit';

  const head = document.createElement('div');
  head.className = 'habit-head';

  const em = document.createElement('span');
  em.className = 'habit-emoji';
  em.textContent = h.emoji;

  const name = document.createElement('h2');
  name.className = 'habit-name';
  name.textContent = h.name;

  const st = document.createElement('span');
  st.className = 'streak';
  const cur = streak(h);
  st.innerHTML = '';
  const b = document.createElement('b'); b.textContent = String(cur);
  st.append('🔥 ', b, ` · best ${bestStreak(h)}`);

  const check = document.createElement('button');
  const tk = today();
  const done = isDone(h, tk);
  check.className = 'check' + (done ? ' done' : '');
  check.type = 'button';
  check.textContent = done ? '✓ Done' : 'Today';
  check.setAttribute('aria-pressed', String(done));
  check.addEventListener('click', () => toggle(h, tk));

  const menu = document.createElement('button');
  menu.className = 'habit-menu';
  menu.type = 'button';
  menu.textContent = '⋯';
  menu.setAttribute('aria-label', `Edit ${h.name}`);
  menu.addEventListener('click', () => editHabit(h));

  head.append(em, name, st, check, menu);
  card.append(head, renderGrid(h));
  return card;
}

function renderGrid(h) {
  const wrap = document.createElement('div');
  wrap.className = 'gridwrap';

  // 53 columns of weeks ending with the current week; rows Sun..Sat
  const end = new Date();
  const endDow = end.getDay(); // 0=Sun
  const lastSat = addDays(end, 6 - endDow);
  const first = addDays(lastSat, -(53 * 7 - 1));

  const months = document.createElement('div');
  months.className = 'months';
  const grid = document.createElement('div');
  grid.className = 'grid';
  grid.setAttribute('role', 'img');
  grid.setAttribute('aria-label', `${h.name}: last year of activity`);

  let lastMonth = -1;
  for (let w = 0; w < 53; w++) {
    const weekStart = addDays(first, w * 7);
    const m = weekStart.getMonth();
    const span = document.createElement('span');
    // cell + gap width; label a column when a new month starts
    span.style.width = 'calc(var(--cell) + var(--gap))';
    if (m !== lastMonth && weekStart.getDate() <= 7) { span.textContent = MONTHS[m]; span.style.overflow = 'visible'; }
    lastMonth = m;
    months.appendChild(span);

    for (let r = 0; r < 7; r++) {
      const d = addDays(weekStart, r);
      const k = dkey(d);
      const cell = document.createElement('i');
      cell.className = 'cell';
      const isFuture = d > end;
      if (isFuture) cell.classList.add('future');
      else {
        const v = h.log[k] ? 1 : 0;
        if (v) cell.dataset.l = intensity(h, k);
        cell.title = `${k}${v ? ' ✓' : ''}`;
        if (k === today()) cell.classList.add('today');
        cell.addEventListener('click', () => toggle(h, k));
        cell.style.cursor = 'pointer';
      }
      grid.appendChild(cell);
    }
  }
  wrap.append(months, grid);
  // scroll to the end (today) after attach
  requestAnimationFrame(() => { wrap.scrollLeft = wrap.scrollWidth; });
  return wrap;
}

function intensity(h, key) {
  // simple boolean habit: shade by recency-agnostic streak context — a cell in
  // a longer consecutive run shows darker->brighter (1..4)
  let run = 1;
  let d = addDays(parseKey(key), -1);
  while (isDone(h, dkey(d)) && run < 8) { run++; d = addDays(d, -1); }
  return String(Math.min(4, Math.max(1, Math.ceil(run / 2))));
}

function renderSyncStatus() {
  const el = $('#sync-status');
  if (sync) { el.textContent = `✓ ${sync.login}`; el.classList.add('on'); $('#foot-where').textContent = `in your GitHub (${sync.login}/${DATA_REPO})`; }
  else { el.textContent = ''; el.classList.remove('on'); $('#foot-where').textContent = 'in this browser'; }
}

/* ---------- habit dialog ---------- */

let editing = null;
const dlgHabit = $('#dlg-habit');

function editHabit(h) {
  editing = h || null;
  $('#dlg-habit-title').textContent = h ? 'Edit habit' : 'New habit';
  $('#habit-name').value = h ? h.name : '';
  $('#habit-emoji').value = h ? h.emoji : '';
  let del = $('#btn-habit-delete');
  if (h) {
    if (!del) {
      del = document.createElement('button');
      del.id = 'btn-habit-delete';
      del.className = 'danger';
      del.type = 'submit';
      del.value = 'delete';
      del.textContent = 'Delete';
      $('#form-habit menu').prepend(del);
    }
  } else if (del) del.remove();
  dlgHabit.showModal();
}

dlgHabit.addEventListener('close', () => {
  const v = dlgHabit.returnValue;
  if (v === 'ok') {
    const name = $('#habit-name').value.trim();
    const emoji = $('#habit-emoji').value.trim();
    if (!name) return;
    if (editing) { editing.name = name; editing.emoji = emoji; }
    else state.habits.push(newHabit(name, emoji));
    persist();
  } else if (v === 'delete' && editing) {
    if (confirm(`Delete “${editing.name}” and its history?`)) {
      state.habits = state.habits.filter(x => x.id !== editing.id);
      persist();
    }
  }
  editing = null;
});

$('#btn-add').addEventListener('click', () => editHabit(null));
$('#btn-add-empty').addEventListener('click', () => editHabit(null));

/* ---------- GitHub sync ---------- */

const dlgSync = $('#dlg-sync');
$('#btn-sync').addEventListener('click', () => {
  $('#sync-connected').hidden = !sync;
  $('#sync-setup').hidden = !!sync;
  if (sync) { $('#sync-user').textContent = sync.login; $('#sync-repo').textContent = `${sync.login}/${DATA_REPO}`; }
  $('#sync-error').hidden = true;
  dlgSync.showModal();
});

dlgSync.addEventListener('close', async () => {
  const v = dlgSync.returnValue;
  if (v === 'disconnect') {
    sync = null; localStorage.removeItem(LS_SYNC); remoteSha = null;
    renderSyncStatus();
  } else if (v === 'connect') {
    const token = $('#sync-token').value.trim();
    if (token) await connect(token);
  }
});

async function gh(path, opts = {}, token = sync && sync.token) {
  const res = await fetch(API + path, {
    ...opts,
    headers: {
      'Accept': 'application/vnd.github+json',
      'Authorization': `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      ...(opts.headers || {}),
    },
  });
  return res;
}

async function connect(token) {
  const err = (m) => { $('#sync-error').textContent = m; $('#sync-error').hidden = false; dlgSync.showModal(); };
  try {
    const who = await gh('/user', {}, token);
    if (!who.ok) return err(`Token rejected (HTTP ${who.status}). Check the token and its permissions.`);
    const { login } = await who.json();

    // ensure repo exists
    let repo = await gh(`/repos/${login}/${DATA_REPO}`, {}, token);
    if (repo.status === 404) {
      const created = await gh('/user/repos', {
        method: 'POST',
        body: JSON.stringify({ name: DATA_REPO, private: true, auto_init: true, description: 'hAiity habit data — created by haiity (static app, your data stays yours)' }),
      }, token);
      if (!created.ok) return err(`Could not create ${DATA_REPO} (HTTP ${created.status}). The token needs repository Administration (or create the repo manually).`);
    } else if (!repo.ok) {
      return err(`Cannot access ${login}/${DATA_REPO} (HTTP ${repo.status}).`);
    }

    sync = { token, login };
    localStorage.setItem(LS_SYNC, JSON.stringify(sync));

    // merge remote if it exists
    await pullMerge();
    renderSyncStatus();
    render();
    schedulePush(0);
  } catch (e) {
    err(`Network error: ${e.message}`);
  }
}

function b64encode(str) { return btoa(String.fromCharCode(...new TextEncoder().encode(str))); }
function b64decode(b64) { return new TextDecoder().decode(Uint8Array.from(atob(b64.replace(/\n/g, '')), c => c.charCodeAt(0))); }

async function pullMerge() {
  if (!sync) return;
  const res = await gh(`/repos/${sync.login}/${DATA_REPO}/contents/${DATA_PATH}`);
  if (res.status === 404) { remoteSha = null; return; }
  if (!res.ok) return;
  const file = await res.json();
  remoteSha = file.sha;
  try {
    const remote = JSON.parse(b64decode(file.content));
    if (remote && Array.isArray(remote.habits)) mergeRemote(remote);
  } catch (e) { /* unreadable remote: local wins on next push */ }
}

function mergeRemote(remote) {
  // union merge: habits by id; logs by union of day-keys (a check-in anywhere counts)
  const byId = new Map(state.habits.map(h => [h.id, h]));
  for (const rh of remote.habits) {
    const lh = byId.get(rh.id);
    if (!lh) { state.habits.push(rh); continue; }
    for (const k of Object.keys(rh.log || {})) lh.log[k] = 1;
    if ((remote.updatedAt || 0) > (state.updatedAt || 0)) { lh.name = rh.name; lh.emoji = rh.emoji; }
  }
  localStorage.setItem(LS_DATA, JSON.stringify(state));
}

function schedulePush(delay = 1500) {
  if (!sync) return;
  clearTimeout(pushTimer);
  pushTimer = setTimeout(push, delay);
}

async function push() {
  if (!sync) return;
  if (pushing) { pushQueued = true; return; }
  pushing = true;
  try {
    const body = {
      message: `habits: ${today()}`,
      content: b64encode(JSON.stringify(state, null, 2)),
    };
    if (remoteSha) body.sha = remoteSha;
    let res = await gh(`/repos/${sync.login}/${DATA_REPO}/contents/${DATA_PATH}`, {
      method: 'PUT', body: JSON.stringify(body),
    });
    if (res.status === 409 || res.status === 422) {
      // stale sha — pull, merge, retry once
      await pullMerge();
      body.content = b64encode(JSON.stringify(state, null, 2));
      if (remoteSha) body.sha = remoteSha; else delete body.sha;
      res = await gh(`/repos/${sync.login}/${DATA_REPO}/contents/${DATA_PATH}`, {
        method: 'PUT', body: JSON.stringify(body),
      });
    }
    if (res.ok) {
      const out = await res.json();
      remoteSha = out.content.sha;
      flashStatus('✓ synced');
    } else {
      flashStatus(`sync failed (${res.status})`, true);
    }
  } catch (e) {
    flashStatus('offline — will retry', true);
    schedulePush(30000);
  } finally {
    pushing = false;
    if (pushQueued) { pushQueued = false; schedulePush(500); }
  }
}

let statusTimer = null;
function flashStatus(msg, isErr) {
  const el = $('#sync-status');
  const base = sync ? `✓ ${sync.login}` : '';
  el.textContent = msg;
  el.classList.toggle('on', !isErr);
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => { el.textContent = base; el.classList.toggle('on', !!sync); }, 2500);
}

/* ---------- import / export ---------- */

$('#btn-export').addEventListener('click', () => {
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `haiity-${today()}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
});
$('#btn-import').addEventListener('click', () => $('#import-file').click());
$('#import-file').addEventListener('change', async (e) => {
  const f = e.target.files[0];
  if (!f) return;
  try {
    const d = JSON.parse(await f.text());
    if (!d || !Array.isArray(d.habits)) throw new Error('not a haiity export');
    mergeRemote(d); // same union semantics
    persist();
    flashStatus('✓ imported');
  } catch (err) { alert(`Import failed: ${err.message}`); }
  e.target.value = '';
});

/* ---------- empty-state decoration ---------- */

(() => {
  const eg = document.querySelector('.empty-grid');
  for (let i = 0; i < 48; i++) {
    const c = document.createElement('i');
    if (Math.random() < 0.45) {
      const l = 1 + Math.floor(Math.random() * 4);
      c.style.background = `var(--l${l})`;
    }
    eg.appendChild(c);
  }
})();

/* ---------- boot ---------- */

render();
if (sync) pullMerge().then(() => { render(); });
// re-render at midnight so "today" moves
(function midnightTick() {
  const now = new Date();
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
  setTimeout(() => { render(); midnightTick(); }, next - now);
})();
