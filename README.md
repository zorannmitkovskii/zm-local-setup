# zm-local-setup

Shared local-development **infrastructure** for the whole org — Postgres, Keycloak, Kafka, nginx. Run it once; the backend services (`ivy-events-be`, `zm-iam-service`) run from your IDE against `localhost`.

| Service          | URL / port                       | Default creds        |
|------------------|----------------------------------|----------------------|
| nginx            | http://localhost                 | —                    |
| Postgres         | localhost:5432                   | postgres / postgres  |
| Kafka            | localhost:9092                   | —                    |
| Kafka UI         | http://localhost:8090            | —                    |
| Keycloak         | http://localhost:8181            | admin / admin        |

Keycloak listens on **8181** (the port the backends expect) and is backed by the `keycloak` database in Postgres (persistent across restarts). Postgres hosts one database per service — ready for the host-run backends to connect to:

| Database        | Owner / creds       | Used by         |
|-----------------|---------------------|-----------------|
| `keycloak`      | keycloak / keycloak | Keycloak        |
| `ivy_events_db` | postgres / postgres | ivy-events-be   |
| `iam_db`        | iam_user / iam_pass | zm-iam-service  |

**`keycloak-bootstrap`** is a one-shot container that seeds a confidential admin client `zm-admin-cli` (secret `zm-admin-secret`) into the `master` realm and grants it the `admin` role. `zm-iam-service` authenticates with it (`KEYCLOAK_ADMIN_CLIENT_ID` / `KEYCLOAK_ADMIN_CLIENT_SECRET`) to reach the Keycloak Admin API.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose v2)
- Ports `80, 443, 5432, 8090, 8181, 9092, 9093` free — override in `.env` if not.

## Run it

```bash
# First time
cp .env.example .env   # optional; only if you want to change defaults

# Start the infrastructure in the background
docker compose up -d

# Watch it boot
docker compose ps
docker compose logs -f keycloak-bootstrap   # confirms the admin client was seeded
```

First boot pulls ~800 MB of images. Subsequent boots are seconds.

### Then run the backends from your IDE

Point them at the infra on `localhost`:

- **zm-iam-service** — `DB_URL=jdbc:postgresql://localhost:5432/iam_db` (iam_user/iam_pass), `KEYCLOAK_BASE_URL=http://localhost:8181`, `KEYCLOAK_ADMIN_CLIENT_ID=zm-admin-cli`, `KEYCLOAK_ADMIN_CLIENT_SECRET=zm-admin-secret`. Its `local` profile already defaults to these.
- **ivy-events-be** — `SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/ivy_events_db`, Keycloak at `http://localhost:8181`. Its `local` profile already matches.

## Stop / reset

```bash
docker compose stop              # pause everything (state preserved)
docker compose down              # stop & remove containers (volumes survive)
docker compose down -v           # ALSO wipe volumes (re-runs Postgres init.sql)
```

## What's where

```
zm-local-setup/
├── docker-compose.yml          # the orchestrator (infra only)
├── .env.example                # copy to .env to override
├── nginx/
│   └── default.conf            # virtual hosts + proxy_pass rules
├── keycloak/
│   ├── bootstrap.sh            # one-shot: seeds the zm-admin-cli admin client
│   └── realms/                 # drop exported realm JSON here for auto-import
└── postgres/
    └── init/
        └── 01-init.sql         # first boot — creates keycloak / ivy_events_db / iam_db
```

## Adding a database for a new project

Edit `postgres/init/01-init.sql`, uncomment the example block, set the name:

```sql
CREATE USER my_project WITH PASSWORD 'my_project';
CREATE DATABASE my_project_db OWNER my_project;
GRANT ALL PRIVILEGES ON DATABASE my_project_db TO my_project;
```

Then `docker compose down -v && docker compose up -d` (this wipes ALL Postgres data). Or `docker exec -it zm_postgres psql -U postgres` and run the SQL by hand if you don't want to lose state.

## Adding a new service

1. Append a service block to `docker-compose.yml`. Pin the major version (`redis:7-alpine`, not `latest`).
2. Add a volume if it has state.
3. Add port override to `.env.example`.
4. Update this README's service table.
5. If it needs a DB, add a `CREATE DATABASE` to `postgres/init/01-init.sql`.

## Troubleshooting

- **Port clash on 5432 / 8181 / etc.** — set a different port in `.env`, `docker compose up -d`.
- **Keycloak won't start** — usually Postgres healthcheck hasn't passed yet; `docker compose logs postgres` to check.
- **iam-service 401s against Keycloak** — the seeded admin client is missing or its secret drifted; re-run `docker compose up -d --force-recreate keycloak-bootstrap` to re-seed the `zm-admin-cli` secret, then check `docker compose logs keycloak-bootstrap`.
- **Kafka log corrupt** — `docker compose down -v` and restart. Local dev data is disposable.
- **Connect to Postgres** — `docker exec -it zm_postgres psql -U postgres -c "\l"` to list DBs.

## Memory budget

Full stack ≈ 2 GB. If you're not using something, stop just that piece:

```bash
docker compose stop kafka kafka-ui keycloak
```
