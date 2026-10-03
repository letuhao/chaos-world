# 0135 Equipping a unique earns a fate once, and unequipping never takes it back

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0065 (narrows "never equipped"; the invariant is preserved, not weakened)
- Depends on: ADR 0134 (the consumer surface)

## Context

ADR 0065 says fate is **earned, never chosen, never equipped, never removed**. The owner now
wants equipping a unique item to grant destiny. Those two statements collide on the word
*equipped*, and leaving the contradiction standing is how a later agent builds the wrong
thing — most likely a grant that comes and goes with the slot, which would make the ledger
unsafe to restore and replay and is the one change ADR 0065's whole ledger argument exists
to prevent.

Read the invariant precisely: the thing it forbids is **fate occupying an equipment slot and
being governed by one**. The ledger stays the single source of truth; the item is a *cause*,
not a *container*.

## Decision

**Equipping a unique earns its fate. Once. Never revoked by unequipping.**

- **A unique is identified by data, not by type.** `UniqueItem.is_unique(def)` is
  `def.tags.has(&"unique")` (`set_bonus/unique_item.gd:31`) — identity is a tag on an ordinary
  `ItemDef`, exactly as ADR 0025/0033 decided. The fate an item grants is a **plain fate id in
  the destiny catalog**, authored on the item and resolved through `FateCatalog`. Never
  `item:<id>`, never a new id namespace — ADR 0065's rule about `quest:` applies to this case
  for the same reason: a fate the catalog cannot resolve would read as a working reference and
  grant nothing.
- **`source` names the SYSTEM, not the item.** `"unique:<item_id>"`, matching `"quest:<id>"`,
  `"event:<id>"` and `"origin"`. The history trail answers "how was this earned" from the
  source string and the fate id from the catalog.
- **The call site is the moment equip succeeds.** `ItemsApi.equip_item` (`items/api.gd:72`) is
  the single place a non-stackable definition enters a slot, and it is the only place that
  knows whether the equip was accepted — an invalid equip changes nothing and leaves the item
  in inventory. Granting on *attempt* would hand out a fate for an equip that never happened.
  So the grant belongs after that method's `return true`, or — because `items` is at the
  twelve-method facade cap and the earn call is a one-liner the module can make itself —
  immediately after `eq.equip(...)` succeeds inside it.
- **Only `equip_item` grants. `unequip_to_inventory` and `Equipment.unequip` grant nothing and
  revoke nothing.** There is no call site in either, and there will never be one: the ledger is
  monotone and there is no verb in `destiny` that could express the subtraction.
- **Re-equipping grants nothing a second time.** `earn_fate` is exactly-once
  (`api.gd:57-58`), so the second equip returns the same ledger. A player may equip and
  unequip the same unique a hundred times and hold the fate exactly once. This is why the
  grant needs **no new once-guard of its own** — and that is the whole reason this reading was
  chosen over the alternatives.
- **Rejection over silence.** An item naming a fate id the catalog does not define is refused
  by `earn_fate` (unchanged ledger), not recorded. So is a fate id that arrives namespaced.
  The equip still succeeds; the player keeps the item. A content bug must not cost a player
  their gear.
- **The eligibility inversion is REFUSED as the answer.** Gating an item's *worn-ness* on
  holding a fate would invert the relationship into a second stat composer on the item side
  and would make a removable object gate a permanent one. If a unique should require a fate,
  that requirement belongs in the existing `ItemRequirement` profile (ADR 0052) or in a
  `has_fate` gate on the quest/event that pays it — never in a bespoke "is this item wearable"
  check that reads the destiny ledger.

## Consequences

- **Nothing in `destiny` changes.** No new verb, no field, no reversal path. `items` gains a
  dependency on `destiny` and one call. That is the cost of the whole decision.
- **`items` MUST declare `destiny` in `tools/arch/registry.json`** (ADR 0134). It currently
  declares `[contracts, core]`. `BARE_REF_UNITS` excludes `modules/*`, so without the entry
  the edge is invisible to `tools arch` and to cycle detection — exactly the `quest` case.
- **The authored fate must exist before the item ships.** An item naming an unearned-in-practice
  fate is legal and refused at runtime; `tools data audit` currently validates fate cross-
  references but has no check that an item's authored fate id is a real `FateDef`. Until one
  exists, a typo ships an item that grants nothing. Recorded as a deferral rather than
  papered over.
- **Balance consequence the owner should weigh before authoring:** because a fate is permanent,
  a unique's fate is a **one-time permanent power-up for an item the player can store in a
  chest and re-equip forever**. If that is the intent, ship it as a deliberately scarce,
  high-consequence reward. If it is not the intent, the relationship must be re-decided — this
  ADR does not accidentally permit "equip for the buff, unequip to drop it".
- **Not implemented.** No `grants_fate` field exists on `ItemDef` today and no `.tres` names
  one. This ADR decides the shape; the field is the next slice and it must land with the
  registry entry and a contract test in the same change.