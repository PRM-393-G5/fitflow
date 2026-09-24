import 'reflect-metadata';

// Tests never touch the development database. MONGODB_TEST_URI must be
// exported in the shell (it is read before .env is loaded); MONGODB_URI
// from .env is ignored because ConfigModule does not override variables
// already set in process.env.
process.env.NODE_ENV = 'test';
process.env.MONGODB_URI =
  process.env.MONGODB_TEST_URI ||
  'mongodb://admin:123456@localhost:27017/fitflow-test?authSource=admin';
