#!/usr/bin/env bash
# Launch github-mcp-server (stdio) against HUIT's GitHub Enterprise Server,
# authenticated with the OAuth token that `gh auth login` stored. No PAT.
#
# Invoked by Claude Code via .mcp.json ("github-huit"). stdout is the MCP
# protocol stream, so every diagnostic goes to stderr. Never print the token.
set -euo pipefail

GHES_HOST="${HUIT_GHES_HOST:-github.huit.harvard.edu}"

log() { printf 'github-huit: %s\n' "$*" >&2; }

# MCP servers are spawned with a minimal PATH on some setups; add the usual
# Homebrew / Linuxbrew / local bin dirs so the binary and gh are found.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$HOME/go/bin"

if ! command -v github-mcp-server >/dev/null 2>&1; then
  log "github-mcp-server not found on PATH. Install it (macOS/Linuxbrew: brew install github-mcp-server)"
  log "or run the github-setup skill in Claude Code: /huit-github:github-setup"
  exit 1
fi

# Token precedence:
#   1. GITHUB_PERSONAL_ACCESS_TOKEN already in the environment (explicit override)
#   2. gh's stored OAuth token for the GHES host (the intended path)
if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    log "gh is not installed. Install it (brew install gh) and run: gh auth login --hostname $GHES_HOST --web"
    exit 1
  fi
  if ! token="$(gh auth token --hostname "$GHES_HOST" 2>/dev/null)" || [[ -z "$token" ]]; then
    log "not logged in to $GHES_HOST. Run: gh auth login --hostname $GHES_HOST --web"
    exit 1
  fi
  export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
  unset token
fi

export GITHUB_HOST="https://$GHES_HOST"

exec github-mcp-server stdio "$@"
