---
name: claude-ai-sync-follows-release-tag
description: claude.ai account-level marketplace sync tracks the latest GitHub release tag, not main; a fix is invisible to synced users until a new release is cut, and sync rejects any plugin with a top-level bin/
metadata:
  type: project
---

claude.ai plugin sync of `harvard-huit/ats-plugin-marketplace` reads the
**latest GitHub release**, not the tip of `main`. Evidence (2026-09-30):
the sync page reported commit 791851f, which is exactly tag v1.0.3, while
`main` had already moved to ecc2cf0 (the rename merge, PR #8) without a
sync. Inferred from that match, not from documentation.

The same sync **skips a plugin that ships a top-level `bin/`** ("added to
PATH on the CLI but not shown on the admin approval surface"). A skipped
plugin stays at its last synced version. `huit-github` hit this on
2026-09-30; its wrapper scripts moved to `scripts/` in 0.3.3 (commit
2af6115 on `dev`), which needs a v1.0.4 release to reach synced users.

**Why:** the rename commit and the bin/ fix both looked "done" on `main`
or `dev` yet did nothing for people who get plugins through claude.ai.

**How to apply:** after merging to `main`, cut a release
(`gh release create vX.Y.Z --target main`) and then re-sync in claude.ai.
Keep executables in `scripts/`, never `bin/` (see the convention in
CLAUDE.md). See also [[marketplace-update-vs-plugin-list]] for the
desktop-app side of the same "looks updated but is not" problem.
