# 0108 A child is born a body and a bloodline, and conception is where the lineage stack runs

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0062 (race), ADR 0063 (bloodline), ADR 0064 (clan)

## Context

ADR 0062/0063/0064 built race, bloodline and clan as three modules, and each one is complete
and tested. None of them is reachable from the game, because nothing calls them.

The reason is `fertility`. `FertilityApi._resolve_labor` builds an offspring by **averaging both
parents' base attribute dictionaries** and nothing else:

```gdscript
var base := _combine(actor.stats.base_dict(), status.partner_base, quality)
var child := Actor.new(StringName("%s_offspring" % actor.id), base)
child.faction = actor.faction
```

So the child of a stoneborn and a tidecaller is the same actor as the child of two commonborn,
apart from an attribute average. A pregnancy produces **bodies, not beings**. The lineage stack
is a set of shelves: three modules, 28 scripts, 1512 passing assertions, and no producer.

That matters more than an ordinary unwired feature, because inheritance is the one place these
three systems have anything to *do*. Bloodline purity exists to be diluted across generations,
and generations only exist because something makes children.

## Decision

- **Conception captures the lineage inputs; birth resolves them.** `try_conceive` records the
  partner id **and the partner's lineage snapshot** on the pregnancy status, so the child's race
  and purity are functions of who conceived it rather than of who happens to be near the mother
  when labor starts. This mirrors `partner_base`, which the module already snapshots for exactly
  this reason.
- **`_resolve_labor` calls `RaceApi` and `BloodlineApi`, and owns neither.** `fertility` declares
  `race` and `bloodline` as deps and reaches them through their facades only. Neither lineage
  module depends on `fertility`, so the stack stays acyclic: race → bloodline → clan, with birth
  as a *consumer* at the top.
- **The conception roll is captured once and reused at birth.** `try_conceive` takes a `roll`
  already; birth takes none. So the race roll is a second, independently supplied value stored on
  the status. Determinism is the reason: the same pregnancy resolved twice must produce the same
  child, which is what makes birth headless-testable.
- **Attribute inheritance is unchanged and stays independent of lineage.** The average still
  happens, because a body plan is not a stat stick: a race changes what the child *can* cultivate
  and which path is closed to it, while the attribute average decides how tall they start. The
  two are deliberately not folded together.
- **`SpeciesDef` is deleted, not aliased.** ADR 0062 moved reproduction parameters onto `RaceDef`
  and it has no production caller; the birth system now reads `gestation_days` from the mother's
  race. Two classes describing one body was the duplication ADR 0062 removed.
- **A child of two parents who both lack a race still gets one.** `resolve_race` answers the
  catalog baseline, so no actor is ever born raceless — which keeps `can_take_path` and every gate
  downstream answerable for every actor.

## Consequences

- The lineage stack gets its producer, and the succubus and birth systems get the payoff they
  were built for: a child is a real function of who the parents were.
- `FertilityApi.resolve_offspring` is the single place birth happens, so a caller never reaches
  into the status and assembles a child itself.
- Bloodline purity now *moves* in the game, which is what makes ADR 0063's dilution curve
  reachable rather than theoretical.
- `SpeciesDef`'s six fields now live on `RaceDef`; `FertilityApi.attach`'s optional `species`
  argument goes with it, so the facade gets smaller rather than wider.
- **Known gap, owned here:** clan is still not written at birth. A child is born into its parents'
  clan only if a caller says so — `resolve_offspring` takes the clan id as an explicit argument
  rather than inferring it, because admission is a gate with its own rules (ADR 0064) and silently
  enrolling a newborn would bypass it.