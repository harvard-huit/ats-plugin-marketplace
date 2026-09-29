---
name: harvard-slack-grid-blocks-ai-apps
description: Harvard Slack Grid rejects AI connectors and all history scopes; a custom internal app to mcp.slack.com was refused 2026-09-28, so a huit-slack plugin is off until ISDP changes policy
metadata:
  type: project
---

Harvard's Slack Enterprise Grid admins rejected the `huit-slack` internal app
on 2026-09-28 under two standing rules: (1) AI assistants, connectors, and
bots such as Claude and ChatGPT are not approved anywhere in the Grid; (2) the
scopes `channels:history`, `groups:history`, `mpim:history`, `im:history` are
not approved for any app. Either rule alone is fatal to a Slack MCP
integration. The policy is under review, aimed at the official ChatGPT and
Claude connectors, pending a test period and an ISDP green light. Record is
issue #2 on harvard-huit/huit-agent-plugins.

**Why:** the internal-app route was tried because Slack's MCP server
(`mcp.slack.com/mcp`) accepts any internal Slack app as its OAuth client (PKCE,
no secret, needs a bot user and the MCP toggle). The bet was that an internal,
workspace-scoped app would get a different review path from the rejected
Marketplace connector. It did not: same reviewers, same blanket policy.

**How to apply:** do not propose, build, or resubmit a Slack integration for
HUIT until the policy review concludes. If official connectors are approved,
point people at Anthropic's official `slack` plugin and close #2; the custom
app is moot. If AI connectors are approved but the official one still refused,
revive the design in #2. Never put the Slack admin's name in this public repo.
Related: [[ghes-oauth-needs-own-app]] (the analogous "server needs an app
registered on the instance" gotcha for GHES).
