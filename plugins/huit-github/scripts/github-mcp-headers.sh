#!/usr/bin/env bash
# headersHelper for GitHub's hosted MCP server ("github" in .mcp.json).
#
# Claude Code runs this before each connection (and again after a 401/403) and
# reads a JSON object of HTTP headers from stdout. We hand it the OAuth token
# that `gh auth login --hostname github.com` stored in the keyring. No PAT.
#
# Why not the server's own OAuth via /mcp: GitHub's authorization server does
# not support Dynamic Client Registration (RFC 7591), which Claude Code's MCP
# OAuth flow requires, so /mcp fails with "Incompatible auth server: does not
# support dynamic client registration". Reusing gh's token avoids that and
# needs no OAuth app registration.
#
# stdout is parsed as JSON, so every diagnostic goes to stderr. The token must
# never appear anywhere except the JSON object on stdout.
set -euo pipefail

log() { printf 'github: %s\n' "$*" >&2; }

# Helpers may be spawned with a minimal PATH; add the usual gh locations.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin"

# Token precedence (same as scripts/github-mcp-ghes.sh):
#   1. GITHUB_PERSONAL_ACCESS_TOKEN already in the environment (explicit override)
#   2. gh's stored OAuth token for github.com (the intended path)
token="${GITHUB_PERSONAL_ACCESS_TOKEN:-}"
if [[ -z "$token" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    log "gh is not installed. Install it (brew install gh) and run: gh auth login --hostname github.com --web"
    exit 1
  fi
  if ! token="$(gh auth token --hostname github.com 2>/dev/null)" || [[ -z "$token" ]]; then
    log "not logged in to github.com. Run: gh auth login --hostname github.com --web (or /huit-github:github-setup)"
    exit 1
  fi
fi

# GitHub tokens are [A-Za-z0-9_]+, so no JSON escaping is needed. Refuse
# anything else rather than emit malformed JSON.
case "$token" in
  *[!A-Za-z0-9_]*) log "token contains unexpected characters; refusing to emit it"; exit 1 ;;
esac

printf '{"Authorization":"Bearer %s"}\n' "$token"
