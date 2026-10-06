---
name: maestro-setup
description: Connect Claude Code to the Maestro Utility MCP server, which answers questions about HUIT's Maestro (IBM Workload Automation) scheduler: jobstream status, why a job is waiting or failed, run history, who submitted an ad-hoc job, PagerDuty and ServiceNow linkage, and the engine-side log of a run. Authentication is a HarvardKey login in the browser through /mcp; there is no token, client ID, or secret. Use when the user asks to set up, connect, log in to, or fix Maestro access, when the maestro MCP server shows as needing authentication, disconnected, or failed, when a Maestro tool returns "a maestro role is required" or "invalid_token", or when someone asks how to ask Claude about Maestro jobs.
---

# Maestro setup (HUIT)

You are walking one person through connecting Claude Code to the Maestro
Utility MCP server. The server is read-only and every call runs as the person,
with the same HarvardKey maestro role they have in the Maestro Utility web app.
There is nothing to install and no credential to create: the plugin already
declares the server, and the login is a HarvardKey sign-in plus one consent
click in their browser. You cannot do that login for them. `/mcp` is an
interactive command, so propose it, explain what will happen, and end your
turn while they complete it.

## 1. Inventory first

- **Already connected?** If Maestro tools (`list_plans`, `find_jobstream`,
  `jobstream_status`, `explain_job`, `run_history`, `who_submitted`,
  `pagerduty_for_run`, `get_job_log`) are in your tool list, the server is
  connected. Skip to step 4.
- **Hand-added duplicate?** Before this plugin existed, people added the server
  themselves with `claude mcp add`. Run:

  ```sh
  claude mcp get maestro
  ```

  A non-zero exit means no hand-added entry, which is what you want. If it
  prints a server, note the scope it reports (user, project, or local) and
  offer to remove it, because otherwise the person has two copies of every
  tool and two logins to keep alive:

  ```sh
  claude mcp remove maestro -s <scope>
  ```

  Do this only with their yes. If their old entry points at a different
  environment than the plugin (the plugin ships production), say so before
  removing it; they can keep a differently named entry for the other tier
  (see "Environments" below).

## 2. Authenticate

Tell the person, in their own terms:

1. Type `/mcp`.
2. Select **maestro** and choose **Authenticate**.
3. A browser tab opens on the Maestro Utility sign-in page. Sign in with
   HarvardKey if asked, review the consent page, and click **Allow**.
4. The tab redirects to a local address and Claude Code reports the server as
   connected.

Then end your turn. When they come back, go to step 4.

What they are agreeing to, if they ask: the server registers Claude Code as a
client on the fly (dynamic client registration), so no client ID or secret is
involved. The token it issues is theirs alone, lasts one hour, and is renewed
silently for up to 30 days, after which `/mcp` asks them to sign in again.
Consent is asked on every new authorization. They can see and revoke every
client holding a token for them under **Connected apps** on the Maestro
Utility home page.

## 3. Troubleshooting

- **"A maestro role is required" after signing in.** Their HarvardKey account
  is not in a maestro admins or app-users group. They request access the same
  way they would for the Maestro Utility web app; the plugin cannot help until
  that is granted. If they had access and just received it, the role snapshot
  is refreshed at consent, so authenticating again is enough.
- **The browser tab shows a HarvardKey error or never redirects back.** The
  redirect URI for this environment may not be whitelisted in the HarvardKey
  app registration. That is an application-owner fix; tell them to report it.
- **"needs authentication" or `invalid_token` some time after it worked.** The
  30-day refresh window passed, or the token was revoked under Connected apps.
  `/mcp` and authenticate again.
- **Tools missing right after install.** `.mcp.json` is read at install time
  and servers connect at session start. `/reload-plugins`, or restart Claude
  Code, then `/mcp`.
- **A tool answers "retry in N seconds".** Each token gets 60 tool calls per
  minute. Wait it out; do not loop on the call.
- **`get_job_log` answers "Splunk API is not configured".** That environment
  has not been given a Splunk key. The other tools still work.
- **Something else.** Run `claude mcp list` and relay what it says about
  `maestro`. A 401 from the server with no login attempt means the plugin is
  fine and only the authentication is missing.

## 4. Verify and hand off

Call `list_plans` once. It is the cheapest tool and proves the token, the role
and the Oracle connection in one go. Then tell the person in a few lines what
is connected and, if anything came up, what they still have to do themselves.

## Using it

- Tool names, arguments, and descriptions come from the server. Read them
  from your tool list rather than guessing; this skill does not duplicate
  them.
- Everything is read-only. The tools cannot submit, cancel, rerun, or hold
  anything, and the admin-only SQL runner is not reachable through MCP. Say
  so plainly if asked to change something.
- Job numbers identify a run but are reused over time. When a person gives
  you a job number, pass the job name or a date alongside it to the tools
  that accept one.
- `get_job_log` returns the scheduler's own record of a run (launch and abend
  events with the return code, plus the engine log lines that mention it).
  The job's application output is not available anywhere the server can
  reach. Do not promise stdout.
- Timestamps are returned exactly as the scheduler database stores them. Do
  not convert them; if the person needs to reconcile them with PagerDuty or
  Splunk times, say which source each time came from.

## Environments

The plugin points at the production Maestro Utility, which reads the
production scheduler. Other tiers expose the same `/maestro-util/mcp` path on
their own host; the exact URL for a tier is shown under **Connected apps** on
that tier's home page. If someone needs another tier, they add it by hand
under a different name so it does not collide with the plugin's server:

```sh
claude mcp add --transport http --scope user maestro-dev <that tier's /maestro-util/mcp URL>
```

and authenticate it separately in `/mcp`.
