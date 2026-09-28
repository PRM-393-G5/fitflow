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
| `GOOGLE_CLIENT_IDS` | — (required) | Comma-separated Google OAuth client IDs accepted as ID-token audience (the app's `serverClientId`) |
| `JWT_ACCESS_SECRET` | — (required, ≥ 32 chars) | HMAC secret for access tokens |
| `ACCESS_TOKEN_TTL_SECONDS` | `900` | Access token lifetime |
| `REFRESH_TOKEN_TTL_DAYS` | `30` | Refresh token lifetime |
| `MONGODB_TEST_URI` | local `fitflow-test` DB | Database used by the test suites (never the dev DB); export it in the shell — `.env` is not read for it |

## Endpoints

| Method | Route | Description |
|---|---|---|
| GET | `/api` | API name and version |
| GET | `/api/health` | `200 {status, database}` when MongoDB answers a ping, `503` otherwise |
| POST | `/api/auth/google` | Body `{idToken}` (Google Sign-In ID token) → `200 {accessToken, expiresIn, refreshToken, user}`; creates the account on first sign-in; `401` if Google does not verify the token or the email |
| POST | `/api/auth/refresh` | Body `{refreshToken}` → new `{accessToken, expiresIn, refreshToken}`; the old refresh token stops working |
| POST | `/api/auth/logout` | Body `{refreshToken}` → `204`; revokes that session |
| GET | `/api/me` | 🔒 Profile `{id, email, name, photoUrl}` of the caller |

🔒 = needs `Authorization: Bearer <accessToken>`.

### Sessions

Access tokens are HS256 JWTs (`sub` = user id) valid for
`ACCESS_TOKEN_TTL_SECONDS`. Refresh tokens are 32 random bytes
(base64url), stored only as SHA-256 hashes in `refreshtokens` with a TTL
index, and single-use: every refresh consumes the token atomically and
returns a new pair.

## Data model

| Collection | Key fields | Notes |
|---|---|---|
| `users` | `googleSub` (unique), `email`, `name`, `photoUrl`, `meta`, `metaUpdatedAt` | Created on first Google sign-in; `meta` is the app's last-write-wins profile blob |
| `refreshtokens` | `userId`, `tokenHash` (unique), `expiresAt` (TTL) | One per open session |

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
