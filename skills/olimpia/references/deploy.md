# Preparing apps for Olimpia

## Contents
- How builds work
- Per stack
- Monorepos
- Dockerfile builds
- Build-time and runtime variables
- Upload commands

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
