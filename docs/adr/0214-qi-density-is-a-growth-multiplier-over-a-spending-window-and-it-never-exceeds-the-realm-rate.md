# 0214 Qi density is a growth multiplier over a spending window and it never exceeds the realm rate

- Status: Accepted
- Date: 2026-10-05
- Closes: DEF-0117
- Depends on: ADR 0066 / 0116 (`RealmRate` is the one rate curve), ADR 0212, ADR 0213

## Context

ADR 0075 decided environment as *survival* and deferred the gain side in one line: "the
mechanic is the same; the balance surface is not". DEF-0117 records the reason the deferral
was correct — a qi-density multiplier inside a domain would be **a second rate curve with no
authored ladder**, and `RATE_STEP` is bounded by the authored `progress_required` ladders
(AGENTS.md §Realm scale). A free multiplier larger than the work a realm charges is exactly
the failure that once made a single breakthrough worth more than everything else combined.

The rest of the context is that the vocabulary already exists and is unused:

- `RealmRate.factor` is the ONLY rate curve (`core/realm_rate.gd:84-88`), `RATE_STEP := 1.02`,
  and it is a bounded per-realm number — "a gain, never a magnitude" (`realm_rate.gd:75`).
- `inside_world_qi_density` is a live stat (`core/inside_world_provider.gd:15`) with no
  consumer; `verdant` is an authored zone kind whose body substrate is
  `SUBSTRATE_QI_THROUGHPUT` and qi substrate is `SUBSTRATE_OVERGROWTH` — i.e. the slot was
  reserved and never filled.
- The gain computation itself is one line, in all three paths' shape:
  `gain = amount * RealmRate.factor(...) * (1 + meridians.get_flow_bonus())`
  (`qi_cultivation/training.gd:57`).

That single multiplication is the seam. Anything that multiplies `gain` is a rate; anything
that adds to `amount` is not.

## Decision

**Yes — environment modifies cultivation gain, as a bounded MULTIPLIER on the gain term, and
it is capped below `RATE_STEP` so it can never outrun the ladder.**

- **The shape is exact and it is one factor.** In the gain expression
  `amount * RealmRate.factor(rank_id) * flow_bonus * QI_DENSITY`, where
  `QI_DENSITY ∈ [0.75, 1.25]`, authored per place. It is a *multiplier on the gain term only* —
  never on `amount` (a price), never on the pool, never on a magnitude. This is the ADR 0212
  rule ("a mitigation percent authored per lever is a cap on an input") applied to a benefit:
  the multiplier is bounded, it composes multiplicatively with `flow_bonus` and `RealmRate`,
  and it is **never summed** with them.
- **The cap: `|QI_DENSITY − 1.0| ≤ 0.25`, so the full multiplier is at most 1.25×, and it is
  one-sided in practice** — a dense place is at most a quarter faster, a thin one at most a
  quarter slower. A multiplier that could reach 2× would let a domain deliver a breakthrough's
  work for free, which is the `RATE_STEP` bound (1.0357 on the deepest authored transition)
  broken by a factor of ~7.
- **Granularity is the zone, at the same resolution point as everything else in 0213.** One
  authored `qi_density` per zone; weather does not touch it (a storm makes a room hotter, it
  does not make it richer). A room with no zone authors `1.0` and is invisible to this rule.
- **It is a *place* property, not a stat, and it is NOT `inside_world_qi_density`.** The inner
  world's density is the actor's personal reservoir (ADR 0018); a domain zone's is ambient. They
  are separate numbers with separate homes, and neither may read the other.
- **It applies to all three paths through one shared read**, so a body cultivator does not get
  a private cultivation-speed multiplier that the gate arithmetic never sees.
- **No DEFER remains.** The condition DEF-0117 named — "the guard is that RATE_STEP must not
  outrun the work a realm charges" — is satisfied by the construction: a bounded multiplier
  below 1.0357 composed into the same gain term cannot desynchronise the ladder, because
  `RealmRate.factor` is still the only per-realm number and the multiplier is realm-independent.

## Consequences

- **`verdant` finally means something on the qi path** — the kind was authored for exactly
  this (`SUBSTRATE_OVERGROWTH`) and has been a hazard with no reward attached.
- **A furnace is now a trade, not a wall.** Under 0210 leaving is free and always correct, so a
  dense zone is the *only* reason a player would ever stand in one — and it pays them for it.
  That is the decision the four levers could not create on their own.
- **The balance surface is exactly one authored field per zone**, inside the closed 1.25/0.75
  band. It cannot drift from the ladder because it never touches `RealmRate`.
- **A `qi_density` above 1.0 is content-visible and must be telegraphed** (0210): an unseen
  buff in a lethal room is not a reward, it is a trap the player cannot read.
- **No deferral is claimed.** If the three paths' gain expressions ever stop sharing a single
  multiplication shape, this ADR is superseded on that point and the multiplier moves with them.