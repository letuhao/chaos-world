# 0099 A numeraire is a unit of account, and is never acquired as an item

- Status: Accepted
- Date: 2026-10-03

## Context

`tools data audit` requires every item to declare an acquisition source, and reports anything that
cannot be acquired by shipping code. `game/data/items/currency/curr_spirit_coin.tres` failed it
twice: it declared `sources = ["loot"]`, and `loot` is not in the source vocabulary (`gather`,
`starter`, `craft:`, `boss:`, `domain:`, `quest` — `tools/data.py`).

Two rules collided, and neither was wrong on its own.

- **The acquisition rule.** An item a player can hold must be obtainable, or the content graph is
  a lie.
- **What the spirit coin actually is.** It is the economy module's numeraire. The facade holds it
  as an integer: `economy/api.gd` exposes `purse(actor) -> int`, `quote()`, `valuation()` and
  `price_of()` all return numbers, and `trade()` is a ledger — "each side is debited its own row
  and credited the other's". Nothing ever puts a coin `ItemDef` in an inventory.

So the coin is a unit of account with an `ItemDef` attached because the option system needs a
definition to hang `trade_value = 1.0` off. Its own fields say so: `realm = ""`, `grade = "mortal"`,
`subcategory = "numeraire"`. For such an item the acquisition requirement is vacuous — there is no
item to acquire — and `sources = ["loot"]` is a false claim about how a purse is filled.

## Decision

- **A numeraire is exempt from the acquisition requirement, and only a numeraire.** The exemption
  keys on `subcategory == "numeraire"`, which is the authored marker of exactly this role. It does
  not key on `realm == ""`, which would exempt every realm-less holdable and silently reopen the
  hole for real items.
- **A numeraire must declare no sources at all.** Declaring one is now itself a finding. Without
  this half the exemption becomes a place to park an item nobody can reach, which is the exact
  failure the acquisition rule exists to prevent.
- **The exemption is a statement about the item, not about the subsystem.** It does not say the
  economy is finished. A purse with no way to earn one is a separate gap, and naming it as such is
  how it stays visible.

## Consequences

- `data audit` no longer requires a route for something that is not held, and no longer accepts a
  fabricated one.
- A designer who wants a coin that *is* looted writes a normal item with a real source; marking it
  `numeraire` to dodge the audit is now a reported error rather than a silent pass.
- If the economy later grows held currency — coins as inventory rather than a balance — this
  decision is wrong and must be superseded, because the exemption would then hide a genuinely
  unreachable item.
