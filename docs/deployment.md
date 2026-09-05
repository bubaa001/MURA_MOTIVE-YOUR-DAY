# MURA Backend — Deployment Guide

The backend is a standard Django 6 / DRF API served by gunicorn. It ships:

- `backend/Dockerfile` — python:3.14-slim + gunicorn; works unchanged on
  Railway, Render, and Fly.io (all three build arbitrary Dockerfiles).
- `backend/docker-compose.yml` — self-contained stack for local/self-hosted
  runs: PostgreSQL 17 + one-shot migrate + web.
- All configuration is environment-driven from `config/settings.py`; no
  settings changes are required to deploy.

## Environment variables

Every value below is read by `config/settings.py` at process start.

| Variable | Default (dev) | Production guidance |
|---|---|---|
| `SECRET_KEY` | `dev-only-insecure-key-change-me` | **Required.** 50+ random chars (`python -c "import secrets; print(secrets.token_urlsafe(64)"`). Rotating it invalidates sessions/JWT signing state. |
| `DEBUG` | `true` | **Must be `false`.** Debug pages leak settings and stack traces. |
| `ALLOWED_HOSTS` | `127.0.0.1,localhost,testserver` | Comma-separated exact hostnames of the deployed domain, e.g. `api.mura.app`. No wildcards in production. |
| `TIMEZONE` | `UTC` | IANA name (e.g. `America/New_York`). Stored timestamps are UTC regardless; this affects display/forms only. |
| `DB_ENGINE` | *(empty → SQLite)* | Set to `postgresql` to activate the Postgres branch. Never run SQLite in production (ephemeral containers lose it). |
| `DB_NAME` | `mura` | Managed-Postgres database name. |
| `DB_USER` | `postgres` | Least-privilege app role. |
| `DB_PASSWORD` | *(empty)* | Store as a platform secret, never in the repo. |
| `DB_HOST` | `127.0.0.1` | Internal DB hostname (compose: `db`; platforms provide their own). |
| `DB_PORT` | `5432` | Usually default. |
| `CORS_ALLOW_ALL` | `true` | **Set `false` in production** and restrict origins — see security checklist. |

### JWT note

Auth uses SimpleJWT with access tokens living **1 day** and refresh tokens
**30 days**, rotation enabled (`SIMPLE_JWT` in `config/settings.py`). The
`token_blacklist` app is *not* installed, so rotated refresh tokens are not
revocable server-side — a leaked refresh token stays valid until expiry. If
that risk profile is unacceptable, enable blacklisting in settings before
going to public production (documented follow-up, not a deployment blocker).

## First-deploy checklist

Run these against the production database (via platform shell/SSH or
`docker compose run --rm web …` locally against the prod DB):

1. **Migrations**
   ```bash
   docker compose run --rm migrate          # compose path
   # or: python manage.py migrate --noinput
   ```
2. **Personal account + starter content** (idempotent; creates the login user
   and seeds the content hub plus demo habits/priorities/reminders):
   ```bash
   python manage.py bootstrap_dev --username <real> --password <real>
   ```
   Use real credentials here — this becomes your API login. Re-running with
   the same username updates nothing harmful (user is kept, demo data only
   fills gaps).
3. **Django admin superuser** (separate from the API account; used for
   `/admin/` content management):
   ```bash
   python manage.py createsuperuser --username admin --email <real>
   ```
4. **Content top-up** (also idempotent; safe to re-run after adding entries
   to `content/management/commands/seed_content.py`):
   ```bash
   python manage.py seed_content
   ```
5. Static assets if the build-time collectstatic was skipped:
   ```bash
   python manage.py collectstatic --noinput
   ```

## Platform notes

All three platforms deploy the existing `backend/Dockerfile` directly — set
the build context / root directory to `backend/`.

### Railway

- New service → Deploy from repo, **Root Directory = backend**; Railway
  auto-detects the Dockerfile.
- Add the Postgres plugin; its `DATABASE_*` variables map to
  `DB_NAME/DB_USER/DB_PASSWORD/DB_HOST/DB_PORT` (set `DB_ENGINE=postgresql`).
- Attach a volume mounted at `/app/media` for uploads. `PORT` is injected and
  the Dockerfile CMD honors it.

### Render

- New Web Service → **Existing image / Docker** runtime, Root Directory =
  `backend`.
- Create a Render PostgreSQL instance; copy its internal connection values
  into the env vars above.
- Add a persistent **Disk** mounted at `/app/media`. Optionally add a deploy
  hook running `python manage.py migrate --noinput && seed_content`.
- Health check path: any cheap authenticated-safe route, e.g. `/admin/login/`.

### Fly.io

- From `backend/`: `fly launch --no-deploy`, accept the detected Dockerfile;
  `fly deploy` afterwards.
- Postgres: `fly postgres create` then `fly postgres attach <app-db>`
  (sets `DATABASE_URL` — translate into `DB_*` vars), or point at any
  external managed Postgres.
- Persistent media: `fly volumes create mura_media --size 1` and declare
  ```toml
  [mounts]
    source = "mura_media"
    destination = "/app/media"
  ```
- Secrets: `fly secrets set SECRET_KEY=… DEBUG=false ALLOWED_HOSTS=mura.fly.dev CORS_ALLOW_ALL=false DB_ENGINE=postgresql …`

## Production security checklist

- [ ] `DEBUG=false`.
- [ ] Strong random `SECRET_KEY`, stored in platform secret manager.
- [ ] `ALLOWED_HOSTS` pinned to exact production hostnames.
- [ ] `CORS_ALLOW_ALL=false` + explicit origin allow-list — **requires a small
      settings change first**: replace `CORS_ALLOW_ALL_ORIGINS` usage with an
      env-driven `CORS_ALLOWED_ORIGINS` list (see "Known settings gaps").
- [ ] HTTPS everywhere: terminate TLS at the platform edge; then add HSTS +
      secure-cookie flags (`SECURE_SSL_REDIRECT`, `SECURE_HSTS_SECONDS`,
      `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`) — currently not
      env-driven, listed under known gaps.
- [ ] PostgreSQL backups: enable daily automated snapshots on the managed DB,
      verify a restore quarterly; self-hosted, cron `pg_dump` off-box plus the
      named volume `pgdata` snapshot.
- [ ] Media persistence: attach the platform volume/disk at `/app/media`;
      include it in backup scope (photos live there).
- [ ] Run migrations via the one-shot service/deploy hook only — never let two
      deploys race `migrate`.

## Known settings gaps (document-only, no code changed)

These do not block deploying this Dockerfile but should be addressed in
`config/settings.py` later:

1. **Static/media serving under gunicorn:** Django only serves `staticfiles`
   and `media` when `DEBUG=true`. In production add WhiteNoise (static) and an
   object store or CDN-backed media URL, or put a reverse proxy in front.
2. **Explicit CORS origins:** only the `CORS_ALLOW_ALL` kill-switch is
   env-driven; `CORS_ALLOWED_ORIGINS` has no env plumbing yet.
3. **TLS/HSTS/security-header flags** are not configurable via env yet.
4. **JWT revocation:** `token_blacklist` app absent (see JWT note above);
   token lifetimes are also hardcoded rather than env-tunable.
5. **Connection pooling/TLS to Postgres:** no `CONN_MAX_AGE` or `sslmode=require`
   option is exposed for the DATABASES block.
