-- ============================================================================
-- zm-local-setup — Postgres init
-- Runs once, on first boot, when the pg_data volume is empty.
-- To rerun: docker compose down -v  (DESTROYS DATA)  then  docker compose up -d
--
-- One database per service (platform rule: no service shares another's DB).
-- ============================================================================

-- Keycloak ------------------------------------------------------------------
CREATE USER keycloak WITH PASSWORD 'keycloak';
CREATE DATABASE keycloak OWNER keycloak;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;

-- ivy-events-be -------------------------------------------------------------
-- The local profile connects as the postgres super-user, so the DB just has
-- to exist. Owned by postgres for simplicity in local dev.
CREATE DATABASE ivy_events_db OWNER postgres;

-- zm-iam-service ------------------------------------------------------------
CREATE USER iam_user WITH PASSWORD 'iam_pass';
CREATE DATABASE iam_db OWNER iam_user;
GRANT ALL PRIVILEGES ON DATABASE iam_db TO iam_user;

-- zm-organization-service ---------------------------------------------------
CREATE USER org_user WITH PASSWORD 'org_pass';
CREATE DATABASE org_db OWNER org_user;
GRANT ALL PRIVILEGES ON DATABASE org_db TO org_user;

-- zm-menu-service -----------------------------------------------------------
CREATE USER menu_user WITH PASSWORD 'menu_pass';
CREATE DATABASE menu_db OWNER menu_user;
GRANT ALL PRIVILEGES ON DATABASE menu_db TO menu_user;
