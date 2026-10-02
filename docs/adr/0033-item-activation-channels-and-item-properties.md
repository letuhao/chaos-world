# 0033 Item activation channels and item properties

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0025 made the master option catalog the sole source for item effects and required every
in-game category to carry both a fixed and a rolled channel. That leaves one open question the
catalog cannot answer on its own: what turns a resolved option into gameplay for an item that is
not a weapon. An option with no consumer is decorative, and registering one anyway would claim
coverage the game does not have.

## Decision

- Every item category maps to exactly one **activation channel**. The mapping is derived from
  the category, never authored per item, so an option can only be placed on an item that has a
  consumer for it:

  | category | channel | consumer |
  |---|---|---|
  | equipment | `equipped` | `Equipment.equip` applies the effect while equipped |
  | consumable | `consumed` | `ItemUse` restores a resource once, bounded by its pool |
  | technique | `learned` | `ItemUse` grants a permanent base-attribute gain |
  | material | `crafted` | `Crafting` reads the item's craft properties as inputs |
  | key / currency / quest / misc | `property` | `ItemUse` exposes the item's numeric properties |

- A catalog record declares `categories`, never `activations`. The activation set is derived
  from the categories in both runtimes, which keeps category -> activation the single source of
  truth and makes an option that claims a consumer its categories do not have invalid.
- Option targets are `stat`, `resource` or `property`.
  - `stat` becomes a source-tagged `StatModifier` while the item is active. An equipped item's
    whole contribution is keyed by its instance id, so a rebuild replaces it instead of stacking.
  - `resource` carries an explicit `scope`. `current` is a one-shot restoration clamped by the
    pool and can never become a permanent modifier; `maximum`/`regen` are persistent and resolve
    to the derived stat `ActorStats` already composes, so there is still one pipeline.
  - `property` names a numeric item property (`craft_potency`, `craft_yield`, `key_reach`,
    `quest_potency`, `trade_value`). Every registered property has a named reader; nothing is
    registered without one.
- Nothing applies because an item is held. Being in the inventory is not an activation.
- Roll-bearing stackables merge only when definition, rarity, realm and every realized
  option/value match. A batch carries its realization, so a consumable never absorbs a different
  roll.

## Consequences

- `ItemDef.effects(instance)` is the single aggregation path for fixed and rolled channels;
  later socket, enchantment, set and unique channels join the same path.
- `tools data options audit` and `tools data audit` enforce the binding: every item resolves to a
  category with a channel, every option it references is registered for that channel, and its
  authored fixed value sits inside the option's realm/rarity magnitude window.
- `tools data items migrate` converts the old raw stat maps in one deterministic, idempotent
  pass; the legacy `flat_modifiers` / `percent_modifiers` fields are gone, so there is no second
  modifier system to keep in sync.
