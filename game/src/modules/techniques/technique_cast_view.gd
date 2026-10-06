class_name TechniqueCastView
extends RefCounted

## What ONE landed cast actually moved, as primitives, for a caller that could not
## answer it from the activation outcome alone (ADR 0053, DEF-0097).
##
## ## Why this is a class and not a facade method
##
## `TechniquesApi` publishes this as a CONSTANT, not as a verb. It is reached the way
## `TechniqueCasting` and `TechniqueDelivery` are reached — a named type in this
## module, named by a constant on the facade. The twelve-verb cap that originally
## forced that shape is gone (ADR 0265); cohesion is what keeps it, because a facade
## that re-exports its own module interior has stopped being an interface.
##
## ```
## var before := TechniqueCastView.snapshot(caster, foe)
## var fired := casting.activate(caster, def, foe)
## var turn := TechniqueCastView.of(fired, before, caster, foe)
## ```
##
## ## What is ALREADY observable, so this does not overclaim
##
## A landed cast is not invisible today. `TechniqueCasting.activate` returns the
## composition root's real `CombatOutcome` as `damage`, and `CombatOutcome.to_dict`
## publishes `amount`, `health_delta` and `effects[]`. `health_delta` is the health a
## target actually lost, negative, and it is the spine's own record of its one sign
## flip. So "the cast damages nothing" is FALSE, and this file exists for the narrower
## question the descriptor cannot answer alone.
##
## ## The gap, as a measurement
##
## `CombatOutcome` publishes the SPINE's fourteen fields and nothing outside the
## spine. A turn that costs qi, spends a cooldown, erodes a sea and wounds a meridian
## is four facts in four systems, and the descriptor carries one of them in a number
## and two of them only inside an `effects[]` row a caller must know how to read.
##
## Mind is the case that makes it sharp. ADR 0071 with ADR 0162 means a mind technique
## erodes a sea and pays only the shared chip floor, so its `amount` is `0.0` BY
## DESIGN and its health cost is 1.0 HP. A caller reading the damage fields alone sees
## a technique that did nothing — which is the DEF-0097 question asked about the one
## path where the answer is deliberately not in those fields.
##
## So this reads the pools and the two state components a cast can move, AFTER it, and
## publishes the whole turn as one primitives-only answer (ADR 0038). It computes no
## damage, reads no tuning, re-resolves nothing, and writes no pool: the spine already
## charged the target, so applying this answer to that pool would be a double spend.
##
## ## The snapshot, and why the caller takes it
##
## A delta needs two readings and this answer is built after the fact, so the BEFORE
## value has to be captured by the caller through [method snapshot] — one call before
## `activate`. That is a real obligation and it is published rather than hidden:
## `measured` is false without a snapshot, every ABSOLUTE value is still correct
## (`health_lost`, `remaining_health`, `status_applied`, `paid`), and the deltas are
## `{}` rather than zeros. A fabricated `before` would be worse than an absent one,
## because it would be indistinguishable from a measured one.

## The pools a cast can move. Qi and stamina are the two an activation drains and the
## two a defender's pools can be drawn down from; nothing else is a technique's
## business, and a `ResourcePool` this actor does not carry is left out rather than
## reported as an unchanged one.
const POOLS := [&"qi", &"stamina"]

## The components whose state a cast can move, read as COMPONENTS and not as paths: a
## path says what was enrolled and a component says what is mounted, and gating on the
## wrong one refuses exactly the actors it exists to enable — the rule
## `CombatBoot._runs_for` states for a mechanism, for the same reason.
const SEA_COMPONENT := &"sea_of_consciousness"
const WOUNDS_COMPONENT := &"body_wounds"

## S12's verdict, transcribed from `effects[]` because ADR 0087 fixed S12's result as
## an `effects[]` entry and `StatusApply` is a `combat_engine` type this module may not
## have a compile-time edge to.
##
## An effect carrying NEITHER key is a mechanism's own write — a body wound and a mind
## erosion both look like that — so it is skipped rather than guessed at, which is what
## keeps `status_applied` from reporting a wound as a status.
const EFFECT_APPLIED := &"applied"
const EFFECT_REFUSED := &"refused"

## The activity an activation is in. `resolved` means a descriptor came back and the
## turn is accounted for; `none` means none did, which is a different message from a
## strike that resolved and missed. A REFUSAL is `fired == false` with no activity, so
## "no resolver was installed" never reads as "the strike missed".
const RESOLVED := &"resolved"
const NONE := &"none"


## Capture the readings [method of] diffs against. Call once, immediately before
## `activate`, and hand the result to [method of] afterwards.
##
## `{}` when neither actor exists, so a caller with no target still measures what the
## cast COST. Pools this actor does not carry are left out of the snapshot entirely,
## which is how an unmeasured delta stays `{}` instead of reading as a zero.
static func snapshot(attacker: Actor, target: Actor = null) -> Dictionary:
	if attacker == null and target == null:
		return {}
	var pools := {}
	if attacker != null:
		pools["actor"] = _pools_of(attacker)
	if target != null:
		pools["target"] = _pools_of(target)
	var state := {}
	if target != null:
		# The SAME two readers `_state_diff` uses for the "after" side, so a snapshot
		# and its diff can never disagree about what a sea or a ledger IS. Two readers
		# for one shape is the defect class this module is written against.
		var sea := _fields_now(target, SEA_COMPONENT, [&"turbulence", &"clarity"])
		if not sea.is_empty():
			state["sea"] = sea
		var wounds := _wounds_now(target)
		if not wounds.is_empty():
			state["wounds"] = wounds
	return {"pools": pools, "state": state}


## What `fired` — one `TechniqueCasting.activate` outcome — actually moved, diffed
## against the [method snapshot] taken before the cast.
##
## `attacker` and `target` are the SAME two actors the snapshot was taken from, and
## they are required for a delta: the "after" reading is taken here, because the
## snapshot is taken before the cast and cannot contain it. Passing one without the
## other, or pairing a snapshot with actors it was not taken from, yields `{}` for
## that side rather than a number derived from the wrong actor.
##
## Total by construction: a refusal, an empty dictionary, or a resolver double's
## `{amount: 12.0}` all degrade to the `none` shape, because this is read from a
## screen's cast handler and an exception there would abort the frame.
static func of(
	fired: Dictionary, before: Dictionary = {}, attacker: Actor = null, target: Actor = null
) -> Dictionary:
	var out := {
		"cast": String(fired.get("id", "")),
		"fired": bool(fired.get("fired", false)),
		"activity": NONE,
		"measured": false,
		"landed": false,
		"damage": 0.0,
		"health_lost": 0.0,
		"remaining_health": 0.0,
		"spent": false,
		"paid": _floats(fired.get("paid", {})),
		"actor_pools": {},
		"target_pools": {},
		"target_state": {},
		"status_applied": false,
		"status_refused": "",
		"effect_count": 0,
	}
	var effects := _effects_of(fired)
	out["effect_count"] = effects.size()
	out["status_applied"] = _status_applied(effects)
	out["status_refused"] = _status_refused(effects)
	var descriptor := _descriptor_of(fired)
	if not descriptor.is_empty():
		out["activity"] = RESOLVED
		_outcome_fields(out, descriptor)
	out["spent"] = not (out["paid"] as Dictionary).is_empty()
	# `before` is the whole [method snapshot] envelope, and its per-side pool tables are
	# NESTED under `pools` — `snapshot` publishes `{"pools": {"actor": …, "target": …}}`.
	# Reading them at the top level instead is the one thing that made this readback lie
	# to every caller: the documented three-line sequence returned `{}` for BOTH deltas
	# for every call shape, because `before["actor"]` never exists. A missing table is
	# deliberately indistinguishable from an unmeasured one, so it read as "nothing was
	# measured" rather than as a failure — the whole pool half of the answer was dead in
	# production and `measured` beside it stayed true.
	var recorded: Dictionary = before.get("pools", {}) as Dictionary
	var rows := _pools_of(attacker)
	out["actor_pools"] = _diff(rows, recorded.get("actor", {}) as Dictionary)
	out["target_pools"] = _diff(_pools_of(target), recorded.get("target", {}) as Dictionary)
	out["measured"] = not recorded.is_empty()
	out["remaining_health"] = _health_of(target)
	out["target_state"] = _state_diff(target, before.get("state", {}) as Dictionary)
	return out


## The spine's own fields under this module's key names.
##
## `landed` is the descriptor's OWN `landed`, never `not missed`: a parry and a block
## are landed hits a defence answered, and ADR 0067's refusal is a RESPONSE to a blow
## rather than an exemption from one. `damage` is the post-S7 amount, which is what a
## readout shows, and `health_lost` is what health actually went down by — the two
## differ whenever a shield absorbed, a pool clamped at zero, or a parry refunded.
static func _outcome_fields(out: Dictionary, descriptor: Dictionary) -> void:
	out["landed"] = bool(descriptor.get("landed", false))
	out["damage"] = float(descriptor.get("amount", 0.0))
	# The spine's one sign flip, negated ONCE. `health_delta` is negative on a
	# defender and `health_lost` is the positive number it spent, so a caller can add
	# it to a total without ever writing a second negation that could disagree.
	out["health_lost"] = maxf(0.0, -float(descriptor.get("health_delta", 0.0)))


## `{pool: {before, after, delta}}` for `live`, against `recorded`.
##
## `delta` is `after - before`: positive for a pool the cast REFILLED, which is leech
## (ADR 0067's S11). `paid` is published beside this rather than merged into it,
## because `paid` is what was CHARGE and `delta` is what the pool did, and the two
## disagree exactly when the spine healed the attacker inside the same call.
##
## A pool the snapshot did not record, or the actor does not carry, is left out — so
## `{}` reads as "not measured" and never as "nothing moved".
static func _diff(live: Dictionary, recorded: Dictionary) -> Dictionary:
	var out := {}
	for pool_id in recorded.keys():
		if not live.has(pool_id):
			continue
		var before := float(recorded[pool_id])
		var after := float(live[pool_id])
		out[String(pool_id)] = {"before": before, "after": after, "delta": after - before}
	return out


## What the cast moved on the target that is not a pool: a sea's turbulence and
## clarity, and each meridian's accrued wound severity.
##
## ## Why the wounds are a per-meridian MAP and not a number
##
## `BodyWounds.severity` is a `{meridian_id: float}` dictionary by construction — a
## body blow lands at a CHANNEL (ADR 0070) and one cast can wound several — so a
## single "severity" number would have to flatten it and lose the location that is the
## whole of the body path. The sea IS two scalars and reads as two rows.
##
## Each row is `{before, after, delta}` beside the meridian id, and a target with no
## sea and no ledger reports `{}` rather than zeros.
static func _state_diff(target: Actor, recorded: Dictionary) -> Dictionary:
	if target == null:
		return {}
	var out := {}
	var sea := _sea_now(target)
	if recorded.has("sea") and not sea.is_empty():
		out["sea"] = _scalar_rows(recorded["sea"] as Dictionary, sea)
	var wounds := _wounds_now(target)
	if recorded.has("wounds") and not wounds.is_empty():
		out["wounds"] = _severity_rows(recorded["wounds"] as Dictionary, wounds)
	return out


## `{field: {before, after, delta}}` for two flat maps of scalars.
static func _scalar_rows(recorded: Dictionary, live: Dictionary) -> Dictionary:
	var out := {}
	for field in recorded.keys():
		if not live.has(field):
			continue
		var before := float(recorded[field])
		out[String(field)] = {
			"before": before, "after": float(live[field]), "delta": float(live[field]) - before
		}
	return out


## `{meridian_id: {before, after, delta}}`. A meridian present in one map and not the
## other is skipped rather than reported as a zero change, for the same reason a
## missing pool is: "not there" and "unchanged" are different claims.
static func _severity_rows(recorded: Dictionary, live: Dictionary) -> Dictionary:
	var out := {}
	for meridian in recorded.keys():
		if not live.has(meridian):
			continue
		var before := float(recorded[meridian])
		var after := float(live[meridian])
		out[String(meridian)] = {"before": before, "after": after, "delta": after - before}
	return out


## Every pool this actor carries among [constant POOLS], as `{pool_id: current}`.
## Total: an actor that carries neither reads `{}`, and one that carries qi alone reads
## one row rather than a qi row and a stamina row of zeros.
static func _pools_of(actor: Actor) -> Dictionary:
	var out := {}
	if actor == null:
		return out
	for raw_id in POOLS:
		var pool: Variant = actor.resource(StringName(raw_id))
		if pool != null:
			out[String(raw_id)] = float(pool.current)
	return out


## The target's health, or 0.0. The one number a caller cannot derive from a delta:
## it is the only question a landed cast is asked that no difference answers, and it
## is what tells a fight layer the target died on this cast.
static func _health_of(target: Actor) -> float:
	var pool: Variant = null if target == null else target.resource(&"health")
	return 0.0 if pool == null else float(pool.current)


## The sea's two scalars, duck-typed so this file names no `mind_cultivation` type
## and declares no edge `registry.json` does not record.
static func _sea_now(target: Actor) -> Dictionary:
	return _fields_now(target, SEA_COMPONENT, [&"turbulence", &"clarity"])


## The wound ledger's per-meridian severity, duck-typed for the same reason. Read off
## the `severity` MAP rather than off `severity_of`, which takes a meridian: the map is
## the whole ledger in one read, and a call per meridian would be a second traversal.
static func _wounds_now(target: Actor) -> Dictionary:
	if target == null:
		return {}
	var ledger: Variant = target.component(WOUNDS_COMPONENT)
	if ledger == null:
		return {}
	var read: Variant = ledger.get(&"severity")
	return read as Dictionary if read is Dictionary else {}


## The named numeric fields of one component, or `{}` when it is absent or is not the
## shape. Guarded rather than typed because three modules write components under these
## ids and a partial one is ordinary — a sea with no clarity, a ledger that is not yet
## a ledger. A field that is not a number is left out rather than written as a zero,
## which would read as a measurement that was never taken.
static func _fields_now(actor: Actor, component_id: StringName, fields: Array) -> Dictionary:
	var out := {}
	if actor == null:
		return out
	var component: Variant = actor.component(component_id)
	if component == null:
		return out
	for raw in fields:
		var read: Variant = component.get(StringName(raw))
		if read is float or read is int:
			out[String(raw)] = float(read)
	return out


## The activation's `damage` descriptor, or `{}`. A resolver that answered with
## anything else — a bare float, an object — is not a descriptor and is treated as
## none, which is the same rule `TechniqueCasting._resolve` applies before handing it
## back. `null` is accepted because a caller may hold an untyped `Variant`.
static func _descriptor_of(fired: Dictionary) -> Dictionary:
	var damage: Variant = fired.get("damage", {})
	return damage as Dictionary if damage is Dictionary else {}


## The descriptor's `effects[]`, or `[]`. `CombatOutcome.to_dict` publishes it always,
## but a resolver double's `{amount: 12.0}` does not — so this is read with a default
## and normalised to an Array rather than assumed.
static func _effects_of(fired: Dictionary) -> Array:
	var descriptor := _descriptor_of(fired)
	var effects: Variant = descriptor.get("effects", [])
	return effects as Array if effects is Array else []


## Whether S12 wrote a status. A body wound and a mind erosion both look like an
## `effects[]` entry and both lack this key, which is exactly what makes the key the
## discriminator rather than the presence of the row.
static func _status_applied(effects: Array) -> bool:
	for entry in effects:
		if entry is Dictionary and bool((entry as Dictionary).get(EFFECT_APPLIED, false)):
			return true
	return false


## S12's own refusal reason — `no_request`, `no_rng`, `resisted`, `already_held` — so a
## caller learns WHICH gate closed rather than only that one did. `""` when none of the
## entries is a status verdict at all, which is a different state from a refusal.
static func _status_refused(effects: Array) -> String:
	for entry in effects:
		if entry is Dictionary and (entry as Dictionary).has(EFFECT_REFUSED):
			return String((entry as Dictionary).get(EFFECT_REFUSED, ""))
	return ""


## A charge table flattened to `{String: float}`. `TechniqueCasting` keys it by
## `StringName`, and a `StringName` key survives a save envelope as its printed form
## rather than as itself — so a caller that serialized the answer would report a charge
## against nothing. Both spellings are read for that reason.
static func _floats(paid) -> Dictionary:
	var out := {}
	if not paid is Dictionary:
		return out
	var table: Dictionary = paid
	for pool_id in table.keys():
		out[String(pool_id)] = float(table[pool_id])
	return out
