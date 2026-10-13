---
name: status
description: Show which revision of an Apigee X proxy is deployed in each environment across the HUIT orgs (nonprod, preprod, prod), plus the latest imported revision and gateway hostnames. Read-only. Use when the user asks what revision is live, what is deployed where, whether dev is ahead of prod or stage, which org hosts an environment, what the gateway host for an env is, or whether a proxy exists in an org. Also use when `gcloud auth login` or `gcloud auth print-access-token` fails for a HUIT user, including "This site can't be reached", ERR_SOCKET_NOT_CONNECTED, or a redirect to accounts.youtube.com during the browser sign-in; the login section below has the known cause.
---

# Apigee status (HUIT)

Read-only. One script call per question; nothing here changes Apigee.

## Deployed revisions

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/status.sh [proxy] [--org <org> ...]
```

With no `--org` it asks all orgs from `.apigee.json` `envs`, or the three
HUIT orgs when there is no config. The proxy defaults to the repo's
`.apigee.json` or the local bundle's `<APIProxy name>`.

Render the stderr table for the person, then add the one caveat that matters:
**revision numbers are per org.** Rev 13 in nonprod and rev 2 in prod may be
the same bundle or may not; to compare, pull both into temp dirs
(`fetch.sh <proxy> --rev N --org <org> --out "$(mktemp -d)"/<proxy> --no-state --lf`)
and `diff -rq` them. Offer that when the question is "is prod behind".

Interpretation:

- `not present (HTTP 404)` in an org: the proxy has never been imported
  there. For a proxy that is only in nonprod, that is normal.
- `HTTP 403`: the account cannot read that org. Name the org; it is an access
  request, not an error in the proxy.
- An env showing an old revision while `latest` is higher: someone imported
  without deploying, or deployed elsewhere. Do not assume it is a mistake.
- The `.apigee-state.json` file in the repo, if any, records what the last
  pull fetched; compare it with `latest` to say whether the local copy is
  current.

## Hosts and environments

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/hosts.sh --org <org> [--env <env>]
```

Lists each environment with its gateway hostnames from the org's environment
groups. Use it for "what is the stage URL" and "which org is test in".
Verified 2026-09-29: stage is in `apigee-x-preprod`; prod answers on both
`go.apis.huit.harvard.edu` and `go.prod.apis.huit.harvard.edu`; test has its
own `go.test.apis.huit.harvard.edu`. Details in
`${CLAUDE_PLUGIN_ROOT}/references/config.md`.

## No login

If either script exits 2 with `gcloud login expired or missing`, the person
runs `gcloud auth login` (or `gcloud auth login --no-launch-browser` on a host
without a browser) in their own terminal. Do not attempt the browser flow
from here and never print a token. A single `print-access-token` failure can
be transient; retry once before sending them to log in.

Tell them this up front, because it is not guessable: **if the browser dies
on `accounts.youtube.com` ("This site can't be reached",
`ERR_SOCKET_NOT_CONNECTED`) right after they pick their Harvard account, the
local network is blocking YouTube and the Harvard VPN will not help**, since
Cisco Secure Client excludes `youtube.com` from the tunnel by policy. Google
Workspace sign-in needs that host once. Fix: do the browser step on a phone
hotspot, paste the code back, reconnect the VPN. Diagnosis commands and the
full explanation are in `${CLAUDE_PLUGIN_ROOT}/references/apigee-gotchas.md`
under "gcloud login on networks that filter YouTube". Upgrading gcloud does
not fix it.
