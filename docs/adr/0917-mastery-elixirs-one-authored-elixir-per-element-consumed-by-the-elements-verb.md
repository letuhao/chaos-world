# 0917 Mastery elixirs: one authored elixir per element, consumed by the elements verb

- Status: Accepted
- Date: 2026-10-07

## Context

ADR 0004's mastery loop grows from three sources — practice, domains and elixirs — and only the first shipped: `ElementTraining.practise` moves `element_mastery_<e>`, and the option catalog carries ten `element_mastery_<e>` options, but no consumable granted mastery and no verb could spend one. The elixir door was a ruling with no content behind it.

The item design constrains where such an elixir may be consumed. ADR 0028 rules that a consumable is "one-shot resource restoration, never a permanent modifier", and `ItemUse._apply_consumed` applies exactly three channels: pool restorations, a cleanse, and a REPORT of base-attribute gains. Mastery is none of the three — it is a base attribute the `elements` module owns and writes through `set_base` — and the option catalog admits `element_mastery_<e>` on equipment, not on consumables.

## Decision

- **One elixir per element, named by convention**: `ElementStats.mastery_elixir_id` (`game/src/modules/elements/stats.gd:99`) spells `element_<e>_mastery_elixir`. The element defs are code-built and the family is uniform, so a per-def field would restate one rule ten times; a content case pins that every element's elixir resolves.
- **Consumed by the path's own verb, not by `ItemUse`**: `ElementsApi.use_elixir` (`game/src/modules/elements/api.gd:280`) spends one item and raises the element's mastery. This is the shape the qi ladder already ships — its channel elixirs are consumables spent by `QiTraining.train_channel`, never by pressing Use — and it keeps ADR 0028's "never a permanent modifier" true for the generic consumable path.
- **The gain is per TIER, in one table**: `ELIXIR_GAIN_BY_TIER` (`game/src/modules/elements/training.gd:80`) pays `100.0` for tier 1 and `240.0` for tier 2 — four practise sittings and nine-plus at `PRACTICE_STEP`'s `25.0` at R1's rate of exactly `1.0`. An elixir does NOT ride `RealmRate` the way a sitting does: a sitting is labour and scales with the cultivator, an elixir is a resource and grants what it says, which is what makes one worth carrying to depth. A tier the table does not name reads tier 1 rather than becoming un-drinkable.
- **The practice gate travels**: `use_elixir` (`game/src/modules/elements/training.gd:100`) refuses `no_spark` for an element the body cannot sense, spends nothing on any refusal, and names `unknown_element` / `no_elixir` / `refused` distinctly.
- **The price is content**: ten elixirs and ten recipes (`game/data/items/consumable/element_*_mastery_elixir.tres`, `game/data/recipes/`), each recipe reusing its element's ward reagent plus `bangle_moon_essence`, so every input already resolves to a terminal acquisition route. The item carries the family's shipped filler (`restore_health`, one roll) exactly as the qi channel elixirs do; the mastery itself is the verb's.
- **The edge**: `elements -> items` (registry.json, mirrored in `ModuleRegistry.BASE_DEPS`) for the one spend. Acyclic: `items` depends on `contracts`/`core`/`destiny`/`status`.

## Consequences

- The owner's ruling is now true end to end: mastery can be practised, and bought with an elixir whose price is authored.
- The elixir's UI press lands with the elements panel (BL-0095); the verb is the contract that panel builds against, per the split dev cycle.
- Pressing Use in the inventory on a mastery elixir heals its filler and does NOT grant mastery — the same wart the thirty qi channel elixirs ship. The verb is the door; the filler is item-family decoration, not a second channel.
- The domain door (DEF-0020) remains: mastery from domains is content that has not shipped, and nothing here changes its shape.
