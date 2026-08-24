# zm-local-setup

The whole ZM stack, locally, in one command. Infrastructure **and** every service
— you do not need a JDK, a Node install, or an IDE run configuration to see the
product working. Compilation happens inside the images, so the host's Java
version is irrelevant.

```bash
cd zm-local-setup
docker compose up -d --build     # first time, or after pulling code
docker compose ps                # watch it come up
```

First build is slow (five Java services and two frontends compile from source,
roughly 10–15 minutes on a cold cache). After that a restart is seconds, and
only the services whose source changed rebuild.

Open **http://localhost:5173**.

## What you get

| What | URL | Notes |
|------|-----|-------|
| **Ivy Events (web)** | http://localhost:5173 | the app you actually test |
| Ivy Events (API) | http://localhost:8081 | |
| Restaurant menus (web) | http://localhost:5174 | separate product |
| Restaurant menus (API) | http://localhost:8585 | |
| zm-iam-service | http://localhost:8282 | login, registration, password reset |
| zm-organization-service | http://localhost:8484 | organizations, collaborator invites |
| zm-notification-service | http://localhost:8384 | consumes email events off Kafka |
| Keycloak | http://localhost:8181 | `admin` / `admin` |
| Kafka UI | http://localhost:8090 | inspect the event topics |
| Postgres | localhost:5432 | `postgres` / `postgres` |
| Redis | localhost:6379 | seating edit locks |
| nginx | http://localhost | optional edge, proxies `/api` |

One database per service — the platform rule that no service reads another's:

| Database | Owner | Used by |
|----------|-------|---------|
| `keycloak` | keycloak / keycloak | Keycloak |
| `ivy_events_db` | postgres / postgres | ivy-events-be |
| `iam_db` | iam_user / iam_pass | zm-iam-service |
| `org_db` | org_user / org_pass | zm-organization-service |
| `menu_db` | menu_user / menu_pass | zm-menu-service |

## Prerequisites

- Docker Desktop (or Docker Engine + Compose v2), ~6 GB free for images
- Ports `80, 443, 5173, 5174, 5432, 6379, 8081, 8090, 8181, 8282, 8384, 8484, 8585, 9092, 9093` free.
  Every one of them is overridable in `.env` — see `.env.example`.

## Signing in

Registration goes through zm-iam-service, so **use the app's own signup form**
rather than creating a user in the Keycloak console. A user created by hand in
Keycloak has no organization and no roles, and lands in a dashboard that
refuses almost everything with a 403 that looks like a bug.

`create-test-user.ps1` and `get-token.ps1` in this directory do the same thing
from a terminal when you need a token for curl.

### To test the agency side (CRM, proposals, branding, profitability)

A self-registered account has **no organization**, and everything under
`/v1/api/crm/*` is scoped to one — so the pipeline, proposals and agency
settings all return 403 until the account has an `orgId`. That is the design,
not a fault: the organization is read from the token and never from the request,
which is the only reason one agency cannot open another's pipeline.

```powershell
.\make-agency-admin.ps1 -Email you@example.com
```

Then **sign out and back in** — the claims live in the token, so an old one in
localStorage keeps every 403 it had. Pass `-OrgId <uuid>` to put several
accounts in the same agency, which is what makes a colleague's leads visible.

The script also grants `ORG_ADMIN`, without which the profitability panel stays
refused. See the roles note above for why.

### Roles worth knowing

Four realm roles, and two of them are easy to confuse:

- **`ADMIN`** — *Ivy's* administrator, i.e. us. Not a customer.
- **`ORGANIZER`** — any user of a customer organization, including junior staff.
- **`ORG_ADMIN`** — who runs that organization. Required for the agency's money:
  `/v1/api/crm/agency/profitability` refuses a plain ORGANIZER by design, so if
  the profitability panel 403s, that is the feature and not a fault. Grant the
  role in Keycloak (realm `event-app` → the user → Role mapping) to see it.
- **`VENDOR`** — a supplier with a marketplace profile.

## Stop / reset

```bash
docker compose stop         # pause, state preserved
docker compose down         # remove containers, volumes survive
docker compose down -v      # ALSO wipe volumes — databases, Kafka, uploads
```

`down -v` is the reset that actually resets: Postgres re-runs `init/01-init.sql`
and every service re-applies its migrations from scratch.

## Rebuilding one service

```bash
docker compose up -d --build ivy-events-be
docker compose logs -f ivy-events-be
```

## What's where

```
zm-local-setup/
├── docker-compose.yml          # infrastructure AND services
├── docker-compose.droplet.yml  # the deployed variant — do not run locally
├── .env.example                # copy to .env to override ports and secrets
├── docker/
│   └── ivy-events-be.Dockerfile  # builds BE + its private provisioning client
├── nginx/default.conf
├── keycloak/
│   ├── bootstrap.sh            # one-shot: seeds the zm-admin-cli admin client
│   └── realms/                 # exported realm JSON, auto-imported
└── postgres/init/01-init.sql   # first boot only — creates the databases
```

**`keycloak-bootstrap`** is a one-shot container that seeds a confidential admin
client `zm-admin-cli` (secret `zm-admin-secret`) into the `master` realm. Every
backend waits for it to exit successfully — that exit is the readiness gate, not
Keycloak's own port being open.

## Adding a database for a new service

`postgres/init/01-init.sql` runs **only on an empty volume**, so adding a line
there does nothing on a machine that has already run this stack. Add an
idempotent bootstrap container instead — copy the `org-db-bootstrap` block; it
is safe to re-run and nobody has to destroy their data to gain a database.

## Troubleshooting

- **Port clash** — set the port in `.env` and `docker compose up -d`. The table
  above lists every published port.
- **The first build looks hung** — it is compiling. `docker compose logs -f`
  shows which service.
- **Keycloak won't start** — Postgres healthcheck has not passed yet;
  `docker compose logs postgres`.
- **iam-service 401s against Keycloak** — the seeded admin client drifted:
  `docker compose up -d --force-recreate keycloak-bootstrap`, then check its logs.
- **"The iss claim is not valid"** — something minted a token against
  `keycloak:8080` instead of `localhost:8181`. `KC_HOSTNAME_URL` pins the issuer
  so both agree; if you changed it, change it back.
- **Everything 403s after signing in** — the account has no organization. Sign
  up through the app rather than through the Keycloak console.
- **Seating locks do nothing** — two people can drag the same plan when Redis is
  absent; the service degrades rather than failing. Check `docker compose ps redis`
  and that `REDIS_HOST=redis` is still on ivy-events-be.
- **Canonical URLs say ivyevents.mk** — `PUBLIC_BASE_URL` is unset. Every SEO tag
  and the sitemap are built from it, and it is only visible in page source.
- **Kafka log corrupt** — `docker compose down -v`. Local event data is disposable.
- **Connect to Postgres** — `docker exec -it zm_postgres psql -U postgres -c "\l"`.

## Memory budget

The full stack is roughly 4 GB with every service running. Stop what you are not
testing:

```bash
docker compose stop zm-menu-service zm-menu-fe kafka-ui nginx
```

Ivy needs postgres, keycloak, redis, kafka, zm-iam-service,
zm-organization-service, ivy-events-be and ivy-events-fe. The menu product and
Kafka UI are independent of it.
