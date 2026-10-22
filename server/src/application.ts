import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { OAuth2Client, type TokenPayload } from 'google-auth-library';
import { z } from 'zod';
import { isIP } from 'node:net';
import type { Config } from './config.js';
import { ApiError, importSchema, saveSchema } from './domain.js';
import type { Repository } from './repository.js';

declare module 'fastify' {
  interface FastifyRequest { ownerId: string | null }
}
export type VerifyGoogle = (idToken: string, audience: string) => Promise<TokenPayload>;

export async function buildApp(repo: Repository, config: Config, options: {
  verifyGoogle?: VerifyGoogle;
  exchangeCode?: (code: string, verifier: string, redirectUri: string) => Promise<string>;
  prepare?: () => Promise<void>;
  factory?: typeof Fastify;
} = {}) {
  // No request-body or credential logging. Errors below return only fixed messages.
  const app = (options.factory ?? Fastify)({ bodyLimit: 4 * 1024 * 1024, logger: false });
  app.decorateRequest('ownerId', null);
  if (!config.VERCEL) await app.register(rateLimit, { max: 300, timeWindow: '1 minute' });
  app.addHook('onRequest', async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    reply.header('X-Content-Type-Options', 'nosniff');
    if (request.url.split('?')[0] === '/health/live') return;
    await options.prepare?.();
    if (config.VERCEL) {
      // Vercel supplies this header; never trust forwarded headers on local servers.
      const forwarded = request.headers['x-vercel-forwarded-for'];
      const ip = typeof forwarded === 'string' && isIP(forwarded.trim())
        ? forwarded.trim() : request.ip;
      const auth = ['/auth/google', '/auth/windows/start', '/auth/windows/complete'].includes(request.url.split('?')[0]!);
      if (!await repo.allowRequest(`requests:${ip}`, 300) ||
          (auth && !await repo.allowRequest(`auth:${ip}`, 20))) {
        reply.header('Retry-After', '60');
        throw new ApiError(429, 'rate_limit', 'Too many requests. Try again shortly.');
      }
    }
  });
  app.addHook('onSend', async (_request, reply, payload) => {
    if (typeof payload === 'string' && Buffer.byteLength(payload) > 4_400_000) {
      reply.code(413);
      return JSON.stringify({ code: 'too_large', message: 'The workspace is too large.' });
    }
    return payload;
  });
  const google = new OAuth2Client();
  const verify = options.verifyGoogle ?? (async (idToken, audience) => {
    const ticket = await google.verifyIdToken({ idToken, audience });
    const payload = ticket.getPayload();
    if (!payload) throw new Error('Missing identity');
    return payload;
  });
  async function identity(idToken: string, audience: string, nonce?: string) {
    let payload: TokenPayload;
    try {
      payload = await verify(idToken, audience);
      if (!payload.sub || !payload.email || !payload.email_verified ||
          !['accounts.google.com', 'https://accounts.google.com'].includes(payload.iss) ||
          payload.aud !== audience || payload.exp * 1000 <= Date.now() ||
          (nonce !== undefined && (payload as TokenPayload & { nonce?: string }).nonce !== nonce)) {
        throw new Error('Invalid identity');
      }
    } catch (error) {
      if (error instanceof ApiError) throw error;
      throw new ApiError(401, 'invalid_google_token', 'Google sign-in could not be verified. Please try again.');
    }
    return repo.login({ sub: payload.sub, email: payload.email!, name: payload.name, picture: payload.picture });
  }
  const authenticate = async (request: import('fastify').FastifyRequest) => {
    const auth = request.headers.authorization;
    const session = auth?.startsWith('Bearer ') ? await repo.authenticate(auth.slice(7)) : null;
    if (!session) throw new ApiError(401, 'unauthorized', 'Your session expired. Please sign in again.');
    request.ownerId = session.user.id;
  };
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof z.ZodError) return reply.code(400).send({ code: 'invalid_request', message: 'Invalid request or data relationships.' });
    if (error instanceof ApiError) return reply.code(error.statusCode).send({ code: error.code, message: error.message });
    const status = (error as { statusCode?: number }).statusCode;
    if (status === 429) return reply.code(429).send({ code: 'rate_limit', message: 'Too many requests. Try again shortly.' });
    if (status === 413) return reply.code(413).send({ code: 'too_large', message: 'The workspace is too large.' });
    if (status === 400) return reply.code(400).send({ code: 'invalid_request', message: 'Invalid request.' });
    return reply.code(503).send({ code: 'unavailable', message: 'The data service is unavailable. Try again shortly.' });
  });
  app.get('/health/live', async () => ({ status: 'ok' }));
  app.get('/health/ready', async () => {
    await repo.db.command({ ping: 1 });
    return { status: 'ready' };
  });
  const authLimit = { rateLimit: { max: 20, timeWindow: '1 minute' } };
  app.post('/auth/google', { config: authLimit }, async request => {
    const body = z.object({ idToken: z.string().min(1).max(12000), platform: z.literal('android') }).strict().parse(request.body);
    return identity(body.idToken, config.GOOGLE_WEB_CLIENT_ID);
  });
  app.post('/auth/windows/start', { config: authLimit }, async request => {
    if (!config.GOOGLE_WINDOWS_CLIENT_SECRET && !options.exchangeCode) {
      throw new ApiError(503, 'google_not_configured', 'Google sign-in is not configured on this server yet. Please contact support.');
    }
    const body = z.object({
      redirectUri: z.string().url(), codeChallenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
      state: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
    }).strict().parse(request.body);
    const uri = new URL(body.redirectUri);
    if (uri.protocol !== 'http:' || uri.hostname !== '127.0.0.1' ||
        Number(uri.port) < 1024 || !uri.port || uri.pathname !== '/oauth/callback' ||
        uri.search || uri.hash || uri.username || uri.password) {
      throw new ApiError(400, 'invalid_redirect', 'Invalid desktop callback.');
    }
    const challenge = await repo.challenge(body.redirectUri, body.codeChallenge);
    const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    url.search = new URLSearchParams({
      client_id: config.GOOGLE_WINDOWS_CLIENT_ID, redirect_uri: body.redirectUri,
      response_type: 'code', scope: 'openid email profile', code_challenge: body.codeChallenge,
      code_challenge_method: 'S256', state: body.state, nonce: challenge.nonce, prompt: 'select_account',
    }).toString();
    return { challengeId: challenge._id, authorizationUrl: url.toString() };
  });
  app.post('/auth/windows/complete', { config: authLimit }, async request => {
    const body = z.object({
      challengeId: z.uuid(), code: z.string().min(1).max(4000),
      verifier: z.string().regex(/^[A-Za-z0-9_-]{43,128}$/),
    }).strict().parse(request.body);
    const challenge = await repo.consumeChallenge(body.challengeId, body.verifier);
    let idToken: string;
    try {
      if (options.exchangeCode) {
        idToken = await options.exchangeCode(body.code, body.verifier, challenge.redirectUri);
      } else {
        const form = new URLSearchParams({
          client_id: config.GOOGLE_WINDOWS_CLIENT_ID, code: body.code,
          code_verifier: body.verifier, redirect_uri: challenge.redirectUri, grant_type: 'authorization_code',
        });
        if (config.GOOGLE_WINDOWS_CLIENT_SECRET) form.set('client_secret', config.GOOGLE_WINDOWS_CLIENT_SECRET);
        const response = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST', body: form, signal: AbortSignal.timeout(15000),
        });
        if (!response.ok) throw new Error('Token exchange rejected');
        const tokens = await response.json() as { id_token?: string };
        if (!tokens.id_token) throw new Error('Missing ID token');
        idToken = tokens.id_token;
      }
    } catch {
      throw new ApiError(401, 'google_exchange_failed', 'Google sign-in failed. Please try again or contact support.');
    }
    return identity(idToken, config.GOOGLE_WINDOWS_CLIENT_ID, challenge.nonce);
  });
  app.get('/auth/me', { preHandler: authenticate }, async request =>
    repo.authenticate(request.headers.authorization!.slice(7)));
  app.post('/auth/logout', async request => {
    if (request.headers.authorization?.startsWith('Bearer ')) {
      await repo.logout(request.headers.authorization.slice(7));
    }
    return { status: 'signed_out' };
  });
  app.get('/workspace', { preHandler: authenticate }, async request => repo.workspace(request.ownerId!));
  app.put('/workspace', { preHandler: authenticate }, async request => {
    const body = saveSchema.parse(request.body);
    return repo.save(request.ownerId!, body.revision, body.operationId, body.data);
  });
  app.post('/workspace/import', { preHandler: authenticate }, async request => {
    const body = importSchema.parse(request.body);
    return repo.save(request.ownerId!, body.revision, body.operationId, body.data, body.sourceId);
  });
  return app;
}
