---
name: review
description: Retake the quiz questions you got wrong earlier in this project, four at a time, until the list is clear. Reads the local missed-questions list that the session and project quizzes write, asks only from it, and clears each entry you now get right. Use when the user says "review quiz", "quiz me on what I missed", "go through my missed questions", "retake", or after a quiz reports that several missed questions are still open. Not for a quiz on the current session or the repo; those are quiz:session and quiz:project. An optional argument sets how many rounds to run, e.g. `all`.
---

# Review quiz

The session and project quizzes record every wrong answer in a local file and
retake one per quiz. That is slow when the list has grown. This skill works
the list directly: nothing but missed questions, four per round, until the
user has got each one right once.

## Step 1: Read the list

Follow "Check the missed list" in
`${CLAUDE_PLUGIN_ROOT}/references/quiz-format.md`. Read that file first; it
also holds the entry format, the asking and grading rules, and how to
record results.

- No file, or no `[open]` entries: say so in one line and stop. Do not
  invent questions; a review with nothing to review is good news.
- Mark entries whose evidence no longer holds as `[stale]` as the format
  describes, and skip them.
- Take the first four `[open]` entries, oldest first. If an argument names
  a category or path (`security`, `setup`, a directory), prefer open
  entries whose question or evidence matches it, still oldest first.

## Step 2: Ask

Write each one as the format describes for a retake: lightly reworded or
with reordered options, same correct fact. One `AskUserQuestion` call for the
round, header `Retake` on every question (or `Retake 1` to `Retake 4`).

## Step 3: Grade and record

Grade as the format describes, pointing at the stored evidence pointer. Then
update every asked entry: `[cleared YYYY-MM-DD]` when right, `misses` plus
one when wrong again.

## Step 4: Another round?

Say how many `[open]` entries remain. If any do and the argument was `all`,
start the next round at once. Otherwise offer one more round in a single
line and continue only on a yes. Stop quietly if the user moves on.

Never write anything other than the missed list, and never change the repo.
