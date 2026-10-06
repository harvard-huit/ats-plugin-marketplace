---
name: pull
description: Download a revision of an Apigee X proxy bundle from the HUIT gateway into the repo without destroying local edits. Use when the user asks to pull, fetch, download, or refresh the proxy bundle or apiproxy directory, get the latest revision, see what changed upstream, or grab the API product definition. Refuses when the bundle directory has uncommitted changes, normalizes line endings, saves the product JSON outside the bundle, records the fetched revision for the push skill's drift check, and lists the proxy's external dependencies (KVMs, shared flows, target servers).
---

# Apigee pull (HUIT)

You are fetching one revision of an API proxy from Apigee X into the repo the
person is working in. The old `apigee-pull` command deleted the local
directory unconditionally; this skill never does. Everything network-side is
one script, `fetch.sh`, so the person approves one command.

Config and defaults: `${CLAUDE_PLUGIN_ROOT}/references/config.md`. Read it if
the repo has a `.apigee.json` or the person asks what a key means.

## Hard rules

- **Never pass `--force` without first showing the person what it discards**
  (the `git status` lines the script prints) and getting a yes.
- Never print a gcloud token. The scripts keep it in a temp file; do not run
  `gcloud auth print-access-token` yourself.
- The org comes from the environment, not from gcloud's active project. If
  the script warns that the org came from gcloud, pass `--env` or `--org`
  explicitly and say which org you used.
- Do not edit `.apigee.json` or the bundle yourself in this skill. Pulling is
  a read of Apigee and a write of the bundle directory only.

## 1. Resolve what to pull

Arguments: `[proxy] [rev]`. Also accept "from stage" or "prod's revision" as
an environment (`--env`), and "rev 12" as a revision.

```sh
gcloud auth print-access-token >/dev/null 2>&1 && echo "gcloud: ok" || echo "gcloud: no login"
"${CLAUDE_PLUGIN_ROOT}"/scripts/lib.sh resolve_proxy
"${CLAUDE_PLUGIN_ROOT}"/scripts/lib.sh resolve_bundle_dir
```

- "no login": tell the person to run `gcloud auth login` (or
  `gcloud auth login --no-launch-browser` on Cloud9 or SSH) in their own
  terminal, then continue. The browser flow cannot be completed from here.
  Add the one warning they cannot guess: if the browser fails on
  `accounts.youtube.com` right after they choose their Harvard account, the
  local network blocks YouTube and the VPN does not cover it (gotchas
  reference, "gcloud login on networks that filter YouTube"); the fix is a
  hotspot for the browser step, not a gcloud upgrade.
- `resolve_proxy` failing with "more than one apiproxy/ directory" (idphoto:
  `apigee-x/` plus the retired `archive/`): ask which one, then pass
  `--bundle-dir`. Suggest a `bundleDir` line in `.apigee.json` so it stops
  asking, but do not add it in this skill unless they say yes.
- No bundle yet (first pull into an empty repo): pass the proxy name; the
  script creates `<repo>/<proxy>/apiproxy/`.
- Default environment is `dev` (nonprod org). Pulling from stage or prod
  reads a different org with its own revision numbers; say so.

Report proxy, org, and target directory in one line before running anything
that writes.

## 2. Fetch

```sh
"${CLAUDE_PLUGIN_ROOT}"/scripts/fetch.sh <proxy> [--rev N] [--env <env>] [--product] --lf
```

Use `--product` unless the person only wants the bundle; use `--lf` always
(exports that passed through a Windows browser carry CRLF, and the diff in
push depends on LF).

- **Exit 3, "has uncommitted or untracked changes":** stop. Show the listed
  files. Offer, in this order: commit them, `git stash push -- <bundle dir>`,
  or (if they explicitly want to discard) `--force`. Untracked files count,
  because a pull would delete them too.
- **Exit 3, "not inside a git repository":** the directory exists but nothing
  could recover its contents. Offer to move it aside (`mv <dir> <dir>.bak`)
  rather than `--force`.
- **Exit 2:** gcloud login; see step 1.
- **HTTP 404 on `/apis/<proxy>`:** wrong org for that proxy or a typo. Run
  `status.sh <proxy>` to see which orgs have it.
- **HTTP 403:** the account has no access to that org. Name the org; this is
  an access request, not a retry.

## 3. Report

From the script's stderr and JSON:

- Revision fetched, and whether it is the latest; deployments of this proxy in
  that org (`dev=rev2`).
- Where the bundle landed, and that the product JSON (if fetched) sits **next
  to** `apiproxy/`, not inside it, because it is not part of the deployable
  bundle.
- The dependency list: KVM names, shared flows, target servers, target URLs.
  These live outside the repo; a shared flow such as `adex-auth` is owned
  elsewhere.
- The state file `.apigee-state.json` was written. If the script warned that
  it is not gitignored, offer to append it to `.gitignore` (one line; show
  it, wait for yes).

If the person pulled to compare rather than to replace (they said "diff",
"what changed", "compare with what is deployed"), pull into a temp directory
instead: `--out "$(mktemp -d)"/<proxy> --no-state`, then `diff -rq` that
against the repo's bundle and summarize per file. Do not touch the repo's
bundle in that case.

## Error to action

| Seen | Meaning | Do |
|---|---|---|
| `gcloud login expired or missing` | no usable token | person runs `gcloud auth login` (`--no-launch-browser` without a browser) |
| browser: "site can't be reached" on `accounts.youtube.com` during login | local network blocks YouTube; VPN excludes it from the tunnel | browser step on a hotspot, paste the code; see gotchas "gcloud login on networks that filter YouTube" |
| `has uncommitted or untracked changes` | pull would destroy local edits | commit, stash, or explicit `--force` after showing the list |
| `not inside a git repository` | no way to recover overwritten files | move the directory aside instead of `--force` |
| `more than one apiproxy/ directory` | layout has a retired or second bundle | `--bundle-dir`, then suggest `bundleDir` in `.apigee.json` |
| HTTP 404 on the proxy | wrong org or name | `status.sh <proxy>` to find where it exists |
| HTTP 403 | no access to that org | access request; name the org |
| `no single API product references <proxy>` | product not named after the proxy and not discoverable | continue without it; mention it |
