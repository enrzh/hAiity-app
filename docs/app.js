/* hAiity — GitHub-style habit tracker (web prototype).
   Storage: this browser's localStorage, and nothing else. This page makes no
   network requests at all — no account, no server, no sync. Moving data in or
   out is the export/import pair at the bottom.
   The iOS app is the one with the iCloud mirror. */
'use strict';

const LS_DATA = 'haiity-data-v1';

/* ---------- state ---------- */

let state = load();

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
function persist() {
  state.updatedAt = Date.now();
  localStorage.setItem(LS_DATA, JSON.stringify(state));
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

/* ---------- merge (shared by import; same union rule as the app) ---------- */

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

let statusTimer = null;
function flashStatus(msg, isErr) {
  const el = $('#flash');
  el.textContent = msg;
  el.classList.toggle('on', !isErr);
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => { el.textContent = ''; el.classList.remove('on'); }, 2500);
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
// re-render at midnight so "today" moves
(function midnightTick() {
  const now = new Date();
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
  setTimeout(() => { render(); midnightTick(); }, next - now);
})();
