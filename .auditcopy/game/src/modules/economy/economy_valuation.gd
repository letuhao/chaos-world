class_name EconomyValuation
extends RefCounted

## The one price formula (ADR 0094). A price is a base worth, a rarity weight and the
## one shared rate curve — never a roll, a margin, a buyer or an index.
##
## ## Why `trade_value` could not be the price
##
## `master_option_pool.jsonl` registers the option with `"contexts": ["base", "prefix",
## "postfix"]` and `"magnitude_policy": "realm_rarity"`. Because currency defs carry
## `roll_spec = {"contexts": ["base"]}`, the property sat inside the rollable pool: a
## realized coin's worth was an `rng` draw, and the authored numbers (`6`, then the
## cluster `33.69 / 34.65 / 35.62 / 36.58 / 37.54`) are `OptionCatalog.magnitude_bounds`
## filler, not prices. A price that varies per instance cannot be a price.
##
## So the base worth is read **only from `fixed_modifiers`**, never from `rolled`. A
## realized instance that rolled a price input is refused rather than priced, so a content
## wave that forgets the structural flag fails loudly instead of inflating silently.
##
## ## One function, one place
##
## Every price in the game is computed here. A second copy is ADR 0066's failure mode, so
## there is exactly one and the facade publishes it read-only.

## The four authored rarity weights. Authored rather than derived from
## `item_magnitude_scale.json` because reconciling the item table with the actor table is
## ADR 0050's open debt and needs its own ADR.
const RARITY_WEIGHT := {
	&"common": 1.0,
	&"magic": 1.6,
	&"rare": 2.6,
	&"legendary": 4.0,
}

## An unknown rarity prices as common rather than refusing: rarity is content, and a
## mistyped rarity should not be able to make an item unsellable.
const DEFAULT_RARITY := ItemRarity.COMMON

## The base worth of the numéraire, so money prices at exactly `RealmRate.NEUTRAL` and the
## same formula covers money and goods with no special case.
const NUMERAIRE_WORTH := 1.0

## The def id of the numéraire. Authored fresh rather than promoted from an existing
## currency item: a generated currency is realm- and rarity-stamped, and a numéraire that
## changed with its holder's realm would make `RealmRate.factor` meaningless for it —
## money would then re-price every time its holder broke through.
const NUMERAIRE_DEF_ID := &"curr_spirit_coin"


## The weight for `rarity`. Never zero and never negative.
static func rarity_weight(rarity: StringName) -> float:
	return float(RARITY_WEIGHT.get(rarity, RARITY_WEIGHT[DEFAULT_RARITY]))


## The authored, non-rolled base worth of `instance`. Reads `fixed_modifiers` directly
## rather than through `ItemDef.property_total`, because `property_total` deliberately
## funnels fixed AND rolled together (ADR 0026) and this reader must be able to say
## "authored only". Returns `0.0` when the def ships no price input, which `unit_price`
## floors to 1 and `EconomyApi.valuation` reports as `no_settlement`.
static func base_worth(instance: ItemInstance) -> float:
	if instance == null or instance.def_ref == null:
		return 0.0
	return base_worth_of(instance.def_ref)


## The authored base worth of a definition, independent of any instance. A def with a
## rolled price input contributes nothing: the structural test in `test_valuation.gd`
## fails on one, and refusing to price it keeps a broken content wave from inflating the
## economy rather than merely mispricing one item.
static func base_worth_of(def: ItemDef) -> float:
	if def == null:
		return 0.0
	var total := 0.0
	for entry in def.fixed_modifiers:
		if StringName(entry.get("option_id", "")) == OptionTarget.TRADE_VALUE:
			total += float(entry.get("value", 0.0))
	return total


## True when `instance` carries a ROLLED price input, which ADR 0094 forbids: a rolled
## worth is an `rng` draw and a price that varies per instance cannot be a price.
##
## Reads `option_id`, which is the key `ItemGenerator` writes and the key the stacking
## signature compares — **not** `target_id`. A realized effect carries both, so matching
## the wrong one would silently never fire, which is the exact failure this guard exists to
## prevent.
static func has_rolled_worth(instance: ItemInstance) -> bool:
	if instance == null:
		return false
	for effect in instance.rolled:
		if StringName(effect.get("option_id", "")) == OptionTarget.TRADE_VALUE:
			return true
	return false


## The price of one unit, per ADR 0094.
##
## `maxi(1, ...)` is load-bearing and not a convenience: an unauthored or zero worth must
## read as "cheap", never as unsellable, and the floor is why the ~250 authored currency
## items are wrong-as-prices without the game being unable to sell them.
static func unit_price(base_worth: float, rarity: StringName, realm: StringName) -> int:
	if base_worth <= 0.0:
		return 1
	return maxi(1, roundi(base_worth * rarity_weight(rarity) * RealmRate.factor(realm)))


## The price of one realized unit. The convenience form of the formula, and the only one
## callers should use.
static func price_of(instance: ItemInstance) -> int:
	if instance == null:
		return 0
	var rarity: StringName = (
		instance.rarity
		if instance.rarity != &""
		else instance.def_ref.rarity if instance.def_ref != null else DEFAULT_RARITY
	)
	return unit_price(base_worth(instance), rarity, instance.realm)


## The price of `quantity` units. Strictly multiplicative — no bulk curve in v1, because a
## bulk curve is a second price function wearing a hat.
static func total_price(instance: ItemInstance, quantity: int) -> int:
	return price_of(instance) * maxi(0, quantity)


## The def id of the numéraire. One authored currency item carries it; every other
## currency def is a good priced by this same formula (ADR 0094).
##
## It is authored fresh rather than promoted from an existing currency def because every
## existing one is realm- and rarity-stamped by the generator, and a numéraire with a
## realm makes `RealmRate.factor` meaningless for it: money would then reprice itself
## every time its holder broke through.
static func numeraire_id() -> StringName:
	return NUMERAIRE_DEF_ID


## The price of the numéraire itself: 1, always, at any realm. Published so a panel and a
## test read the invariant from one place instead of restating it.
static func numeraire_price() -> int:
	return unit_price(NUMERAIRE_WORTH, ItemRarity.COMMON, &"")
