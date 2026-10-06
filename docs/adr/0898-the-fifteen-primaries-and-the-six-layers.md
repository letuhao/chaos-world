# 0898 the fifteen primaries and the six layers

- Status: Accepted
- Date: 2026-10-07

## Context

- The Keepverse 12-aptitude roster (ADR 0881, ADR 0882) does not fit this game: the owner
  directed a 15-stat foundation — 3 paths x 5 principles — with breakthrough materials
  distributing points, and "a magnitude and a rate are different kinds of number" already
  governs how realm growth works.
- The design sessions produced `game/src/contracts/stat_ledger.json` and its reconciliation
  test (`tests/contracts/test_stat_ledger.gd`), which measured the whole vocabulary: after
  three enrichment rounds the ledger holds 211 rows, every live id has a row, and grown
  channels are separated from state readouts.

## Decision

- **The fifteen primaries** are `body`/`qi`/`mind` x `sinh`/`phat`/`tang`/`luyen`/`luu`:
  Sinh Cơ, Kình Lực, Căn Cốt, Cương Chất, Thân Pháp / Nguyên Tức, Khí Thế, Khí Hải, Chân
  Nguyên, Hành Khí / Thần Sinh, Tâm Hỏa, Định Tâm, Thần Ý, Linh Giác. The wuxing names are
  hidden grammar only: they never appear in ui and never in an id.
- **Ownership**: every channel belongs to exactly ONE principle; its owners are that
  principle's cells, with authored weights summing to 1. Universal contests read COLUMNS
  (`accuracy` = luyen, `evasion` = luu); identity channels read cells. The home cell's weight
  is the identity claim; shared weights are how universally a channel can be earned.
- **The six layers and their write rules**: L0 derived + resources — the read surface, every
  layer contributes, one owning mechanism per channel; L1 the 15 primaries — written ONLY by
  breakthroughs, one fixed budget per step split by a weight vector, materials shape weights
  and never magnitude; L2 innate — the 7 base attributes + race, never grown by cultivation;
  L3 progression secondary — owned by the progression system, materialised as L0; L4 mastery
  — element/status/weapon, adds channels and coefficients and never primaries; L5 composite
  paths — dual cultivation and successors, compose the majors and never mint a 16th primary.
- **The ledger is the machine register.** Its test gates shape (15 primaries, one per
  path x principle), weights (sum to 1, owners share the channel's principle) and
  reconciliation against the live vocabulary, and prints the distribution report. The WEIGHTS
  are placeholders under DEF-0344's discipline: ship the structure, move the values with
  evidence.
- **The 12-aptitude roster retires when the machine re-keys**: its rows stay as `L1-old`
  legacy, so the old vocabulary remains a visible trace and never a second live system.
- Resource POOLS (health/qi/stamina) and the L4 element/status families are deliberately not
  ledger rows; their masteries own them.

## Consequences

- The re-key is a roster swap on an existing pipeline (grant -> shares -> matrix edges ->
  flat channels), not a rebuild; the persistence cache (ADR 0888) and the sheet surface
  (ADR 0890) re-key with it.
- Material distribution, the ledger emit/validate tool (DEF-0356) and the impact census are
  their own slices.
- Every new system hangs its channels on L0, owned by an L1 cell. A stat that cannot name its
  principle is a design defect rather than a ledger row.
