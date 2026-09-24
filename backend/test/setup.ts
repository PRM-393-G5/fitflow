import 'reflect-metadata';

// Tests never touch the development database: they use MONGODB_TEST_URI
// (or the local default) and ignore MONGODB_URI from .env — ConfigModule
// does not override variables already set in process.env.
process.env.NODE_ENV = 'test';
process.env.MONGODB_URI =
  process.env.MONGODB_TEST_URI ??
  'mongodb://admin:123456@localhost:27017/fitflow-test?authSource=admin';
