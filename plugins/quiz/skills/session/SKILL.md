---
name: session
description: Short multiple-choice comprehension check on what happened in the current session, so important things that scrolled past (security-relevant changes, decisions Claude made on the user's behalf, gotchas, unfinished work) don't get lost. This is the default quiz. Use when the user says "quiz me", "did I miss anything", "what should I know", or wants to check their understanding before wrapping up, unless the session is so small that nothing was really done, or the session was about learning the project itself rather than changing it; in those two cases use the quiz:project skill instead. Also offer it unprompted right after a significant change lands (a merged feature, a multi-file refactor, anything touching auth, secrets, permissions, or external systems). An optional argument narrows the focus, e.g. `security` or `decisions`.
---

# Session quiz

Long sessions accumulate things the user never actually read: tool output that
scrolled by, permission prompts approved on autopilot, judgment calls Claude
made without asking, work done by subagents. This quiz surfaces those before
the session ends.

## Session or project?

"Quiz me" means this skill unless one of these holds, in which case hand off
to the `quiz:project` skill and say so in one line:

- **Nothing was really done.** The session is a short Q&A, a trivial edit, or
  otherwise has no changes, decisions, or approvals worth asking about.
- **The session was about the project itself.** The user spent it reading,
  exploring, or onboarding to the codebase rather than changing it, so what
  they need checked is their model of the repo, not of the session.
- **The user said project, repo, or codebase.**

If an argument was given (e.g. `security`), bias question selection toward
that category but still include anything critical from other categories.

## Step 1: Find what whizzed by

Scan the whole session, including any compaction summary, and collect
candidates. Prefer things the user is least likely to have noticed:

- **Long tool results** the user almost certainly skimmed: test output, diffs,
  logs, API responses. What conclusion was drawn from them?
- **Judgment calls Claude made silently**: an assumption chosen over asking, a
  scope interpretation, a default picked among alternatives, a fix applied to a
  different place than the user pointed at.
- **Work done out of sight**: subagent results, background tasks, anything
  summarized rather than shown.
- **Things approved quickly**: commands run behind a permission prompt,
  especially ones that changed state (installs, config edits, deletes,
  network calls, git operations).
- **Things skipped, deferred, or left half-done**, and why.

Then rank candidates by how much it would cost the user to be wrong about them:

1. **Security and safety**: auth, secrets, permissions, input handling,
   external calls, data exposure, destructive or irreversible operations.
   If the session touched any of these, at least one question covers it.
2. **The headline change**: what was built or changed and where it lives.
3. **Non-obvious decisions and gotchas**: tradeoffs, constraints worked
   around, behavior that would surprise a cold reader in a month.
4. **Loose ends**: what is not finished, what still needs verification.

If nothing rises to this bar, say so in one line; the format file says what
to do when there is still a missed question to retake.

## Steps 2 to 5: Write, ask, grade, record

Follow `${CLAUDE_PLUGIN_ROOT}/references/quiz-format.md` for the missed-list
check, question style, how to ask, how to grade, and how to record misses.
Read it before writing the questions. When grading a wrong answer, point to
the evidence in this session: the tool result, the file and function, or the
turn where the decision was made. When recording that miss, anchor it to
something in the project instead (the file the session changed, the commit,
the doc section), since the next quiz will not have this conversation.
