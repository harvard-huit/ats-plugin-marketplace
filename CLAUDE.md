# huit-agent-plugins

A self-hosting Claude Code plugin marketplace for the AAIS group / HUIT org.
Repo: `harvard-huit/huit-agent-plugins` (github.com, **public** by decision
on 2026-09-25, see the visibility item under open questions). Marketplace
name: `huit-agent-plugins`. It holds four plugins: `huit-github`, which gives
people a working GitHub integration **without creating or storing a Personal
Access Token**, `huit-aws`, which logs people into HUIT AWS accounts via
HarvardKey (see "huit-aws plugin" below), `quiz`, multiple-choice
comprehension checks on the current session or a repo's gotchas (see "quiz
plugin" below), and `huit-apigee`, pull/push/status for Apigee X proxy
bundles (see "huit-apigee plugin" below). Onboarding is two slash commands
per plugin.

Status (2026-09-19): restructured to `plugins/<name>/`, both plugins validate
and install locally. The GHES path is verified end to end. Nothing is committed
or published yet.
Status (2026-09-20): the github.com path no longer uses the hosted server's
own OAuth (`/mcp` login fails, see decision 2). It now reuses `gh`'s token via
a `headersHelper` script; `huit-github` bumped to 0.3.0.
Status (2026-09-25): renamed from `huit-claude-plugins` to `huit-agent-plugins`
(repo, marketplace name, local checkout) before anyone else installs it, so
the name is vendor-neutral. Versions bumped to 0.3.1 / 0.1.1 for the new
`repository` URL. Still not announced to the org.
Status (2026-09-25, later): added the `quiz` plugin (0.1.0) with `session`
(moved from JaZahn's personal `session-quiz` skill) and a new `project` skill.
Committed as 197a9d9 and pushed to `main` 2026-09-26; the personal
`session-quiz` was deleted the same day. Two copies exist on JaZahn's
machine: the marketplace install in `~/.claude/plugins/cache/` (the one that
loaded on 2026-09-26) and `quiz@synced` from claude.ai plugin sync. They
carry the same version; if they ever diverge, the cache copy is the one
`/plugin update` refreshes.
Status (2026-09-26): `huit-aws` 0.2.0. The `aws-login` skill now defaults to
`aws login` into the `default` profile (person picks any role in the console)
and refreshes saved profiles that share the session; `login_all` is the
"all" path only. Committed as 0952f0b.
Status (2026-09-28): a `huit-slack` plugin was designed and its Slack app
**rejected** by the Harvard Slack Grid admins. Not built. See "huit-slack
(rejected)" below and issue #2.
Status (2026-09-29): added the `huit-apigee` plugin (0.1.0) from issue #5
with `pull`, `push`, `status` skills, eight scripts, and two references.
`trace` and `kvm` deferred. Scripts tested live read-only against
`ats-snow-proxy` (fetch, dirty-tree refusal, validate-only import, status,
hosts, smoke); no revision was created and nothing was deployed. Uncommitted;
the five proxy repos are not migrated yet.

@.claude/memory/INDEX.md

## Why this exists

- The org has not approved the GitHub connector in claude.ai. That is a Claude
  admin setting for claude.ai; Claude Code's MCP config is separate and local.
  Adding GitHub's MCP server here does OAuth directly against GitHub, not through
  Anthropic. Be transparent with the admins about this rather than treating it as
  a workaround. Ask before publishing to the org.
- Current practice is PAT-based (`GITHUB_PAT`, `GITHUB_HUIT_PAT` in
  `~/.claude/.credentials.env`). PATs are long-lived, over-scoped, and each person
  has to make and guard their own. Goal is zero PATs for plugin users.

## Two GitHubs, two auth paths

| Host | Org | Hosted MCP server (token from `gh` via `headersHelper`) | `gh` device-flow login | Local MCP binary |
|---|---|---|---|---|
| github.com | `harvard-huit` (SAML SSO) | yes, primary path | yes | not needed |
| github.huit.harvard.edu (GHES 3.19) | `HUIT` | **no** (GHES has no remote hosting) | yes, verified 2026-09-19 | yes, via `GITHUB_HOST` |

Some repos are live on GHES while the github.com copy is a stale mirror. Check
`pushed_at` on both before assuming which is canonical. Cross-instance `#N`
references do not auto-link.

## Design decisions (made 2026-09-19)

1. **One repo is both the plugins and the marketplace.** `.claude-plugin/marketplace.json`
   at the root lists each plugin with `"source": "./plugins/<name>"`. Users run
   `/plugin marketplace add harvard-huit/huit-agent-plugins` then
   `/plugin install <name>@huit-agent-plugins`. Naming history: started as
   `huit-github-plugin`; renamed 2026-09-19 to `huit-claude-plugins` so the
   marketplace can grow beyond GitHub (the same day `huit-github` moved from
   the repo root to `plugins/huit-github/`, version 0.1.0 to 0.2.0, when
   `huit-aws` was added); renamed 2026-09-25 to `huit-agent-plugins` to drop
   the vendor name. The marketplace name is baked into every user's install
   command and local registration, so **do not rename again** once anyone
   else has added it.
   **Codex / Agent Plugins (checked 2026-09-25):** OpenAI's Codex reads the
   same `skills/<name>/SKILL.md` layout and accepts
   `.claude-plugin/marketplace.json` as a legacy fallback, so a Codex port of
   this repo is plausible but not "just an extra directory". Codex wants a
   root `plugin.json` in the vendor-neutral Agent Plugins schema
   (agent-plugins.org; steering committee is Amazon, Cursor, Microsoft,
   OpenAI, Vercel, not Anthropic) and a root `mcp.json`. It has no
   `headersHelper` and no `${CLAUDE_PLUGIN_ROOT}`, and declares hooks under
   an `extensions.com.openai` namespace. The GHES-style stdio wrapper that
   reads the token from `gh` is the pattern that would port; keep it.
2. **github.com path is GitHub's hosted MCP server over HTTP, authenticated
   with `gh`'s token through a `headersHelper`.** Declared in plugin-root
   `.mcp.json` as `{"type": "http", "url": "https://api.githubcopilot.com/mcp/",
   "headersHelper": "${CLAUDE_PLUGIN_ROOT}/bin/github-mcp-headers.sh"}`. The
   helper prints `{"Authorization":"Bearer <gh auth token>"}`; Claude Code runs
   it on every connection and again after a 401/403. `${CLAUDE_PLUGIN_ROOT}` is
   documented as expanded in `url`, `headers`, and `headersHelper`.
   **The server's own OAuth does not work from Claude Code** (hit 2026-09-20):
   GitHub's authorization server has no Dynamic Client Registration, so
   choosing `github` in `/mcp` fails with "Incompatible auth server: does not
   support dynamic client registration". Claude Code's alternative is a
   pre-registered `oauth.clientId` plus a client secret, which would mean an
   OAuth app registration and a secret to distribute; the `gh` token needs
   neither. Verified 2026-09-20 that the hosted server answers `initialize`
   with 200 given a `gh`-stored token and 401 without one. Caveat: the token
   in this machine's keyring for github.com is a classic PAT (`ghp_`, pasted
   in at some point), so acceptance of a device-flow `gho_` token is expected
   but not yet observed. No org-owner approval of an OAuth app is needed on
   this path; SAML authorization of the `gh` token (`gh auth refresh`) is the
   only per-person step.
3. **GHES path is the local `github-mcp-server` binary behind a wrapper script.**
   `bin/github-mcp-ghes.sh` sets `GITHUB_HOST=https://github.huit.harvard.edu`,
   pulls the token from `gh auth token --hostname github.huit.harvard.edu`, and
   execs `github-mcp-server stdio`. The binary is on Homebrew (`github-mcp-server`,
   1.12.x at time of writing) and Docker. No PAT: the token comes from `gh`'s
   OAuth device-flow login.
4. **A `github-setup` skill does the bootstrap.** It checks for `gh` and the MCP
   binary, offers the install commands (brew on Mac, apt/dnf otherwise), runs
   `gh auth login --hostname <host> --web` for whichever host the person needs.
   No `/mcp` login on either host; both servers read the `gh` token. A skill
   cannot install anything itself; it instructs Claude, and the user approves
   each command.
5. **A `SessionStart` hook nudges, never blocks.** `hooks/hooks.json` runs a
   script that checks `gh auth status` for both hosts and prints a one-line hint
   if either is missing. It must exit 0 quickly and be silent when all is well.
6. **Permissions are NOT shipped in the plugin.** Plugin-root `settings.json`
   only supports `agent` and `subagentStatusLine`; permission keys are rejected.
   So the plugin cannot pre-allow `Bash(gh *)`. Instead the setup skill offers to
   add a narrow read-only allowlist to the user's `~/.claude/settings.json`
   (e.g. `Bash(gh pr view *)`, `Bash(gh pr list *)`, `Bash(gh issue view *)`,
   `Bash(gh issue list *)`, `Bash(gh repo view *)`, `Bash(gh api *)` read-only).
   Writes should keep prompting. Never allow bare `Bash(gh *)`.
7. **`gh` is the fallback when MCP tools are unavailable.** Skill guidance should
   prefer MCP tools when the server is connected and fall back to `gh` otherwise,
   so the plugin still works for someone who only did the `gh` login.

## Layout

```
huit-agent-plugins/
├── .claude-plugin/
│   └── marketplace.json      # name: huit-agent-plugins, plugins: huit-github, huit-aws
├── plugins/
│   ├── huit-github/
│   │   ├── .claude-plugin/plugin.json   # name, version, description, author, repository
│   │   ├── .mcp.json                    # github (hosted http, headersHelper) + github-huit (wrapper script)
│   │   ├── bin/github-mcp-headers.sh    # gh auth token -> {"Authorization":"Bearer ..."} for the hosted server
│   │   ├── bin/github-mcp-ghes.sh       # GITHUB_HOST + gh auth token -> github-mcp-server stdio
│   │   ├── hooks/hooks.json             # SessionStart -> scripts/check-gh-auth.sh
│   │   ├── scripts/check-gh-auth.sh
│   │   └── skills/github-setup/SKILL.md # install gh / MCP binary, device-flow login per host, /mcp, allowlist
│   ├── huit-aws/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/aws-login/SKILL.md    # aws-login login_all or aws login attach; see design below
│   ├── quiz/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── references/quiz-format.md    # shared: writing questions, asking, grading
│   │   ├── skills/session/SKILL.md      # /quiz:session, the default "quiz me"
│   │   └── skills/project/SKILL.md      # /quiz:project, gotchas of the repo
│   └── huit-apigee/
│       ├── .claude-plugin/plugin.json
│       ├── scripts/                     # lib, fetch, import, deploy, smoke, status, hosts, lint-bundle
│       ├── references/config.md         # .apigee.json / .apigee-state.json, verified HUIT org+host table
│       ├── references/apigee-gotchas.md # consolidated Apigee knowledge from five proxy repos
│       └── skills/{pull,push,status}/SKILL.md
├── README.md                 # user-facing: install, updates, one section per plugin
├── CLAUDE.md                 # this file
└── .claude/memory/INDEX.md   # committed project memory (portable across machines)
```

Inside each plugin, only `plugin.json` lives in `.claude-plugin/`; everything
else is at that plugin's root. Use `"${CLAUDE_PLUGIN_ROOT}"/bin/... ` (quoted)
in hook commands and `.mcp.json` so paths resolve after install. Skill `name`
in frontmatter is the invocation name (`/<plugin>:<skill>`); keep it stable.

## Open questions to settle first

- [x] **Does `gh auth login --hostname github.huit.harvard.edu --web` work?**
      Yes (verified 2026-09-19, gh 2.96.0): `gh api --hostname
      github.huit.harvard.edu user` returns the login, and `GH_HOST=... gh
      release download` works. The `Authorization: Bearer` 401 applies only to
      classic PATs, not to OAuth tokens from device-flow login. GHES shows
      3.19 in its API docs URL now, not 3.17.
- [x] **Does the local `github-mcp-server` work against that GHES with the `gh` token?**
      Yes (verified 2026-09-19, binary 1.12.2): the wrapper started with
      `host=https://github.huit.harvard.edu`, and `get_me` plus
      `search_repositories` succeeded over stdio using the `gh` OAuth token.
- [ ] **Does the hosted server need a Copilot license or org policy?** Nothing
      documented says so. It answered JaZahn's `gh`-stored token on 2026-09-20;
      still confirm with an account that has no Copilot seat.
- [x] **Who authorizes the OAuth app for `harvard-huit` SAML?** Moot as of
      2026-09-20: the hosted server's OAuth flow is unusable from Claude Code
      (no DCR), and the `gh`-token path uses GitHub CLI's own OAuth app, which
      the org already accepts wherever `gh` works against it.
- [ ] **Does a device-flow `gho_` token work with the hosted server?** Expected
      yes; verify by running `gh auth login --hostname github.com --web` on a
      machine whose keyring holds a PAT, then checking `/mcp` shows `github`
      connected.
- [x] **Where does the marketplace repo live, and at what visibility?** github.com
      `harvard-huit/huit-agent-plugins`, **public** (decided 2026-09-25 by
      JaZahn). Internal was the original intent, but it would force a
      SAML-authorized github.com login before `/plugin marketplace add`, and
      the goal is that anyone can install regardless of `harvard-huit` org
      access. Basis: a scan of every tracked file and the full commit history
      found no tokens, keys, or account IDs; the org permits member-created
      public repos; write access is unchanged by visibility. Known
      disclosures accepted as non-secret: the GHES hostname (public DNS), the
      Okta embed link (useless without HarvardKey; mention it to HUIT
      security), the `admints-dev` example alias and the
      `*-standard-saml-poweruser-iam-role` naming pattern. Follow-ups: add a
      license (public with no license is all-rights-reserved), tell the
      admins before announcing, consider branch protection on `main`, and
      optionally swap `admints-dev` for a generic placeholder in user-facing
      files.
- [x] **Does the local server's OAuth device-code fallback work for GHES?**
      Only with an OAuth App or GitHub App registered on the GHES instance and its
      client ID passed via `GITHUB_OAUTH_CLIENT_ID`; the baked-in app is github.com
      only. That is an admin ask we do not need, so the wrapper keeps using `gh`.

## huit-aws plugin

Log into HUIT AWS accounts from Claude Code. Wraps two tools rather than
replacing either: the HUIT `aws-login` binary (SAML via HarvardKey + Okta Verify
push; canonical repo `HUIT/aws-login-saml-cli` on GHES, github.com mirror
`harvard-huit/aws-login-saml-cli`) and the native `aws login` command (AWS CLI
2.32.0+). Skill first, hook second. The skill lives at
`plugins/huit-aws/skills/aws-login/SKILL.md` and is invoked as
`/huit-aws:aws-login <account>`. It was drafted as a personal skill on
2026-09-19 and moved here the same day; the personal copy was deleted so there
is one source of truth.

### Facts established 2026-09-19 (do not re-derive)

- **`aws sso login` does not apply.** HUIT federates SAML straight to IAM roles
  (`*-standard-saml-poweruser-iam-role`); there is no IAM Identity Center.
- **IAM SAML federation is IdP-initiated only.** AWS's sign-in page cannot
  redirect to Okta, so `aws login`'s "sign in to new session" button lands on the
  IAM-user page and is a dead end for us. There is no config key that accepts an
  IdP URL. `login_session` is an identity ARN
  (`arn:aws:sts::<acct>:assumed-role/<role>@<region>/<user>`), not a location.
- **The working `aws login` flow is: console session first, then attach.** Open
  the Okta embed link, finish HarvardKey and pick the role, then run
  `aws login --profile <alias>` and select the existing session in the browser.
  Confirmed working for one role; the role therefore already carries the
  `SignInLocalDevelopmentAccess` policy that `aws login` requires.
- **Okta embed link is per-app, not per-user**, so one URL serves everyone in
  HUIT with the AWS console app:
  `https://login.harvard.edu/home/harvard_awsconsole_1/0oa1u9wgsl3Ca8aIO1d8/aln1u9wlto0AtKDqe1d8`.
  Keep it as one named constant in the skill.
- **Trade-off between the two tools.** `aws-login login_all` gets every mapped
  profile from a single Okta push (best for multi-account). `aws login` needs
  one console login per role but refreshes credentials every 15 minutes for the
  life of the console session, bounded by the role's max session duration (best
  for a long single-role session). Console multi-session allows up to five role
  sessions in one browser, so several `aws login --profile` attachments are
  possible without logging out.
- **Both tools block on out-of-band action** (push approval or browser click).
  The skill must say so and not treat a long-running command as a hang.
- **`aws-login` surface (v2.0.x).** Subcommands: `login [alias]`, `login_all`,
  `list`, `list-role-map`, `switch <alias>`, `assume <alias>`,
  `configure_keyring`. Flags: `-version`, `-show-config` (prints the loaded
  config as JSON, creates an empty config file if none), `-h`, `-v`, `-t`,
  `-keyring=false`, `-d` (prints credentials, never use). **Bare `aws-login` is
  `login`**, which prompts for a password and a role picker. Config path is
  `~/Library/Application Support/huit_aws/config.json` on macOS and
  `~/.config/huit_aws/config.json` on Linux. Releases: 2.0.3 (2025-06, what is
  installed here), 2.0.4 (2026-05-19, latest stable), 2.1.0-beta1 (2026-06,
  adds browser `-passkey` login; prerelease). Local checkout at
  `~/workshop/aws-login-saml-cli` is at the 2025-06-09 commit.
- **Interactive prompts cannot be answered from Claude's Bash tool.** The
  `Enter Password:` prompt (no keyring), `login` without an alias (role picker),
  and `aws login --remote` (paste a code) all need the person's own terminal.
  With `configure_keyring` done, `login_all` needs only the push approval and
  runs fine from Claude.
- **Credential precedence gotcha (verified in bundled botocore, awscli 2.36.49).**
  Profile providers run in this order: web-identity, sso, shared-credentials-file,
  login, custom-process, config-file. So a `[<alias>]` stanza that `aws-login`
  wrote in `~/.aws/credentials` beats `login_session` for the same profile name in
  `~/.aws/config`, and once those static keys expire the profile fails with
  `ExpiredToken` even though the `aws login` session is healthy.
- **`aws login` auto-refresh confirmed 2026-09-19.** With
  `AWS_SHARED_CREDENTIALS_FILE=/dev/null` the `default` profile (where the test
  `login_session` landed, because `aws login` was run without `--profile`)
  resolved via the login provider and the cache expiry advanced by 15 minutes.
- **`gh release download` from GHES works** now that `gh` holds a GHES OAuth
  login, so the skill can offer the `aws-login` install without curl or a PAT.

### Facts established 2026-09-26 (from awscli 2.36.49 and aws-login source, do not re-derive)

- **`aws login` caches by session, not profile.** The cache file is
  `~/.aws/login/cache/<sha256(login_session ARN)>.json`
  (`botocore.utils.generate_login_cache_key`). Every profile whose
  `login_session` equals the same ARN reads the same cache, so one attach
  refreshes all of them. The ARN is stable per person, role, and region.
- **`aws login` refuses a profile with static keys**, error `Profile 'X' is
  already configured with Access Key credentials`. The check reads
  `session.full_config`, which merges `~/.aws/credentials` into the profile
  map, so an `aws-login` stanza under the same name blocks it.
- **`aws login` writes `[default]` in `~/.aws/config`** when the profile is
  `default` (`[profile X]` otherwise), plus `region` only if it had to prompt.
  It honors `AWS_PROFILE` when `--profile` is absent, so the skill always
  passes `--profile`.
- **Overwriting an existing `login_session` prompts `(y/n)` on stdin.** From
  Claude's Bash tool that is EOF and a traceback; `printf 'y\n' | aws login
  --profile X` answers it. The prompt is skipped when the ARN is unchanged.
- **`aws logout --profile X`** deletes only the cache file for X's session
  (which other profiles may share); it does not remove `login_session` from
  the config, so it does not avoid the prompt above.
- **`aws-login` and `default`:** `login <alias>` and `switch <alias>` write
  static keys into `[default]` in `~/.aws/credentials` (`commands.go`
  `SaveAwsCredentials` with a default credential, and `switchRoles`).
  `login_all` passes `nil` and writes only the mapped aliases. So the skill
  runs `login_all` but never `login <alias>` or `switch`. The empty
  `[DEFAULT]` (uppercase) seen in some credentials files is a leftover of the
  ini library's special section; harmless.
- `aws configure get login_session --profile X` reads the key without opening
  the config file by hand (exit 1 when absent); `aws configure list-profiles`
  lists names from both files.

### Skill design (`skills/aws-login/SKILL.md`)

- Two branches, chosen by the request (changed 2026-09-26 by JaZahn; before
  that, no alias meant `login_all`):
  - **Default, `aws login` (branch B):** no profile named means target
    `default`; the person picks any account and role on the Okta role
    chooser. A named profile means `--profile <name>`. Flow: check the target
    for static keys and an existing `login_session`, `open <okta-url>` (Mac)
    or print the URL (Linux), end the turn, then on their go-ahead run
    `aws login --profile <target>` (piping `y` if a session is being
    replaced), verify with STS, then compare the new `login_session` against
    every profile from `aws configure list-profiles`: same ARN means already
    refreshed (say so, verify); a plain-name profile for the same account
    with a different or no session gets an offered `aws login --profile
    <name>` (one click, same console session); a `<name>-login` static alias
    cannot be refreshed this way, offer branch A. On a host without a browser
    (Cloud9) use `aws login --remote`.
  - **Branch A, `aws-login login_all`:** "all", "everything", several
    aliases, or `aws-login` asked for by name; also the fallback when `aws
    login` is unavailable.
- Always finish with `aws sts get-caller-identity --profile <alias>`.
- Read aliases from `aws-login list-role-map`; never hardcode a person's
  aliases or account IDs in the plugin.
- Never run `aws-login switch` or `aws-login login <alias>`: both write static
  keys to `[default]`, which shadows and then blocks the `aws login` default
  session (see the 2026-09-26 facts). A `[default]` with static keys is the
  one edit the skill asks the person to make.
- **Profile naming convention (decided 2026-09-19 by JaZahn):** `aws-login`
  aliases in `profile_map` end in `-login` (`admints-dev-login`), and `aws
  login` sessions use the plain account name (`admints-dev`). This avoids the
  precedence gotcha above. The skill checks for a static stanza under the plain
  name before attaching and, if one exists, offers to rename the aliases in the
  config rather than attaching under a colliding name.
- `aws-login` on macOS reads only `~/Library/Application Support/huit_aws/config.json`.
  `~/.huit_aws/config` (1.x) and `~/.config/huit_aws/config.json` may linger
  from older installs and are ignored there; the skill says so. The timeout
  key is `default_timeout_secs`; `default_timeout_sec` is silently ignored.
- The skill never edits `~/.aws/config` or `~/.aws/credentials` and never reads
  the credentials file or `~/.aws/login/cache/`; validity is checked with STS.

### To do

- [x] Draft the skill (2026-09-19), move `huit-github` to `plugins/huit-github/`
      and add `plugins/huit-aws/` (same day; `huit-github` bumped to 0.2.0).
- [ ] Use the skill against real logins for a while before publishing. Still
      unverified: whether `aws login --profile <new-name>` creates a
      `[profile ...]` stanza in `~/.aws/config` for a name that does not exist
      yet, and whether it writes `region`.
- [x] Next `aws-login login_all` should write `*-login` stanzas only; confirmed
      from source 2026-09-26: `login_all` writes only mapped aliases. The
      `[default]` static stanza comes from `login <alias>` or `switch`.
- [ ] Exercise the new default flow end to end: remove the static `[default]`
      from `~/.aws/credentials`, run `aws login --profile default` with a
      different role than the one currently in `default` (the `printf 'y\n'`
      path), and confirm `admints-<x>` reports "same session (refreshed)".
- [ ] Test the single-alias branch on Cloud9: no `open`, must fall back to the
      printed URL and `aws login --remote`.
- [ ] Confirm `SignInLocalDevelopmentAccess` is on every standard SAML role, not
      just the one tested. If not, that is a HUIT cloud team ask; document who.
- [ ] Decide whether the credential check is a `SessionStart` nudge (matches
      `huit-github`) or a `PreToolUse` hook on `Bash` commands starting with
      `aws ` that fails fast with "run /aws-login" when credentials are expired.
      The PreToolUse form saves a wasted turn but is the first blocking hook in
      the marketplace; keep it silent when credentials are valid either way.
- [ ] Test the install story drafted in the skill on a clean machine:
      `GH_HOST=github.huit.harvard.edu gh release download -R HUIT/aws-login-saml-cli`
      with the `{Darwin,Linux}-{arm64,x86_64}` asset pattern, Gatekeeper
      `xattr` step, `~/bin` on PATH, then config.json from `aws-login list`.
- [x] Probe for installed vs configured: `aws-login -version` and
      `aws-login -show-config` (empty `profile_map` means not configured).

## quiz plugin

Comprehension checks, decided 2026-09-25. The plugin boundary is the *quiz*
axis, not the *session* axis: a session quiz and a project quiz share the
question style, the ask mechanics, and the grading (one file,
`references/quiz-format.md`, referenced from both skills via
`${CLAUDE_PLUGIN_ROOT}`, which Claude Code substitutes in plugin skill
content), and the same person wants both. The cost-report skills
(`session-token-report`, `weekly-cost-report`) share only a data source with
the quiz, so they stay personal; a separate plugin if anyone asks. Plugin
name `quiz` was chosen for the invocation (`/quiz:session`, `/quiz:project`);
"tools" was rejected as a catch-all that invites dumping.

- **Disambiguation rule (JaZahn, 2026-09-25):** a bare "quiz me" means
  `session`, unless the session is so small nothing was really done, or the
  session was specifically about the project (exploring or learning it rather
  than changing it); then `project`. Both descriptions carry the rule, because
  the description is all Claude sees when choosing a skill. Each skill body
  also says when to hand off to the other.
- `session` is the former personal `~/.claude/skills/session-quiz` verbatim,
  minus the format section (now shared). `spin-down` (personal, not in the
  marketplace: it encodes JaZahn's memory routing) invokes `quiz:session`
  first and falls back to `session-quiz`, then to inline questions.
- `project` reads only. In a large repo it delegates the wide scans to an
  Explore subagent. It ranks candidates by cost-of-being-wrong: security,
  conventions with no guardrail, reversed decisions, setup traps.
- [x] Installed from the pushed commit 2026-09-26; `/quiz:session` and
  `/quiz:project` both appear after `/reload-plugins`; personal
  `session-quiz` deleted. Gotcha: the desktop app's "check for updates"
  refreshes the marketplace clone but not the plugin picker, see
  `.claude/memory/marketplace-update-vs-plugin-list.md`.
- [x] Verified 2026-09-26 on the first `/quiz:session` run from the installed
  copy: `${CLAUDE_PLUGIN_ROOT}` was substituted to the cache path and
  `references/quiz-format.md` read fine. Consequence: a quiz skill zipped on
  its own for claude.ai upload loses its format; upload the plugin, not a
  skill.

## huit-slack (rejected, not built)

Full design record is issue #2 on this repo; do not re-derive it. The short
version, so nobody retries the same route:

- Slack's hosted MCP server (`https://mcp.slack.com/mcp`) is "bring your own
  app": any Marketplace or internal Slack app with the Model Context Protocol
  toggle on and PKCE enabled works as the OAuth client, no server code and no
  client secret. Claude Code config is `{"type":"http","url":...,"oauth":
  {"clientId":..., "callbackPort":...}}`. A `huit-slack` plugin would be that
  one file.
- An internal app with the read-and-post user scopes was submitted and
  **rejected 2026-09-28** on two independent Harvard Slack Grid rules: AI
  assistants, connectors, and bots (Claude, ChatGPT) are not approved at all,
  and the history scopes (`channels:history`, `groups:history`,
  `mpim:history`, `im:history`) are not approved for any app. Dropping DM
  scopes would not have helped. The internal-app route got the same reviewers
  and the same blanket policy as the Marketplace connector.
- The policy is under review with ISDP holding the green light, aimed at the
  *official* ChatGPT and Claude connectors. If that lands, the answer is
  Anthropic's official `slack` plugin, not a custom app; add a README pointer
  and close #2. Revive the custom design only if AI connectors are approved
  but the official one is still refused.
- Never name the Slack admin in this repo or its issues; the repo is public.

## huit-apigee plugin

Designed in issue #5 (github.com `harvard-huit/huit-agent-plugins`), which
lists what the old `~/.claude/commands/apigee-{pull,push}.md` and the
`aais-maestro-api/.claude/commands/` copies got wrong. First draft built
2026-09-29: `pull`, `push`, `status` skills over REST scripts (curl plus
`gcloud auth print-access-token`); apigeecli is not required. `trace` and
`kvm` are designed in the issue but not built. Consumers to migrate after it
ships: `ats-snow-proxy`, `aais-splunk-api`, `aais-idphoto-api`,
`aais-maestro-api`, `person-api-proxy` (add `.apigee.json`, delete the
command copies, move the Apigee gotcha sections out of their CLAUDE.md files
and point at `references/apigee-gotchas.md`).

### Facts established 2026-09-29 (verified live, do not re-derive)

- **Org per env, from the env groups API:** `apigee-x-nonprod-406719` hosts
  dev, test, sand, train, archive; `apigee-x-preprod` hosts stage;
  `apigee-x-prod-406719` hosts prod. `ats-snow-proxy/CLAUDE.md` saying
  nonprod hosts stage is wrong.
- **Hosts:** `go.<env>.apis.huit.harvard.edu` for dev, test, sand, stage.
  Prod has both `go.apis.huit.harvard.edu` and `go.prod.apis.huit.harvard.edu`
  attached, so both documented forms work. `test` has its own host (the old
  command mapped it to stage's). `train` and `archive` share dev's group.
  Every group also has bare `<env>.apis...` and `apigee-x.<env>.apis...`
  names; the scripts prefer `go.*`. Table lives in `references/config.md`.
- `action=validate` on `POST /apis?action=validate&name=X` with the multipart
  zip works on nonprod and creates no revision (response has no `revision`).
- Lint findings on the real bundles: `validate-spec` and `Quota-1` are
  declared but never stepped in snow, splunk, maestro; snow's default flow
  uses `MatchesPath "/"`; maestro's `am-set-path-api` and person-api's
  `am-post` use `<Set><Path>`. Parenthesized `!=` conditions deploy fine in
  splunk and person-api, so the "`!=` fails deploy" gotcha from maestro
  applies to unparenthesized `!=` combined with and/or, and to `NotLike`; the
  lint warns only on those.
- macOS `/usr/bin/env bash` is 3.2: the scripts avoid associative arrays and
  `mapfile`, and guard empty-array expansions with `${arr[@]+"${arr[@]}"}`.
- The token never touches stdout or `ps`: `lib.sh` writes it to a mode-600
  temp file that curl reads with `-H @file`, removed on exit.
- `unzip -l` prints the archive path in its header, so content checks must
  use `unzip -Z1` (a `grep '\.zip$'` on `-l` output matched the archive
  itself).
- `gcloud auth print-access-token` failed once at the start of the session
  and worked minutes later without a re-login; treat a single failure as
  transient before telling the person to log in again.

### Design

- **Config:** `.apigee.json` at the consumer repo root (`proxy`, `bundleDir`,
  `envs.<env>.{org,host,confirm,note}`, `prePush`, `smoke[]`, `postDeploy`);
  `.apigee-state.json` written by pull, gitignored, read by push's drift
  check. Resolution: flag > config > HUIT default table > gcloud project
  (with a warning). Schema in `references/config.md`.
- **Scripts** (`scripts/`, bash 3.2 compatible, `set -euo pipefail`,
  human summary on stderr, JSON on stdout, `--help` everywhere): `lib.sh`,
  `fetch.sh` (refuses on a dirty or non-git bundle dir; `--force` to
  override; `--product` writes the product JSON *outside* the bundle;
  `--lf`), `import.sh` (zips only `apiproxy/`, excludes `.DS_Store`, dies if
  a product JSON or zip is inside; `--validate`), `deploy.sh` (prints
  `previousRevision` and the rollback command before deploying; exit 6 on
  ERROR, 7 on timeout), `smoke.sh` (routes from config, `$VAR` headers
  expanded and never printed, host from `hosts.sh`), `status.sh`, `hosts.sh`,
  `lint-bundle.sh` (errors for what fails import; warnings for drift and the
  gotcha patterns).
- **Skills** call one script per step so each network action is one approval.
  `push` order: resolve, drift check, prePush, lint, validate, diff against
  the deployed revision, confirm (stage/prod or org mismatch), import,
  deploy, smoke, postDeploy, report. No archive-zip step.
- Proxy name comes from the `<APIProxy name>` manifest, never the directory.
  More than one `apiproxy/` (idphoto) is refused until `bundleDir` pins it.

### To do

- [ ] Commit and push, then install from the marketplace and run
      `/huit-apigee:status` and `/huit-apigee:pull` from an installed copy.
- [ ] First real `push` to dev (ats-snow-proxy is the candidate once its
      spec rewrite is committed): exercise import, deploy, `previousRevision`,
      smoke, and the rollback offer. Not done in this pass by decision.
- [ ] Migrate the five repos; delete `~/.claude/commands/apigee-*.md` and
      `aais-maestro-api/.claude/commands/apigee-*.md`.
- [ ] `trace` skill (debug sessions: `?timeout=180`, no `count`) and `kvm`
      skill (names only, values never echoed); then fix snow's misnamed
      `apikey` KVM entry.
- [ ] Decide whether `push` should offer a read-only `settings.json`
      allowlist (`status.sh`, `hosts.sh`, `lint-bundle.sh`); never
      `gcloud auth print-access-token`.

## Conventions

- Validate before every commit. Each `claude plugin validate <dir>` call checks
  one thing: the marketplace manifest for `.`, a plugin manifest for a plugin
  dir, and skill frontmatter for a `skills` dir. So run all nine:
  `claude plugin validate .`, then `... plugins/<name>` and
  `... plugins/<name>/skills` for each of `huit-github`, `huit-aws`, `quiz`,
  `huit-apigee`.
- Test locally with `/plugin marketplace add ~/workshop/huit-agent-plugins` then
  `/plugin install <name>@huit-agent-plugins` (or the same via `claude plugin ...`
  on the CLI). Installs copy to `~/.claude/plugins/cache/huit-agent-plugins/<name>/<version>/`;
  `claude plugin list --json` shows `installPath`. The cache is a copy, not a
  link: after editing anything, `claude plugin uninstall` then `install` again
  (or bump the version). `.mcp.json` and hooks are read at install time; skills
  at session start. A local-path install copies gitignored files too, so nothing
  sensitive may sit in this tree.
- **Bump `version` in the plugin's `plugin.json` on every published change.**
  That field is the update signal: Claude Code refreshes marketplaces in the
  background after session start (when auto-update is enabled for the
  marketplace, which is off by default for non-Anthropic marketplaces) and
  prompts `/reload-plugins` when a version changed. Without a bump users keep
  the cached copy. Manual path: `/plugin marketplace update huit-agent-plugins`
  then `/plugin update <name>@huit-agent-plugins`. Admins can set
  `autoUpdate: true` on the marketplace entry in managed settings. No custom
  update-check hook; the built-in mechanism covers it.
- Scripts must be executable in git (`chmod +x`, and check `git ls-files -s`
  shows mode 100755); the installer preserves modes, it does not add them.
- Do not put a `.mcp.json` at the repo root. Claude Code reads a root
  `.mcp.json` as a *project* MCP config whenever this repo is the working
  directory, and `${CLAUDE_PLUGIN_ROOT}` is not expanded there, so a phantom
  `github-huit` failed with ENOENT in every session opened here until the
  plugin moved under `plugins/`.
- `brew install github-mcp-server` has no bottle on macOS versions Homebrew
  no longer supports (Tier 3, e.g. macOS 14) and exits without installing.
  The setup skill's fallback is the release tarball via
  `gh release download -R github/github-mcp-server` into `~/.local/bin`,
  checksum-verified. Tested 2026-09-19.
- Hook and wrapper scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, no
  Mac-only paths (this will run on Linux too). Never print tokens.
- **Testing token-emitting scripts from Claude's Bash tool.** Always redact:
  pipe `bin/github-mcp-headers.sh` through
  `sed -E 's/Bearer [A-Za-z0-9_]+/Bearer <redacted>/'` and `gh auth token`
  through `cut -c1-4`. Pointing `gh` at an empty `GH_CONFIG_DIR` is **not** a
  no-login simulation: `gh` still finds the keyring entry and also honors
  `GH_TOKEN`/`GITHUB_TOKEN`. A 2026-09-20 attempt at exactly that printed a
  live PAT into a transcript. Simulate "no login" with `PATH` that lacks `gh`,
  or by unsetting the env vars and using a throwaway `GH_CONFIG_DIR` **and**
  `GH_TOKEN=` only if you have first confirmed there is no keyring entry.
- Never put a token, hostname-specific secret, or a person's login in this repo.
- Memory routing: durable, portable, project-scoped facts go in
  `.claude/memory/` here (this repo is git-tracked). Machine-specific facts stay
  in `~/.claude` memory.
- `~/workshop/claude-plugins/` is an empty shell created the same morning, now
  superseded by this repo (which is the multi-plugin marketplace). Safe to delete.

## References

- Plugin reference: https://code.claude.com/docs/en/plugins-reference.md
- Marketplaces: https://code.claude.com/docs/en/plugin-marketplaces.md
- Managed MCP / managed settings (if admins later want to push this org-wide):
  https://code.claude.com/docs/en/managed-mcp.md
- GitHub MCP server (remote OAuth, local binary, `GITHUB_HOST`): https://github.com/github/github-mcp-server
- `gh auth login`: https://cli.github.com/manual/gh_auth_login
- HUIT GHES gotchas live in `~/.claude/memory/huit-github-enterprise-api.md`
