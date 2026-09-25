import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    root: './',
    setupFiles: ['./test/setup.ts'],
    include: ['**/*.e2e-spec.ts'],
    // Suites share the fitflow-test database; run them one at a time.
    fileParallelism: false,
  },
});
