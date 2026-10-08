class_name OptionTarget
extends RefCounted

## Typed option targets owned by the master catalog (ADR 0025/0028). Stat ids
## stay owned by contracts/modules; resource ids by their owning module; the
## item properties below are read inside this module by Crafting and ItemsApi.

const STAT := &"stat"
const RESOURCE := &"resource"
const PROPERTY := &"property"
## The lifespan a consumable extends. `tests/modules/items/test_lifespan_elixir.gd` reads it as a
## `target_type`, and the recipe/elixir pair tags itself `&"lifespan"` — this was the only half
## missing, and its absence stopped that suite from PARSING, which aborted the whole module run.
const LIFESPAN := &"lifespan"

# Resource scopes: one-shot restoration vs a persistent capacity/regen change.
const SCOPE_CURRENT := &"current"
const SCOPE_MAXIMUM := &"maximum"
const SCOPE_REGEN := &"regen"

# Item properties, each with a named consumer.
const CRAFT_POTENCY := &"craft_potency"  # Crafting: raises output quality/yield.
const CRAFT_YIELD := &"craft_yield"  # Crafting: extra-output chance.
const KEY_REACH := &"key_reach"  # ItemsApi.key_reach: highest domain a key opens.
const QUEST_POTENCY := &"quest_potency"  # ItemsApi.quest_potency: reward size.
## The fixed, authored worth a price is computed from (ADR 0094). Never rolled.
const TRADE_VALUE := &"trade_value"

const PROPERTIES := [CRAFT_POTENCY, CRAFT_YIELD, KEY_REACH, QUEST_POTENCY, TRADE_VALUE]
