# Troubleshooting deployments

## Contents
- By error
- Build failures
- Runtime failures
- Limits
- Tool errors
- The Olimpia page instead of the app
- Domains

Start with `get_deployment(app)` (latest) and read `status`, `error` and `build_log_tail`.

## By error

| `error` | Meaning | What to do |
| --- | --- | --- |
| `source_failed` | The code could not be fetched. | Upload: the `source_key` expired or was never uploaded; get a new URL, upload, deploy. GitHub: the repo or branch is no longer accessible to the Olimpia GitHub App, or the branch does not exist. |
| `build_failed` | Railpack or the Dockerfile build failed. | Read `build_log_tail`. See "Build failures". |
| `import_failed` | The built image could not be stored. | Platform side: deploy again; if it repeats, tell the user to write to hola@olimpia.dev. |
| `release_failed` | The new container exited, kept restarting or never stayed up. | Usually the start command exits immediately or a variable is missing. Olimpia undoes the release: the previous version keeps serving (a first deploy is left with nothing live). Check `get_logs(app, since="15m")`, fix and deploy again. |
| `internal_error` | Platform error. | Retry once with `deploy(app)`. |

## Build failures

- **No start command / could not determine how to build**: add a `start` script, a `Procfile` or a `railpack.json`, or set `root_dir` for monorepos. See [deploy.md](deploy.md).
- **Lockfile mismatch** (`npm ci`, `pnpm install --frozen-lockfile`, `bun install --frozen-lockfile`): regenerate the lockfile locally, then upload again.
- **TypeScript or lint errors during `build`**: fix them in the code; the build runs in production mode.
- **Missing env var at build time** (for example `NEXT_PUBLIC_*`, or code that reads env vars while building): `set_env`, then deploy.
- **Out of memory / killed**: reduce build parallelism or use a multi-stage Dockerfile.
- **Native modules** (`sharp`, `bcrypt`, `canvas`): usually fine with Railpack; if not, use a Dockerfile based on a full Debian image.

## Runtime failures (status `active` but the app does not work)

`active` only means the container started. Check:

1. `curl -sS -i <url>`.
2. `get_logs(app)`: `since` is `15m`, `1h` (default), `24h` or `7d`, and `limit` up to 500 lines (default 100). Omit `app` to read every live app of the project together. A stack trace comes as one entry, and runs of the same pattern are summarized. If `covered_from` is present, that app wrote more than the 2000 lines read and older lines of the window were not searched.

`query` narrows it; terms are separated by spaces and all must match:

| Term | Matches |
| --- | --- |
| `level:error`, `level:error,warn` | A level (`error`, `warn`, `info`, `debug`); a comma means OR. |
| `service:api` | One app, when reading the whole project. |
| `http.status_code:>=500`, `duration_ms:>1000` | Any attribute parsed from JSON, logfmt or access logs, compared as a number with `>`, `>=`, `<`, `<=`. |
| `http.route:/api/*` | A prefix. |
| `timeout`, `"connection refused"`, `error:"unexpected token"` | Words or quoted phrases in the raw line, or a quoted attribute value. |
| `-healthcheck`, `-level:debug` | A leading `-` excludes. |
| `pattern:<hash>` | Every line of one pattern from `top_patterns`. |

`around=<timestamp of a line>` returns the lines just before and after that moment instead of the newest ones.

Common causes:

- **Bad gateway / no response**: the app listens on `localhost` or a fixed port instead of `0.0.0.0:$PORT`. Fix the code or set `port` to the real one with `update_app` (or `set_env PORT=...`), then deploy.
- **Crash loop**: missing env var or database. `get_env`, then `set_env` / `connect_resource`. A crashed app is restarted automatically after a few seconds. If the logs stop without an error and the boot messages show up again, see "Limits".
- **Database connection refused**: using a public URL or `localhost` instead of the internal `DATABASE_URL`; or migrations not run.
- **404 on deep links in an SPA**: serve `index.html` as the fallback.

## Limits

Every app and database runs with fixed limits; they cannot be raised, so the fix is in the app.

- **App killed for memory** (4 GiB, no swap): the process dies without a stack trace (at most a `Killed` line) and the app boots again a few seconds later. Stream large files and query results instead of loading them, lower the worker or thread count, cap the runtime heap (`NODE_OPTIONS=--max-old-space-size=3072`), or move heavy jobs to another app.
- **CPU** (4 CPUs): the app is slowed down, not killed. Look for slow requests with `duration_ms:>1000`.
- **Processes** (2,048 processes and threads): `fork: Resource temporarily unavailable` or `can't start new thread`. Lower the worker count and reuse thread pools.
- **Disk**: an app that writes more than 5 GiB to its own filesystem is restarted with a clean one, and every deploy resets it too. Store files in a bucket and rotate or drop temporary files.
- **Network**: raw sockets are not available, so `ping` fails from an app; test connectivity with TCP or HTTP.
- **Postgres** (8 GiB, 4 CPUs): `too many connections for role "app"` means the pools of the apps add up to more than 20; see [data.md](data.md#postgres).
- **Redis** (2 GiB, 2 CPUs): `OOM command not allowed when used memory > 'maxmemory'` means it holds 1 GB of data; delete keys or add TTLs, since nothing is evicted.

## Tool errors

| Error | What to do |
| --- | --- |
| `app_limit` | The account already has 20 apps (copies made by `create_environment` count). Ask the user which one to delete. |
| `environment_limit` | The project already has 5 environments. |
| `too_many_creates` | More than 30 apps, databases, buckets, email domains, projects or environments were created in the last hour. Wait; do not retry in a loop. |
| `too_many_requests` | Rate limited: 240 tool calls per minute per agent (wait a minute), `run_backup` once every 10 minutes per database. |
| `network_pending`, `server_unavailable`, `database_unreachable` | The platform or the database is still getting ready. Retry in a minute. |
| `name_taken` | If an earlier call already created it, use that one instead of creating it again. |
| `confirmation_required` | Ask the user, then repeat the call with the `confirm` value from the message. |

## The Olimpia page instead of the app

A page from Olimpia on `*.olimpia.cc` means there is no live deployment for that subdomain yet, or the subdomain changed. `get_app` shows the current `url`.

## Domains

`check_domain` reports `verified`, `errors` and the expected `dns_records`. A new domain needs both records: the TXT at `_olimpia.<domain>` proves ownership (until then nothing is routed, and after 7 days unverified the domain is removed: add it again) and the CNAME routes the traffic. DNS changes can take minutes. A CNAME at the root of a domain needs CNAME flattening or ALIAS support at the DNS provider. `domain_taken` means the hostname is already attached to an app.
