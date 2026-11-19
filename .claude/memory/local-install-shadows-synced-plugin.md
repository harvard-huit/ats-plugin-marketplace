---
name: local-install-shadows-synced-plugin
description: Plugin name conflicts resolve by manifest name and origin precedence, never by version; a `claude plugin install` from the dev-branch marketplace shadows the claude.ai-synced copy of the same plugin until uninstalled
metadata:
  type: project
---

Claude Code loads at most one plugin per manifest `name` (the `name` in
`plugin.json`), not per `name@marketplace`. When two copies exist, origin
precedence picks the winner, highest first: managed-settings
`enabledPlugins`, then `--plugin-dir` / `--plugin-url`, then installed
marketplace plugins (`claude plugin install`), then skills-directory
plugins, then claude.ai-synced plugins. Version numbers are not compared.
The loser's skills, MCP servers, and hooks do not load; `/plugin` shows the
synced copy as not loaded. Documented at
https://code.claude.com/docs/en/plugins/loading (section "Name conflicts").

**Why:** we test unreleased plugins by registering this repo locally pinned
to `ref: dev` and installing from it, while the team gets the released
copies through claude.ai account sync. The dev install silently wins even
after a newer release lands in sync.

**How to apply:** when a dev-branch test is done, run
`claude plugin uninstall <plugin>@ats-plugin-marketplace` so the synced
copy loads again. Expect no duplicate `/<plugin>:<skill>` entries or
`plugin:<plugin>:<server>` servers from an overlap; a missing update is the
symptom instead. Related: [[claude-ai-sync-follows-release-tag]],
[[marketplace-update-vs-plugin-list]].
