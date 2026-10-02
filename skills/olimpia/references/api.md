# Headless access (CI, scripts, agents without OAuth)

## Personal tokens

The user creates a token in the dashboard: Account → Agents & tokens → Create token. It starts with `olimpia_pat_` and has the same permissions as the account. Store it as a secret (for example `OLIMPIA_TOKEN` in CI).

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

Base URL `https://api.olimpia.dev`, header `Authorization: Bearer $OLIMPIA_TOKEN`, JSON bodies. Errors come as `{"error": "<code>"}`.

| Action | Request |
| --- | --- |
| Projects | `GET /projects` |
| Apps of a project | `GET /apps?project=<project_id>` |
| App detail | `GET /apps/<app_id>` |
| Upload URL | `POST /apps/<app_id>/source` → `{key, upload_url}` |
| Deploy | `POST /apps/<app_id>/deployments` with `{"source": "<key>", "message": "..."}` (`{}` rebuilds) |
| Deployments | `GET /apps/<app_id>/deployments` |
| Build log | `GET /apps/<app_id>/deployments/<deployment_id>/log?offset=0` |
| Env vars | `GET` / `PUT /apps/<app_id>/env` with `{"vars": [{"key": "...", "value": "..."}]}` (PUT replaces all) |

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
