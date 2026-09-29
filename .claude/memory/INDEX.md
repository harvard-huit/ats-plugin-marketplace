# Project memory index

Portable, project-scoped facts. Imported by CLAUDE.md. One line per memory.

- [GHES OAuth needs own app](ghes-oauth-needs-own-app.md) — github-mcp-server's built-in OAuth is github.com only; GHES would need an app registered on the instance, so the wrapper uses `gh`'s token
- [SessionStart hook output](session-start-hook-output.md) — plain stdout goes to Claude only; `systemMessage` JSON reaches the user; use `gh auth token` not `gh auth status` for a no-network check
- [Marketplace update vs plugin list](marketplace-update-vs-plugin-list.md) — desktop "check for updates" pulls the clone at `~/.claude/plugins/marketplaces/<name>` but the picker is stale until `/reload-plugins`; check the clone's `git log` before re-adding the marketplace
- [Harvard Slack Grid blocks AI apps](harvard-slack-grid-blocks-ai-apps.md) — internal app to `mcp.slack.com` rejected 2026-09-28: AI connectors banned Grid-wide and all `*:history` scopes unapproved; wait for the ISDP policy review, then use the official `slack` plugin, not a custom app (issue #2)
- [Redact token scripts when testing](redact-token-scripts-when-testing.md) — always pipe `gh auth token` / the headers helper through sed or `cut -c1-4`; empty `GH_CONFIG_DIR` is not a no-login test (leaked a PAT 2026-09-20)
