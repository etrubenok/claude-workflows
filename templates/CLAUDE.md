# CLAUDE.md

<!-- A starting point for a project the factory drives. Replace every <…>; keep the sections the factory's
     prompts point at: "Hard stops", "Writing for the owner", the check command and where decisions live. -->

Working rules for coding agents in this repository, the factory's sessions included.

## What this is
<One paragraph: what the project does, for whom, and what matters most — the thing a wrong change would break.>

## Priorities
In this order: <1. correctness of …> · <2. …> · <3. operating cost> · <4. code growth>. The factory's own
tooling is a means, never the goal.

## Working discipline
1. **Verify against the live docs and the code, not memory.** Never invent an endpoint, a schema or a limit;
   what you cannot verify is marked as such, with the reason.
2. **Root-cause before re-fixing.** A part flagged in two review rounds gets its cause fixed or the feature cut,
   never a third patch.
3. **Minimum change, one decision per area.** Look for prior art in the code and in `docs/decisions/` and follow
   it; a new pattern is a new dated file there, naming the least-change alternative it beat.
4. **Done means verified.** Every acceptance item checked green, CI included (`gh pr checks <n>`; read a red log
   before moving on).

## Hard stops — the owner decides, always
- Deleting or rewriting data the project keeps (`data`): <the database, user files, …>.
- Changing what a stored field, a timestamp or a public interface means (`data-meaning`).
- Weakening a rule this file calls non-negotiable, or editing the specification (`spec`): <specs/**, …>.
- Force-pushing; spending money; credentials or account actions (`force-push`, `money-credentials`).
- <Anything else, as `hard-stop:<name>`.>

Everything else — a design detail, a metric, a threshold, a test plan — the agent decides from a measurement it
quotes, records on the issue, and the owner reverses afterwards if wrong. A recommended default is a decision,
never a question.

## Writing for the owner
Everything written for a person stands alone: a reader who opened nothing else understands it. Say the thing,
not its label; lead with the outcome and what the owner must do (usually nothing); short, everyday words;
evidence under a `<details>` fold. Qualify every GitHub reference with its kind — `PR #19`, `issue #4` — except a
PR body's bare `Closes #N`, which GitHub's auto-close parser needs.

## Commands
`<the check command — the factory's FACTORY_CHECK>` (format, lint, tests) · <how to run it locally> ·
<how it is deployed, if it is>.

## Don't
- Add a dependency or infrastructure this file does not name without a decision file.
- Fabricate endpoints, schemas or limits.
