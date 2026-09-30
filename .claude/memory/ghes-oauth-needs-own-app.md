---
name: ghes-oauth-needs-own-app
description: Why the GHES MCP path uses gh's token instead of github-mcp-server's built-in OAuth login
metadata:
  type: project
---

`github-mcp-server`'s local OAuth login (browser flow with device-code fallback,
token kept in memory) only works out of the box for github.com, because the
official builds embed a github.com OAuth app. For GitHub Enterprise Server it
needs an OAuth App or GitHub App registered on that GHES instance, with its
client ID passed via `GITHUB_OAUTH_CLIENT_ID` / `--oauth-client-id` and the
callback URL registered on the same host. Confirmed 2026-09-19 from
github/github-mcp-server `docs/oauth-login.md`.

**Why:** registering an app on github.huit.harvard.edu is an admin ask we want
to avoid. `gh auth login --hostname <ghes> --web` already gives an OAuth token
with no admin involvement.

**How to apply:** keep `scripts/github-mcp-ghes.sh` reading the token from
`gh auth token --hostname github.huit.harvard.edu` and exporting it as
`GITHUB_PERSONAL_ACCESS_TOKEN` (the binary's only token input; a set value
bypasses OAuth). Revisit only if HUIT registers an OAuth App on GHES. See
[[huit-github-enterprise-api]] for the classic-PAT Bearer 401 gotcha, which is
still unverified for `gh` OAuth tokens and for the binary.
