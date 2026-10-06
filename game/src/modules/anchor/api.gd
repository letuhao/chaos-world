class_name AnchorApi
extends RefCounted

## Public facade for the `anchor` module (ADR 0132). Other modules may reference ONLY this
## file (`api.gd`).
##
## ## What this is
##
## **The building feature, built as its own module.** An anchor is a structure the player
## RAISES, which then repairs their soul while they stand in it. That is the wiring the rebirth
## program asked for and could not find: `holdings` is a claim over ground that already existed,
## with no build verb and no cost to construct, and it is at its twelve-method facade cap.
##
## ## Why the soul is repaired HERE and not by the soul module
##
## **Repair needs a place, and the place is the anchor's.** `soul` owns the integrity number and
## nothing else — it must not know where the number came from, or a repair would become a second
## way to change integrity and the module's own ledger would stop being the single source. So
## `anchor` calls `SoulApi.repair` and `soul` never names `anchor`.
##
## ## One verb per question, under the cap
##
## Twelve methods is the ceiling and fifteen modules already sit on it. `summary` answers the
## whole screen rather than publishing per-anchor getters.

## The store's ledger key, and the actor mirror's `module_data` key.
const MODULE_KEY := AnchorState.MODULE_KEY

## Where the anchors are. Null until `set_store` installs one, and the in-memory ledger is the
## documented-wrong default: it is a seam, not an endorsement (ADR 0101).
static var _store: RefCounted = null


## Install the holder for the shared anchor ledger — any object with `read_ledger()` and
## `write_ledger(ledger)`. `app/` installs the file-backed save store.
##
## Named that way and never `load` / `save`: those are global GDScript builtins, and a
## `RefCounted` method of that name resolves to the builtin — a compile error rather than a
## loud failure, invisible until the suite runs.
static func set_store(store: RefCounted) -> void:
	_store = store


## Attach the module to `actor`: mirror the ledger onto its `module_data` so a save carries it.
## Reads from the STORE and writes the actor copy, never the reverse — a restore that wrote the
## store from the actor would make a save authoritative for the world.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, AnchorState.normalize(_state()))


## How much `anchor_id` still costs to raise, as `{coins, items, complete}`. Authored on the
## def, never a literal in code, so retuning an anchor never rewrites a save.
static func cost_of(anchor_id: StringName) -> Dictionary:
	var def := AnchorCatalog.instance().anchor_definition(anchor_id)
	if def == null:
		return {"ok": false, "reason": "unknown_anchor", "coins": 0, "items": {}, "complete": false}
	var coins := int(def.build_cost.get("coins", 0))
	var items := def.build_cost.get("items", {}) as Dictionary
	return {"ok": true, "reason": "", "coins": coins, "items": items.duplicate(), "complete": false}


## Raise `anchor_id` for `actor`, charging its authored cost and recording the debt outstanding.
##
## **A raised anchor is a WORLD fact, so the ledger lives in the store** — a rival must see it
## standing or they raise their own on the same ground (ADR 0101's argument, unchanged).
##
## Refuses `unknown_anchor`, `already_raised` and `cannot_afford`, and names which. Refuses
## `realm_floor` when the body is below the authored floor, because an anchor nobody can reach
## yet is content that cannot be used and silently ignoring the floor hides that.
static func raise_anchor(actor: Actor, anchor_id: StringName, at: String = "") -> Dictionary:
	if actor == null:
		return _refuse("no_actor")
	var def := AnchorCatalog.instance().anchor_definition(anchor_id)
	if def == null:
		return _refuse("unknown_anchor")
	var ledger := _state()
	if AnchorState.is_raised(ledger, anchor_id):
		return _refuse("already_raised")
	if def.realm_floor != &"" and not _meets_floor(actor, def.realm_floor):
		return _refuse("realm_floor")
	var cost := cost_of(anchor_id)
	var owed := int(cost["coins"])
	var missing := _missing_items(actor, cost["items"] as Dictionary)
	if not missing.is_empty():
		# The debt is RECORDED rather than refused outright: a player part-way through raising
		# something must be able to come back and finish, and a ledger that forgets the progress
		# makes the second attempt pay twice.
		ledger["debt"][String(anchor_id)] = owed
		_persist(actor, ledger)
		return {
			"ok": false,
			"reason": "cannot_afford",
			"anchor_id": String(anchor_id),
			"owed": owed,
			"missing": missing,
		}
	# **Coins are NOT a gate here.** The purse belongs to `economy`, this module declares no edge
	# to it, and subtracting from it directly would be the ADR 0066 failure — a second place to
	# disagree about a number. So the authored coin figure is the RECORDED price, the real gate is
	# the item cost above, and a purse-aware caller settles the coins before calling this. That is
	# stated here because "the price is authored but not charged" reads as an omission otherwise.
	AnchorState.raise(ledger, anchor_id, at)
	_append(ledger, "raised", anchor_id, owed)
	_persist(actor, ledger)
	return {
		"ok": true,
		"reason": "",
		"anchor_id": String(anchor_id),
		"owed": 0,
		"missing": [] as Array,
	}


## Charge `amount` against `anchor_id`'s outstanding debt without raising it. The verb a partial
## payment uses; it returns what is STILL owed so a caller can show the remainder.
static func pay_down(actor: Actor, anchor_id: StringName, amount: int) -> Dictionary:
	var ledger := _state()
	if AnchorState.is_raised(ledger, anchor_id):
		return _refuse("already_raised")
	var owed := AnchorState.charge_debt(ledger, anchor_id, amount)
	_append(ledger, "payment", anchor_id, amount)
	_persist(actor, ledger)
	return {"ok": true, "reason": "", "anchor_id": String(anchor_id), "owed": owed}


## Repair `actor`'s soul by `periods` whole periods while they stand in a raised anchor that
## repairs. Returns what was actually restored.
##
## **`periods` is explicit and there is no tick** (DEF-0111): a caller that owns time — the
## composition root's period boundary — calls this. A repair that accrued on its own clock would
## be a second source of truth for when time passed.
##
## Refuses `no_periods` for zero or fewer, `not_raised` when nothing stands, and `no_repair`
## when what stands only shelters. Returns the amount RESTORED, so a caller learns the real
## delta rather than the one it asked for.
static func repair(actor: Actor, periods: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "restored": 0}
	if periods <= 0:
		return {"ok": false, "reason": "no_periods", "restored": 0}
	var ledger := _state()
	var anchor_id := _first_repairing(ledger)
	if anchor_id == &"":
		var raised := AnchorState.raised_ids(ledger)
		return {
			"ok": false,
			"reason": "not_raised" if raised.is_empty() else "no_repair",
			"restored": 0,
			"anchor_id": "",
		}
	var def := AnchorCatalog.instance().anchor_definition(anchor_id)
	if def == null:
		return {"ok": false, "reason": "unknown_anchor", "restored": 0, "anchor_id": ""}
	# Fractional repair per period, floored ONCE at the end: truncating per period would make a
	# slow anchor repair nothing at all, which is a silent no-op a content audit cannot see.
	# ADR 0899: multiplied by the actor's `soul_anchor` INSIDE the same floor, so the shipped
	# factor 1.0 restores exactly what it restored before the stat existed.
	var amount := int(floor(def.repair_per_period * float(periods) * SoulApi.anchor_factor(actor)))
	if amount <= 0:
		return {
			"ok": false,
			"reason": "nothing_to_repair",
			"restored": 0,
			"anchor_id": String(anchor_id),
			# WHY, because `nothing_to_repair` on a raised hearth reads as a wiring fault and is
			# usually CONTENT: a fractional rate below 1.0 restores nothing over a single
			# period, which is exactly what one waiting a season sees.
			"repair_per_period": def.repair_per_period,
			"periods": periods,
		}
	var healed := SoulApi.repair(actor, amount, "anchor:%s" % anchor_id)
	var restored := int(healed.get("applied", 0))
	if restored > 0:
		var entry = (ledger["raised"] as Dictionary).get(String(anchor_id))
		if entry is Dictionary:
			(entry as Dictionary)["integrity"] = (
				int((entry as Dictionary).get("integrity", 0)) + restored
			)
		_append(ledger, "repair", anchor_id, restored)
	_persist(actor, ledger)
	return {
		"ok": restored > 0,
		"reason": "" if restored > 0 else "already_whole",
		"restored": restored,
		"anchor_id": String(anchor_id),
	}


## Whether a raised anchor would shelter the actor from a further death's cost. A shelter
## does not repair what is lost; it stops the next death taking any more, which is a
## different promise and therefore a different id.
##
## The anchor is read from the shared ledger rather than from the actor, so `_actor` names
## a caller-supplied argument the verb does not need. It stays in the signature because
## every other verb on this facade answers per actor and a screen that reached for
## `summary` and `shelters` would otherwise have to remember which one takes what.
static func shelters(_actor: Actor) -> Dictionary:
	var ledger := _state()
	for anchor_id in AnchorState.raised_ids(ledger):
		var def := AnchorCatalog.instance().anchor_definition(anchor_id)
		if def != null and def.shelters:
			return {"ok": true, "anchor_id": String(anchor_id)}
	return {"ok": false, "anchor_id": ""}


## Whether `anchor_id` stands raised in this world.
##
## `_actor` is accepted for the same reason [method shelters] accepts one: the answer comes
## from the world ledger, but the facade answers per actor everywhere else.
static func is_raised(_actor: Actor, anchor_id: StringName) -> bool:
	return AnchorState.is_raised(_state(), anchor_id)


## The ledger exactly as the save carries it.
##
## `_actor` is accepted for the same reason [method shelters] accepts one: the ledger is
## the world's, but this facade answers per actor everywhere else.
static func state(_actor: Actor) -> Dictionary:
	return _state()


## Everything an anchor screen needs in one call: the ledger, every authored anchor as a
## primitive row, and what the actor may currently do with each. Primitives only, `{}` with no
## actor.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var ledger := _state()
	var rows: Array[Dictionary] = []
	for anchor_id in AnchorCatalog.instance().ids():
		var def := AnchorCatalog.instance().anchor_definition(anchor_id)
		if def == null:
			continue
		(
			rows
			. append(
				{
					"id": String(anchor_id),
					"display_name": String(def.display_name),
					"description": String(def.description),
					"repair_per_period": def.repair_per_period,
					"repairs": def.repairs,
					"shelters": def.shelters,
					"realm_floor": String(def.realm_floor),
					"raised": AnchorState.is_raised(ledger, anchor_id),
					"raised_integrity": AnchorState.raised_integrity(ledger, anchor_id),
					"owed": int((ledger["debt"] as Dictionary).get(String(anchor_id), 0)),
					"reachable": def.realm_floor == &"" or _meets_floor(actor, def.realm_floor),
				}
			)
		)
	return {
		"actor": String(actor.id),
		"anchors": rows,
		"raised_count": (ledger["raised"] as Dictionary).size(),
		"outstanding_debt": (ledger["debt"] as Dictionary).size(),
	}


## Content audit: every authored anchor is usable. A def that repairs nothing and shelters
## nothing is a building a player can raise for no reason, so it fails the gate rather than
## shipping as content that does nothing.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var catalog := AnchorCatalog.instance()
	if not catalog.is_loaded():
		problems.append("anchor: no authored anchors loaded")
		return problems
	for anchor_id in catalog.ids():
		var def := catalog.anchor_definition(anchor_id)
		if def == null:
			problems.append("anchor: %s has no definition" % anchor_id)
			continue
		if def.display_name.is_empty():
			problems.append("anchor: %s has no display name" % anchor_id)
		if not def.repairs and not def.shelters:
			problems.append("anchor: %s neither repairs nor shelters" % anchor_id)
		if def.repairs and def.repair_per_period <= 0.0:
			problems.append("anchor: %s claims to repair at zero per period" % anchor_id)
		# **A repairing anchor must repair at least ONE integrity over ONE period.** A rate below
		# 1.0 floors to zero, so a player who waits a single season gets nothing and nothing
		# reports an error — the hearth stands, costs a fortune, and heals nobody. That is the
		# silent content gap DEF-0047 records, and it is caught here rather than in play.
		if def.repairs and def.repair_per_period < 1.0:
			problems.append(
				(
					(
						"anchor: %s repairs %s per period, which floors to nothing over one "
						+ "period - author at least 1.0"
					)
					% [anchor_id, def.repair_per_period]
				)
			)
	return problems


# --- Internals -------------------------------------------------------------


## The ledger, from the store when one is installed and empty otherwise. The actor mirror is the
## documented-wrong default (ADR 0101) and the reason it is kept is that it is what a save
## carries.
static func _state() -> Dictionary:
	if _store != null and _store.has_method(&"read_ledger"):
		return AnchorState.normalize(_store.call(&"read_ledger"), _known())
	return AnchorState.empty()


## Write the store and then the actor mirror. Both, always: the store is truth and the mirror is
## what a save carries, so writing only one of them loses the anchors on one path or the other.
static func _persist(actor: Actor, ledger: Dictionary) -> void:
	var normalized := AnchorState.normalize(ledger, _known())
	if _store != null and _store.has_method(&"write_ledger"):
		_store.call(&"write_ledger", normalized)
	actor.set_module_data(MODULE_KEY, normalized)


## The known-anchor filter. An empty catalog reports an empty filter, which `normalize` reads as
## "keep everything" — so a tree that failed to load is told apart from a build that ships none.
static func _known() -> Dictionary:
	if not AnchorCatalog.instance().is_loaded():
		return {}
	return AnchorCatalog.instance().known_anchors()


## The first raised anchor that repairs, in id order so the answer does not depend on which
## `.tres` a scan reached first.
static func _first_repairing(ledger: Dictionary) -> StringName:
	for anchor_id in AnchorState.raised_ids(ledger):
		var def := AnchorCatalog.instance().anchor_definition(anchor_id)
		if def != null and def.repairs:
			return anchor_id
	return &""


## Whether the actor carries the realm the anchor's floor names. A floor of `""` is always met,
## which is why `def.realm_floor == &""` short-circuits in the two callers.
static func _meets_floor(actor: Actor, floor: StringName) -> bool:
	if floor == &"":
		return true
	return String(actor.realm()) == String(floor)


## Item ids `actor` is short of for `wanted`, as `{def_id: count}`. Empty means affordable, which
## is the answer `raise_anchor` branches on — and it is computed here rather than in the caller so
## two callers cannot disagree about what "affordable" means.
static func _missing_items(actor: Actor, wanted: Dictionary) -> Dictionary:
	var missing := {}
	for def_id in wanted.keys():
		var need := int(wanted[def_id])
		if need <= 0 or ItemsApi.has_item(actor, StringName(def_id), need):
			continue
		missing[String(def_id)] = need
	return missing


## Append one bounded trail row.
static func _append(ledger: Dictionary, kind: String, anchor_id: StringName, amount: int) -> void:
	var trail := ledger["history"] as Array
	trail.append({"kind": kind, "anchor_id": String(anchor_id), "amount": maxi(0, amount)})
	if trail.size() > AnchorState.HISTORY_LIMIT:
		ledger["history"] = trail.slice(trail.size() - AnchorState.HISTORY_LIMIT)


static func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"anchor_id": "",
		"owed": 0,
		"missing": [] as Array,
	}
