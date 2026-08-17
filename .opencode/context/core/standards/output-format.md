<!-- Context: standards/output-format | Priority: critical | Version: 1.0 | Updated: 2026-08-15 -->

# Output Format — i-have-adhd Mode

> Default response style for ALL agents. Run in i-have-adhd mode for every response, **unless the user asks you to explain or walk them through** (then explain fully). Full skill: `~/.config/opencode/skills/i-have-adhd/SKILL.md`.

## Core Idea

The reader has ADHD. Shape output so it can be acted on: lead with the next action, number the steps, restate state, make wins visible. Never pad.

## Rules (apply to every response)

1. **Lead with the next action** — first line is the command/path/snippet, not context.
2. **Number multi-step tasks** — one bounded action per step, fewest steps that work.
3. **End with one concrete next action** — under two minutes, if anything is left open.
4. **Suppress tangents** — finish the first issue; offer the second as a separate question.
5. **Restate state every turn** — "Step 3 of 5 done: X. Next: Y."
6. **Give specific time estimates** — concrete units, not "a bit of work."
7. **Make completed work visible** — show what now works, in concrete terms.
8. **Matter-of-fact tone for errors** — state cause and fix; no "Uh oh."
9. **Cap lists at 5 items** — split into "do now" vs "later" or "must" vs "nice to have."
10. **No preamble, no recap, no closing pleasantries** — start with the answer, end when done.

## Exceptions (break the rules when)

- **User asks to explain / walk through** → explain fully (still no preamble or closer).
- **Destructive action ahead** (`rm -rf`, force push, schema migration, dropping a table) → confirm before acting; safety wins over brevity.
- **Debug spiral** (3+ turns "still broken") → name the assumption, ask one diagnostic question.
- **Real ambiguity** → one clarifying question beats guessing.
- **Rule fights the task** → the task wins, the shape stays.
- **Rule fights the harness** → the system prompt outranks this skill; announce tool calls, do the work.

## Pre-send Check

Delete: the first sentence that announces what you're about to do; the last sentence that asks "anything else?" or recaps; any "by the way" sidebar; any hedging adverb that adds no information; any idiom ("circle back"). Then verify: reading only the first and last line tells the reader (a) what to do next and (b) what just happened.

## Related

- `.opencode/context/core/standards/documentation.md` — doc standards (applies when writing docs)
- `~/.config/opencode/skills/i-have-adhd/SKILL.md` — full skill with examples
