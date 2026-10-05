# 0120 WorldState.pay_upkeep is deleted, as ADR 0058 decided

- **Status**: accepted
- **Supersedes**: ADR 0058 (one bullet only; its Decision and the rest stand)

## Context

ADR 0058:50-52 decided "`WorldState.pay_upkeep` is deleted, not wired", and ADR 0058:85
recorded the consequence: "`upkeep_rate` now has no payer". The deletion was never made.
The method survived at `core/world_creation.gd:79-82` — a second copy of the upkeep
check that charges nothing and has no caller:

```
Select-String -Path game/src/core/world_creation.gd -Pattern 'pay_upkeep'
  35: var upkeep_rate: float = 0.0
  79: func pay_upkeep(qi_amount: float) -> bool:
```

`Select-String` over `game/src` and `game/tests` finds no caller. The only other
definition is `WorldApi.pay_upkeep` (`modules/world/api.gd:121`), which ADR 0058 already
ruled the sole surface, and the seven `tests/modules/world/test_world_api.gd:253-305`
assertions all go through that facade, never the core copy.

## Decision

- **ADR 0058's deletion is carried out now.** `WorldState.pay_upkeep` is removed; there
  is no behaviour change, because a method with no caller has none.
- **`WorldApi.pay_upkeep` stays and stays non-charging.** It is the one upkeep surface,
  and a charge with no consumer of the qi is a number with no meaning. `upkeep_rate`
  still has no payer — that is the decision, not a gap.
- **Implemented, not superseded.** This is the one divergence in this set where the
  accepted ADR was right and only the work was missing: five dead lines, an owned file,
  and a deletion already argued for in an accepted ADR. Writing a superseding ADR that
  merely re-states the lie would have been cheaper and worth less.

Rejected: *keep it and describe it as "the world's own affordability check"* — that is
ADR 0058's rejected alternative verbatim: a second copy of a check in `core` that
`WorldApi` already re-implements inline, which is the ADR 0066 shape.

## Consequences

- Verified by `uv run python -m tools test --suite world` — `test_world_api.gd`'s seven
  upkeep assertions must stay green, which is the proof that the removed copy was not
  the one under test.
- **Guard:** nothing mechanical prevents this class of lie returning — an accepted ADR
  naming a deletion, and no test proving the name is gone. A `tests/arch_rules` scan for
  identifiers an ADR calls deleted is the obvious candidate and is **not** built here;
  it needs an owner of `tests/arch_rules/`.