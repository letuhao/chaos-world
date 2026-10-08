# 0926 the gain-side multiplier is the actor's rate stat and the place's density and neither compounds with the realm rate

- Status: Accepted
- Date: 2026-10-08
- Closes: DEF-0117, BL-0931
- Depends on: ADR 0214 (the place half), ADR 0066 / 0116 / 0268 (`RealmRate` is the one curve)

## Context

Two gaps, one seam. ADR 0214 decided the place half of this — a bounded `qi_density`
per zone, published onto the actor and multiplied into the gain — and shipped the class
(`core/cultivation_gain.gd`), the zone field, and the ADR. The **wiring never landed**:
`scale_gain` had zero callers, no zone authored a density, and the tracker entry
(DEF-0117) stayed open. Separately, `Stat.CULTIVATION_RATE` was derived
(`actor_stats.gd`: `1.0 + aptitude * 0.02`) and granted by dozens of authored sources —
item options, bloodlines, sets, fates, consumables — and read by **no cultivation gain
at all** (BL-0931): a live stat whose grants were decorative.

The owner ruled both into one bounded slice (2026-10-08): wire the stat, make the zone
reward real, and prove with the `RATE_STEP` guard that the multiplier cannot outrun the
work a realm charges.

## Decision

**The gain expression gains ONE composed call, and it is two bounded factors MULTIPLIED.**

```
gain = amount * RealmRate.factor(realm_id) * (1.0 + meridians.get_flow_bonus())
gain = CultivationGain.scale_gain(actor, gain)     # = gain * density * rate
```

- **The actor factor is `Stat.CULTIVATION_RATE`, clamped to `[RATE_FLOOR, rate_ceiling()]`**
  where `rate_ceiling()` is `RealmRate.rate_span()` — DERIVED from the shared curve, never
  typed — and `RATE_FLOOR` is `0.25` so a debuff slows cultivation to a quarter rather
  than stalling a path at zero. A shipped actor reaches neither bound (authored `aptitude`
  tops out near `13`, so the derived rate tops out near `1.26`).
- **The place factor is ADR 0214's `qi_density`, band `[0.75, 1.25]`, unchanged.** The
  ruling's phrase "zone statuses grant a capped `cultivation_rate`" is satisfied in
  outcome, not in mechanism: ADR 0214 already decided a place is a published property and
  not a stat — a status is an instance on the actor, while a place is where they stand —
  and the zone's STATUS remains the hazard (`env_scourge`). Standing in a rich zone raises
  a capped multiplier on the gain; that is the observable the ruling asks for.
- **The place is published at the two moments a room is entered and cleared on leaving**
  (`DomainBoot._apply_zones` publishes the room's RICHEST zone density, or `NEUTRAL` when
  the room authors none; `leave_domain` clears). Publish-don't-skip: a hero who walks out
  of a rich room must not keep its number through a key nobody cleared.
- **All three paths read it through the one call** — qi, body and mind — so no path can
  carry a private multiplier the gate arithmetic never sees; a source pin in
  `tests/core/test_realm_rate.gd` fails a path that multiplies its gain without it.
- **Neither factor is realm-dependent, and neither touches `RealmRate.factor`.** The
  bounds are constants: the multiplier adds a fixed factor at every realm and can never
  compound with `1.02^ordinal`. `RATE_STEP` stays the only per-realm number, and the
  helper may not read `RealmDefaults` (pinned).
- **The factors are multiplied, never summed.** Summing rate factors is the shape that
  once made a single breakthrough worth more than everything else combined.

## Consequences

- **The item grants are live.** Every authored `core_cultivation_rate` grant — options,
  bloodlines, sets, fates, consumables — now moves a real number. That is a balance shift
  by construction, and it is bounded: a fully stacked build is capped by the ladder span.
- **`verdant` pays at last.** `ash_camp_ley_spring` (`ash_camp`, in every template's room
  kit) authors `qi_density = 1.2`: the kind that was authored for this is now a trade —
  the overgrowth hazard for a fifth more per sitting — and a content pin fails if the kit
  loses its only rich zone.
- **The ceiling moves with the ladder.** A retune of `RATE_STEP`/`rate_span` moves the
  ceiling because it is computed, not copied; the rate/magnitude split is untouched.
- **The stat's own value is still shown as derived.** The ceiling is on the READ; the
  presenter keeps displaying the stat's own number, and no shipped actor diverges.
