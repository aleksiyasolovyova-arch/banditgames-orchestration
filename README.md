This project is configured to run entirely via Docker Compose using environment variables for all secrets, credentials, and image configuration. Follow the steps below to set up your environment and run services with either remote or local images.

***

## Environment setup

This project uses a `.env` file for configuration (database credentials, admin users, hostnames, image names, paths, etc.).  
The repository includes a public `.env.example` template that you should copy and customize.

### 1. Create your `.env`

```bash
cp .env.example .env
```

Then open `.env` and fill in:

- Database settings (PostgreSQL, MySQL)
- Keycloak admin credentials
- RabbitMQ credentials
- Image names for all services (platform backend/frontend, connect4 backend/frontend, AI player)
- Optional local build paths (if you build any service locally)

Keep `.env` **local only**:

```bash
git update-index --assume-unchanged .env   # or ensure .env is in .gitignore
```

Never commit `.env`.

***

## Docker Compose layout

At the root of the `orchestration` directory you have:

- `docker-compose.yml`  
  Base compose file. Defines:
  - Infrastructure services:
    - `platform_postgres` (PostgreSQL)
    - `rabbitmq`
    - `idp_mysql` (MySQL for Keycloak)
    - `idp_keycloak`
  - Application services (always using images from `.env`):
    - `platform_backend`
    - `platform_frontend`
    - `connect4_backend`
    - `connect4_frontend`
    - `ai_connect4_player`

- `local/`  
  Directory containing per-service override files for **local builds**:
  - `local/platform-backend.yml`
  - `local/platform-frontend.yml`
  - `local/connect4-backend.yml`
  - `local/connect4-frontend.yml`
  - `local/ai-connect4-player.yml`

Each file in `local/` overrides **only one service** to build from local source using a `*_PATH` environment variable while keeping all other configuration (depends_on, networks, env, healthchecks) from the base `docker-compose.yml`.

***

## Running everything with remote images

This is the default and simplest mode: all services use images from a container registry as defined by the `*_IMAGE` variables in `.env`.

```bash
docker compose -f docker-compose.yml up
```

- `platform_postgres`, `rabbitmq`, `idp_mysql`, `idp_keycloak` run as defined in `docker-compose.yml`.
- `platform_backend`, `platform_frontend`, `connect4_backend`, `connect4_frontend`, `ai_connect4_player` all run using their `*_IMAGE` tags.  
- On first run, Docker will pull any missing images.

To stop and remove containers:

```bash
docker compose -f docker-compose.yml down
```

***

## Using local builds for specific services

If you want to test a local version of a service (e.g. your local Spring Boot backend) without touching others, you combine the base file with one or more overrides from `local/`.

### 1. Configure local build paths in `.env`

For any service you want to build locally, set the corresponding path and image in `.env`, for example:

```env
# Images (remote tags)
PLATFORM_BACKEND_IMAGE=radu0matei1enciu/platform-backend:main
PLATFORM_FRONTEND_IMAGE=radu0matei1enciu/platform-frontend:main
CONNECT4_BACKEND_IMAGE=radu0matei1enciu/connect4-backend:main
CONNECT4_FRONTEND_IMAGE=radu0matei1enciu/connect4-frontend:main
AI_CONNECT4_PLAYER_IMAGE=radu0matei1enciu/ai-connect4-player:main

# Local build paths (only needed for services you build locally)
PLATFORM_BACKEND_PATH=../platform/platform-backend/
PLATFORM_FRONTEND_PATH=../platform/platform-frontend/
CONNECT4_BACKEND_PATH=../connect4/connect4-backend/
CONNECT4_FRONTEND_PATH=../connect4/connect4-frontend/
AI_CONNECT4_PLAYER_PATH=../ai-connect4-player/
```

Only the `*_PATH` values for services you actively build need to be valid; the others can be left empty if you are not using their local overrides.

### 2. Run one service locally, others remote

Example: build and run **only `platform_backend`** from your local source; keep everything else on remote images:

```bash
docker compose \
  -f docker-compose.yml \
  -f local/platform-backend.yml \
  up --build
```

What happens:

- `platform_backend`:
  - Uses `build.context: ${PLATFORM_BACKEND_PATH}` from `local/platform-backend.yml`.
  - Uses `image: ${PLATFORM_BACKEND_IMAGE}` so the built image is tagged consistently.
- All other services (`platform_frontend`, `connect4_backend`, `connect4_frontend`, `ai_connect4_player`) use their remote images as defined in `docker-compose.yml`.

Note: You don t have to docker compose down when you change code! As long as you have --build it will always get the latest changes from your laptop. If you do not have --build, it will not take any new changes and just use the image that is already created locally

### 3. Run multiple services locally

You can stack as many override files as you need.

Example: local backend + local connect4 backend:

```bash
docker compose \
  -f docker-compose.yml \
  -f local/platform-backend.yml \
  -f local/connect4-backend.yml \
  up --build
```

Example: all five services local:

```bash
docker compose \
  -f docker-compose.yml \
  -f local/platform-backend.yml \
  -f local/platform-frontend.yml \
  -f local/connect4-backend.yml \
  -f local/connect4-frontend.yml \
  -f local/ai-connect4-player.yml \
  up --build
```

Compose merges the files **in order**:
- Base configuration (networks, environment, depends_on, healthchecks) comes from `docker-compose.yml`.
- For services listed in any `local/*.yml`, `image` and `build` are overridden by the last file that mentions them.

To shut them down:

```bash
docker compose \
  -f docker-compose.yml \
  -f local/platform-backend.yml \
  [other -f local/...] \
  down
```

***

## Summary of typical workflows

- **Remote-only (what teammates/CI should use):**

  ```bash
  docker compose -f docker-compose.yml up -d
  ```

- **Test a local backend (platform_backend) against the full remote stack:**

  ```bash
  docker compose \
    -f docker-compose.yml \
    -f local/platform-backend.yml \
    up --build
  ```

- **Test multiple local services together (e.g. platform backend + connect4 backend):**

  ```bash
  docker compose \
    -f docker-compose.yml \
    -f local/platform-backend.yml \
    -f local/connect4-backend.yml \
    up --build
  ```

Add a short “Run only some services” section and show how to target just what you need.

You can append something like this to the README:

***

## Run only specific services

You don’t always need the full stack. You can tell Docker Compose exactly which services to start.

### Example: backend + database only

Run the backend and its dependencies (PostgreSQL, RabbitMQ, Keycloak DB, Keycloak), but no frontends:

```bash
docker compose -f docker-compose.yml up platform_backend
```

- Compose will start `platform_backend` and automatically start any services it depends on via `depends_on` (for example: `platform_postgres`, `rabbitmq`, `idp_mysql`, `idp_keycloak`), but it will NOT start `platform_frontend`, `connect4_frontend`, etc.  
- To run in the background:

```bash
docker compose -f docker-compose.yml up -d platform_backend
```

### Example: connect4 backend + DB/RabbitMQ only

```bash
docker compose -f docker-compose.yml up connect4_backend
```

This starts `connect4_backend` plus its dependencies (`rabbitmq`, `platform_postgres`), but not the platform or connect4 frontends.

### Example: mix with local overrides

You can still combine this with local build overrides:

```bash
docker compose \
  -f docker-compose.yml \
  -f local/platform-backend.yml \
  up --build platform_backend
```

This will:

- Build and start only the local `platform_backend` service.  
- Start any required dependencies (Postgres, RabbitMQ, Keycloak) from the base file.  
- Skip all frontends and any other services you didn’t list on the command line.
