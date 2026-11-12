# Headless access (CI, scripts, agents without OAuth)

## Personal tokens

The user creates a token in the dashboard: Account → Agents & tokens → Create token. It starts with `olimpia_pat_`, has the same permissions as the account and expires 90 days after it is created: calls then answer `401` and the user has to create a new one and update the secret. Store it as a secret (for example `OLIMPIA_TOKEN` in CI). Tokens can only be created and revoked from the dashboard, up to 50 per account.

## MCP with a token

Any MCP client that supports headers can skip OAuth:

```json
{
  "mcpServers": {
    "olimpia": {
      "type": "http",
      "url": "https://api.olimpia.dev/mcp",
      "headers": { "Authorization": "Bearer ${OLIMPIA_TOKEN}" }
    }
  }
}
```

## REST API

Base URL `https://api.olimpia.dev`, header `Authorization: Bearer $OLIMPIA_TOKEN`, JSON bodies. Errors come as `{"error": "<code>"}`, some with a `message`. The limits of the MCP server apply here too: 20 apps per account (`app_limit`) and 30 creations per hour (`too_many_creates`).

| Action | Request |
| --- | --- |
| Projects | `GET /projects` (one row per environment: `slug` is `shop` for production or `shop.staging`, `parent_id` points to production) |
| New environment | `POST /projects/<project_id>/environments` with `{"name": "staging", "copy": true}` (copies from `<project_id>`) |
| Apps of a project | `GET /apps?project=<project_id>` (the id of the environment) |
| App detail | `GET /apps/<app_id>` |
| Upload URL | `POST /apps/<app_id>/source` → `{key, upload_url}` |
| Deploy | `POST /apps/<app_id>/deployments` with `{"source": "<key>", "message": "..."}` (`{}` rebuilds) |
| Deployments | `GET /apps/<app_id>/deployments` |
| Build log | `GET /apps/<app_id>/deployments/<deployment_id>/log?offset=0` |
| Env vars | `GET` / `PUT /apps/<app_id>/env` with `{"vars": [{"key": "...", "value": "..."}]}` (PUT replaces all), or `PATCH` with `{"set": {"KEY": "value"}, "remove": ["OLD"]}` to merge |

## Deploy from GitHub Actions

```yaml
name: Deploy to Olimpia
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Upload and deploy
        env:
          OLIMPIA_TOKEN: ${{ secrets.OLIMPIA_TOKEN }}
          APP_ID: ${{ vars.OLIMPIA_APP_ID }}
        run: |
          api=https://api.olimpia.dev
          auth="Authorization: Bearer $OLIMPIA_TOKEN"
          upload=$(curl -fsS -X POST -H "$auth" "$api/apps/$APP_ID/source")
          git archive --format=tar.gz --prefix=src/ -o /tmp/src.tar.gz HEAD
          curl -fsS -X PUT -T /tmp/src.tar.gz "$(echo "$upload" | jq -r .upload_url)"
          curl -fsS -X POST -H "$auth" -H 'content-type: application/json' \
            -d "{\"source\": \"$(echo "$upload" | jq -r .key)\", \"message\": \"$GITHUB_SHA\"}" \
            "$api/apps/$APP_ID/deployments" > /dev/null
```

The app must have been created with `source=upload`. Apps connected to GitHub redeploy on push by themselves and do not need this.
