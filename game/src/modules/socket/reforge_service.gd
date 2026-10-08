class_name ReforgeService
extends RefCounted

## Replacing ONE rolled affix on an instance the actor already holds.
##
## The socket program had three transactions and all three were ADDITIVE or
## MOVING: open a slot, impute it, seat a gem, treat a target. None of them
## changed an owned item's own rolled options, so a lucky drop could only be worn
## or discarded — never improved. That is the shape where gear is replaced rather
## than invested in, and it is what this verb removes.
##
## It is deliberately NOT a reroll. `OptionCatalog` forbids one for a reason
## (ADR 0025/0027): a generated instance is a seed, and anything that re-reads
## the seed to chase a better outcome destroys reproducibility. A reforge does
## the opposite: the instance keeps its seed, its provenance and its generation
## record, and gains a SEPARATE recorded transaction in this module's ledger. What
## replaces the affix is not a new roll of the item, it is a new entry with its
## own request id.
##
## Four things answer "make it stronger", and a verb with one of them is a
## treadmill rather than a choice:
##   - It costs material that competes with every other use of that material.
##   - The cost ESCALATES with each reforge of the same instance, and the cap is
##     finite, so chasing one affix is a budget rather than a lottery ticket.
##   - It may only replace the instance's OWN rolled affix. An authored fixed
##     option, a set threshold, or a unique's locked signature is not a target.
##   - The replacement never delivers LESS of the measure it replaced (see
##     `SocketPools.roll_reforge`), so the investment cannot be lost to luck.
##
## Preview and commit are separate for the same reason the enchantment's are: a
## preview reads the candidate list and the refusals and touches nothing.

const ACTION_PREVIEW := &"preview_reforge"
const ACTION_COMMIT := &"commit_reforge"


## What replacing `option_id` on `target_id` could produce, and what would stop
## it. Pure read: no unit consumed, no state written, and `rng` never advanced.
static func preview(
	actor: Actor,
	ledger: SocketLedger,
	target_id: StringName,
	option_id: StringName,
	reagent: ItemDef,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	# Captured so the preview can report that it left the caller's stream alone.
	var stream_before := 0 if rng == null else int(rng.state)
	var owner := SocketOwnership.locate(actor, target_id)
	var target := owner.get("instance") as ItemInstance
	var attempts := ledger.reforge_count(target_id)
	var cap := 0 if target == null else SocketPolicy.reforge_cap(target.rarity)
	var units := SocketPolicy.reforge_cost_units(attempts)
	var out := {
		"ok": false,
		"reason": "",
		"action": String(ACTION_PREVIEW),
		"target": String(target_id),
		"option": String(option_id),
		"cost": [],
		"units": units,
		"permitted": [],
		"current": {},
		"attempts": attempts,
		"cap": cap,
		"locked": [],
		"rolled": false,
		"stream_advanced": false,
	}
	if target != null:
		out["current"] = _current(target, option_id).duplicate(true)
		out["locked"] = _locked(target)
	var refusal := _refusal(actor, target, option_id, reagent, ledger, target_id)
	if not refusal.is_empty():
		out["reason"] = refusal
		out["stream_advanced"] = _advanced(rng, stream_before)
		return out
	out["ok"] = true
	out["cost"] = _repeat(reagent.id, units)
	out["permitted"] = SocketPools.permitted_reforge(
		ItemRarity.sanitize(target.rarity),
		_kept_ids(target, option_id),
		_realm_id(target),
		_rarity_index(target),
		_floor(target, option_id)
	)
	out["stream_advanced"] = _advanced(rng, stream_before)
	return out


## Replace `option_id` on `target_id`, spending the escalated reagent cost.
## Idempotent: the same `request_id` returns the recorded result without
## consuming a second unit, in this session or after a save/load round trip.
static func commit(
	actor: Actor,
	ledger: SocketLedger,
	target_id: StringName,
	option_id: StringName,
	reagent: ItemDef,
	request_id: StringName,
	seed: int
) -> Dictionary:
	var replay := ledger.request(request_id)
	if not replay.is_empty():
		return replay.duplicate(true)
	var owner := SocketOwnership.locate(actor, target_id)
	var target := owner.get("instance") as ItemInstance
	if target == null:
		return SocketResult.refused(ACTION_COMMIT, target_id, "unknown_target")
	# Read-only until every check has passed, so a refused reforge leaves both the
	# ledger and the instance byte-identical.
	var attempts := ledger.reforge_count(target_id)
	var units := SocketPolicy.reforge_cost_units(attempts)
	var refusal := _refusal(actor, target, option_id, reagent, ledger, target_id)
	if not refusal.is_empty():
		return SocketResult.refused(ACTION_COMMIT, target_id, refusal)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var replacement := SocketPools.roll_reforge(
		ItemRarity.sanitize(target.rarity),
		_kept_ids(target, option_id),
		_realm_id(target),
		_rarity_index(target),
		rng,
		_floor(target, option_id)
	)
	if replacement.is_empty():
		return SocketResult.refused(ACTION_COMMIT, target_id, "no_legal_option")
	# Spend only after every read-only check has passed, so a refusal is free.
	var cost := SocketCosts.spend(ItemsApi.inventory(actor), _repeat(reagent.id, units))
	if cost != OK:
		return SocketResult.refused(ACTION_COMMIT, target_id, "cost_failed")
	# Read the whole array out before writing: `_swap` re-derives every other
	# entry's index from `previous`, so a mutating helper that took the array and
	# an index would see its own write mid-scan.
	var previous := target.rolled.duplicate(true)
	if not _swap(target, option_id, replacement):
		return SocketResult.refused(ACTION_COMMIT, target_id, "option_vanished")
	var attempts_after := ledger.record_reforge(target_id, option_id)
	var result := (
		SocketResult
		. committed(
			ACTION_COMMIT,
			target_id,
			_repeat(reagent.id, units),
			{
				"option": String(option_id),
				"replaced": previous,
				"rolled": previous,
				"effect": replacement.duplicate(true),
				"attempts": attempts_after,
				"cap": SocketPolicy.reforge_cap(target.rarity),
				"units": units,
			}
		)
	)
	ledger.record_request(request_id, result)
	ledger.commit(actor)
	_rebind(target)
	_reapply(actor, ledger, target)
	return result


## Every reason a reforge would refuse right now. Empty means it would commit.
static func refusal(
	actor: Actor,
	ledger: SocketLedger,
	target_id: StringName,
	option_id: StringName,
	reagent: ItemDef
) -> String:
	var owner := SocketOwnership.locate(actor, target_id)
	var target := owner.get("instance") as ItemInstance
	return _refusal(actor, target, option_id, reagent, ledger, target_id)


# --- Internals ---------------------------------------------------------------


## Whether a caller's roll stream moved during a preview. It never should.
static func _advanced(rng: RandomNumberGenerator, stream_before: int) -> bool:
	return rng != null and int(rng.state) != stream_before


static func _refusal(
	actor: Actor,
	target: ItemInstance,
	option_id: StringName,
	reagent: ItemDef,
	ledger: SocketLedger,
	target_id: StringName
) -> String:
	if target == null:
		return "unknown_target"
	if reagent == null:
		return "unknown_reagent"
	if target.bound_to != &"" and target.bound_to != actor.id:
		return "bound_to_other"
	# The affix must be one this instance's OWN roll produced. An authored fixed
	# option, a set threshold and a unique's locked signature are all refused
	# here rather than silently treated as reforgeable, which is the whole reason
	# the item carries a channel on every effect.
	if SocketPolicy.rolled_index(target, option_id) < 0:
		return "unknown_option"
	if not SocketPolicy.is_reforgable(target, option_id):
		return "option_locked"
	if not SocketPolicy.meets_tier(
		SocketPolicy.tier_of(actor.realm()), SocketPolicy.tier_of(reagent.realm)
	):
		return "realm_tier_too_low"
	var attempts := ledger.reforge_count(target_id)
	if attempts >= SocketPolicy.reforge_cap(target.rarity):
		return "cap_exhausted"
	if not SocketCosts.can_pay(
		ItemsApi.inventory(actor), _repeat(reagent.id, SocketPolicy.reforge_cost_units(attempts))
	):
		return "missing_cost"
	if (
		SocketPools
		. permitted_reforge(
			ItemRarity.sanitize(target.rarity),
			_kept_ids(target, option_id),
			_realm_id(target),
			_rarity_index(target),
			_floor(target, option_id)
		)
		. is_empty()
	):
		return "no_legal_option"
	return ""


## The effect `option_id` currently contributes, or an empty dictionary. Read
## through the item's own aggregation so it is the number the item actually
## publishes, not a re-derivation that could disagree with it.
static func _current(target: ItemInstance, option_id: StringName) -> Dictionary:
	for effect in SocketPolicy.effects_of(target):
		if StringName(effect.get("option_id", &"")) == option_id:
			return effect
	return {}


## Every affix on `target` a reforge may not replace, as strings.
static func _locked(target: ItemInstance) -> Array:
	var out: Array = []
	for option_id in SocketPolicy.locked_reforge_ids(target):
		out.append(String(option_id))
	return out


## The option ids a replacement may NOT be, being every affix the instance carries
## EXCEPT the one being replaced. The replaced id is left out so drawing it again
## is legal — that is the only way a reforge can return what it was given, and a
## worse result is impossible because of the floor rather than because of this
## exclusion.
static func _kept_ids(target: ItemInstance, option_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for effect in target.rolled:
		var candidate := StringName(effect.get("option_id", &""))
		if candidate != &"" and candidate != option_id and not out.has(candidate):
			out.append(candidate)
	return out


## The measure the replacement may not undershoot: the effect being replaced. Empty
## when there is nothing comparable to hold to, which is what leaves the candidate
## list unbounded in value rather than refusing every reforge.
static func _floor(target: ItemInstance, option_id: StringName) -> Dictionary:
	return _current(target, option_id)


## Replace the rolled entry carrying `option_id` with `replacement`, in place, so
## every other affix keeps its realized value and its position. False when the
## entry is not there any more, which the commit reports rather than writing.
static func _swap(target: ItemInstance, option_id: StringName, replacement: Dictionary) -> bool:
	var index := SocketPolicy.rolled_index(target, option_id)
	if index < 0:
		return false
	target.rolled[index] = replacement.duplicate(true)
	return true


## The reagent id repeated `units` times, the shape `SocketCosts` spends.
static func _repeat(reagent_id: StringName, units: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for _i in maxi(1, units):
		out.append(reagent_id)
	return out


static func _realm_id(target: ItemInstance) -> StringName:
	if target == null:
		return &""
	if target.realm != &"":
		return target.realm
	if target.def_ref != null:
		return target.def_ref.realm
	return &""


static func _rarity_index(target: ItemInstance) -> int:
	return OptionCatalog.rarity_tier(target.rarity if target != null else &"common")


## Re-point a reforged instance's definition reference so a later read resolves
## the same definition the reforge validated against.
static func _rebind(target: ItemInstance) -> void:
	if target == null or target.def_ref != null:
		return
	target.def_ref = SocketContent.resolve(target.def_id)


## Republish the item's contribution after its rolled options changed.
##
## A WORN item applies its own fixed and rolled effects under its instance id, so
## replacing one entry has to rebuild that source — otherwise the actor keeps
## contributing the affix that was just replaced until the item is unequipped and
## worn again. An unequipped item publishes nothing, so only the socket
## contribution needs re-syncing and the instance's numbers are read fresh when it
## is next worn.
static func _reapply(actor: Actor, ledger: SocketLedger, target: ItemInstance) -> void:
	if actor == null or target == null:
		return
	var equipment := ItemsApi.equipment(actor)
	var worn := SocketOwnership.equip_slot_of(actor, target.instance_id)
	if equipment != null and worn != &"":
		equipment.rebuild(actor, worn)
	SocketEffects.sync(actor, ledger)
