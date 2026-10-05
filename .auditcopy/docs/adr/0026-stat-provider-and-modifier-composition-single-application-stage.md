# 0026 Stat provider and modifier composition: single application stage

- Status: Accepted
- Date: 2026-10-02

## Context

`ActorStats` computes core derived stats from base attributes plus a source-tagged modifier
stack, then lets `StatProvider` contributions take precedence for the stats they return. Item
modifiers on provider-contributed stats are therefore ignored. `ElementProvider` passes
`element_mastery_<e>` through from `StatContext.value()` (a base attribute); applying the
modifier stack to provider outputs would double-apply mastery.

## Decision

- A provider's contribution is the baseline (a replacement) for the stats it owns; the core
  formula for an overlapping id is superseded, not added.
- The modifier stack (flat / percent / mult) applies exactly once, at one resolution stage,
  to every stat — core-derived and provider-contributed.
- Providers read post-modifier inputs via `StatContext.value()`, so an item modifier on a base
  attribute (e.g. `element_mastery_<e>`) flows into provider formulas (e.g. elemental power)
  with no stale input and no double application.
- Providers do not pass through stats that core already owns as base attributes;
  `element_mastery_<e>` stays core-owned and is contributed only as an input to power.
- Overlapping ids (`move_speed`, `poise`, `qi_absorption`) resolve to the provider baseline.
- Cache invalidation uses the existing version counter; resource pools clamp current to a
  decreased maximum and never refill on equip.

## Consequences

- Item modifiers affect provider-owned and dynamic-element stats exactly once.
- No accidental last-provider-wins semantics; provider ownership is explicit.
- Equip / unequip / rebuild / save / load cause no drift, duplication, or refill exploit.
