import 'reflect-metadata';

// Tests must not depend on an untracked .env: provide the local defaults
// (an exported variable or .env value still takes precedence).
process.env.MONGODB_URI ??=
  'mongodb://admin:123456@localhost:27017/fitflow-test?authSource=admin';
