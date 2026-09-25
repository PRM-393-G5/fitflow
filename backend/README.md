# FitFlow API

REST backend for the FitFlow app, built with NestJS and MongoDB (Mongoose).
It replaces Firebase: Google Sign-In on the device, ID token verified here,
then the API issues its own JWT and stores per-user sync data.

## Requirements

- Node.js 24 and npm
- MongoDB 7+ running locally (default URI assumes user `admin` / `123456`
  authenticating against the `admin` database). These are local development
  credentials only — use your own user and password for any shared or
  deployed database.

## Setup and run

```sh
cd backend
npm install
cp .env.example .env   # adjust MONGODB_URI / PORT if needed
npm run start:dev      # http://localhost:3001/api
```

Every route lives under `/api`. The app refuses to start when a required
environment variable is missing or invalid (see `src/config/env.validation.ts`).

| Variable | Default | Purpose |
|---|---|---|
| `NODE_ENV` | `development` | `development`, `production` or `test` |
| `PORT` | `3001` | HTTP port |
| `MONGODB_URI` | — (required) | MongoDB connection string |
| `MONGODB_TEST_URI` | local `fitflow-test` DB | Database used by the test suites (never the dev DB); export it in the shell — `.env` is not read for it |

## Endpoints

| Method | Route | Description |
|---|---|---|
| GET | `/api` | API name and version |
| GET | `/api/health` | `200 {status, database}` when MongoDB answers a ping, `503` otherwise |

## Data model

| Collection | Key fields | Notes |
|---|---|---|
| `users` | `googleSub` (unique), `email`, `name`, `photoUrl`, `meta`, `metaUpdatedAt` | Created on first Google sign-in; `meta` is the app's last-write-wins profile blob |

Every error uses the same body:
`{ statusCode, error, message, path, timestamp }`.

## Quality checks and tests

```sh
npm run lint
npx prettier --check "src/**/*.ts" "test/**/*.ts"
npm test           # unit tests (Vitest)
npm run test:e2e   # HTTP + MongoDB integration tests (needs MongoDB running;
                   # suites run one at a time on the fitflow-test database)
npm run build
```

## Roadmap

The migration off Firebase is split into small PRs — see
[`docs/backend-migration.md`](../docs/backend-migration.md).
