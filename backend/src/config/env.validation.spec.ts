import { NodeEnv, validateEnv } from './env.validation.js';

describe('validateEnv', () => {
  it('applies defaults and converts types', () => {
    const env = validateEnv({ MONGODB_URI: 'mongodb://localhost/fitflow' });
    expect(env.NODE_ENV).toBe(NodeEnv.Development);
    expect(env.PORT).toBe(3000);

    expect(validateEnv({ MONGODB_URI: 'x', PORT: '4000' }).PORT).toBe(4000);
  });

  it('rejects a missing MONGODB_URI', () => {
    expect(() => validateEnv({})).toThrow(/MONGODB_URI/);
  });

  it('rejects an out-of-range PORT', () => {
    expect(() => validateEnv({ MONGODB_URI: 'x', PORT: '70000' })).toThrow(
      /PORT/,
    );
  });
});
