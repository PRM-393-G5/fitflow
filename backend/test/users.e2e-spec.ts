import { Test, TestingModule } from '@nestjs/testing';
import { getModelToken } from '@nestjs/mongoose';
import type { Model } from 'mongoose';
import { AppModule } from '../src/app.module.js';
import { User } from '../src/users/schemas/user.schema.js';
import { UsersService } from '../src/users/users.service.js';

describe('UsersService (MongoDB)', () => {
  let moduleRef: TestingModule;
  let users: UsersService;
  let model: Model<User>;

  beforeAll(async () => {
    moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    await moduleRef.init();
    users = moduleRef.get(UsersService);
    model = moduleRef.get(getModelToken(User.name));
    await model.syncIndexes();
  });

  beforeEach(async () => {
    await model.deleteMany({});
  });

  afterAll(async () => {
    await moduleRef?.close();
  });

  const google = {
    sub: 'google-123',
    email: 'Athlete@Example.com',
    name: 'Athlete',
    photoUrl: 'https://example.com/a.png',
  };

  it('creates an account on first sign-in with empty meta', async () => {
    const user = await users.upsertFromGoogle(google);
    expect(user.googleSub).toBe('google-123');
    expect(user.email).toBe('athlete@example.com');
    expect(user.meta).toEqual({});
    expect(user.metaUpdatedAt).toBe(0);
  });

  it('reuses the account and refreshes the profile on later sign-ins', async () => {
    const first = await users.upsertFromGoogle(google);
    await model.updateOne({ _id: first._id }, { metaUpdatedAt: 42 });
    const second = await users.upsertFromGoogle({ ...google, name: 'New' });
    expect(second.id).toBe(first.id);
    expect(second.name).toBe('New');
    expect(second.metaUpdatedAt).toBe(42);
    expect(await model.countDocuments()).toBe(1);
  });

  it('keeps one account when first sign-ins race', async () => {
    const results = await Promise.all(
      Array.from({ length: 5 }, () => users.upsertFromGoogle(google)),
    );
    expect(new Set(results.map((user) => user.id)).size).toBe(1);
    expect(await model.countDocuments()).toBe(1);
  });

  it('finds and removes by id, tolerating malformed ids', async () => {
    const user = await users.upsertFromGoogle(google);
    expect((await users.findById(user.id))?.email).toBe(user.email);
    expect(await users.findById('not-an-id')).toBeNull();

    expect(await users.remove('not-an-id')).toBe(false);
    expect(await users.remove(user.id)).toBe(true);
    expect(await users.findById(user.id)).toBeNull();
  });

  it('exposes only public profile fields', async () => {
    const user = await users.upsertFromGoogle({ sub: 's', email: 'a@b.c' });
    expect(UsersService.toProfile(user)).toEqual({
      id: user.id,
      email: 'a@b.c',
      name: null,
      photoUrl: null,
    });
  });
});
