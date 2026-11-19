---
name: project
description: Short multiple-choice check on the gotchas of the repo you are in, for a developer who is new to it or coming back to it. Finds the things a newcomer would not read on their own (rules in CLAUDE.md or CONTRIBUTING, decisions reversed in git history, setup steps nobody automated, "do not" comments, how secrets and deploys work) and asks about the ones with consequences. Use when the user says "quiz me on this project / repo / codebase", "what should I know before I touch this", "what are the gotchas here", or when they say "quiz me" in a session that was about exploring or learning the project rather than changing it, or in a session where nothing was really done. Otherwise "quiz me" means the quiz:session skill. An optional argument narrows the focus, e.g. `security`, `setup`, or a path.
---

# Project quiz

A codebase accumulates knowledge that lives only in a few heads: conventions
enforced by comment rather than by tooling, decisions that were tried and
reversed, setup steps everyone did once and forgot. This quiz finds that
knowledge and checks whether the user has it, before the gap costs them a
regression or a wasted afternoon.

## Project or session?

"Quiz me" with no qualifier means the `quiz:session` skill, unless the session
has no real work in it, or the session was spent learning the project rather
than changing it. If you were invoked and the session is in fact full of
changes the user has not reviewed, offer the session quiz first in one line,
then continue with whichever the user picks.

If an argument was given, scope the scan to it: a category (`security`,
`setup`, `conventions`, `history`), or a path or subsystem.

## Step 1: Find what a newcomer would miss

Look where the surprises live. In a large repo, hand the wide scans to an
Explore subagent so the main context stays clean, and ask it for conclusions
with file references, not file dumps. Do not modify anything in the repo; the
only file a quiz writes is the local missed list described in the format.

- **The rules people wrote down**: `CLAUDE.md`, `AGENTS.md`, `README`,
  `CONTRIBUTING`, docs directories, committed memory files. Prefer the
  "do not", "never", "always", "gotcha", and "known issue" statements over the
  overview prose; those exist because someone got burned.
- **The rules people only left in comments**: grep for `TODO`, `FIXME`,
  `HACK`, `XXX`, `WORKAROUND`, `do not`, `careful`, `gotcha`, `intentionally`.
  Anything that explains why the code is deliberately odd is a candidate.
- **Decisions that were reversed**: recent `git log`, commits whose messages
  say revert, fix, regression, workaround, or rename; a decision log in the
  docs. Something that changed direction once will be re-litigated by every
  newcomer who does not know why.
- **Setup and configuration traps**: required environment variables, files
  that must exist but are gitignored, scripts or make targets with side
  effects, CI steps that differ from local, tool version pins, platform
  differences.
- **Security and boundaries**: how secrets are loaded and where they must
  never appear, what runs against production or external systems, what is
  public versus internal, permissions or allowlists the project expects.
- **Things that are not what they look like**: a stale mirror, a directory
  that is generated, a config file that is read from somewhere unexpected, a
  name that no longer matches its behavior.

If the session already covered the project (the user read files, asked
questions, had things explained), prefer facts that came up there: the quiz is
then also a check on what they retained.

Rank candidates by how much it would cost a developer to be wrong about them:

1. **Security and safety**: secrets, credentials, destructive operations,
   anything that touches production or an external system. If the repo has
   any of these, at least one question covers it.
2. **Conventions with no guardrail**: rules the tooling does not enforce, so
   the only protection is knowing them.
3. **Reversed or non-obvious decisions**: things a newcomer would "fix" back
   to the way that was already tried.
4. **Setup traps**: what fails on a clean machine and why.

If the repo is small and plain enough that nothing rises to this bar, say so
in one line; the format file says what to do when there is still a missed
question to retake.

## Steps 2 to 5: Write, ask, grade, record

Follow `${CLAUDE_PLUGIN_ROOT}/references/quiz-format.md` for the missed-list
check, question style, how to ask, how to grade, and how to record misses.
Read it before writing the questions. When grading a wrong answer, point to
the file (and line if useful), the commit, or the doc section where the fact
lives, so the user reads the source rather than taking your word for it; the
same pointer goes into the recorded entry.
