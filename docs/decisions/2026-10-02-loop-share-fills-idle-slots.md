# 2026-10-02 — The loop-share brake never idles a free slot

**Context.** The loop caps the share of its sessions spent on its own tooling (issues of `FACTORY_LOOP_CLASS`) at
`FACTORY_LOOP_SHARE_MAX` (20 %) of the trailing 24 h, so that the project, not the loop, gets most of the work.
In the project the factory was extracted from, the brake held every tooling issue whenever the share was over the
cap. From 2026-09-30 22:08Z the project's own queue was empty — every product issue waited for the owner's answer,
for a set time, or behind one of those — so the only sessions left were the loop's own, the share rose to 100 %
and could never fall again: for 27 hours the loop started nothing, with nine tooling issues ready and three slots
free.

**Decision.** Over the cap, a tooling candidate is set aside, not dropped. When the walk of the queue ends with
nothing else startable, the first one set aside that passes the usual checks (its areas free, no open blocker)
takes the slot, and the log says so in one line. While any other issue can start, the brake holds exactly as
before. The walk is in priority order, so a startable product issue is always picked before a tooling one is even
looked at; the fallback can only fill a slot nothing else could use. A queue list that failed part-way keeps the
tooling issues held, since it may hide an issue that outranks them.

**Alternatives.** Count only sessions that made progress (the hourly close re-checks that held the share at 100 %
here would drop out) — fixes this instance, not the shape: any quiet project queue starves the loop the same way.
Reserve one slot for tooling — spends a slot when the project has work. Turn the brake off — loses the cap the
owner asked for.

**Revisit if:** tooling issues take most sessions on a project with a steady queue of its own (then the cap is too
loose, not this rule wrong), or a project wants the loop idle rather than working on itself (an empty
`FACTORY_LOOP_CLASS` turns the brake off; there is no "idle instead" switch yet).

**Tests.** `tests/factory-tick-test.sh`, "loop-share brake": the idle-loop shape takes the slot; a startable product
issue goes first; an unrated issue is preferred and the tooling one is held; a blocked tooling issue does not start;
no class, no brake. A copy of the driver without the fallback fails the first and the fourth.
