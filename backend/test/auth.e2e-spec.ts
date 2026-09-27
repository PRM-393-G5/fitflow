import { INestApplication } from '@nestjs/common';
import { getModelToken } from '@nestjs/mongoose';
import { Test } from '@nestjs/testing';
import type { Model } from 'mongoose';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/app.setup.js';
import { OAuth2Client } from 'google-auth-library';
import { User } from '../src/users/schemas/user.schema.js';

/** Syntactically valid JWTs; the fake Google client decides which is "good". */
const GOOD_TOKEN = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJnb29kIn0.c2ln';
const BAD_TOKEN = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJiYWQifQ.c2ln';

describe('Auth (e2e)', () => {
  let app: INestApplication<App>;
  let users: Model<User>;

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
  });

  beforeEach(async () => {
    await users.deleteMany({});
  });

  afterAll(async () => {
    await app?.close();
  });

  const signIn = (body: object) =>
    request(app.getHttpServer()).post('/api/auth/google').send(body);

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
});
