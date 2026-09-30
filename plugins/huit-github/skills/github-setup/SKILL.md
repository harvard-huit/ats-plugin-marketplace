---
name: github-setup
description: Set up GitHub access for AAIS / HUIT in Claude Code without a Personal Access Token. Installs gh and the GitHub MCP server binary, runs gh device-flow login for github.com and/or github.huit.harvard.edu, and optionally adds a narrow read-only gh allowlist. Both MCP servers (github, github-huit) authenticate with gh's stored OAuth token, so no /mcp login is needed. Use when the user asks to set up, connect, log in to, or fix GitHub access, when a github MCP server shows as disconnected or failed, when /mcp reports "does not support dynamic client registration", or when gh reports no login.
---

# GitHub setup (HUIT)

You are walking one person through connecting Claude Code to GitHub. The goal is
**zero Personal Access Tokens**. Every credential comes from an OAuth login the
person completes in their browser. You cannot install or log in on their behalf:
propose each command, explain what it does in one line, and let them approve it.

Two GitHubs are in play. Ask which the person needs before installing anything.

| Host | Org | How Claude reaches it | Auth |
|---|---|---|---|
| github.com | `harvard-huit` (SAML SSO) | GitHub's hosted MCP server (`github`), token supplied by `bin/github-mcp-headers.sh` | `gh auth login` device flow |
| github.huit.harvard.edu (GHES) | `HUIT` | local `github-mcp-server` behind `bin/github-mcp-ghes.sh` (`github-huit`) | `gh auth login` device flow |

Both MCP servers read the token `gh` stored, so the `gh` login is the whole
authentication story. Do **not** send the person to `/mcp` to log in to
`github`: GitHub's authorization server has no Dynamic Client Registration, so
that flow fails with "Incompatible auth server: does not support dynamic
client registration". `gh` is the fallback for both hosts when MCP tools are
unavailable.

## 1. Inventory first

Run these read-only checks and summarize the result in a few lines. Do not skip
steps the person already completed.

```sh
command -v gh && gh --version | head -1
command -v github-mcp-server || ls ~/.local/bin/github-mcp-server 2>/dev/null
env | grep -E '^(GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN)=' | cut -d= -f1
gh auth token --hostname github.com >/dev/null 2>&1 && echo "github.com: logged in" || echo "github.com: no login"
gh auth token --hostname github.huit.harvard.edu >/dev/null 2>&1 && echo "GHES: logged in" || echo "GHES: no login"
uname -s
```

The `env | grep` line prints only variable **names**. If it prints anything,
the person has a token exported in their shell, and `gh auth token` returns
that instead of the keyring login, so "logged in" may really mean "has a PAT
in the environment". Tell them, and never print or echo the value. The
`~/.local/bin` check matters because the release-binary install (step 3) puts
the binary there, which is often not on the interactive shell's PATH even
though the wrapper adds it.

Also check whether the `github` and `github-huit` MCP servers are currently
connected (their tools appear in your tool list, or `/mcp` lists them). If the
tools are present, that host is done.

Then ask: **github.com, GHES, or both?** Only do the steps for what they need.

## 2. Install `gh` (both hosts)

Skip if present.

- macOS: `brew install gh`
- Debian/Ubuntu: follow https://github.com/cli/cli/blob/trunk/docs/install_linux.md (apt repo), or `sudo apt install gh` if their distro already ships it
- Fedora/RHEL: `sudo dnf install gh`
- Anything else: https://cli.github.com

## 3. Install `github-mcp-server` (GHES only)

Skip unless they need GHES. The remote github.com server needs no binary.

- Homebrew (macOS or Linuxbrew): `brew install github-mcp-server`. On a macOS
  version Homebrew no longer supports (Tier 3, for example macOS 14) there is
  no bottle and the command exits without installing anything. Always check
  `command -v github-mcp-server` afterwards; if it is missing, use the release
  binary.
- Release binary (any OS). Needs the github.com `gh` login from step 4, so do
  that first if necessary. Assets are named
  `github-mcp-server_{Darwin,Linux}_{arm64,x86_64}.tar.gz` plus a checksums file:

  ```sh
  arch=$(uname -m); case "$arch" in aarch64) arch=arm64 ;; esac
  tmp=$(mktemp -d)
  gh release download -R github/github-mcp-server -D "$tmp" \
    -p "github-mcp-server_$(uname -s)_${arch}.tar.gz" -p '*checksums*'
  (cd "$tmp" && grep -q "$(shasum -a 256 github-mcp-server_*.tar.gz | cut -d' ' -f1)" *checksums* \
    && echo "checksum OK" && tar -xzf github-mcp-server_*.tar.gz)
  mkdir -p ~/.local/bin && install -m 755 "$tmp/github-mcp-server" ~/.local/bin/github-mcp-server
  ~/.local/bin/github-mcp-server --version
  ```

  Stop if the checksum line does not print. The wrapper already adds
  `~/.local/bin` to PATH. Docker is also supported by the upstream project,
  but the wrapper script in this plugin expects a binary on PATH.

## 4. Log in with `gh` (device flow, no PAT)

One login per host they need. `--web` opens the browser device-code flow; `gh`
stores the resulting OAuth token in the OS keyring.

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth login --hostname github.huit.harvard.edu --git-protocol https --web
```

Notes to relay when relevant:

- The person picks "HTTPS" and "Login with a web browser" if prompted. Say yes to
  "Authenticate Git with your GitHub credentials" so `git push` also stops
  needing a PAT.
- **github.com + SAML:** `harvard-huit` enforces SAML SSO. If `gh api user/orgs`
  or a repo call later returns 403 mentioning SAML, the person must authorize the
  token for the org: `gh auth refresh --hostname github.com` and follow the
  SSO prompt, or visit the org's SSO page in their browser.
- **GHES:** the classic-PAT `Authorization: Bearer` 401 gotcha does not apply to
  OAuth tokens from `gh`; device-flow login, `gh api`, and the local MCP binary
  all work against GHES with it. If `gh auth login` against GHES fails anyway,
  capture the exact error and stop; do not fall back to creating a PAT.

Verify each login without network calls: `gh auth token --hostname <host> >/dev/null && echo ok`.
For a real round-trip: `gh api --hostname <host> user --jq .login`.
To confirm it is really an OAuth login and not a pasted PAT:
`gh auth token --hostname <host> | cut -c1-4` prints `gho_` for a device-flow
token and `ghp_` for a classic PAT. Never print more than those four
characters. If it is `ghp_`, offer `gh auth login --hostname <host> --web`
again; `gh` replaces the stored token, and the person can then revoke the PAT.

## 5. Connect the MCP servers

Nothing to authorize beyond step 4 on either host. Both servers are declared in
the plugin's `.mcp.json` and pick up the `gh` token themselves: `github` through
a `headersHelper` script that prints an `Authorization: Bearer` header from
`gh auth token --hostname github.com`, and `github-huit` through a wrapper that
exports the GHES token to the local binary. Claude Code reads `.mcp.json` at
install time and connects at session start, so after a fresh `gh` login the
person may need to restart Claude Code (or `/reload-plugins`) before the tools
appear. If a server shows as failed in `/mcp`, run its script by hand to see
the stderr, then fix what it reports. Get the install path from
`claude plugin list --json` (the `installPath` field; typically
`~/.claude/plugins/cache/ats-plugin-marketplace/huit-github/<version>`), then:

```sh
"<installPath>"/bin/github-mcp-headers.sh | sed -E 's/Bearer [A-Za-z0-9_]+/Bearer <redacted>/'   # github
"<installPath>"/bin/github-mcp-ghes.sh </dev/null                                                  # github-huit
```

Always pipe the headers helper through that `sed` so the token never lands in
the conversation. Common causes: no `gh` login for that host, or (GHES only)
the binary not on PATH. MCP servers may launch with a minimal PATH; both
scripts add Homebrew and `~/.local/bin`.

**If `/mcp` for `github` says "Incompatible auth server: does not support
dynamic client registration":** that is the hosted server's own OAuth flow,
which cannot work from Claude Code. The plugin does not use it. Check that the
installed plugin is version 0.3.0 or later (`claude plugin list`) and that the
`gh` login for github.com exists; then restart Claude Code.

**SAML:** `harvard-huit` enforces SSO. If MCP calls against `harvard-huit` repos
return 403 mentioning SAML while `gh api user` works, the `gh` token needs org
authorization: `gh auth refresh --hostname github.com` and follow the SSO
prompt. No admin action is needed; GitHub CLI's OAuth app is already approved
for the org wherever `gh` works against it.

## 6. Optional: narrow read-only `gh` allowlist

Plugins cannot ship permissions, so offer (do not assume) to add a small
allowlist to the person's `~/.claude/settings.json` so read-only `gh` calls stop
prompting. Show exactly what you will add and wait for a yes. Merge into the
existing `permissions.allow` array; never overwrite other entries.

```json
"Bash(gh auth status:*)",
"Bash(gh repo view:*)",
"Bash(gh pr list:*)",
"Bash(gh pr view:*)",
"Bash(gh pr diff:*)",
"Bash(gh pr checks:*)",
"Bash(gh issue list:*)",
"Bash(gh issue view:*)",
"Bash(gh run list:*)",
"Bash(gh run view:*)",
"Bash(gh search:*)"
```

Rules: **never** add bare `Bash(gh:*)` or `Bash(gh *)`. Do not add `gh api`
even though it is often read-only; it also performs writes with `-X`/`--method`
and cannot be constrained by a prefix rule. Writes (`gh pr create`, `gh pr
merge`, `gh issue create`, `gh repo delete`, ...) must keep prompting.

## 7. Verify and hand off

Do one real read per host they set up, preferring MCP tools and falling back to
`gh`: for example, list open PRs on a repo they name, or `gh repo view <org>/<repo>`.
Then tell them, in a few lines, what is connected, what is not, and anything
they still have to do themselves (a restart so the MCP servers pick up a new
login, or `gh auth refresh` for SAML, if either came up).

## Ongoing usage guidance

- Prefer the `github` / `github-huit` MCP tools when connected; fall back to
  `gh --hostname <host>` when they are not. Say which you are using if it matters.
- Some repos are live on GHES while the github.com copy is a stale mirror.
  Compare `pushed_at` on both before assuming which is canonical.
- Cross-instance `#N` references do not auto-link. Use full URLs when citing
  issues or PRs across the two hosts.
- `gh` on GHES: if a call returns 401 with a classic PAT in play, that is the
  known `Authorization: Bearer` rejection; the fix is to use the `gh` OAuth login,
  not another PAT.
