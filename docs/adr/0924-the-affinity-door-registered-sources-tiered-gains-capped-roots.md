# 0924 the affinity door: registered sources, tiered gains, capped roots

- Status: Accepted
- Date: 2026-10-08

## Context

The completeness audit (BL-0926) found `ElementsApi.awaken` — the S1 "rare resource
raises the AFFINITY" door — with no caller and no authored resource: an element a
race never granted (commonborn ships the five base only; emberblood fire) could never
be trained, and `element_power_<e> = affinity * (...)` reads 0.0 forever at affinity
0. The novels open roots many ways — treasures, elixirs, life-bound dharma treasures,
refining arts — and the list grows with the game, so one item family would be a door
that has to be rebuilt per feature.

## Decision

- **The door is a registered-source seam.** `contracts/affinity_source.gd`
  (`AffinitySource`) carries the grant (`element`, `amount`, `tier`, `once`) and the
  source's own `check`/`consume` Callables; `ElementsApi.register_affinity_source`
  registers it and `ElementsApi.attune(actor, element)` resolves the best available
  source. Treasures and awakening elixirs ship as the module's own DERIVED sources
  (item ids it already names); anything else — a root-refining art today, the
  life-bound dharma treasure later — registers through the same call.
- **The gate is the existing one.** `attune` refuses by `element_locked` through
  `ElementMastery.usable` — the rank must reach the element's tier AND the qi realm
  must allow it — never a second opinion (ADR 0044).
- **The price is tiered and capped** (owner ruling 2026-10-08): a treasure pays
  +2/+3/+5 by tier, an awakening elixir doubles it (+4/+6/+10), and a root stops at
  12/15/18 by tier. The cap bounds the INNATE axis only: mastery stays uncapped and
  the realm multiplier is shared, so the climb keeps scaling while a root stays
  finite. A grant never overshoots the cap — the last treasure pays the room left.
- **The families ship as authored content**: 13 awakening treasures
  (`element_<e>_awakening_treasure`, domain drops — the six elemental domains and the
  realm-matched qi warden pools) and 13 awakening elixirs
  (`element_<e>_awakening_elixir`, crafted from a treasure + the element's own
  materials). `once` grants (the arts' openings) are remembered in the actor's
  `module_data`, so a save cannot re-open a root.
- **The screen**: the elements screen gains an Attune action and an affinity row; the
  selection prefers an element whose press would land, then the weakest root.
  Enrollment keeps the name "Awaken" (S2's shape).

## Consequences

- Any feature can open a root without touching the elements module: register a
  source. The life-bound dharma treasure (本命法宝) is deferred as its own feature
  (DEF-0379) and will register through this seam.
- The pipeline is proved end to end by a test: no spark → treasure → the spark opens
  → `practise` lands → the mastery elixir stops refusing `no_spark`.
- An element's TIER, not the player's race, decides how far a root can be pushed, and
  the per-element cap keeps affinity from becoming a second power ladder.
