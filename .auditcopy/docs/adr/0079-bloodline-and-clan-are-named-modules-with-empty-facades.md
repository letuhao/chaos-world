# 0079 Bloodline and clan are named modules with empty facades

- Status: Accepted (superseded on the facts — the decision stands)
- Date: 2026-10-03
- Supersedes: ADR 0063 (a bloodline is a diluted unlock-gated inheritance)
- Corrects: ADR 0064 (a clan is a standing with obligations) — extends, does not replace
- Facts superseded by: the lineage program's own builds. See the status table below.

## Status of this record, read first

This ADR was written when `bloodline` and `clan` were registered boundaries with empty facades.
**They are not empty now.** Both modules are built, tested and wired to birth:

| Claim | Then | Now |
|---|---|---|
| `BloodlineApi` is an empty file, no members at all | TRUE | **FALSE** — a full facade at its 12-method cap (`game/src/modules/bloodline/api.gd`, 216 lines) |
| `ClanApi` is the same empty shape | TRUE | **FALSE** — full facade, 279 lines |
| `RETENTION` / `FLOOR` / `BLEND_CONSTANT` have 0 occurrences | TRUE | **FALSE** — `BloodlineState:41,45,48`, and `test_purity_reachability.gd` asserts the chain |
| `game/data/bloodlines/` does not exist | TRUE | **FALSE** — 5 authored lineages |
| `game/data/clans/` does not exist | TRUE | **FALSE** — 3 authored houses in a mutual-rival cycle |
| the mandated reachability test does not exist | TRUE | **FALSE** — `tests/modules/bloodline/test_purity_reachability.gd` |
| `standing` / `rank` / `patronage` / `duty` are not vocabulary | TRUE | **FALSE** — all authored on `ClanDef` and read by `ClanApi.summary` |

**What survives from this record, and it is the part that mattered:** the warning to *re-derive*
the arithmetic rather than trust a published constant. It was acted on — ADR 0063's first draft
shipped two permanently unreachable tiers, which a research pass caught before implementation, and
the constants were rebuilt from the fixed point outward so `RETENTION`, `FLOOR` and the additive
term are three names for one relationship rather than three independent numbers.

The line this ADR was right to protect also stands, verbatim: a module that says nothing depends
on it yet. `clan` still has no in-game caller that admits anyone — a child is born into no house
(ADR 0108) — but it now has a producer-shaped surface and a real gate.

## Context

ADR 0063 is the most confidently written ADR in `docs/adr/`: it publishes `RETENTION = 0.70`,
`FLOOR = 0.15`, `BLEND_CONSTANT = 0.045`, a nine-generation purity table and a three-tier
threshold table, it explicitly corrects an earlier draft for shipping dead tiers, and it *mandates*
the reachability test that would have caught them. It reads as the most-settled decision in the
repo.

**`BloodlineApi` is an empty file.** Not a thin implementation — no members at all:

```gdscript
class_name BloodlineApi
extends RefCounted

## Public facade for the `bloodline` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
```

`ClanApi` (`modules/clan/api.gd`) is byte-for-byte the same shape with `clan` substituted. There
is nothing else in either module.

| ADR 0063/0064 claim | Reality |
|---|---|
| `RETENTION`, `FLOOR`, `BLEND_CONSTANT` | 0 occurrences in `game/` + `tools/` |
| `awaken_threshold`, any purity field or tier | 0 occurrences |
| `BloodlineDef`, `BloodlineState`, `ClanDef`, `ClanState` | 0 occurrences |
| `game/data/bloodlines/` | does not exist |
| `game/data/clans/` | does not exist |
| `game/tests/modules/bloodline/` | `.gitkeep` only — **the mandated reachability test does not exist** |
| `game/tests/modules/clan/` | `.gitkeep` only |

## Decision

**Both modules are registered boundaries and nothing else. The vocabularies are unpublished
proposals.**

- The registry entries are real and correct, and they are the only true part of either ADR:
  `bloodline -> [contracts, core, race]`, `clan -> [contracts, core, bloodline, race]`
  (`tools/arch/registry.json`). ADR 0063's and ADR 0064's dependency-stack reasoning holds.
- **`standing`, `rank`, `patronage`, `duty`, `min_purity`, bloodline `purity` and the three
  `awaken_threshold` tiers are not vocabulary yet.** No code, no content, no test names them. Do
  not build a panel, a gate or a `def` around them expecting a counterpart.
- **The arithmetic must be re-derived, not trusted.** ADR 0063's own note — that its first draft's
  `0.10` floor "never applied" and "the 0.70 and 0.85 tiers were unreachable by any inheritance
  path" — is the reason to distrust any constant published here without a test that walks the
  generations. `tools test --suite bloodline` currently matches no test file at all.
- **ADR 0064's honest line is preserved verbatim, because it was the right call:**
  *"nothing depends on it yet. It is the top of the lineage stack, so nothing can depend on it
  without a cycle."* Verified: `clan` appears once in `registry.json` (its own entry) and there are
  zero `ClanApi` references outside `modules/clan/`. **ADR 0064 must not be "corrected" for saying
  that.** What it overstates is everything *before* it — it describes `ClanDef`, `standing` and
  `rank` in the present tense as though authored.

## Consequences

- **BL-0236 already records this:** *"clan and bloodline are empty scaffolds with Accepted ADRs and
  no backlog entry."* The ADRs were the one artifact that did not say so.
- The acyclic stack race → bloodline → clan is real and worth keeping; it cost nothing and it is
  why adding the two facades ahead of their content was a defensible order.
- ADR 0063's dependency on ADR 0062 is now doubly unsafe: ADR 0062 itself needed superseding by
  ADR 0078 (race is never assigned), so a child that resolves a race is a child that resolves
  nothing today.
- The deferred ledger carries the social-feature deferrals already (DEF-0005 race and bloodline).
  What was missing was a durable statement that the *published numbers* were never implemented.
