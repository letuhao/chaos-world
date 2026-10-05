class_name BodyPracticeAction
extends RefCounted

## The two practice VERBS, as an `app/` action: `wield` and `reshape`.
##
## ## Why this file exists instead of two more facade methods
##
## `BodyCultivationApi` is at `rules.MAX_FACADE_PUBLIC_METHODS` (12) and
## `tools arch` fails a 13th. The read side cost nothing — the rows ride
## `panel_state` — but the two verbs need somewhere to live, and `app/` is the
## only unit that may reach a module's internals (`rules.PRIVATE_UNITS`). This
## is the ADR 0143 bridge applied to a module at its method cap: the verbs are
## injected, `ui/` names neither, and the ledger stays a module internal.
##
## ## It holds wiring, not rules
##
## Every refusal, price and rate is decided inside `body_cultivation`. This file
## forwards and returns the report unchanged, so the rule has one home and the
## two screens that call it cannot get different answers out of the same press.

const _ITEMS := preload("res://src/modules/items/api.gd")

## The swing that costs a body its demand. One press of the button: a single
## landed, uncountered strike. Named here rather than typed at a call site, for
## the reason `BodyCultivationApi.STEPS` exists on the other facade.
const DEFAULT_DEMAND_DELTA := 0.5


## One use of `kind_id`. `countered` is the defender's read, supplied by whatever
## resolved the exchange. Returns the module's own report verbatim.
static func wield(
	actor: Actor,
	kind_id: StringName,
	landed: bool = true,
	countered: bool = false,
	demand_paid: StringName = &"",
	demand_delta: float = DEFAULT_DEMAND_DELTA
) -> Dictionary:
	return BodyWeaponUse.wield(actor, kind_id, landed, countered, demand_paid, demand_delta)


## Turn matter into a limb. Returns the module's own report verbatim.
static func reshape(actor: Actor, art_id: StringName) -> Dictionary:
	return BodyMaterialArt.reshape(actor, art_id)


## Whether `counter_id` answers `kind_id` — the bridge between the combat
## module's read of a matchup and the use loop's mastery payout. Forwarded, never
## restated: a second matchup table would be a second answer.
static func answered_by(kind_id: StringName, counter_id: StringName) -> bool:
	return BodyWeaponUse.answered_by(kind_id, counter_id)


## Whether this body could pay for the reshape, and what it is missing when it
## could not. The price is the module's own `cost_of`; this only reports the
## inventory gap, because "may not act" is a fact a screen has to be able to show
## (ADR 0150).
static func missing_material(actor: Actor, art_id: StringName) -> int:
	var cost := BodyMaterialArt.cost_of(art_id)
	if cost.is_empty() or actor == null:
		return 0
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return int(cost.get("material_cost", 0))
	var needed := int(cost.get("material_cost", 0))
	var held := inventory.count(StringName(cost.get("material_item", "")))
	return maxi(0, needed - held)


## A read model a panel renders whole: the practice rows plus whether each row
## could act. Never a rule — every entry is already decided by the module.
static func summary(actor: Actor) -> Dictionary:
	var state := BodyCultivationApi.panel_state(actor)
	var practice: Variant = state.get("practice", {})
	var weapons: Array = []
	for row in practice.get("weapons", []):
		var entry: Dictionary = row
		entry["answered"] = answered_by(
			StringName(entry.get("id", "")), StringName(entry.get("counters", ""))
		)
		weapons.append(entry)
	var materials: Array = []
	for row in practice.get("materials", []):
		var entry: Dictionary = row
		entry["missing_material"] = missing_material(actor, StringName(entry.get("id", "")))
		materials.append(entry)
	practice["weapons"] = weapons
	practice["materials"] = materials
	return practice
