# MemeSpeak

MemeSpeak translates Gen-Z slang, internet shorthand, emoji, and meme language into plain English. The project includes a Spring Boot REST API and a React frontend.

## Features

- Context-aware translations with a short meaning and explanation
- Google sign-in; the frontend sends a Google ID token to the API
- Input safety checks, PII redaction, rate limiting, and cached translations
- PostgreSQL persistence and Redis caching/rate limiting
- Swagger UI and Spring Boot Actuator health information

## Project structure

```text
src/main/java/       Spring Boot API
src/main/resources/  Application configuration and guardrail dictionaries
src/test/java/       Backend tests
frontend/            React 19 + Vite client
docker-compose.yml   Local PostgreSQL, Redis, and backend services
```

## Requirements

- Java 21 and Maven (or use the included Maven wrapper if one is added)
- Node.js and npm
- Docker and Docker Compose for the containerized setup
- A Google OAuth client ID and an API key for Gemini or another OpenAI-compatible LLM provider

The Maven compiler is configured for Java 21.

## Configuration

For Docker Compose, copy the sample environment file and fill in the credentials:

```bash
cp .env.example .env
```

Set these values in `.env`:

| Variable | Purpose |
| --- | --- |
| `DATABASE_USERNAME` / `DATABASE_PASSWORD` | PostgreSQL credentials |
| `LLM_API_KEY` | Gemini or compatible provider key |
| `LLM_BASE_URL` | Provider's OpenAI-compatible API base URL |
| `LLM_MODEL` | Model name, such as `gemini-3.5-flash` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Google OAuth client credentials |
| `VITE_GOOGLE_CLIENT_ID` | Same value as `GOOGLE_CLIENT_ID`, used by the browser for Google sign-in |

The sample defaults target Gemini. `VITE_GOOGLE_CLIENT_ID` must be in this root `.env` file: `frontend/vite.config.js` sets `envDir: '../'`, so a `frontend/.env.local` file is **not** read.

In the Google Cloud console, the OAuth client must list `http://localhost:5173` under Authorized JavaScript origins, and if the consent screen is in Testing mode, every developer's Google account must be added as a test user.

Keep real credentials in local environment files; do not commit them.

## Run with Docker Compose

With `.env` configured, start PostgreSQL, Redis, and the API:

```bash
docker compose up --build
```

The backend listens on [http://localhost:8080](http://localhost:8080) and, because the Docker image bundles the built frontend, it also serves the website there (Google sign-in then needs `http://localhost:8080` as an authorized JavaScript origin). Stop the services with `Ctrl+C`, or run `docker compose down`. Persistent PostgreSQL data is stored in the `postgres_data` volume.

## Deploy as a single cloud service (e.g. Render)

The `Dockerfile` builds the React frontend and bundles it into the Spring Boot JAR, so one container serves both the website and the API on one URL. That means no CORS setup and only one Google origin to register.

1. Create a PostgreSQL database and a Redis-compatible (Key Value) instance on your host.
2. Create a Web Service from this GitHub repo using the `Dockerfile`, with auto-deploy on push to `main`.
3. Set these environment variables on the web service:
   - `DATABASE_URL` as `jdbc:postgresql://HOST:5432/DBNAME` (it must start with `jdbc:`; do not paste the host's `postgres://` link), plus `DATABASE_USERNAME` and `DATABASE_PASSWORD`
   - `REDIS_HOST` and `REDIS_PORT`. If your Redis requires a password or TLS, also set `SPRING_DATA_REDIS_PASSWORD` and `SPRING_DATA_REDIS_SSL_ENABLED=true`
   - `LLM_API_KEY`, `LLM_BASE_URL` and `LLM_MODEL`
   - `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`
   - `VITE_GOOGLE_CLIENT_ID` (same value as `GOOGLE_CLIENT_ID`). Render passes service env vars to the Docker build, which is how the frontend gets it, so set it **before** the first deploy.
4. In the Google Cloud console, add the deployed service URL (for example `https://your-app.onrender.com`) under Authorized JavaScript origins.
5. Use `/actuator/health` as the health check path.

Free tiers may put the service to sleep when idle, so open the site a few minutes before a demo.

## Run services locally

Start only PostgreSQL and Redis from Compose (plain `docker compose up` also starts the backend container on port 8080, which clashes with `mvn spring-boot:run`):

```bash
docker compose up -d postgres redis
```

Then export the backend settings from `.env` into the same shell you will run the API from. `mvn spring-boot:run` does not read `.env` by itself; without these variables the API still starts, but uses placeholder defaults and every translation fails.

```bash
# macOS / Linux / Git Bash
set -a; source .env; set +a
```

```powershell
# Windows PowerShell
Get-Content .env | Where-Object { $_ -match '^\s*[^#\s]' } | ForEach-Object { $k,$v = $_ -split '=',2; [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process') }
```

Run the API from the project root (Java 21 required):

```bash
mvn spring-boot:run
```

The API needs internet access at startup, because it fetches Google's sign-in keys from `accounts.google.com`.

In another terminal, start the frontend:

```bash
cd frontend
npm install
npm run dev
```

Vite serves the UI locally and proxies `/api` requests to the backend at `localhost:8080`. The frontend needs `VITE_GOOGLE_CLIENT_ID` set in the root `.env` file (see Configuration) for Google sign-in.

If you change `DATABASE_PASSWORD` after the first run, the old password stays inside the `postgres_data` volume. Reset it with `docker compose down -v` (this deletes the local database).

## API

All application endpoints are under `/api/v1` and require a valid Google ID token in the `Authorization` header.

### Translate text

`POST /api/v1/translate`

```http
Authorization: Bearer <google-id-token>
Content-Type: application/json
```

```json
{
  "text": "Bro is absolutely cooked 💀"
}
```

The `text` field must contain 1–500 non-blank characters. A successful response looks like:

```json
{
  "meaning": "He's in serious trouble.",
  "explanation": "\"Cooked\" means someone is in a situation where failure or a bad outcome is very likely."
}
```

### Current user

`GET /api/v1/me` returns the authenticated user's Google ID, email, and name.

### API documentation and health

- Swagger UI: [http://localhost:8080/swagger-ui.html](http://localhost:8080/swagger-ui.html)
- OpenAPI JSON: [http://localhost:8080/v3/api-docs](http://localhost:8080/v3/api-docs)
- Health: [http://localhost:8080/actuator/health](http://localhost:8080/actuator/health)

Expected API errors include `400` for invalid input, `401` for missing or invalid authentication, `422` for blocked input, `429` for rate limiting, and `503` when the LLM is unavailable.

## Development commands

From the project root:

```bash
mvn test
mvn package
```

From `frontend/`:

```bash
npm run dev
npm run build
npm run lint
```

