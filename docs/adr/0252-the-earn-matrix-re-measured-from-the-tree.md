# 0252 The earn matrix is read from the tree, never written by hand

- Status: Accepted
- Date: 2026-10-05
- Supersedes: the earn matrix in ADR 0134 §3. ADR 0134 is immutable and is not
  edited; this is the dated correction it should have carried.

## Context

ADR 0134 §3 publishes the earn matrix — the table a module author is told to trust
when deciding how to grant fate. An independent audit found it **wrong on 5 of 8
rows**, and 11 of its citations pointed at lines that no longer held their claim.
The ADR's own instruction was "verify the negative before writing it down", and it
was not followed: the matrix recorded what was unbuilt when it was written and was
never revisited as the work landed.

A stale matrix is worse than no matrix. It is a contract a new author reads and
codes against, and it told them combat and all three cultivation paths grant
nothing when all four did.

`uv run python -m tools adr-cite` now measures these claims on demand and reports
567 drifted citations across the tree, so the drift was never in doubt — only
unmeasured.

## Decision

**The matrix is read from the tree, never written by hand.** Measured 2026-10-05 by
scanning `game/src` for non-comment `DestinyApi.earn_fate` / `earn_destiny` calls
and reading whether each verifies with `has_fate` / `has_destiny` (ADR 0134 §1a).

**12 earn sites; 10 verified, 2 did not.** Both unverified ones are now fixed, so
the shipped state is **12 of 12**.

| Site | Verb | Verifies |
|---|---|---|
| `app/character_creation_flow.gd:294` | `earn_fate` | **was no — fixed** |
| `app/character_creation_flow.gd:299` | `earn_destiny` | yes |
| `app/soul_arrival_marks.gd:83` | `earn_fate` | yes (ADR 0190 arrival marks) |
| `modules/combat/duel.gd:126` | `earn_fate` | **was no — fixed** |
| `modules/combat/duel.gd:152` | `earn_fate` | yes |
| `modules/body_cultivation/advancement.gd:384` | `earn_fate` | yes |
| `modules/qi_cultivation/advancement.gd:114` | `earn_fate` | yes |
| `modules/mind_cultivation/advancement.gd:563` | `earn_fate` | yes |
| `modules/quest/quest_grants.gd:105` | `earn_fate` | yes |
| `modules/quest/quest_grants.gd:112` | `earn_destiny` | yes |
| `modules/event/event_prize.gd:103` | `earn_fate` | yes |
| `modules/event/event_prize.gd:112` | `earn_destiny` | yes |

Corrected against ADR 0134 §3:

- **quest** said "no (DEF-0167)". It declares `destiny` in `registry.json` and has
  two earn sites, both verifying. DEF-0167/0193 are closed.
- **combat** said "not built, neither calls destiny". Two sites, both verifying.
- **all three cultivation paths** said "not built, no oath FateDef authored". Three
  sites, one per path, all verifying a shipped fate id.
- **`items` was absent entirely.** ADR 0135's `ItemDef.grants_fate` shipped after
  this table was last written; `ItemsApi._grant_fate` is the one site.
- **`clan` was absent.** `ClanHeir.register` (ADR 0239) writes the
  `household_heir_registered` fact four quest steps demand. It grants no fate itself,
  but until it was wired two fates and one destiny were unobtainable.
- **ADR 0134 §1b's claim about `counter()` is CORRECT and unchanged.** It was retired
  at the facade cap to pay for `events()`; `DestinyApi` is at exactly 12 public
  methods and `counter` is gone. Gates read a counter through `DestinyApi.gate`.

## Consequences

**A matrix maintained by hand is a matrix that goes stale.** The reader above is a
throwaway script, not a committed tool, because `adr-cite` already verifies the
*citations*; what it cannot do is count earn sites, and that count is what a new
author needs. If a thirteenth earn site appears, this table is wrong again in
exactly the way ADR 0134 was.

**`tools arch` cannot see any of this.** `BARE_REF_UNITS` excludes `modules/*`, so
neither a bare earn nor its registry entry is a boundary violation. The enforcement
is `game/tests/arch_rules/test_module_facade_edges_declared.gd`, which scans source
rather than trusting the registry — that is the guard, not this document.

**Verify, or it did not happen.** Every row was read off the tree, and the two
unverified sites were found by that reading rather than by a test failing. The
lesson is the one DEF-0285 records: a claim about the current state needs a
mechanism that re-reads the current state, because prose asserting "no player can
earn anything" reads exactly like prose asserting the opposite.