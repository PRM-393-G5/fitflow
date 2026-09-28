import { INestApplication } from '@nestjs/common';
import { getModelToken } from '@nestjs/mongoose';
import { Test } from '@nestjs/testing';
import type { Model } from 'mongoose';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/app.setup.js';
import { OAuth2Client } from 'google-auth-library';
import { RefreshToken } from '../src/auth/tokens/refresh-token.schema.js';
import { User } from '../src/users/schemas/user.schema.js';

/** Syntactically valid JWTs; the fake Google client decides which is "good". */
const GOOD_TOKEN = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJnb29kIn0.c2ln';
const BAD_TOKEN = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJiYWQifQ.c2ln';

describe('Auth (e2e)', () => {
  let app: INestApplication<App>;
  let users: Model<User>;
  let refreshTokens: Model<RefreshToken>;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      // Only Google's network call is faked: the real GoogleVerifier runs,
      // including the audience parsed from GOOGLE_CLIENT_IDS.
      .overrideProvider(OAuth2Client)
      .useValue({
        verifyIdToken: (options: { idToken: string; audience: string[] }) => {
          const audienceOk = options.audience.includes(
            process.env.GOOGLE_CLIENT_IDS!,
          );
          if (options.idToken !== GOOD_TOKEN || !audienceOk) {
            return Promise.reject(new Error('Wrong recipient'));
          }
          return Promise.resolve({
            getPayload: () => ({
              sub: 'google-e2e',
              email: 'e2e@example.com',
              email_verified: true,
              name: 'E2E',
            }),
          });
        },
      })
      .compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    users = moduleRef.get(getModelToken(User.name));
    refreshTokens = moduleRef.get(getModelToken(RefreshToken.name));
  });

  beforeEach(async () => {
    await users.deleteMany({});
    await refreshTokens.deleteMany({});
  });

  afterAll(async () => {
    await app?.close();
  });

  const signIn = (body: object) =>
    request(app.getHttpServer()).post('/api/auth/google').send(body);
  const refresh = (refreshToken: string) =>
    request(app.getHttpServer())
      .post('/api/auth/refresh')
      .send({ refreshToken });
  const me = (accessToken?: string) => {
    const req = request(app.getHttpServer()).get('/api/me');
    return accessToken
      ? req.set('Authorization', `Bearer ${accessToken}`)
      : req;
  };

  it('signs in with a valid Google token and creates the user once', async () => {
    const first = await signIn({ idToken: GOOD_TOKEN }).expect(200);
    expect(first.body.user).toMatchObject({
      email: 'e2e@example.com',
      name: 'E2E',
      photoUrl: null,
    });

    const second = await signIn({ idToken: GOOD_TOKEN }).expect(200);
    expect(second.body.user.id).toBe(first.body.user.id);
    expect(await users.countDocuments()).toBe(1);
  });

  it('rejects a token Google does not accept with 401', async () => {
    await signIn({ idToken: BAD_TOKEN }).expect(401);
    expect(await users.countDocuments()).toBe(0);
  });

  it('validates the body', async () => {
    const missing = await signIn({}).expect(400);
    expect(missing.body.message).toContain('idToken must be a jwt string');
    await signIn({ idToken: GOOD_TOKEN, extra: 1 }).expect(400);
  });

  it('returns a session whose access token opens GET /api/me', async () => {
    const { body } = await signIn({ idToken: GOOD_TOKEN }).expect(200);
    expect(body).toMatchObject({ expiresIn: 900 });
    expect(body.refreshToken).toHaveLength(43);

    const profile = await me(body.accessToken).expect(200);
    expect(profile.body).toEqual(body.user);
  });

  it('stores only a hash of the refresh token', async () => {
    const { body } = await signIn({ idToken: GOOD_TOKEN }).expect(200);
    const stored = await refreshTokens.find().lean();
    expect(stored).toHaveLength(1);
    expect(stored[0].tokenHash).not.toBe(body.refreshToken);
  });

  it('rejects /api/me without a valid access token', async () => {
    await me().expect(401);
    await me('not-a-jwt').expect(401);
  });

  it('rotates refresh tokens: the old one stops working', async () => {
    const session = (await signIn({ idToken: GOOD_TOKEN }).expect(200)).body;
    const rotated = (await refresh(session.refreshToken).expect(200)).body;
    expect(rotated.refreshToken).not.toBe(session.refreshToken);
    await me(rotated.accessToken).expect(200);

    await refresh(session.refreshToken).expect(401);
    await refresh(rotated.refreshToken).expect(200);
  });

  it('lets only one of two concurrent refreshes succeed', async () => {
    const session = (await signIn({ idToken: GOOD_TOKEN }).expect(200)).body;
    const results = await Promise.all([
      refresh(session.refreshToken),
      refresh(session.refreshToken),
    ]);
    expect(results.map((res) => res.status).sort()).toEqual([200, 401]);
  });

  it('rejects an expired refresh token even before the TTL sweep', async () => {
    const session = (await signIn({ idToken: GOOD_TOKEN }).expect(200)).body;
    await refreshTokens.updateMany({}, { expiresAt: new Date(Date.now() - 1) });
    await refresh(session.refreshToken).expect(401);
  });

  it('logs out by revoking the refresh token', async () => {
    const session = (await signIn({ idToken: GOOD_TOKEN }).expect(200)).body;
    await request(app.getHttpServer())
      .post('/api/auth/logout')
      .send({ refreshToken: session.refreshToken })
      .expect(204);
    await refresh(session.refreshToken).expect(401);
  });

  it('answers 401 on /api/me once the account is gone', async () => {
    const session = (await signIn({ idToken: GOOD_TOKEN }).expect(200)).body;
    await users.deleteMany({});
    await me(session.accessToken).expect(401);
  });
});
