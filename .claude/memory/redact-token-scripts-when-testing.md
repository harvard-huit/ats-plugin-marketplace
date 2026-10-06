---
name: redact-token-scripts-when-testing
description: Never run gh auth token or the headers helper unredacted from Claude's Bash tool; an empty GH_CONFIG_DIR is not a no-login simulation (leaked a PAT on 2026-09-20)
metadata:
  type: feedback
---

When testing anything in this repo that emits a credential on its success path
(`scripts/github-mcp-headers.sh`, `gh auth token`), always redact in the same
pipeline: `| sed -E 's/Bearer [A-Za-z0-9_]+/Bearer <redacted>/'` or
`| cut -c1-4`. Do this even when you expect the failure path to run.

**Why:** On 2026-09-20 I "simulated no login" with `GH_CONFIG_DIR=$(mktemp -d)`
and ran the helper unredacted, expecting an error. `gh` found the token
anyway (it reads the OS keyring regardless of the config dir, and also honors
`GH_TOKEN`/`GITHUB_TOKEN`), so a live classic PAT was printed into the
conversation and persisted in the session transcript. The token had to be
rotated.

**How to apply:** Treat every command whose success output is a secret as
unsafe to run bare, no matter which branch you expect. To test a no-login
path, remove `gh` from `PATH` for that command, or confirm there is no keyring
entry first. Check for exported tokens with
`env | grep -E '^(GH_TOKEN|GITHUB_TOKEN)=' | cut -d= -f1` (names only). See
also [[session-start-hook-output]] for the other "what reaches the
transcript" gotcha in this repo.
