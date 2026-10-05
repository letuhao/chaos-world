# 0096 The qi catalysts are deleted rather than given a fourth role

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0024 (qi realm contracts), ADR 0031 (the third consumable role)

## Context

`QiRealmSeed` declared three consumable roles — `breakthrough_item`, `training_item`,
`recovery_item` (`realm_seed.gd:9-14`) — and 90 further qi consumables under
`game/data/items/consumable/` matched nothing in `game/src/`:

- `qi_<realm>_dantian_catalyst`, `qi_<realm>_meridian_catalyst`, `qi_<realm>_sea_catalyst`,
  30 each, each craftable by one of 90 recipes under `game/data/recipes/`
  (`qi_<realm>_dantian_catalyst_recipe`, `_meridian_catalyst_recipe`, `_sea_recipe`).

Nothing referenced them. A scan of every `.tres` under `game/data` and every `.gd`/`.py` under
`game/src`, `game/tests` and `tools` found the ids only inside the items themselves and inside
their own recipes' `outputs`.

What they actually are settles it. All 90 are `restore_health` stat sticks:
`fixed_modifiers = [{"option_id": &"restore_health", ...}]`, `subcategory` `tonic` or `elixir`,
values 6 for the dantian/meridian families and 33.7-37.6 for the sea family.
`qi_body_integration_dantian_catalyst` is named "Vessel Fusion Ore" and described as "Dantian
strengthening catalyst for Body Integration" while restoring 6 health. **One of the three is
named after a component that does not exist on this path at all** — the sea of consciousness is
the mind path's container (`MindRealmSeed.sea_catalyst` is mind's own, untouched here).

## Decision

**Delete the 90 items and their 90 recipes.** A fourth role is the wrong fix for this content,
for three reasons that the content itself supplies.

- **There is nothing for a catalyst to gate that is not already gated, and the one gate it could
  take over is the worse one.** Qi's entry gate is already seven-part — progress budget,
  comprehension floor, dantian quality, dantian fill, channel state, channel depth, realm pill —
  and every part is discriminating (ADR 0095). The dantian's quality is raised by `cultivate`, a
  free action priced in work: taxing it behind a mandatory consumable removes the player's only
  lever and replaces "did I cultivate well" with "do I hold the item". That is the same defect a
  fourth item would be, one step removed.
- **A mandatory item must be a *different* decision from the pill, and these are not.** The pill
  already is "you may not attempt this realm without having prepared this realm". Adding a second
  mandatory per-realm consumable doubles the acquisition cost of every boundary and adds no choice
  between them — which is the definition of a fourth reason to grind.
- **The brief's own test fails on the data.** "What does the catalyst do that the recovery elixir
  cannot, and why must it be required?" — it restores health, which is neither a qi gate input nor
  anything `recovery_item` cannot do, and it is not required by anything. A gate named "dantian
  catalyst" that restores health would be incoherent content in a gate position.

Rejected: *give them a fourth role on `QiRealmSeed` and gate on it.* It changes the realm-seed
schema for 90 items that are mislabelled health tonics, and the schema change would outlive the
mistake. Rejected: *keep them as un-gated optional content.* A fourth item the player can spend
for a bonus nothing requires is a fourth reason to grind, and `sea_catalyst` naming a component
this path does not have is the tell that the whole family came from a shared five-role template
rather than from a design. Rejected: *re-point them at the mind path*, which has a real
`sea_catalyst` role and its own 30 of them.

## Consequences

- `game/data/items/consumable/qi_*_catalyst.tres` (90) and
  `game/data/recipes/qi_*_dantian_catalyst_recipe.tres`, `qi_*_meridian_catalyst_recipe.tres`,
  `qi_*_sea_recipe.tres` (90) are gone. Qi's recipe count per realm drops from 7 to 4.
- No schema change: `QiRealmSeed` keeps three consumable roles, so nothing had to migrate and the
  facade keeps its three item verbs. If a real fourth role is ever wanted, it should be a gate on
  something the path measures and nothing currently does.
- **Left as found, and reported rather than fixed:** `qi_<realm>_breakthrough_pill_recipe` and
  `qi_<realm>_pill_recipe` both output `qi_<realm>_breakthrough_pill`, from two different herb/core
  pairs (`guardian_core` + `cultivation_herb`, and `qi_herb` + `warden_core`). 30 realms, so 30
  duplicated pills with two acquisition routes each. That is redundancy, not deadness — both routes
  resolve — and removing one is an acquisition-balance decision, not a qi-path one.
- **Needs a hand elsewhere:** `tools/generate_qi_items.py:240-241` still emits
  `qi_<realm>_dantian_catalyst` and `qi_<realm>_meridian_catalyst`, so running it re-creates the
  family this ADR deletes. That file is not the qi path's to edit.