# ats-plugin-marketplace

Claude Code plugins for ATS (Administrative Technology Services) at Harvard
University IT, maintained by the AAIS team. This repo is both the marketplace
and the plugins.

This is the **ATS-level** marketplace. HUIT has an org-wide one,
[`harvard-huit/huit-plugin-marketplace`](https://github.com/harvard-huit/huit-plugin-marketplace),
which is where plugins useful across all of HUIT should end up. Plugins here
will move there as it matures; anything ATS-specific stays here. Until a
plugin has moved, install it from here.

| Plugin | What it does | Entry point |
|---|---|---|
| `huit-github` | GitHub access for both of our GitHubs **without a Personal Access Token** | `/huit-github:github-setup` |
| `huit-aws` | Log into HUIT AWS accounts with HarvardKey, from inside Claude Code | `/huit-aws:aws-login [account]` |
| `quiz` | Multiple-choice comprehension checks on the current session or on the repo's gotchas | `/quiz:session`, `/quiz:project` |
| `huit-apigee` | Pull, push, and inspect Apigee X proxy bundles on the HUIT gateway without clobbering edits or the wrong org | `/huit-apigee:pull`, `/huit-apigee:push`, `/huit-apigee:status` |

## Install

This repo is public on github.com, so no GitHub login is needed to add it.
Inside Claude Code:

```
/plugin marketplace add harvard-huit/ats-plugin-marketplace
/plugin install huit-github@ats-plugin-marketplace
/plugin install huit-aws@ats-plugin-marketplace
/plugin install quiz@ats-plugin-marketplace
/plugin install huit-apigee@ats-plugin-marketplace
```

Install whichever you need. You approve every command a skill proposes.

## Updates

Claude Code checks marketplaces for updates shortly after a session starts and
tells you to run `/reload-plugins` when something changed, but only if
auto-update is enabled for this marketplace. It is off by default for
non-Anthropic marketplaces: open `/plugin`, find `ats-plugin-marketplace`, and turn
auto-update on. To update by hand:

```
/plugin marketplace update ats-plugin-marketplace
/plugin update huit-github@ats-plugin-marketplace
/plugin update huit-aws@ats-plugin-marketplace
/plugin update quiz@ats-plugin-marketplace
/plugin update huit-apigee@ats-plugin-marketplace
/reload-plugins
```

## huit-github

Connects Claude to GitHub with OAuth logins you complete in your browser. No
PAT is created or stored.

| Host | Org | How it works |
|---|---|---|
| github.com | `harvard-huit` | GitHub's hosted MCP server, sent the token from `gh auth login` on each connection |
| github.huit.harvard.edu (GHES) | `HUIT` | GitHub's `github-mcp-server` binary run locally, using the token from `gh auth login` |

Run `/huit-github:github-setup` and follow along. It checks what you already
have, installs `gh` (and `github-mcp-server` if you need GHES), and runs
`gh auth login --web` for the host(s) you need. That login is the whole
authentication step; there is no separate `/mcp` login. Restart Claude Code
after a new login so the MCP servers pick it up.

You get MCP tools for issues, pull requests, repos, code search, and Actions on
whichever host(s) you connected (`github` for github.com, `github-huit` for
GHES), with `gh` as a fallback. A one-line nudge at session start tells you if
`gh` is missing a login; it never blocks. The skill can also offer a narrow
read-only `gh` allowlist for your `~/.claude/settings.json`; nothing is added
without your yes.

Requirements: `gh`. For GHES only, `github-mcp-server` on your PATH
(`brew install github-mcp-server` where Homebrew has a bottle for your OS,
otherwise the release binary from `github/github-mcp-server` in `~/.local/bin`;
the skill walks through both).

Admin notes: no admin action is required. Both servers use the token GitHub
CLI's own OAuth app issued at `gh auth login`, which `harvard-huit` already
accepts. This is separate from the GitHub connector setting in claude.ai.
Claude Code's MCP configuration is local to the machine and authenticates
directly against GitHub, not through Anthropic.

### Why `gh auth login` and not an MCP login

You might expect to authenticate in `/mcp`, the way other remote MCP servers
work. That was the first design, and it fails on both hosts for different
reasons.

- **github.com.** Choosing `github` in `/mcp` fails with "Incompatible auth
  server: does not support dynamic client registration". Claude Code's MCP
  OAuth flow registers itself as a client on the fly, and GitHub's
  authorization server does not implement that (Dynamic Client Registration).
  Claude Code's only other option is a pre-registered OAuth app: a client ID
  plus a client secret. That would mean an app to register, an org owner to
  approve it for `harvard-huit` SAML, and a secret to hand to every user,
  which is the kind of shared credential this plugin exists to avoid.
- **GHES.** There is no hosted MCP server for github.huit.harvard.edu at all,
  so the plugin runs `github-mcp-server` locally. That binary can do its own
  device-code login, but only with the OAuth app baked into it, which is
  registered on github.com. Using it against GHES would need an OAuth app
  registered on the GHES instance by an admin.

GitHub CLI already solves both problems: `gh auth login --web` uses GitHub's
own OAuth app, which both hosts accept, issues a short-lived OAuth token
rather than a PAT, and stores it in your keyring. So the plugin reads that
token and passes it along: a `headersHelper` script puts it in the
`Authorization` header for the hosted server, and a wrapper script hands it
to the local binary for GHES. One browser login per host covers both the MCP
tools and the `gh` fallback, and nothing is stored that you did not already
have.

Troubleshooting: if a server shows failed in `/mcp`, run its script by hand to
see why. Find the install path with `claude plugin list --json`
(`installPath`), then `<installPath>/scripts/github-mcp-ghes.sh </dev/null` for
GHES, or `<installPath>/scripts/github-mcp-headers.sh | sed -E 's/Bearer .*/Bearer <redacted>/'`
for github.com (keep the `sed`; the raw output is your token). Usual causes:
no `gh` login for that host, or the GHES binary not on PATH. A 403 mentioning
SAML on github.com means `gh auth refresh --hostname github.com` and
authorizing the token for `harvard-huit`. If `GH_TOKEN` or `GITHUB_TOKEN` is
exported in your shell, `gh` (and therefore both servers) uses that instead of
the keyring login.

## huit-aws

Gets you working AWS CLI credentials for HUIT accounts. HUIT federates
HarvardKey (Okta) straight to IAM roles, so there is no IAM Identity Center and
`aws sso login` does not apply. The skill wraps two tools:

| Tool | Best for | You do | Credentials last |
|---|---|---|---|
| `aws login` (AWS CLI 2.32+), the default | your `default` profile, or one named profile | log into the console in your browser, pick a role, then click once | refreshed every 15 minutes while the console session lives |
| HUIT `aws-login` CLI | every mapped account at once | approve one Okta Verify push | fixed, default 4 hours |

Say "log me into AWS" or run `/huit-aws:aws-login` and the skill opens the
HarvardKey console link, waits for you to pick an account and role, then
attaches `aws login` to that session as your `default` profile. Any saved
profile that points at the same console session is refreshed at the same
time, because `aws login` caches by session, not by profile name. Name a
profile (`/huit-aws:aws-login admints-dev`) to attach under that name
instead, or say "all" for the one-push `aws-login login_all` path. An `aws`
command failing with `ExpiredToken` also triggers it. Every blocking step is
announced before it runs, and it finishes with `aws sts get-caller-identity`.

Profile naming: `aws-login` aliases end in `-login` (`admints-dev-login`);
plain account names (`admints-dev`) and `default` belong to `aws login`.
Static keys in `~/.aws/credentials` win over an `aws login` session under the
same name and make `aws login` refuse that profile, so the skill never runs
`aws-login login <alias>` or `aws-login switch`, both of which write static
keys into `[default]`. If you already have such a `[default]`, the skill asks
you to remove it once.

Requirements: AWS CLI 2.32 or newer for `aws login`; the HUIT `aws-login`
binary (releases on github.huit.harvard.edu, `HUIT/aws-login-saml-cli`) for
the one-push path. The skill can download it for you once `gh` is logged into
GHES. Okta Verify push must be enrolled. `aws-login configure_keyring` once,
in your own terminal, lets the skill run logins without a password prompt.

The skill never reads your credentials files and never prints keys.

## quiz

Three or four multiple-choice questions, answered in Claude Code's select UI,
graded in a sentence each. The point is not the score; it is finding out what
you did not know while it is still cheap to look.

| Skill | Asks about | Say |
|---|---|---|
| `/quiz:session` | what happened in this session: changes you approved without reading, decisions Claude made for you, security-relevant edits, loose ends | "quiz me", "did I miss anything" |
| `/quiz:project` | the gotchas of the repo you are in: rules in `CLAUDE.md`, decisions reversed in git history, setup traps, "do not" comments | "quiz me on this repo", "what should I know before I touch this" |

A bare "quiz me" means the session quiz, unless the session was too small to
have anything in it or was spent learning the project rather than changing it;
then you get the project quiz. Claude also offers the session quiz on its own
after a significant change lands. An argument narrows either quiz, e.g.
`/quiz:session security` or `/quiz:project setup`.

Neither skill changes anything. The project quiz reads files and git history;
in a large repo it uses a read-only subagent for the scan.

## huit-apigee

Replaces the `apigee-pull` / `apigee-push` command files that several proxy
repos carried in drifting copies. Three skills, all driven by small shell
scripts you approve one at a time; the Apigee Management API is called with
`gcloud auth print-access-token`, so the only requirement is a `gcloud` login.

| Skill | Does | Say |
|---|---|---|
| `/huit-apigee:pull [proxy] [rev]` | downloads a revision into `<dir>/apiproxy/`, saves the API product next to it, normalizes line endings, records the revision, lists KVMs / shared flows / target servers the proxy depends on | "pull the bundle", "get the latest revision" |
| `/huit-apigee:push [proxy] [env]` | drift check, pre-push hook, lint, server-side validate, diff against the deployed revision, confirm for stage/prod, import, deploy, wait for READY, smoke test through the gateway, rollback offer | "deploy to dev", "push to apigee", "ship it" |
| `/huit-apigee:status [proxy]` | deployed revision per environment across the nonprod, preprod, and prod orgs; gateway hostnames per environment | "what revision is live", "which org is stage in" |

What it refuses to do: overwrite a bundle directory with uncommitted or
untracked changes (commit, stash, or an explicit `--force`), take the org
from gcloud's active project silently (the environment picks the org:
nonprod for dev/test/sand, preprod for stage, prod for prod), zip anything but
`apiproxy/`, or deploy to stage or prod without showing the diff and asking.

Optional `.apigee.json` at the repo root pins the proxy name and bundle
directory (needed when a repo has more than one `apiproxy/`), overrides orgs
and hosts, adds a pre-push command (spec regeneration), smoke routes with
expected status codes, and a post-deploy command. Header values in smoke
routes are `$VAR` references, read from your shell and never printed. Schema:
`plugins/huit-apigee/references/config.md`. The pull skill writes a gitignored
`.apigee-state.json` that the push skill uses to warn when someone else
imported since your last pull.

The plugin also ships `references/apigee-gotchas.md`: the condition-parser
quirks, path-rewrite rules, TargetEndpoint boundary, BasicAuthentication
`AssignTo` trap, and the one import endpoint that works, collected from five
HUIT proxy repos. The push skill reads it whenever an import or deploy fails.
Debug sessions (`trace`) and KVM editing (`kvm`) are planned, not shipped.

Requirements: `gcloud` (logged in; `gcloud auth login --no-launch-browser` on
Cloud9), `curl`, `python3`, `zip`/`unzip`. No apigeecli needed; it remains a
fine alternative for CI (`apigeecli apis create bundle --ovr --wait`).

## Layout

```
.claude-plugin/marketplace.json          the marketplace (four plugins)
plugins/huit-github/
  .claude-plugin/plugin.json             manifest
  .mcp.json                              github (hosted, headersHelper) + github-huit (wrapper)
  scripts/github-mcp-headers.sh          gh token -> Authorization header for the hosted server
  scripts/github-mcp-ghes.sh             GITHUB_HOST + gh token -> github-mcp-server stdio
  hooks/hooks.json                       SessionStart -> scripts/check-gh-auth.sh
  scripts/check-gh-auth.sh               login nudge, silent when all is well
  skills/github-setup/SKILL.md           the bootstrap walkthrough
plugins/huit-aws/
  .claude-plugin/plugin.json             manifest
  skills/aws-login/SKILL.md              the login walkthrough
plugins/quiz/
  .claude-plugin/plugin.json             manifest
  references/quiz-format.md              question style, asking, grading (shared by both skills)
  skills/session/SKILL.md                what happened in this session
  skills/project/SKILL.md                gotchas of the repo you are in
plugins/huit-apigee/
  .claude-plugin/plugin.json             manifest
  scripts/lib.sh                         token file, .apigee.json reader, proxy/org/bundle resolution
  scripts/fetch.sh                       download a revision; refuses to clobber uncommitted edits
  scripts/import.sh                      zip apiproxy/ only, import or --validate
  scripts/deploy.sh                      record previous revision, deploy, poll to READY
  scripts/smoke.sh                       routes from .apigee.json through the gateway host
  scripts/status.sh, hosts.sh            read-only: deployments per org, env-group hostnames
  scripts/lint-bundle.sh                 manifest vs disk, unstepped policies, known-gotcha patterns
  references/config.md                   .apigee.json / .apigee-state.json schema and HUIT defaults
  references/apigee-gotchas.md           the consolidated Apigee knowledge
  skills/pull, push, status/SKILL.md
```

Validate before committing:

```
claude plugin validate .
claude plugin validate plugins/huit-github
claude plugin validate plugins/huit-github/skills
claude plugin validate plugins/huit-aws
claude plugin validate plugins/huit-aws/skills
claude plugin validate plugins/quiz
claude plugin validate plugins/quiz/skills
claude plugin validate plugins/huit-apigee
claude plugin validate plugins/huit-apigee/skills
```

Bump the plugin's `version` on every change you publish; that field is what
tells installed copies an update exists.
