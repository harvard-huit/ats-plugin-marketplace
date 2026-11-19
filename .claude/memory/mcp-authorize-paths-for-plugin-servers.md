---
name: mcp-authorize-paths-for-plugin-servers
description: How an OAuth MCP server can be authorized in Claude Code (2.1.267, checked 2026-10-06) and why a plugin-shipped server has only the in-session /mcp path; `claude mcp login` needs a TTY and cannot see plugin servers; MCP tools are not slash commands
metadata:
  type: project
---

Checked 2026-10-06 against Claude Code 2.1.267 while building `huit-maestro`.

- **`claude mcp login <name>`** runs the OAuth flow from a terminal for a
  server added at user, project, or local scope. Verified against the
  hand-added `maestro` entry: discovery, dynamic client registration, and the
  authorize URL all happened; `--no-browser` prints the URL for SSH/Cloud9.
  It requires an interactive terminal ("stdin isn't a terminal" when run from
  Claude's Bash tool), so a skill can only tell the person to run it.
- **Plugin-shipped servers are invisible to the `claude mcp` CLI.**
  `claude mcp get plugin:huit-maestro:maestro` answers "No MCP server named",
  and `claude mcp list` omits them. In a session they appear as
  `plugin:<plugin>:<server>` and tools as `mcp__plugin_<plugin>_<server>__<tool>`.
  The only authorize trigger for them is the in-session `/mcp` menu. Nothing
  in `.mcp.json` (`oauth.clientId`, `callbackPort`, `scopes`,
  `authServerMetadataUrl`) pre-authorizes or auto-starts the flow, and there
  is no documented way to seed a token into Claude Code's credential store.
- **The alternative design**, if a terminal/headless authorize matters: drop
  `.mcp.json` and have the setup skill run
  `claude mcp add --transport http --scope user <name> <url>` (with the
  person's approval), then tell them to run `claude mcp login <name>`. Cost:
  the server is not registered by install alone, and uninstall leaves it
  behind unless the skill offers `claude mcp remove`. Not adopted for
  `huit-maestro` as of 2026-10-06; revisit if VS Code cannot authorize plugin
  servers.
- **VS Code extension:** typing `/mcp` in the chat panel opens a dialog that
  manages OAuth (documented at code.claude.com/docs/en/vs-code). Whether a
  `plugin:*` server shows an Authenticate action there is undocumented. The
  plugin's server did get authenticated on JaZahn's Mac by 2026-10-31 (which
  client was used is not recorded). A session that predates the plugin
  install never loads the plugin's server at all, which looks the same as
  "no authorize option"; start a fresh session before concluding anything.
- **MCP tools are not slash commands.** `list_plans` has no `/` form. Two
  ways to get one: a plugin skill (`/huit-maestro:<skill>`) that calls the
  tool, or server-side MCP prompts (`prompts/list` + `prompts/get`), which
  Claude Code exposes as `/mcp__<server>__<prompt>`. The Maestro server
  implements only `initialize`, `ping`, `tools/list`, `tools/call`.

**Why:** people expect an "authorize" button or command; the plugin cannot
provide one, and the reason is a Claude Code boundary, not a plugin bug.

**How to apply:** setup skills for plugin-shipped OAuth servers should say
"type `/mcp`" and nothing else; offer `claude mcp login` only for hand-added
entries. Related: [[local-install-shadows-synced-plugin]].
