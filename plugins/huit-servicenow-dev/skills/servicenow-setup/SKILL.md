---
name: servicenow-setup
description: Connect Claude Code to HUIT's hosted ServiceNow MCP server (snow-mcp, dev tier), which answers questions about ServiceNow records as you: incidents, changes, requests and RITMs, catalog items, CMDB CIs, people and groups, knowledge articles, approvals, attachments, record history, and any table your account can see. Read-only. Authentication is a ServiceNow login (HarvardKey SSO) in the browser through /mcp; there is no token, client ID, or secret. Requires the HUIT cloudadmin VPN. Use when the user asks to set up, connect, log in to, or fix ServiceNow or snow-mcp access, when the service-now MCP server shows as needing authentication, disconnected, or failed, when a ServiceNow tool returns 401 or 403, when the connection hangs, or when someone asks how to ask Claude about ServiceNow tickets.
---

# ServiceNow setup (HUIT, dev)

You are walking one person through connecting Claude Code to HUIT's hosted
ServiceNow MCP server (snow-mcp). The plugin already declares the server as
`service-now`; there is nothing to install and no credential to create. The
login is a ServiceNow sign-in through HarvardKey SSO plus one consent click in
their browser, and you cannot do it for them. `/mcp` is an interactive
command, so propose it, explain what will happen, and end your turn while they
complete it.

Two things make this server different from the others in this marketplace:

- **It is reachable only on the HUIT cloudadmin VPN.** The hostname resolves
  to private addresses. The OAuth redirect is followed by the person's
  browser, so they must stay on the VPN for the whole login, not only for the
  first request.
- **It is the dev tier.** It talks to the `harvardtest` ServiceNow instance,
  not production, so the records it returns are test data. Say so before the
  person starts drawing conclusions from a ticket. When the production server
  is published it will live in the org-level marketplace
  (`harvard-huit/huit-plugin-marketplace`), and this plugin goes away.

## 1. Inventory first

- **Already connected?** If ServiceNow tools (`whoami`, `connection_info`,
  `query_records`, `describe_table`, and the like) are in your tool list, the
  server is connected. Skip to step 4.
- **On the VPN?** Run:

  ```sh
  curl -sS --max-time 10 https://snow.mcp.dev.cloud.huit.harvard.edu/health
  ```

  `{"status":"ok"}` means reachable. A hang, a DNS failure, or a connection
  refusal means the VPN is not up; ask them to connect to the HUIT cloudadmin
  VPN and run it again. Do not go further until this passes.
- **Hand-added duplicate?** Before this plugin existed, people added the
  server themselves with `claude mcp add`, under `service-now` (the name in
  this repo's issue) or `snow` (the name in the server's own docs). Run both:

  ```sh
  claude mcp get service-now
  claude mcp get snow
  ```

  A non-zero exit means no hand-added entry, which is what you want. If one
  prints a server at the same dev URL, note the scope it reports (user,
  project, or local) and offer to remove it, because otherwise the person
  has two copies of every tool and two logins to keep alive:

  ```sh
  claude mcp remove <name> -s <scope>
  ```

  Do this only with their yes. If the entry points at a different URL (for
  example the production host once it exists), leave it alone and say why.

## 2. Authenticate

Tell the person, in their own terms:

1. Make sure the VPN is connected and stays connected.
2. Type `/mcp`.
3. Select **service-now** and choose **Authenticate**.
4. A browser tab opens on the ServiceNow sign-in page. Sign in through
   HarvardKey if asked, review the consent page, and allow it.
5. The tab redirects to a local address and Claude Code reports the server as
   connected.

Then end your turn. When they come back, go to step 4.

What they are agreeing to, if they ask: the server registers Claude Code as a
client on the fly (dynamic client registration) and proxies the login to
ServiceNow's own OAuth endpoints, so no client ID or secret is involved and
the server never sees their password. Every tool call then runs under their
own ServiceNow account with the same ACLs they have in the ServiceNow UI. The
ServiceNow access token lasts about 30 minutes and is refreshed silently; the
refresh token lasts about 100 days, after which `/mcp` asks them to sign in
again.

## 3. Troubleshooting

- **`curl` hangs or cannot connect, or the server shows "failed" with no
  login attempt.** Not on the cloudadmin VPN. Nothing else is wrong.
- **The browser cannot load the sign-in page, or the tab never comes back.**
  The VPN dropped mid-flow. Reconnect and authenticate again.
- **`redirect_uri mismatch` on the ServiceNow page.** The server's callback
  URL is not registered on the instance. That is a server-owner fix (the
  snow-mcp maintainers), not something the person can change; tell them to
  report it.
- **Sign-in works, then every tool returns 403.** ServiceNow ACLs. The server
  grants nothing beyond what the account already has. On an instance with
  explicit-role REST ACLs the account also needs the
  `snc_platform_rest_api_access` role; that is a ServiceNow admin request.
- **Empty results that "should" exist.** Also ACLs. Compare with what the
  same account sees in a ServiceNow list view; the tool returns exactly that,
  no more and no less. Remember this is `harvardtest`, so a production ticket
  may simply not be there.
- **401 or "needs authentication" after a period of inactivity.** The refresh
  window passed, or the server's signing key was rotated (which logs everyone
  out at once). `/mcp` and authenticate again.
- **Tools missing right after install.** `.mcp.json` is read at install time
  and servers connect at session start. `/reload-plugins`, or restart Claude
  Code, then `/mcp`.
- **A write tool such as `create_incident` is missing.** Correct. The hosted
  server runs read-only and removes every create, update, and delete tool
  from the server entirely.
- **Something else.** Run `claude mcp list` and relay what it says about
  `service-now`. A 401 from the server with no login attempt means the plugin
  is fine and only the authentication is missing.

## 4. Verify and hand off

Call `whoami` once. It must return the person's own ServiceNow user (name,
email, roles), never a service account; if it does not, stop and tell them
the deployment is wrong. Then `connection_info` to confirm the instance URL
and that the server reports read-only. Tell the person in a few lines what is
connected, that it is the dev tier against `harvardtest`, and anything they
still have to do themselves.

## Using it

- Tool names, arguments, and descriptions come from the server. Read them
  from your tool list rather than guessing; this skill does not duplicate
  them.
- Everything is read-only. The tools cannot create, update, resolve, assign,
  approve, or delete anything. Say so plainly if asked to change a record.
- `query_records` takes the same encoded-query syntax as a UI list filter,
  and `describe_table` shows the columns of an unfamiliar table. Prefer those
  two over guessing field names.
- Results are scoped to the person's own account. If something seems to be
  missing, it is their ACLs or the dev data, not a bug to work around.
- Reading a knowledge article may bump its view counter, the same as opening
  it in the portal. Everything else leaves no trace beyond the server's
  audit log.
