# Postgres, Redis and buckets

## Contents
- Connecting apps
- Postgres: ORMs, migrations and SQL
- Redis
- Buckets
- Public access from outside Olimpia

## Connecting apps

`connect_resource(app, kind, name)` (or `create_resource(..., connect_to_app=app)`) writes the variables into the app and redeploys:

| Kind | Variables |
| --- | --- |
| postgres | `DATABASE_URL` (change it with `env_key`) |
| redis | `REDIS_URL` |
| bucket | `AWS_ENDPOINT_URL_S3`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `BUCKET_NAME` |

These are internal URLs on Olimpia's private network: no TLS parameters needed, and they do not work from the user's machine. One app can use several resources; a resource can be shared by several apps.

## Postgres

- Version 18. User `app` owns the database `app` (not a superuser: no `CREATE EXTENSION` for untrusted extensions, no `ALTER SYSTEM`). Common trusted extensions such as `pgcrypto`, `citext` and `pg_trgm` work.
- Prisma: `DATABASE_URL` works as is. Run migrations at start (`"start": "prisma migrate deploy && node server.js"`): the build runs on separate machines and cannot reach the database.
- Drizzle, Knex, TypeORM, SQLAlchemy, Django, Ecto, sqlx: read `DATABASE_URL`; run migrations on start or as a release step in the start command.
- Inspect with `list_tables` and `query_postgres(database, sql)`: read mode accepts one SELECT/WITH/VALUES query and returns up to 200 rows as JSON.
- `query_postgres(..., write=true)` runs any statements separated by `;` in one transaction with a 30 s timeout, as the `app` role. Use it for quick fixes or seeding; prefer the app's migrations for schema changes. Ask the user before destructive statements.
- Olimpia keeps its own daily backups. To also get dumps in the user's own S3, the user configures it in the dashboard (Postgres → Backups).

## Redis

- Version 8, persisted to disk (AOF), no eviction: keys are never dropped, which suits queues (BullMQ, Sidekiq, Celery).
- User `default`; admin commands (`CONFIG`, `ACL`, `SHUTDOWN`) are disabled.
- Use `REDIS_URL` as is (`redis://default:...@host:6379`).

## Buckets

S3-compatible storage (Tigris). Each bucket has its own access key limited to it. Any S3 SDK works:

```js
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
const s3 = new S3Client({});
await s3.send(new PutObjectCommand({ Bucket: process.env.BUCKET_NAME, Key: "a.txt", Body: "hola" }));
```

The AWS SDKs read `AWS_ENDPOINT_URL_S3` and `AWS_REGION` (`auto`) automatically. For browser uploads, generate presigned URLs in the app. `set_public_access(kind=bucket, public=true)` makes objects readable by URL (`public_url` in `get_connection`).

## Public access from outside Olimpia

By default Postgres and Redis only accept connections from apps on Olimpia. To connect from a laptop, a BI tool or another cloud, ask the user, then `set_public_access(kind, name, public=true)` and use `public_url` from `get_connection`:

- Host `pg-<id>.db.olimpia.cc:5432` / `rd-<id>.db.olimpia.cc:6379`, TLS required with SNI.
- Postgres: `sslmode=require`, libpq 14 or newer (`psql`, recent drivers).
- Redis: `rediss://` scheme.

Turn it off again when it is no longer needed.
