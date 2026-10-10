// Status push for Developer Tools for Homey.
//
// Runs on a schedule (GitHub Actions). For every Personal Access Token in
// HOMEY_PATS it reads the build status of all apps (own apps and organization
// apps) from the Athom Apps API, compares it with the previous run and sends a
// push through OneSignal for every change: draft, Test, in review, approved,
// rejected, Live.
//
// Env:
//   HOMEY_PATS          one or more Personal Access Tokens, separated by newlines or commas (secret)
//   ONESIGNAL_API_KEY   OneSignal REST API key (secret)
//   ONESIGNAL_APP_ID    OneSignal App ID
//   STATE_DIR           where the previous status is kept (default .notify-state)
//   DRY_RUN=1           log instead of sending
//   TEST_PUSH=1         send one test push per account (same targeting as real pushes)

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const ATHOM = 'https://api.athom.com';
const APPS = 'https://apps-api.athom.com/api/v1';
const STATE_DIR = process.env.STATE_DIR || '.notify-state';
const STATE_FILE = join(STATE_DIR, 'state.json');
const DRY_RUN = process.env.DRY_RUN === '1';
const TEST_PUSH = process.env.TEST_PUSH === '1' || process.env.TEST_PUSH === 'true';

const pats = (process.env.HOMEY_PATS || '').split(/[\n,]/).map((s) => s.trim()).filter(Boolean);
const oneSignalKey = (process.env.ONESIGNAL_API_KEY || '').trim();
const oneSignalApp = (process.env.ONESIGNAL_APP_ID || '').trim();

if (!pats.length || (!oneSignalKey && !DRY_RUN) || !oneSignalApp) {
  console.log('Not configured: set the HOMEY_PATS and ONESIGNAL_API_KEY secrets (and ONESIGNAL_APP_ID). Nothing to do.');
  process.exit(0);
}

async function http(url, { method = 'GET', token, body } = {}) {
  const res = await fetch(url, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      Accept: 'application/json',
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} → HTTP ${res.status}: ${text.slice(0, 200)}`);
  try { return JSON.parse(text); } catch { return text; }
}

const localized = (v) => (typeof v === 'string' ? v : v && (v.en || v.nl || Object.values(v)[0])) || '';
const tagSafe = (s) => String(s).replace(/[^A-Za-z0-9]/g, '_');

async function delegationToken(pat) {
  const r = await http(`${ATHOM}/delegation/token?audience=apps`, { method: 'POST', token: pat, body: {} });
  const t = typeof r === 'string' ? r.replace(/["\s]/g, '') : r.token || r.access_token;
  if (!t) throw new Error('No delegation token');
  return t;
}

async function allApps(token) {
  const out = new Map();
  const add = (a) => { if (a && a.id && !out.has(a.id)) out.set(a.id, a); };
  (await http(`${APPS}/app/me`, { token })).forEach?.(add);
  const orgs = await http(`${APPS}/org`, { token }).catch(() => []);
  for (const org of Array.isArray(orgs) ? orgs : []) {
    const full = await http(`${APPS}/org/${encodeURIComponent(org.id)}`, { token }).catch(() => org);
    for (const ref of full.apps || []) {
      if (ref && typeof ref === 'object' && (ref.liveBuild || ref.testBuild || ref.installs !== undefined)) { add(ref); continue; }
      const id = typeof ref === 'string' ? ref : ref && ref.id;
      if (!id || out.has(id)) continue;
      add(await http(`${APPS}/app/${encodeURIComponent(id)}`, { token }).catch(() => null));
    }
  }
  return [...out.values()];
}

const TEST_KINDS = {
  draft: 'draft',
  test: 'test',
  in_review: 'inReview',
  reviewed_approved: 'approved',
  approved: 'approved',
  reviewed_rejected: 'rejected',
  rejected: 'rejected',
};

const TEXT = {
  draft: { en: (v) => `${v}was uploaded as a draft.`, nl: (v) => `${v}is geüpload als draft.` },
  test: { en: (v) => `${v}is now in Test.`, nl: (v) => `${v}staat nu in Test.` },
  inReview: { en: (v) => `${v}was submitted for certification.`, nl: (v) => `${v}is ingediend voor certificering.` },
  approved: { en: (v) => `${v}was approved by Athom.`, nl: (v) => `${v}is goedgekeurd door Athom.` },
  rejected: { en: (v) => `${v}was rejected. Check the reviewer's comments.`, nl: (v) => `${v}is afgekeurd. Bekijk de opmerkingen van de reviewer.` },
  live: { en: (v) => `${v}is now live.`, nl: (v) => `${v}staat nu live.` },
};

async function send(body, label) {
  if (DRY_RUN) { console.log('[dry run]', JSON.stringify(body)); return; }
  const res = await fetch('https://api.onesignal.com/notifications?c=push', {
    method: 'POST',
    headers: { Authorization: `Key ${oneSignalKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let hint = '';
  try {
    const r = JSON.parse(text);
    if (r.errors) hint = ` → ${JSON.stringify(r.errors)}`;
    if (!r.id || /not subscribed/i.test(text)) hint += ' → no device matched: open the app, turn on "Direct via push" and check the tags in OneSignal (Audience → Subscriptions).';
  } catch {}
  console.log(`${label}: HTTP ${res.status} ${text.slice(0, 200)}${hint}`);
}

async function testPush({ userId, accountName }) {
  await send({
    app_id: oneSignalApp,
    target_channel: 'push',
    filters: [{ field: 'tag', key: `u_${tagSafe(userId)}`, relation: '=', value: '1' }],
    headings: { en: 'HomeyDev', nl: 'HomeyDev' },
    contents: {
      en: `Test push for ${accountName}. Status pushes are working.`,
      nl: `Testmelding voor ${accountName}. Statusmeldingen werken.`,
    },
  }, `test push ${accountName} (tag u_${tagSafe(userId)})`);
}

async function push({ userId, accountName, multiple, app, kind, version }) {
  const v = version ? `v${version} ` : '';
  const name = localized(app.name) || localized(app.liveBuild?.name) || app.id;
  const body = {
    app_id: oneSignalApp,
    target_channel: 'push',
    filters: [
      { field: 'tag', key: `u_${tagSafe(userId)}`, relation: '=', value: '1' },
      { field: 'tag', key: `k_${kind}`, relation: '=', value: '1' },
    ],
    headings: { en: name, nl: name },
    contents: { en: TEXT[kind].en(v), nl: TEXT[kind].nl(v) },
    ...(multiple && accountName ? { subtitle: { en: accountName, nl: accountName } } : {}),
    thread_id: app.id,
    collapse_id: `${app.id}.${kind}.${version}`.slice(0, 64),
    data: { appId: app.id, kind },
  };
  await send(body, `push ${kind} ${app.id} ${version}`);
}

let state = {};
try { state = JSON.parse(await readFile(STATE_FILE, 'utf8')); } catch { console.log('No previous state: this run only records the current status.'); }

const next = {};
for (const pat of pats) {
  try {
    const me = await http(`${ATHOM}/user/me`, { token: pat });
    const userId = me._id || me.id;
    const accountName = [me.firstname, me.lastname].filter(Boolean).join(' ') || me.email || '';
    if (TEST_PUSH) await testPush({ userId, accountName });
    const apps = await allApps(await delegationToken(pat));
    const before = state[userId];
    const now = {};
    let changes = 0;
    for (const app of apps) {
      const seen = {
        live: app.liveBuild?.id ?? null,
        test: app.testBuild?.id ?? null,
        state: app.testBuild?.state ?? '',
        liveVersion: app.liveVersion ?? app.liveBuild?.version ?? '',
        testVersion: app.testVersion ?? app.testBuild?.version ?? '',
      };
      now[app.id] = seen;
      const prev = before && before[app.id];
      if (!prev) continue;
      if (seen.live != null && seen.live !== prev.live) {
        await push({ userId, accountName, multiple: pats.length > 1, app, kind: 'live', version: seen.liveVersion });
        changes++;
      }
      const testChanged = seen.test !== prev.test || seen.state !== prev.state;
      const kind = TEST_KINDS[seen.state];
      if (testChanged && seen.test != null && kind) {
        await push({ userId, accountName, multiple: pats.length > 1, app, kind, version: seen.testVersion });
        changes++;
      }
    }
    next[userId] = now;
    const summary = apps.map((a) => `${a.id}=${a.testBuild?.state || '-'}/${a.liveBuild?.version || a.liveVersion || '-'}`).join(', ');
    console.log(`${accountName}: ${apps.length} apps checked, ${before ? `${changes} change(s)` : 'first run (status recorded)'}`);
    console.log(`  status: ${summary}`);
  } catch (e) {
    console.error(`Account check failed: ${e.message}`);
  }
}

// Keep accounts we couldn't read this time, so a hiccup doesn't cause a flood later.
for (const [id, apps] of Object.entries(state)) if (!next[id]) next[id] = apps;

await mkdir(STATE_DIR, { recursive: true });
await writeFile(STATE_FILE, JSON.stringify(next));
