import { NodeEnv, splitList, validateEnv } from './env.validation.js';

const required = { MONGODB_URI: 'x', GOOGLE_CLIENT_IDS: 'client' };

describe('validateEnv', () => {
  it('applies defaults and converts types', () => {
    const env = validateEnv({
      ...required,
      MONGODB_URI: 'mongodb://localhost/fitflow',
    });
    expect(env.NODE_ENV).toBe(NodeEnv.Development);
    expect(env.PORT).toBe(3001);

    expect(validateEnv({ ...required, PORT: '4000' }).PORT).toBe(4000);
  });

  it('rejects a missing MONGODB_URI', () => {
    expect(() => validateEnv({})).toThrow(/MONGODB_URI/);
  });

  it('rejects an empty MONGODB_URI', () => {
    expect(() => validateEnv({ ...required, MONGODB_URI: '' })).toThrow(
      /MONGODB_URI/,
    );
  });

  it('rejects an out-of-range PORT', () => {
    expect(() => validateEnv({ ...required, PORT: '70000' })).toThrow(/PORT/);
  });

  it('requires GOOGLE_CLIENT_IDS', () => {
    expect(() => validateEnv({ MONGODB_URI: 'x' })).toThrow(
      /GOOGLE_CLIENT_IDS/,
    );
  });
});

describe('validateEnv lists', () => {
  it('rejects GOOGLE_CLIENT_IDS without any ID', () => {
    expect(() =>
      validateEnv({ ...required, GOOGLE_CLIENT_IDS: ' , ' }),
    ).toThrow(/at least one ID/);
  });
});

describe('splitList', () => {
  it('splits on commas and drops blanks', () => {
    expect(splitList(' a, b ,,c ')).toEqual(['a', 'b', 'c']);
  });
});
