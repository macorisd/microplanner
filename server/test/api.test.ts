import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { MongoMemoryReplSet } from 'mongodb-memory-server';
import { MongoClient } from 'mongodb';
import type { TokenPayload } from 'google-auth-library';
import { buildApp } from '../src/application.js';
import { readConfig } from '../src/config.js';
import { Repository } from '../src/repository.js';
import type { Workspace } from '../src/domain.js';
import { createRuntime } from '../src/runtime.js';

let mongo: MongoMemoryReplSet;
let client: MongoClient;
let repo: Repository;
let app: Awaited<ReturnType<typeof buildApp>>;
let currentNonce = '';
const config = readConfig({ MONGODB_URI: 'mongodb://127.0.0.1/test', MONGODB_DB: 'test' });
const fixture = (sub: string, audience = config.GOOGLE_WEB_CLIENT_ID): TokenPayload => ({
  sub, email: `${sub}@example.com`, name: sub, email_verified: true,
  aud: audience, iss: 'https://accounts.google.com', iat: Math.floor(Date.now() / 1000),
  exp: Math.floor(Date.now() / 1000) + 3600,
});
before(async () => {
  mongo = await MongoMemoryReplSet.create({ replSet: { count: 1, storageEngine: 'wiredTiger' } });
  client = new MongoClient(mongo.getUri()); await client.connect();
  repo = new Repository(client, 'microplanner_test'); await repo.initialize();
  app = await buildApp(repo, config, {
    verifyGoogle: async (token, audience) => {
      if (token === 'forged') throw new Error('bad signature');
      if (token === 'wrong-audience') return fixture('intruder', 'another-client');
      if (token === 'expired') return { ...fixture('expired'), exp: 1 };
      if (token === 'wrong-issuer') return { ...fixture('intruder'), iss: 'https://evil.example' };
      if (token === 'unverified') return { ...fixture('unverified'), email_verified: false };
      if (token === 'windows') return { ...fixture('desktop-user', audience), nonce: currentNonce } as TokenPayload;
      return fixture(token);
    },
    exchangeCode: async () => 'windows',
  });
});
after(async () => { await app?.close(); await client?.close(); await mongo?.stop(); });
async function login(sub = randomUUID()) {
  const response = await app.inject({ method: 'POST', url: '/auth/google', payload: { idToken: sub, platform: 'android' } });
  assert.equal(response.statusCode, 200, response.body);
  return response.json<{ token: string; user: { id: string } }>();
}
const headers = (token: string) => ({ authorization: `Bearer ${token}` });
async function state(token: string): Promise<Workspace> {
  const response = await app.inject({ url: '/workspace', headers: headers(token) });
  assert.equal(response.statusCode, 200, response.body); return response.json();
}
const save = (token: string, workspace: Workspace, operationId = randomUUID()) => {
  const { revision, ...data } = workspace;
  return app.inject({ method: 'PUT', url: '/workspace', headers: headers(token), payload: { revision, operationId, data } });
};

test('readiness pings MongoDB and anonymous access is rejected', async () => {
  assert.equal((await app.inject('/health/live')).statusCode, 200);
  assert.equal((await app.inject('/health/ready')).statusCode, 200);
  assert.equal((await app.inject('/workspace')).statusCode, 401);
  assert.equal((await app.inject({ method: 'PUT', url: '/workspace', payload: {} })).statusCode, 401);
});
test('rejects forged, wrong-audience, expired, wrong-issuer and unverified identities', async () => {
  for (const idToken of ['forged', 'wrong-audience', 'expired', 'wrong-issuer', 'unverified']) {
    const response = await app.inject({ method: 'POST', url: '/auth/google', payload: { idToken, platform: 'android' } });
    assert.equal(response.statusCode, 401);
  }
});
test('stable Google identity and revocable sessions survive API restart', async () => {
  const first = await login('stable-user'); const second = await login('stable-user');
  assert.equal(first.user.id, second.user.id);
  const restarted = await buildApp(new Repository(client, 'microplanner_test'), config);
  assert.equal((await restarted.inject({ url: '/auth/me', headers: headers(first.token) })).statusCode, 200);
  await app.inject({ method: 'POST', url: '/auth/logout', headers: headers(first.token) });
  assert.equal((await restarted.inject({ url: '/workspace', headers: headers(first.token) })).statusCode, 401);
  assert.equal((await restarted.inject({ url: '/workspace', headers: headers(second.token) })).statusCode, 200);
  await restarted.close();
});
test('all workspace reads and writes are isolated by the authenticated user', async () => {
  const a = await login(); const b = await login();
  const data = await state(a.token);
  data.boards[0]!.name = 'A private board';
  data.subjects.push({ id: 'math', name: 'Mathematics', boardId: 'default-board', color: 0xffaabbcc });
  data.tasks.push({ id: 'task', name: 'Private task', boardId: 'default-board', subjectId: 'math',
    description: 'Preserve me', deadline: '2026-10-25T22:55:00.000Z', createdAt: '2026-10-22T12:00:00.000Z',
    isCompleted: false, typeIndex: 2, priorityIndex: 2 });
  assert.equal((await save(a.token, data)).statusCode, 200);
  const saved = await state(a.token);
  assert.equal(saved.tasks[0]!.deadline, data.tasks[0]!.deadline);
  const other = await state(b.token);
  assert.equal(other.tasks.length, 0); assert.equal(other.subjects.length, 0);
  assert.equal(other.boards[0]!.name, 'Board 1');
  const withOwner = { ...data, ownerId: a.user.id };
  const invalid = await app.inject({ method: 'PUT', url: '/workspace', headers: headers(b.token),
    payload: { revision: 0, operationId: randomUUID(), data: withOwner } });
  assert.equal(invalid.statusCode, 400);
  other.tasks = data.tasks; // Foreign board/subject relations are not valid in B's space.
  assert.equal((await save(b.token, other)).statusCode, 400);
  assert.equal((await state(a.token)).tasks.length, 1);
  // B can use the same entity ID in its own account without changing A.
  other.tasks = []; other.boards[0]!.name = 'B board';
  assert.equal((await save(b.token, other)).statusCode, 200);
  assert.equal((await state(a.token)).boards[0]!.name, 'A private board');
});
test('retries are idempotent and stale or concurrent edits do not overwrite data', async () => {
  const { token } = await login(); const original = await state(token); const op = randomUUID();
  original.boards[0]!.name = 'First';
  assert.equal((await save(token, original, op)).statusCode, 200);
  assert.equal((await save(token, original, op)).statusCode, 200);
  assert.equal((await state(token)).revision, 1);
  assert.equal((await save(token, original)).statusCode, 409);
  const current = await state(token);
  const results = await Promise.all([save(token, current), save(token, current)]);
  assert.deepEqual(results.map(r => r.statusCode).sort(), [200, 409]);
  assert.equal((await state(token)).revision, 2);
});
test('a delayed retry stays idempotent after more than fifty later saves', async () => {
  const { token } = await login();
  const first = await state(token);
  const operation = randomUUID();
  first.boards[0]!.name = 'Initial operation';
  assert.equal((await save(token, first, operation)).statusCode, 200);
  for (let i = 0; i < 52; i++) {
    const current = await state(token);
    current.boards[0]!.name = `Later change ${i}`;
    assert.equal((await save(token, current)).statusCode, 200);
  }
  const beforeRetry = await state(token);
  const retry = await save(token, first, operation);
  assert.equal(retry.statusCode, 200, retry.body);
  assert.deepEqual(await state(token), beforeRetry);
  const changedPayload = structuredClone(first);
  changedPayload.boards[0]!.name = 'Different operation';
  const mismatch = await save(token, changedPayload, operation);
  assert.equal(mismatch.statusCode, 409);
  assert.equal(mismatch.json().code, 'operation_id_reused');
  assert.deepEqual(await state(token), beforeRetry);
});
test('invalid domain values and duplicate or cross-board references are rejected', async () => {
  const { token } = await login(); const original = await state(token);
  original.boards.push({ ...original.boards[0]! });
  assert.equal((await save(token, original)).statusCode, 400);
  const valid = await state(token);
  valid.subjects.push({ id: 'subject', name: 'Bad relation', boardId: 'someone-elses-board', color: 1 });
  assert.equal((await save(token, valid)).statusCode, 400);
  assert.equal((await state(token)).revision, 0);
});
test('import commits atomically, preserves existing cloud data and cannot migrate twice or to another account', async () => {
  const a = await login(); const b = await login(); const original = await state(a.token);
  const sourceId = randomUUID(); const { revision, ...data } = original;
  data.boards[0]!.name = 'Imported local board';
  data.subjects.push({ id: 'local-subject', name: 'Old subject', boardId: 'default-board', color: 7 });
  data.tasks.push({ id: 'local-task', name: 'Old task', boardId: 'default-board', subjectId: 'local-subject',
    description: null, deadline: '2026-11-01T12:00:00.000Z', createdAt: '2026-10-20T12:00:00.000Z',
    isCompleted: true, typeIndex: 0, priorityIndex: 1 });
  const payload = { revision, operationId: randomUUID(), sourceId, data };
  const call = (token: string) => app.inject({ method: 'POST', url: '/workspace/import', headers: headers(token), payload });
  assert.equal((await call(a.token)).statusCode, 200);
  const imported = await state(a.token);
  assert.equal(imported.boards.length, 2); assert.equal(imported.tasks.length, 1);
  assert.notEqual(imported.tasks[0]!.boardId, 'default-board');
  assert.equal(imported.tasks[0]!.subjectId, imported.subjects[0]!.id);
  assert.equal((await call(a.token)).statusCode, 200);
  assert.equal((await state(a.token)).tasks.length, 1);
  assert.equal((await call(b.token)).statusCode, 409);
  assert.equal((await state(b.token)).tasks.length, 0);
});
test('desktop OAuth binds redirect, PKCE, nonce and single-use challenge', async () => {
  const verifier = randomBytes(32).toString('base64url');
  const codeChallenge = createHash('sha256').update(verifier).digest('base64url');
  const payload = { redirectUri: 'http://127.0.0.1:54321/oauth/callback', codeChallenge, state: randomBytes(32).toString('base64url') };
  assert.equal((await app.inject({ method: 'POST', url: '/auth/windows/start',
    payload: { ...payload, redirectUri: 'https://evil.example/oauth/callback' } })).statusCode, 400);
  const start = await app.inject({ method: 'POST', url: '/auth/windows/start', payload });
  assert.equal(start.statusCode, 200);
  const details = start.json<{ challengeId: string; authorizationUrl: string }>();
  const authorizationUrl = new URL(details.authorizationUrl);
  assert.equal(authorizationUrl.searchParams.get('code_challenge'), codeChallenge);
  assert.equal(authorizationUrl.searchParams.get('code_challenge_method'), 'S256');
  currentNonce = authorizationUrl.searchParams.get('nonce')!;
  const complete = { challengeId: details.challengeId, code: 'code', verifier };
  assert.equal((await app.inject({ method: 'POST', url: '/auth/windows/complete',
    payload: { ...complete, verifier: randomBytes(32).toString('base64url') } })).statusCode, 401);
  const signedIn = await app.inject({ method: 'POST', url: '/auth/windows/complete', payload: complete });
  assert.equal(signedIn.statusCode, 200, signedIn.body);
  assert.equal((await app.inject({ method: 'POST', url: '/auth/windows/complete', payload: complete })).statusCode, 401);
});
test('server errors never echo credentials or raw database errors', async () => {
  const { token } = await login();
  const broken = await buildApp({
    authenticate: async () => { throw new Error('mongodb+srv://user:TOP_SECRET@host'); },
  } as unknown as Repository, config);
  const result = await broken.inject({ url: '/workspace', headers: headers(token) });
  assert.equal(result.statusCode, 503); assert.ok(!result.body.includes('TOP_SECRET'));
  await broken.close();
});
test('the production Google verifier rejects an unsigned token', async () => {
  const realVerifier = await buildApp(repo, config);
  const response = await realVerifier.inject({ method: 'POST', url: '/auth/google',
    payload: { idToken: 'not-a-signed-google-token', platform: 'android' } });
  assert.equal(response.statusCode, 401);
  await realVerifier.close();
});
test('missing desktop configuration fails before opening a Google consent flow', async () => {
  const unconfigured = await buildApp(repo, config);
  const response = await unconfigured.inject({ method: 'POST', url: '/auth/windows/start', payload: {
    redirectUri: 'http://127.0.0.1:54321/oauth/callback',
    codeChallenge: randomBytes(32).toString('base64url'), state: randomBytes(32).toString('base64url'),
  } });
  assert.equal(response.statusCode, 503);
  assert.equal(response.json().code, 'google_not_configured');
  await unconfigured.close();
});

test('Vercel rate limits span instances and ignore a spoofed external proxy header', async () => {
  const hosted = readConfig({ MONGODB_URI: mongo.getUri(), MONGODB_DB: 'microplanner_test', VERCEL: '1' });
  const first = await buildApp(repo, hosted);
  const second = await buildApp(new Repository(client, 'microplanner_test'), hosted);
  try {
    // Two instances must share the same twenty-request authentication allowance.
    const results = await Promise.all(Array.from({ length: 21 }, (_, i) =>
      (i % 2 ? first : second).inject({ method: 'POST', url: '/auth/google', payload: {}, headers: {
        'x-vercel-forwarded-for': '203.0.113.100', 'x-forwarded-for': `198.51.100.${i}`,
      } })));
    assert.equal(results.filter(r => r.statusCode === 429).length, 1);
    assert.equal(results.filter(r => r.statusCode === 400).length, 20);
    const independent = await first.inject({ method: 'POST', url: '/auth/google', payload: {},
      headers: { 'x-vercel-forwarded-for': '203.0.113.101' } });
    assert.equal(independent.statusCode, 400);
    assert.equal(independent.headers['cache-control'], 'no-store');
  } finally { await first.close(); await second.close(); }
});

test('oversized saves and merged imports roll back without losing prior cloud data', async () => {
  const { token } = await login();
  const original = await state(token);
  const task = { id: 'large', name: 'Task', boardId: 'default-board', subjectId: null,
    description: 'a'.repeat(19000), deadline: '2026-11-01T12:00:00.000Z',
    createdAt: '2026-10-20T12:00:00.000Z', isCompleted: false, typeIndex: 0, priorityIndex: 1 };
  original.tasks = Array.from({ length: 211 }, (_, i) => ({ ...task, id: `large-${i}` }));
  assert.equal((await save(token, original)).statusCode, 413);
  assert.equal((await state(token)).revision, 0);
  original.tasks = original.tasks.slice(0, 110);
  assert.equal((await save(token, original)).statusCode, 200);
  const { revision, ...data } = await state(token);
  const imported = await app.inject({ method: 'POST', url: '/workspace/import', headers: headers(token),
    payload: { revision, data, sourceId: randomUUID(), operationId: randomUUID() } });
  assert.equal(imported.statusCode, 413);
  assert.equal((await state(token)).tasks.length, 110);
  assert.equal((await state(token)).revision, revision);
});

test('runtime retries initialization failures and shares initialization across warm requests', async t => {
  let initializations = 0;
  const original = Repository.prototype.initialize;
  t.mock.method(Repository.prototype, 'initialize', async function (this: Repository) {
    if (++initializations === 1) throw new Error('Temporary initialization failure');
    return original.call(this);
  });
  const runtime = await createRuntime(readConfig({ MONGODB_URI: mongo.getUri(), MONGODB_DB: 'runtime_test' }));
  try {
    assert.equal((await runtime.inject('/health/live')).statusCode, 200);
    assert.equal((await runtime.inject('/health/ready')).statusCode, 503);
    const responses = await Promise.all(Array.from({ length: 8 }, () => runtime.inject('/health/ready')));
    assert.ok(responses.every(r => r.statusCode === 200));
    assert.equal(initializations, 2);
  } finally { await runtime.close(); t.mock.restoreAll(); }
});
