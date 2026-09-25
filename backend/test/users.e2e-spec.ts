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
    model = moduleRef.get(getModelToken(User.name));
    // Start without the collection (and its indexes) so the test proves
    // UsersService builds the unique index itself at startup.
    await model.collection.drop().catch(() => undefined);
    await moduleRef.init();
    users = moduleRef.get(UsersService);
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

  it('has the unique googleSub index once the module is initialised', async () => {
    const indexes = await model.collection.indexes();
    const index = indexes.find((item) => item.key.googleSub === 1);
    expect(index?.unique).toBe(true);
  });

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
    const second = await users.upsertFromGoogle({
      ...google,
      name: 'New',
      photoUrl: undefined,
    });
    expect(second.id).toBe(first.id);
    expect(second.name).toBe('New');
    expect(second.photoUrl).toBeNull();
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
    // 12 arbitrary characters are not an ObjectId either.
    expect(await users.findById('aaaaaaaaaaaa')).toBeNull();

    expect(await users.remove('not-an-id')).toBe(false);
    expect(await users.remove(user.id)).toBe(true);
    expect(await users.findById(user.id)).toBeNull();
  });

  it('rejects a Google profile without an email', async () => {
    await expect(
      users.upsertFromGoogle({ sub: 'x', email: '' }),
    ).rejects.toThrow(/email/);
    expect(await model.countDocuments()).toBe(0);
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
