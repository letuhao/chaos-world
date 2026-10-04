# 0190 A soul arrival grants its authored fates, and the grant rides the carried ledger

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0181 (fate belongs to the soul; a rebirth carries the whole ledger), ADR 0130 (a
  soul re-embodies into an arrival it earned), ADR 0159 (an arrival is spent by the death that earns
  it — a receipt, not a claim), ADR 0135 (a reference the catalog cannot resolve "reads as a working
  reference and silently grants nothing"), ADR 0134 (the consumer contract a caller may rely on),
  ADR 0113 (the fact ledger is the world's memory; nothing is refunded), ADR 0113's monotone
  counters, ADR 0065 (fate is earned, never chosen, never removed)
- Amends: ADR 0181's guard 3 in `test_soul_fate_across_rebirth.gd` — **the TEST, not the
  invariant.** The invariant ADR 0181 asserts is untouched and is restated here in the same words:
  *nothing the game does takes a fate back.* What is amended is an assertion that was stronger
  than the claim it was written for (see Amendment below). ADR 0181's file is immutable and its
  other four guards are untouched.
- Consistent with: ADR 0159 (an arrival grants no destiny, ever), ADR 0135 (a mark is a bare id
  the catalog can resolve), ADR 0127 (no `soul -> destiny` edge is created), ADR 0113 (no counter
  moves), ADR 0065 (an earn, exactly once, and never removed)
- Consumes: `SoulDef.marks` (`game/src/modules/soul/soul_def.gd:34`), authored on all three
  shipped arrivals and read by NOTHING in `game/src` before this change.

## Context

ADR 0181 said a rebirth arrival grants no fate, and recorded the omission as owed work in its own
Consequences: "a rebirth arrival that grants no fate is an arrival with no authored identity in the
module the whole world reads." The authored content was already there and already said what it
meant:

| arrival | authored `marks` | read by |
|---|---|---|
| `the_walker_back_through_ash` (order 0) | `soul_marked_once` | nothing |
| `the_one_who_was_carried_out` (order 1) | `soul_marked_twice`, `debt_carried_forward` | nothing |
| `the_ledger_knows_your_name` (order 2) | `the_ledger_knows_your_name` | nothing |

`soul_marked_once -> soul_marked_twice` is a DEATH-COUNT LADDER. A mark only means something if a
mark is what the soul EARNED by dying — and an authored Array with no reader is not a decision, it
is an unfinished one.

Two things make this more than a one-line wiring job.

**The namespace is load-bearing and the obvious choice is wrong.** A mark must be a fate id in
`destiny`'s own catalog, never `soul:<id>`. ADR 0135's rule is exactly this: an id the catalog
cannot resolve "reads as a working reference and silently grants nothing". A namespaced mark would
leave all three arrivals authoring marks, all three marks unresolvable, `earn_fate` refusing every
one of them with the SAME empty return it gives an already-held fate (ADR 0134 §1a) — and no error
anywhere in the game.

**The ORDER is load-bearing and has exactly one correct position.** `_carry_destiny` is a
WHOLESALE OVERWRITE (`to.set_module_data(DestinyState.MODULE_KEY, ledger.duplicate(true))`), so a
grant placed before it is silently erased by the copy. A grant placed after `_rebind` misses the
`DestinyApi.attach` that builds the projection. The window is between them, and nothing else.

## Decision

**A mark IS a fate id in destiny's catalog, named on the arrival the soul earned by dying, granted
by `DestinyApi.earn_fate` on the death that mints that arrival, between the carry and the rebind.**

- **When.** On the DEATH, not at the mint and not at birth. Never on a guardian death (the body
  never fell), never on an out-of-lives death (no body was owed back), and never on the
  incarnation-0 body: `the_walker_back_through_ash` is deliberately BOTH the first arrival and the
  initial body (ADR 0159), so a birth-path grant would claim a death that never happened.
- **What.** `DestinyApi.earn_fate` and nothing else. Never a destiny, never a group, never a
  picker — an arrival is a receipt, not a claim (ADR 0159), and `earn_destiny` would put a rebirth
  into the `origin` exclusivity set and hand the player the destination picker ADR 0065 forbids.
- **`source` is `"soul_arrival:<arrival_id>"`** — it names the SYSTEM, never the fate id
  (ADR 0065's rule for sources), and the ARRIVAL rather than the mark so the history discriminator
  stays unique per grant instead of colliding across a ladder naming one fate twice.
- **Verification happens AFTER `_rebind`, not after the earn.** `DestinyApi.attach` calls
  `DestinyState.normalize`, which drops any fate id not in `_known_fates()`
  (`destiny/api.gd:321-327`, `destiny_state.gd:72`) — so a typo'd mark PASSES `has_fate` at grant
  time and VANISHES at adopt. Verifying after the rebind catches the typo and the null-body refusal
  in one place, and the verdict's `ungranted_marks` is what makes that catch reachable instead of a
  silent no-op.
- **The verdict gains two keys, `marks` and `ungranted_marks`, and nothing else changes.** The
  existing verdict keys are consumed by `SoulLedgerPanel.DEATH_TEXT`
  (`ui/panels/soul_ledger_panel.gd:35-39`) and the `last_death` envelope
  (`app/item_workbench_play.gd:250`); adding breaks nothing, renaming or removing one is a UI break.
- **The rename: arrival 2's mark was `the_ledger_knows_your_name`, now `soul_marked_thrice`.**
  Legal (the two catalogs are separate) but a bare-id collision waiting to happen, and the ladder
  reads better when the three marks are visibly `once / twice / thrice`.
- **The four marks are PURE NARRATIVE: zero `flat_modifiers`, zero `percent_modifiers`.** A
  modifier on a mark would move `DestinyProjection.modifier_count` across a death, which is
  precisely what ADR 0181's guard 2 asserts is unchanged — so it would turn a shipped guard red
  and reopen DEF-0241's balance scope. **Marks do not grow the balance scope.** They are the story
  of the ladder and nothing else; the power curve across three bodies stays exactly what ADR 0181
  already named as its cost.
- **No registry change, and no new edge.** `soul` stays `[contracts, core, items]`; `destiny` stays
  `[contracts, core]`; `app` is exempt (`LAYER_DEPS["app"] == {"*"}`). `SoulArrivalMarks` lives in
  `app/` for three load-bearing reasons and not one: the exemption, `soul_death.gd` already being
  past `LINE_BUDGET = 400`, and NEITHER FACADE BEING ABLE TO GROW — `SoulApi` is at 12/12 and
  `DestinyApi` is at 12/12. There is no legal home for a `SoulApi.grant_marks` verb, which is the
  design working, not the design failing.

## Amendment to ADR 0181's guard 3 — and what the wrong fix would have been

`test_soul_fate_across_rebirth.gd`'s guard 3 asserted `DestinyApi.state(_actor) == held` — BYTE
EQUALITY — after the first death and again after the second. Granting marks makes the new ledger a
strict SUPERSET, so both halves went red.

**The assertion was stronger than the invariant it was written for.** Byte-equality encodes "the
carry is a pure copy", which stops being true the moment an arrival grants anything — and that was
never the claim being guarded, which is ADR 0065's earn-only invariant. So it is restated as a
**MONOTONE SUPERSET**, asserted by EXPLICIT SET DIFFERENCE and never by equality: every
`fates`/`destinies` key present before is present after, every counter is `>=` its prior value, and
the pre-death history is a PREFIX of the post-death history. A STRICT-superset assertion is kept
alongside it, so a ledger that fails to GROW still fails.

**The wrong fixes, recorded so the next agent does not reach for them:** deleting the case, or
softening it to `assert_true`. Either is ADR 0188's "a guard that cannot fail" failure verbatim. A
guard that can no longer fail is not a relaxed guard; it is a missing guard.

ADR 0181's guard 5 (the no-`soul -> destiny`-edge boundary test) is **not** touched.

## What a consumer may rely on

| Claim | Where it comes from |
|---|---|
| After a rebirth, `DestinyApi.fates(new)` is a SUPERSET of `DestinyApi.fates(falling)` plus `SoulArrivalMarks.marks_for(arrival)` | this ADR; the grant rides the carried ledger between copy and adopt |
| Every fate and destiny held before a death is still held after; every counter is `>=` its prior value; the fate trail only ever grows | ADR 0065, ADR 0113 — restated by the amended guard 3 |
| `DestinyApi.fates(new) - DestinyApi.fates(falling)` is EXACTLY `SoulArrivalMarks.marks_for(arrival)` and nothing else | this ADR; no other code path earns onto a rebirth body |
| `soul_death.gd` returns `ungranted_marks`, and a non-empty one names the fate id the catalog could not resolve | this ADR; `earn_fate` refuses an unknown and an already-held id identically (ADR 0134 §1a) |
| A mark's ledger `source` reads `soul_arrival:<arrival_id>` — the SYSTEM and the ARRIVAL, never the fate id | this ADR; ADR 0065's rule for `source` strings |
| An arrival NEVER grants a destiny, so the held-destiny set is byte-identical across a rebirth | ADR 0159; `earn_destiny` appears nowhere in `soul_death.gd` |
| A mark carries no stat, so `DestinyProjection.modifier_count` is unchanged by any death | this ADR; all four marks ship zero modifiers. DEF-0241's balance scope did not grow |
| A guardian death and an out-of-lives death grant nothing | this ADR; both branches return before `_rebody` |

## Consequences

- **`game/data/soul/arrivals/` is still invisible to `tools/data.py`.** The audit has no `soul`
  key in `TYPE_BY_FOLDER`/`SCHEMA_FOR_PREFIX`, so a mark naming no `FateDef`, a duplicate arrival
  id (`SoulCatalog._ensure_loaded` is last-wins at `soul_catalog.gd:91`), and a `race_id` naming no
  authored race are all still un-audited. The GDScript suite gates the first of the three by name
  (`test_soul_arrival_marks.gd`, the content gate); the other two are owed to whoever owns
  `tools/data.py`.
- **A fourth authored arrival must add a mark or the ladder reads as unearned.** That is a content
  obligation, not a code one, and the suite asserts each arrival carries at least one so an emptied
  `.tres` cannot pass as "nothing to check".
- **`the_walker_back_through_ash` grants nothing on the initial body, by design.** A first-life
  player therefore holds no mark until they die once, which is the ladder's whole meaning — but it
  does mean `DestinyApi.summary` shows no mark row at `incarnation: 0`.
- **The codex grows by four rows over a full run.** `DestinyApi.summary` publishes every authored
  fate, so the four marks appear as hidden/teaser rows from the first frame and as held rows as the
  ladder is walked. No screen change is owed.