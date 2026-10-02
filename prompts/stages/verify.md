## verify
You are in the primary checkout on `main`. First give the issue **exactly one** priority label of
`{{PRIORITIES}}` (highest first; what each means: `gh label list --repo "$REPO" --json name,description`,
and the project's `.factory/labels`). None → `lbl` the one its meaning names; two or more → keep the
highest and `unlbl` the rest; `bug` is not one. It goes on before steps 1 and 2 can park the issue,
because the loop never guesses a class and an unrated issue sorts last.
1. **Not already done?** Grep the code and docs for what the issue asks, and check
   `gh pr list --state merged --search "<keywords>"`. If it is done: comment what implements it
   (file/PR), `gh issue close "$N" --reason completed`, stop. Done but for a wait on the clock
   (header, "A wait"; this is also where a `time:` un-park lands when the issue has no PR): park
   it (`lbl waiting; unlbl ready`), stop. **Its own PR already merged** (`gh pr list --head
   "issue-$N" --state merged`) and the issue still asks for more: that merged work is a first round —
   steps 2–5 judge what is left, and step 5 starts a new round for it.
2. **Design complete?** The issue (body + comments) must state what to change (touch points), the
   acceptance evidence, and — when a choice is not obvious — how it is decided. **Whatever is
   missing, you write:** the least-change option that keeps the project's rules (CLAUDE.md), or, when
   the choice is measurable, an experiment of at most two variants scored by the project's own checks
   and the issue's metrics; every threshold comes from a measurement you quote, never a number you
   invented. Post it as a **Decided** comment with a "revisit if" line and carry on to step 3. Only
   a hard stop or a step the owner must physically do stops the issue: a **Decision needed** (or
   **Action needed from you**) comment naming that item, `lbl needs-decision; unlbl ready`, stop.
3. Give the issue its `area:` labels from the project's list (`.factory/labels`; never a new one;
   `gh label list --repo "$REPO" --search area: --json name,description` reads it as GitHub holds
   it, and where the two differ the file wins): every area its touch points name, and for an issue
   with no clear touch point the one its meaning names. An issue whose touch points are all files no
   area names takes none. Two issues in flight never share an area, so an area is a part of the code
   whose changes would collide at merge.
4. **Must it follow another issue?** Each one its body or comments name ("after issue #M", "needs
   issue #M first") is a GitHub "blocked by" link, which the pick reads before it spends a session.
   Read the links: `gh api repos/$REPO/issues/$N/dependencies/blocked_by --jq '.[] | "\(.number)
   \(.state)"'`. Add each missing one: `gh api repos/$REPO/issues/<M> --jq .id`, then `gh api -X
   POST repos/$REPO/issues/$N/dependencies/blocked_by -F issue_id=<that id>`, then read the links
   again. **Never park an issue for a dependency GitHub lists:** while a listed blocker is open,
   change no label, comment one line ("Checked: clear enough to build, but it has to wait for issue
   #M (<what that is>), now recorded as its "blocked by" link. It stays in the queue and starts by
   itself once issue #M is closed. Nothing needed from you."), stop. An open blocker the second
   read does not list (the link did not record) is the one park left: a **Waiting** comment that
   says so, tagged `[blocked-on: issue:<M>]`, `lbl waiting; unlbl ready`, stop.
5. Otherwise `lbl in-progress; unlbl ready`, comment one line ("Checked: not built yet, and clear
   enough to build. Building starts at the loop's next run. (`<priority>`, `<areas>` or no area)";
   for a new round, say what is left and which PR merged the first), stop. The driver runs
   `implement` next — or sends the issue back to `ready` while an issue in flight shares one of its
   areas (never two in flight in one area).
