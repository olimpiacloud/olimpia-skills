<p align="center">
  <img src="assets/logo.png" width="96" alt="Olimpia">
</p>

<h1 align="center">Olimpia for agents</h1>

<p align="center">
  The official skill and plugin to deploy and operate <a href="https://olimpia.dev">Olimpia</a> from Claude Code, Codex, Cursor and any agent that speaks MCP.
</p>

---

[Olimpia](https://olimpia.dev) is a cloud platform from Buenos Aires: app hosting, managed Postgres and Redis, and S3-compatible buckets, grouped in projects. This repository gives your agent two things:

- **The Olimpia MCP server** (`https://api.olimpia.dev/mcp`): tools to create apps, upload and deploy code, set env vars, create and connect databases, run SQL, add domains and read logs. It signs in with OAuth the first time.
- **The `olimpia` skill**: the workflows and the details agents get wrong otherwise, like binding to `$PORT`, uploading a folder, connecting a database and fixing failed builds.

## Install

**Claude Code** (plugin: skill and MCP server together)

```
/plugin marketplace add olimpiacloud/olimpia-skills
/plugin install olimpia@olimpia
```

Then ask Claude to connect to Olimpia: it gives you a link, you authorize on olimpia.dev and paste the 8-character code back into the chat. It works the same on your laptop and on a remote machine (a VPS over SSH, a container), with no browser needed where the agent runs.

**Any agent with skills support** (Claude Code, Codex, Cursor, OpenCode, Gemini CLI and others)

```bash
bunx skills add olimpiacloud/olimpia-skills
```

and add the MCP server to your client:

| Client | Command or config |
| --- | --- |
| Claude Code (without the plugin) | `claude mcp add --transport http olimpia https://api.olimpia.dev/mcp`; on a remote machine `claude mcp login olimpia --no-browser` |
| Codex | `codex mcp add olimpia --url https://api.olimpia.dev/mcp` |
| Cursor, VS Code, Windsurf | `{"mcpServers": {"olimpia": {"url": "https://api.olimpia.dev/mcp"}}}` |
| claude.ai, ChatGPT | Add a custom connector with the URL `https://api.olimpia.dev/mcp` |

**CI and scripts**: create a personal token in Account → Agents & tokens and send it as `Authorization: Bearer`. See [skills/olimpia/references/api.md](skills/olimpia/references/api.md).

## Try it

> Deploy this folder to Olimpia with a Postgres database.

> The last deploy of `web` failed, find out why and fix it.

> Point app.mycompany.com to the `web` app.

## What's inside

```
.claude-plugin/        plugin and marketplace manifests
.mcp.json              the remote Olimpia MCP server, authenticated by scripts/headers.sh
scripts/headers.sh     creates this agent's credential (never shown) and sends it to Olimpia
skills/olimpia/
  SKILL.md             resource model, tools by intent, workflows and rules
  references/
    deploy.md          preparing apps per stack, monorepos, Dockerfiles, uploads
    data.md            Postgres, Redis and buckets: connecting, ORMs, SQL, backups, public access
    troubleshooting.md failed deployments and apps that don't respond
    api.md             personal tokens, REST API, GitHub Actions
```

## Safety

The agent acts with your account's permissions. Delete tools require the exact resource name as confirmation, secrets are hidden unless explicitly requested, and you can revoke any connected agent from Account → Agents & tokens.

## Links

- Website: https://olimpia.dev
- For LLMs: https://olimpia.dev/llms.txt
- Contact: hola@olimpia.dev

## License

MIT
