# 0337 Ten grades across four tiers, three realms per grade

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0007 (grades gate realm tier), ADR 0055 (grade is a floor, not a scale)
- Amends: ADR 0007 (6 grades → 10 grades)

## Context

The technique program needs 10 grades for 30 realms: 3 grades per tier for tiers 1-3, 1 grade for tier 4. The current 6-grade system (mortal, spirit, earth, heaven, immortal, divine) maps 4 tiers to 6 grades, which is too coarse for 30 realms of content.

## Decision

**10 grades, 4 tiers, 3 realms per grade:**

| Tier | Grade | Realms |
|---|---|---|
| 1 | initiate | 1-3 |
| 1 | adept | 4-6 |
| 1 | disciple | 7-9 |
| 2 | practitioner | 10-12 |
| 2 | expert | 13-15 |
| 2 | master | 16-18 |
| 3 | grandmaster | 19-21 |
| 3 | elder | 22-24 |
| 3 | sage | 25-27 |
| 4 | immortal | 28-30 |

`ItemGrade.ALL` lists all 10. `TIER_BY_GRADE` maps each to its tier (1,1,1,2,2,2,3,3,3,4). `required_tier()` is unchanged.

## Consequences

- Every existing technique's grade is remapped: mortal→initiate, spirit→practitioner, earth→expert, heaven→grandmaster, immortal→sage, divine→immortal.
- `ItemGrade` grows from 6 to 10 entries. `tools/arch` line budget is unaffected.
- The diversity validator checks all 10 grades are represented per build.
