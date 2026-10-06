# 0508 Nine rarities with magnitude budgets

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0025 (rarity policy), ADR 0055 (rarity budgets options, never power)
- Amends: ADR 0025 (4 rarities → 9 rarities)

## Context

The technique program needs 9 quality levels per technique. The current 4 rarities (common, magic, rare, legendary) are too coarse for a game with 30 realms and 10 elements.

## Decision

**9 rarities with magnitude budgets:**

| # | Rarity | Budget |
|---|---|---|
| 1 | common | 0.0 |
| 2 | uncommon | 0.15 |
| 3 | magic | 0.25 |
| 4 | rare | 0.5 |
| 5 | epic | 0.75 |
| 6 | legendary | 1.0 |
| 7 | mythic | 1.5 |
| 8 | divine | 2.0 |
| 9 | transcendent | 3.0 |

`ItemRarity.ALL` lists all 9. `POLICY` maps each to `{count, contexts, sockets, budget}`. `sanitize()` clamps to common for unknown values.

## Consequences

- Every existing technique's rarity is remapped: common→common, magic→magic, rare→rare, legendary→legendary.
- The diversity validator checks all 9 rarities are represented per build.
- `ItemRarity` grows from 4 to 9 entries.
