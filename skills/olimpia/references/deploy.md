# Preparing apps for Olimpia

## Contents
- How builds work
- Per stack
- Monorepos
- Dockerfile builds
- Build-time and runtime variables
- Upload commands
- Templates

## How builds work

Olimpia builds with [Railpack](https://railpack.com): it detects the language from the files at `root_dir`, installs dependencies, runs the build script and the start command. The image runs with the app env vars plus `PORT`. Builds have a 40 minute limit.

The process must:

- listen on `0.0.0.0` and the port in `$PORT` (default 3000, change it with `port` on `create_app`/`update_app` or `set_env PORT=...`);
- keep running in the foreground;
- write logs to stdout/stderr (they show up in `get_logs`);
- not rely on local disk for data: the filesystem is reset on every deploy. Use Postgres, Redis or a bucket.

## Per stack

**Node / Bun.** Railpack uses the lockfile to pick npm, pnpm, yarn or bun, runs the `build` script if present and starts with the `start` script. Make sure `start` exists and serves production (`next start`, `node dist/server.js`, `bun run src/index.ts`). Pin the version with `engines.node` or `.nvmrc` when it matters.

- Next.js: `"start": "next start -p ${PORT:-3000}"` or just `next start` (it reads `PORT`).
- Vite/React SPA without a server: Railpack serves `dist` as a static site; for client-side routing a `Caddyfile` or a small server is needed only if deep links 404.
- Express/Fastify/Hono: `app.listen(process.env.PORT || 3000, "0.0.0.0")`.

**Python.** Detected from `requirements.txt`, `pyproject.toml` (uv/poetry) or `Pipfile`. Provide a start command via `Procfile` (`web: uvicorn main:app --host 0.0.0.0 --port $PORT`) or a `[project.scripts]`/`main.py` Railpack recognizes. Django: `gunicorn project.wsgi --bind 0.0.0.0:$PORT`, run `collectstatic` in the build.

**Go.** `go.mod` at the root; the binary must read `PORT`.

**Rust.** `Cargo.toml`; release build, bind `0.0.0.0:$PORT`. Large builds take several minutes.

**PHP, Ruby, Java, Elixir, Deno, static sites** are also detected. A folder with only `index.html` is served as a static site.

When detection picks the wrong command, the `build_log_tail` shows Railpack's plan. Fix it with a `Procfile`, the `start` script, or a `railpack.json` (`{"deploy": {"startCommand": "..."}}`), or switch to a Dockerfile.

## Monorepos

Upload (or connect) the whole repository and set `root_dir` to the app folder, for example `apps/web`. Workspaces that need files outside `root_dir` (shared packages) build better with a Dockerfile at the repo root and `root_dir` empty.

## Dockerfile builds

Set `dockerfile` to its path relative to `root_dir` (for example `Dockerfile` or `docker/Dockerfile.prod`). The image must `EXPOSE`/listen on `$PORT`. Multi-stage builds are fine.

## Build-time and runtime variables

All app env vars are available both at build time and at runtime. The build runs on separate build machines, so it cannot reach Olimpia databases: run migrations and anything that needs the database when the app starts. Changes apply on the next deploy: `set_env(..., redeploy=true)` or `deploy(app)` without `source_key`.

Frameworks that inline variables at build time (`NEXT_PUBLIC_*`, `VITE_*`) need a new build after changing them.

## Upload commands

`create_app(source=upload)` and `get_upload_url` return:

- `command_git`: `git add -A && ref=$(git stash create) && git archive --format=tar.gz --prefix=src/ -o /tmp/olimpia-src.tar.gz "${ref:-HEAD}" && curl -fsS -X PUT -T /tmp/olimpia-src.tar.gz '<url>'`. It packs the working tree (committed and uncommitted tracked files, plus new files staged by `git add -A`) and respects `.gitignore`. It does not create commits or stashes.
- `command_tar`: packs the current folder excluding `node_modules`, `.git`, `.env*`, `.next`, `dist`, `build`, `target`, `.venv` and `__pycache__`.

Both produce a `.tar.gz` whose files sit under one top-level folder, which the builder requires. Run them from the folder you want to deploy (the repo root for monorepos). The limit is 300 MB. On Windows without a POSIX shell, use Git Bash or WSL.

## Templates

The catalog only has templates that run as a single app on Olimpia: the [Dokploy templates](https://github.com/Dokploy/templates) that fit (one web container that keeps its data in Postgres, Redis or nowhere) plus a few curated by Olimpia. `list_templates(search?)` lists them, or the ones whose name, description or tags match every word. `postgres`/`redis` say which databases `deploy_template` creates; they replace the ones the original compose file had, with the connection already in the env vars.

If a tool is not in the catalog, it usually needs a persistent disk, several containers, a custom command or mounted config files, which Olimpia apps do not support yet. Tell the user; `create_app(source="image")` only works when the image keeps its state in Postgres, Redis or a bucket and runs with its default command.

`deploy_template(template, name?, project?)`: `name` defaults to the template id and is also the subdomain and the name of its databases. Secrets are generated once per app (hex, base64, lowercase passwords or UUIDs, as the template expects). Read them with `get_env(app, reveal=true)` only when the user needs one, and never paste them in full in the chat. Initial admin users usually come from env vars such as `ADMIN_EMAIL`/`ADMIN_PASSWORD`; generated emails are `admin@example.com`.

After deploying, follow `get_deployment` until `active`, then `curl` the URL and read `get_logs`: some tools run migrations on the first boot and take a few minutes.

Curated templates:

| Template | Image | Port | Postgres | After deploying |
| --- | --- | --- | --- | --- |
| `n8n` | `n8nio/n8n:stable` | 5678 | yes | Open the URL and create the owner account. Webhooks use `N8N_WEBHOOK_URL`; binary data is stored in Postgres. Keep `N8N_ENCRYPTION_KEY`: losing it makes saved credentials unreadable. |
| `centrifugo` | `centrifugo/centrifugo:v6` | 8000 | no | Admin panel at the URL with `CENTRIFUGO_ADMIN_PASSWORD`. Backends publish with `CENTRIFUGO_HTTP_API_KEY` (`X-API-Key` header on `/api/*`); clients connect to `wss://<host>/connection/websocket` with a JWT signed with `CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY`. `CENTRIFUGO_CLIENT_ALLOWED_ORIGINS` is `*`; suggest restricting it to the user's frontend origin (space-separated list). |
| `umami` | `ghcr.io/umami-software/umami:3` | 3000 | yes | First login `admin` / `umami`: ask the user to change the password right away. |
| `metabase` | `metabase/metabase:latest` | 3000 | yes | The first boot runs migrations and takes a few minutes; `get_logs` shows progress. Then the setup wizard creates the admin. To query an Olimpia database from Metabase, use its internal host from `get_connection`. |

- Values are rendered once, when the app is created. If the subdomain changes later (`update_app`) or a custom domain becomes the main URL, update the variables that contain the old URL (`get_env` shows them) with `set_env(..., redeploy=true)`.
- `name_taken` means an app, or a database the template needs, already has that name in the project: pass another `name`.
