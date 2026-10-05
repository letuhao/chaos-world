class_name BodyMaterialArt
extends RefCounted

## The MATERIAL half of the practice loop: turn matter into a body.
##
## ## This is the "destroy and recreate" payoff, and it LITERALLY grows a limb
##
## [method reshape] does not buff an arm. It writes a `BodyPart` the body did
## not have, and a body that never paid this price has no entry for that limb at
## all — `BodyPractice.has_part` answers false. The part is created by MATTER,
## which is the only thing in this module that creates anatomy.
##
## ## Coordination with the injury system, stated rather than assumed
##
## The injury program owns what a wound costs a body and what repairs it. This
## module does NOT own a second wound flag and does not read its ledger: the seam
## is deliberately narrow and deliberately one-directional. A rebuilt part is
## `integrity`-backed, and `body_integrity` is the reservoir the injury system's
## severity is already measured in (`BodyWounds.add` divides damage by that pool's
## `maximum`), so a rebuilt limb is already denominated in the currency a wound
## spends. What is NOT built here is the reverse edge — an amputation that
## removes a part this module grew. That belongs to the injury program, and the
## request is recorded in `docs/deferred.jsonl` rather than guessed at here.

const _ITEMS := preload("res://src/modules/items/api.gd")


## One resculpt. Returns `{ok, part, created, drain, reason}` — `created` is the
## literal "this body did not have that limb" answer, and `part` is null on any
## refusal.
##
## ## All-or-nothing, and the same rule `BodyTraining.recover` uses
##
## Decide first, mutate second: the material is consumed, the integrity drained,
## the art credited and the part written, or NOTHING changes and the caller is
## told why. A reshape that half-happened would leave a body with a limb made of
## unpaid matter.
static func reshape(actor: Actor, art_id: StringName) -> Dictionary:
	var art := MaterialArtCatalog.find(art_id)
	var refusal := _refusal(actor, art)
	if not refusal.is_empty():
		return refusal
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	if pool == null or pool.current < art.price_drain:
		return _denied("body_integrity too low to reshape")
	if not _ITEMS.consume_item(actor, art.material_item, art.material_cost):
		return _denied("material missing")
	var practice: BodyPractice = actor.component(BodyCultivationApi.PRACTICE_ID)
	var part := practice.part(art.transforms_into)
	var created := part == null
	if created:
		part = BodyPart.new()
		part.id = art.transforms_into
		part.display_name = art.display_name
	part.art_id = art.id
	part.demand = art.draws_demand
	part.integrity = maxf(0.0, pool.current - art.price_drain)
	part.rebuilds += 1
	practice.add_part(part)
	practice.art_mastery[String(art.id)] = practice.art_level(art.id) + art.base_gain
	WeaponDemand.credit_demand(actor, art.draws_demand, art.base_gain)
	WeaponDemand.credit_attribute(actor, art.draws_demand, art.base_gain)
	pool.change(-art.price_drain)
	actor.mark_stats_dirty()
	return {
		"ok": true,
		"part": part,
		"created": created,
		"drain": art.price_drain,
		"reason": &"",
	}


## The whole cost train one reshape pays, as primitives, so a screen can print the
## price without re-deriving it and a test can assert it without reading the def.
static func cost_of(art_id: StringName) -> Dictionary:
	var art := MaterialArtCatalog.find(art_id)
	if art == null:
		return {}
	return {
		"material": String(art.material),
		"material_item": String(art.material_item),
		"material_cost": art.material_cost,
		"integrity": art.price_drain,
		"demand": String(art.draws_demand),
		"part": String(art.transforms_into),
		"base_gain": art.base_gain,
	}


## A refusal in the ONE shape `reshape` always returns, so a caller reads `part` and
## `drain` on a refusal without probing for the key: `ok` false, `created` false,
## `part` null, and nothing was drained or consumed.
static func _denied(reason: String) -> Dictionary:
	return {"ok": false, "part": null, "created": false, "drain": 0.0, "reason": reason}


## The GATE, and it answers `{}` — not a refusal — when every precondition holds.
##
## ## Why `{}`, and why that was the whole bug
##
## The caller asks `if not refusal.is_empty()`, the same idiom `BodyWeaponUse._refusal`
## uses, and that idiom only works if a clean body answers the EMPTY dictionary.
## Returning the full `{ok: false, part: null, ...}` payload here made it non-empty,
## so the gate refused EVERY reshape on EVERY stocked actor: an empty `reason`, no
## matter consumed and no drain paid, on a body that had everything it needed. It is
## invisible in the code and loud in play, which is exactly why the shape is pinned.
static func _refusal(actor: Actor, art: MaterialArtDef) -> Dictionary:
	if actor == null:
		return _denied("no actor")
	if art == null:
		return _denied("unknown material art")
	if actor.component(BodyCultivationApi.PRACTICE_ID) == null:
		return _denied("no practice ledger")
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return _denied("no body path")
	# `index_of` answers -1 for a rank this tree does not know and `maxi` folds that
	# to rung 0 rather than refusing a body the ladder cannot place: an actor off the
	# authored ladder is a first-rung body, the answer every other gate gives.
	if maxi(0, RealmDefaults.ladder().index_of(state.rank_id)) < art.min_realm_index:
		return _denied("realm too shallow for this art")
	return {}
