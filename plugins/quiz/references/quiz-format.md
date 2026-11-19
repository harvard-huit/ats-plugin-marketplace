# Quiz format

Shared by every skill in the `quiz` plugin. Each skill owns Step 1 (finding
and ranking candidates); everything from writing the questions onward is
here, so the quizzes feel like one tool.

The framing is a check the user can pass in under a minute, not an exam. Pass
or fail matters less than the user finding out *what* they did not know.

## Check the missed list

Before writing questions, look for questions the user got wrong in an earlier
quiz in this project. They live in one local file, per checkout and never
committed:

```sh
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cat "$root/.claude/quiz-missed.local.md" 2>/dev/null
```

No file, or no entry whose heading starts with `[open]`, means nothing to
retake. Otherwise take the **first** `[open]` entry in the file (entries are
appended, so the first is the oldest). Before using it, glance at its
evidence pointer: if the fact no longer holds (the file changed, the
decision was reversed, the thing was removed), change that entry's `[open]`
to `[stale]` and take the next `[open]` one instead.

## Write the questions

- 3 or 4 questions. Each maps to a specific fact the skill actually found, not
  to general knowledge.
- **When there is an entry to retake, write at most 3 fresh questions and put
  the retake in slot 4.** Reword it lightly, or reorder its options, so it
  checks the fact rather than the memory of the previous quiz. Keep the
  correct answer the same fact.
- Multiple choice, 2 to 4 options. Exactly one is correct. The wrong options
  are the beliefs a skimmer would plausibly have formed, so a guess is
  informed rather than automatic. Avoid trivia (exact line numbers, variable
  names) in favor of consequences (what would break, who can now access what,
  what still needs doing).
- Keep each question and its options scannable. One sentence per option.
- Do not add a catch-all like "none of the above" or "not sure"; the user can
  always answer freely in their own words.
- If the skill's Step 1 found nothing that rises to its bar, say so in one
  line. Then, if there is an entry to retake, ask just that one; otherwise
  stop. Do not manufacture questions to fill a quota.

## Ask

Use whatever the environment offers for structured questions:

- **Claude Code**: one `AskUserQuestion` call carrying every question (the tool
  holds up to 4, which is why the retake takes slot 4 rather than a second
  call), so the user answers them together in the select UI. Use a short
  header per question (e.g. `Security`, `Change`, `Gotcha`, `Setup`); the
  retake's header is `Retake`.
- **Anywhere else** (no structured-question tool): post the questions as a
  numbered list with lettered options in one message and wait for the user's
  reply before grading.

## Grade

Reply in normal text, briefly:

- Confirm correct answers in a few words each.
- For wrong or partial answers, give the right answer and point to where the
  evidence lives (file and function, the tool result, the commit, the decision
  point in the conversation) so the user can go look.
- If a wrong answer is about a security or safety item, say plainly that it
  deserves a closer look before moving on. That is the one place the quiz
  should push a little.
- Collegial tone. If the user skips or dismisses the quiz, drop it without
  comment, and record nothing.

## Record the misses

After grading, update the missed list. This is the one thing a quiz writes.

**New misses.** Append one entry per fresh question answered wrong or
partially. Write it so it still makes sense weeks later in a new session:
the evidence pointer must be something that exists in the project (a file
and function, a commit, a section of `CLAUDE.md` or a doc), never "the tool
result above" or "the turn where we decided". A session-quiz miss whose only
evidence is the conversation is still worth recording; anchor it to
whatever the conversation changed or read.

**The retake** (and every question in a review). Answered correctly: change
its heading from `[open]` to `[cleared YYYY-MM-DD]`. It is never asked
again. Answered wrong again: leave it `[open]`, add one to `misses`, and
update `answered` to the new wrong answer, so the entry shows the
persistent misconception.

**The file.** `.claude/quiz-missed.local.md` under the project root (the git
root, or the working directory outside git). Create it with the header below
if it does not exist. In a git checkout, keep it out of the shared tree
without touching tracked files, the first time it is created:

```sh
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
mkdir -p "$root/.claude"
if git rev-parse --git-common-dir >/dev/null 2>&1; then
  git check-ignore -q .claude/quiz-missed.local.md \
    || echo .claude/quiz-missed.local.md >> "$(git rev-parse --git-common-dir)/info/exclude"
fi
```

Never commit it, never add it to a tracked `.gitignore` on the user's behalf,
and never write anything else into it. The user may edit or delete entries
by hand at any time.

Format:

```markdown
# Missed quiz questions (local, not committed)

Written by the quiz plugin. One entry per question answered wrong; the next
quiz retakes the oldest `[open]` one. Edit or delete entries freely.

## [open] 2026-11-19 session
- question: When `aws-login login <alias>` runs, where do the static keys land?
- options: only in the `[<alias>]` stanza / in `[default]` too / in the keyring, not on disk
- correct: in `[default]` too, where they shadow the `aws login` session
- answered: only in the `[<alias>]` stanza
- evidence: CLAUDE.md "Facts established 2026-09-26"; `commands.go` SaveAwsCredentials
- misses: 1
```

One `##` heading per entry: status, date asked, and which skill asked it
(`session` or `project`; a retake or review keeps the original skill name).
Options are separated by ` / `. Keep each field on one line so the file
stays easy to scan and to edit by hand.

## Suggest a review

After recording, count the `[open]` entries. If there are **more than 5**,
end the reply with one line, no more:

> 7 missed questions are still open here; `/quiz:review` runs through them.

Say it once per session. The `review` skill asks only from the list, four
at a time, and clears what the user gets right; it is the way to work the
list down faster than one retake per quiz.

## What a good question looks like

Good: "When a request to the upstream API fails, what ends up in the logs?"
with options: the status code only / the full response body, which may include
the token echo / nothing, failures are silent / a redacted summary. The correct
answer surfaces something the user probably did not see and has a real
consequence.

Weak: "What HTTP library was used?" The answer has no consequence and the user
can find it in one grep.
