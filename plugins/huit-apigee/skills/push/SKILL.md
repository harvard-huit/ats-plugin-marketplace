---
name: push
description: Import the local Apigee X proxy bundle as a new revision and deploy it to an environment on the HUIT gateway, safely. Use when the user asks to push, deploy, ship, release, or promote the proxy, upload a new revision, or redeploy or roll back, and when an Apigee error appears such as "bundle contains errors", a deployment stuck in PROGRESSING or ending in ERROR, or "Both operands for AND expression should be logical". Checks for upstream drift since the last pull, runs the repo's pre-push step, lints the bundle, validates server-side without creating a revision, diffs against the deployed revision, resolves the org per environment (nonprod, preprod, prod) and confirms before stage or prod, records the previous revision, waits for READY, smoke-tests through the gateway, and offers a rollback on failure.
---

# Apigee push (HUIT)

You are shipping the bundle in this repo to one Apigee environment. The order
below exists because each step catches something the old `apigee-push`
command let through: a stale local copy, a manifest out of step with disk, a
bundle that fails import, a deploy to the wrong org, a prod push with no way
back. Do the steps in order and stop at the first failure.

Config, defaults, and the org table: `${CLAUDE_PLUGIN_ROOT}/references/config.md`.
On **any** import or deploy error, read `${CLAUDE_PLUGIN_ROOT}/references/apigee-gotchas.md`
before explaining it; most of these errors have a known cause there.

## Hard rules

- **Never deploy to `stage` or `prod` without an explicit yes** for that
  environment, in this conversation, after showing the diff. Same when the
  resolved org differs from gcloud's active project, whatever the env.
- Never take the org from gcloud's active project. Always pass `--env` (the
  scripts resolve the org) or `--org`. Say which org you are using.
- Never print a token, an API key, or a smoke-test header value. Header
  values in `.apigee.json` are `$VAR` references; the script expands them.
- Never zip or upload anything but `apiproxy/`; never commit a zip. The old
  archive-zip step is gone on purpose.
- Do not edit the bundle to make a lint pass without telling the person what
  you changed and why. Lint warnings are theirs to accept.
- One script per step, so the person approves each network action once.

## 1. Resolve

Arguments: `[proxy] [env]`. Default env is `dev`.

```sh
gcloud auth print-access-token >/dev/null 2>&1 && echo "gcloud: ok" || echo "gcloud: no login"
"${CLAUDE_PLUGIN_ROOT}"/scripts/lib.sh resolve_proxy
"${CLAUDE_PLUGIN_ROOT}"/scripts/lib.sh resolve_bundle_dir
"${CLAUDE_PLUGIN_ROOT}"/scripts/lib.sh resolve_org <env>
gcloud config get-value project 2>/dev/null
cat .apigee-state.json 2>/dev/null
```

State in one line: proxy, bundle dir, env, org, and whether that org matches
gcloud's project. No login: the person runs `gcloud auth login` themselves.
If `envs.<env>.note` exists in `.apigee.json` (promotion owned by another
team, for example), print it now.

## 2. Drift check

Compare `.apigee-state.json` `revision` (and its `org`) with the org's latest:

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/status.sh <proxy> --org <org>
```

- Latest is **higher** than the state revision: someone imported since the
  last pull. Say so, name both numbers, and offer to stop and run the `pull`
  skill into a temp dir to diff (`fetch.sh --out "$(mktemp -d)"/<proxy> --no-state --lf`).
  Continue only if they say the local bundle is authoritative.
- No state file, or state from a different org: no drift check is possible;
  say so and rely on the diff in step 5.
- Latest equals state: fine.

## 3. Pre-push and lint

If `.apigee.json` has `prePush`, run it from the repo root and show its
output. That is where spec regeneration lives (maestro's
`convert-spec-3.0.py`), not in this skill.

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/lint-bundle.sh
```

- **Exit 1 (errors):** these fail import or deploy (a Step to a missing
  policy, a RouteRule to a missing target, a BasicAuthentication literal
  User/Password). Stop and show them.
- **Warnings:** summarize in one line each and continue. Known ones in this
  fleet: `validate-spec` and `Quota-1` declared but never stepped, a manifest
  `<Policies>` list missing files that exist (import regenerates it),
  `MatchesPath "/"`, `<Set><Path>`. Offer to fix only when asked.

## 4. Validate server-side

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/import.sh <proxy> --env <env> --validate
```

Creates no revision. On exit 5 the script prints the server's violations
(file and rule); read the gotchas reference, explain the cause, and stop.

## 5. Diff against what is deployed

Fetch the revision currently deployed in the target env (from step 2's
output) into a temp dir and diff it against the local bundle:

```sh
tmp=$(mktemp -d)
"${CLAUDE_PLUGIN_ROOT}"/scripts/fetch.sh <proxy> --rev <deployed-rev> --org <org> --out "$tmp/<proxy>" --no-state --lf >/dev/null
diff -rq "$tmp/<proxy>/apiproxy" <bundle-dir> | grep -v '/ats-.*\.xml$' ; diff -ru "$tmp/<proxy>/apiproxy" <bundle-dir> --exclude='*.DS_Store' | head -200
```

Summarize the change per file in plain words (the manifest's `revision`
attribute always differs; ignore it). **If nothing else differs, say so and
ask whether they still want a new revision**; usually the answer is no.

## 6. Confirm

Required when `envs.<env>.confirm` is true (default for `stage` and `prod`),
or when the org differs from gcloud's active project. Show: proxy, org, env,
the revision currently deployed there, the one-paragraph diff summary, and
the `note` if any. Ask for a yes. Nothing so far has changed Apigee; this is
the last point where stopping costs nothing.

## 7. Import and deploy

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/import.sh <proxy> --env <env>
"${CLAUDE_PLUGIN_ROOT}"/scripts/deploy.sh <proxy> --rev <new-rev> --env <env>
```

`deploy.sh` prints the **previous revision** and the exact rollback command
before it deploys, then polls every 10 seconds (READY in 30 to 50 seconds is
normal; it gives up at 180). Run it with a five-minute timeout.

- Exit 6 (`ERROR`): show `.errors[]`, read the gotchas reference, and
  **offer the printed rollback command**. Do not run it unasked.
- Exit 7 (timed out, still PROGRESSING): run `status.sh` once more before
  concluding anything; slow deploys happen. If still not READY, offer the
  rollback.

## 8. Smoke and post-deploy

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/smoke.sh <proxy> --env <env>
```

Routes and expected statuses come from `.apigee.json` `smoke`; without them
the script hits the base path and treats anything but a gateway 404 as
reachable (a 401 or 405 means the proxy answered; a 404 means the base path
is not deployed on that host). The host comes from the org's env groups, not
a table. A route whose `$VAR` header is unset is reported as skipped, not
failed silently; tell the person which variable to export.

On failure, offer the rollback command from step 7. On success, run
`postDeploy` from `.apigee.json` if present (newman, integration tests) and
show its result.

## 9. Report

Proxy, org, env, new revision, previous revision (kept for rollback; it is
not deleted), smoke results, anything skipped, and any lint warnings the
person chose to leave. If the repo has no `.apigee.json` yet, offer to write
one with the values used this time (proxy, bundleDir, env org, and the smoke
route you just ran).

## Error to action

| Seen | Meaning | Do |
|---|---|---|
| `gcloud login expired or missing` | no token | person runs `gcloud auth login` |
| `bundle contains errors` (exit 5 from import.sh) | server rejected the bundle; violations printed | gotchas reference, fix, re-validate |
| `The User element is required` | BasicAuthentication with a literal, not `ref=` | use `ref=`; see gotchas |
| `Both operands for AND expression should be logical` | condition parser rejected `NotLike` or an unparenthesized `!=` with and/or | parenthesize or rewrite with `JavaRegex`; see gotchas |
| HTTP 404 on import | wrong endpoint or content type | the script already uses the working form; check org and proxy name |
| HTTP 403 | no access to that org | access request; name the org |
| deployment `ERROR` | see `.errors[]` | gotchas reference; offer rollback |
| still `PROGRESSING` after 180 s | slow or stuck | `status.sh`, then offer rollback |
| smoke 404 | base path not served on that host | check env/host with `hosts.sh --org <org>`; offer rollback |
| smoke 401/403/405 on the default check | proxy answered; auth or method expected | reachable; add a real route to `smoke` |
| `latest is higher than state` | someone imported since the last pull | diff in a temp dir before overwriting their change |
