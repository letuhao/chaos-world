extends TestCase

## DEF-0097: an ACTIVE technique fires, pays its cost, starts its cooldown — and what
## does it actually MOVE? `TechniqueCastView` is the readback that answers, and this
## file is the evidence that it answers truthfully.
##
## ## What is being claimed, stated narrowly
##
## A landed cast is NOT unobservable today, and this suite does not pretend otherwise.
## `TechniqueCasting.activate` returns the composition root's real `CombatOutcome` as
## `damage`, and `health_delta` in it is the health a target actually lost. ADR 0123
## and ADR 0133 have the spine built and wired; `game/tests/app/
## test_combat_reachability.gd` fires all three mechanisms through the PRODUCTION seam
## and asserts real damage. So "an active technique cannot damage anything" (DEF-0080's
## phrasing) is FALSE as stated.
##
## What was true, and what this closes, is narrower: **`CombatOutcome` publishes
## fourteen fields and every one of them belongs to the SPINE.** A turn that paid qi,
## spent a cooldown, eroded a sea and wounded a meridian is four facts in four
## systems, and the descriptor carries one as a number and two only inside `effects[]`
## rows a caller must already know how to read.
##
## Mind is the case that makes it sharp rather than academic. ADR 0071 with ADR 0162
## means a mind technique's `amount` is `0.0` BY DESIGN — it erodes a sea and pays only
## the shared chip floor. A caller reading the damage fields alone concludes a mind
## technique did nothing, which is DEF-0097's question asked about the one path where
## the answer is deliberately not in those fields.
##
## ## What this file is and is not evidence for
##
## Every case below drives `TechniqueCasting.activate` with an injected resolver, so it
## proves the READBACK is faithful — it never asserts that a hit landed, which is
## `combat_engine`'s and `app/`'s claim to make and `test_combat_reachability.gd`'s to
## prove. What is proven here is the weaker and still load-bearing half: that whatever
## moved, the technique side reports it, and reports nothing that did not move.
##
## The seam stays INJECTED and no case names `CombatEngineApi`: `techniques` declares
## deps `contracts`, `core`, `items` (`tools/arch/registry.json`), so a test that reached
## into `combat_engine` would be asserting through an edge production code is forbidden
## to have. The `_Ledger` doubles below stand in for the sea and the wound ledger under
## their real component ids, because the readback reads components rather than paths.

const MORTAL := &"qi_refining"

## The two component ids the readback reads. Duplicated as literals rather than named
## from `TechniqueCastView` on purpose: the constants are THIS module's own, and a test
## that reads them from the code under test cannot catch the code renaming one.
const SEA := "sea_of_consciousness"
const WOUNDS := "body_wounds"

## `TechniqueCatalog` is process-wide, so a serial keeps every fixture id unique and no
## two defs in this file can be the same row.
static var _serial: int = 0

# --- Doubles: the two components a cast can move -------------------------------


## Stands in for a `SeaOfConsciousness`: two float fields a mind cast moves. Not a real
## sea, because `mind_cultivation` is a module this one may not depend on — the readback
## is DUCK-TYPED precisely so it needs no such type, and a double is how that claim is
## proven rather than assumed.
class _Ledger:
	extends RefCounted

	var turbulence: float = 0.0
	var clarity: float = 0.5


## Stands in for a `BodyWounds`: `severity` is a `{meridian_id: float}` MAP by
## construction, because a body blow lands at a CHANNEL (ADR 0070). A scalar double
## would let a flattening bug through unnoticed, so this carries the real shape.
class _Wounds:
	extends RefCounted

	var severity: Dictionary = {}


## A resolver that moves the systems a real mechanism moves, so the readback has
## something to observe. Returns a `CombatOutcome.to_dict`-shaped descriptor: the point
## is that the readback consumes the SPINE's published shape, so feeding it a shape the
## spine does not publish would prove nothing.
##
## ## Why the mutations run INSIDE `resolve`, and not before the cast
##
## This is the fixture bug that made every delta read zero on the first run, and it is
## worth naming because the suite would otherwise have looked green for the wrong
## reason. `_fire` snapshots BEFORE `activate` calls the resolver, so a test that
## mutated a pool as setup would have the snapshot read the ALREADY-MUTATED value —
## `before == after`, `delta == 0.0`, and every assertion below would be testing a
## degenerate case that passes for free.
##
## `on_hit` is therefore called at the moment the seam runs, which is exactly when a
## real mechanism's `effects[]` are settled by `CombatEffectApply`.
class _Resolver:
	extends RefCounted

	var descriptor: Dictionary = {}
	var on_hit: Callable = Callable()
	var calls: int = 0

	func resolve(_attacker: Actor, _target: Actor, _def: TechniqueDef) -> Dictionary:
		calls += 1
		if on_hit.is_valid():
			on_hit.call()
		return descriptor


## A resolver whose seam moves `pool` on `target` by `delta`, the shape a qi drain
## takes. Returns the pair so the caller can attach it with one line.
func _moving(descriptor: Dictionary, pool_id: StringName, delta: float, target: Actor) -> _Resolver:
	var resolver := _Resolver.new()
	resolver.descriptor = descriptor
	resolver.on_hit = func() -> void:
		var pool: Variant = target.resource(pool_id)
		if pool != null:
			pool.change(delta)
	return resolver


func _actor(qi: float = 500.0, stamina: float = 100.0, health: float = 0.0) -> Actor:
	var actor := Actor.new(&"caster", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", qi))
	actor.add_resource(ResourcePool.new(&"stamina", stamina))
	if health > 0.0:
		actor.add_resource(ResourcePool.new(&"health", health))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	TechniquesApi.attach(actor)
	return actor


func _target(health: float = 100.0) -> Actor:
	var actor := Actor.new(&"ward", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", health))
	return actor


func _active(actor: Actor, qi_cost: float = 0.0, stamina_cost: float = 0.0) -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("cast_view_%d" % _serial)
	def.display_name = "Strike"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = PathState.QI
	def.qi_cost = qi_cost
	def.stamina_cost = stamina_cost
	def.magnitude = 100.0
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


func _casting(actor: Actor) -> TechniqueCasting:
	return actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting


## The spine's published descriptor shape, for a landed hit that spent `lost` health.
## Only the keys the readback reads are set, which is the point: an absent key must read
## its zero rather than crash, and `test_an_unreadable_descriptor_degrades` proves it.
func _descriptor(amount: float, lost: float, effects: Array = []) -> Dictionary:
	return {
		"amount": amount,
		"health_delta": -lost,
		"landed": true,
		"effects": effects,
	}


## Fire `def` at `target` through `resolver`, measuring before and after — the exact
## three-call sequence a caller performs, so the suite exercises the real usage rather
## than a shape only the test knows.
##
## ## Why the seam is INSTALLED here rather than passed per call
##
## `TechniqueCasting.activate` falls back to the PROCESS-WIDE
## `TechniqueCasting._installed_resolver` when a caller passes none, and a process-wide
## binding outlives the test that set it: `run_tests.gd` calls `teardown` after every
## test precisely because it leaks between suites, and it is `app/` — not this file —
## that installs the spine binding. Installing our own double here, inside the same
## helper every case goes through, is what makes a per-call argument the ONLY seam in
## play. It is re-installed immediately before `activate`, never left behind, and it
## makes the outcome of this suite independent of whatever composition root ran last.
func _fire(caster: Actor, target: Actor, def: TechniqueDef, resolver: Callable) -> Dictionary:
	var before := TechniqueCastView.snapshot(caster, target)
	TechniqueCasting.set_resolver(resolver)
	var fired := _casting(caster).activate(caster, def, target, resolver)
	return TechniqueCastView.of(fired, before, caster, target)


# --- A landed cast's damage IS already observable; this does not restate it ------


func test_a_landed_casts_health_loss_is_reported_as_a_positive_number() -> void:
	var caster := _actor(500.0, 100.0)
	var ward := _target(100.0)
	var turn := _fire(
		caster,
		ward,
		_active(caster),
		_moving(_descriptor(40.0, 40.0), &"health", -40.0, ward).resolve
	)
	assert_eq(String(turn["activity"]), "resolved", "the descriptor came back")
	assert_eq(bool(turn["landed"]), true, "so the strike landed")
	assert_almost_eq(float(turn["damage"]), 40.0, "the amount is the spine's own")
	# The sign is the readback's one contribution: `health_delta` is negative on a
	# defender (ADR 0067's convention) and this is the positive number it spent, so a
	# caller never writes a second negation that could disagree with the spine's.
	assert_almost_eq(float(turn["health_lost"]), 40.0, "spent health, positive")
	assert_almost_eq(float(turn["remaining_health"]), 60.0, "and what is left of the target")


func test_the_readback_never_recomputes_health_loss_from_the_amount() -> void:
	# A shield absorbed part of it, or the pool clamped at zero: `amount` and
	# `health_delta` legitimately disagree, and a readback that derived one from the
	# other would report damage the target never took.
	var caster := _actor()
	var ward := _target(4.0)
	var turn := _fire(
		caster,
		ward,
		_active(caster),
		_moving(_descriptor(90.0, 4.0), &"health", -4.0, ward).resolve
	)
	assert_almost_eq(float(turn["damage"]), 90.0, "the amount is the full blow")
	assert_almost_eq(
		float(turn["health_lost"]),
		4.0,
		"but only 4 reached health, so the readback reports what the spine recorded"
	)
	assert_almost_eq(float(turn["remaining_health"]), 0.0, "and the target died on it")


# --- What a cast TOOK from the target, which the descriptor cannot say -----------


func test_a_qi_cast_reports_the_qi_it_drained_from_the_defender() -> void:
	var caster := _actor()
	var ward := _target()
	ward.add_resource(ResourcePool.new(&"qi", 80.0))
	# The seam drains the pool, exactly as a mechanism's `effects[]` would have
	# `CombatEffectApply` do it — and inside the seam, so the snapshot was taken
	# BEFORE the drain. See `_Resolver`'s docblock for why that ordering is the
	# whole difference between a real assertion and one that passes for free.
	var resolver := _moving(_descriptor(20.0, 0.0), &"qi", -30.0, ward)
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_eq(resolver.calls, 1, "the seam ran once")
	var row := (turn["target_pools"] as Dictionary).get("qi", {}) as Dictionary
	assert_almost_eq(float(row.get("before", 0.0)), 80.0, "the qi it held before the cast")
	assert_almost_eq(float(row.get("after", 0.0)), 50.0, "and after")
	assert_almost_eq(float(row.get("delta", 0.0)), -30.0, "so the drain is a negative delta, named")


func test_the_actor_s_own_cost_is_reported_separately_from_the_damage_it_took() -> void:
	# Two record spaces, not one: "what a blow did" and "what a technique spent" have
	# opposite signs. A caller that merged them would subtract the caster's own qi cost
	# from the target, which is why the key names are not interchangeable.
	var caster := _actor(500.0, 100.0)
	var ward := _target()
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(20.0, 20.0)
	var turn := _fire(caster, ward, _active(caster, 30.0, 25.0), resolver.resolve)
	assert_almost_eq(float((turn["paid"] as Dictionary).get("qi", 0.0)), 30.0, "charged qi")
	assert_almost_eq(
		float((turn["paid"] as Dictionary).get("stamina", 0.0)), 25.0, "charged stamina"
	)
	assert_eq(bool(turn["spent"]), true, "so the cast is reported as having spent")
	var qi_row := (turn["actor_pools"] as Dictionary).get("qi", {}) as Dictionary
	assert_almost_eq(float(qi_row.get("before", 0.0)), 500.0, "the caster held this much qi")
	assert_almost_eq(float(qi_row.get("after", 0.0)), 470.0, "and this much after paying")
	assert_almost_eq(float(qi_row.get("delta", 0.0)), -30.0, "so the cost is measurable too")
	assert_eq(
		(turn["target_pools"] as Dictionary).keys().has("qi"),
		false,
		"while the target's own qi never moved, and says so by omission"
	)


func test_a_pool_the_actor_does_not_carry_is_absent_rather_than_reported_as_zero() -> void:
	# An absent pool and an unchanged one are different claims: a caller dividing by a
	# delta would see 0/0 and could not tell which it had.
	var caster := _actor()
	var ward := _target()
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(20.0, 20.0)
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_eq(
		(turn["target_pools"] as Dictionary).keys().has("qi"),
		false,
		"a defender with no qi pool contributes no row"
	)
	assert_eq(bool(turn["measured"]), true, "but the pools that DO exist were measured")


# --- The mind case, which is the one DEF-0097 is really about ------------------


func test_a_mind_cast_reports_the_sea_it_eroded_though_its_amount_is_zero() -> void:
	# ADR 0071 with ADR 0162: mind never subtracts a share of its own erosion, so
	# `amount` is 0.0 BY DESIGN and the only health it pays is the shared chip floor.
	# A caller reading the damage fields alone concludes this technique did nothing —
	# which is DEF-0097's question, asked about the one path where the answer is
	# deliberately not in those fields.
	var caster := _actor()
	var ward := _target()
	var sea := _Ledger.new()
	ward.set_component(SEA, sea)
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(0.0, 1.0)
	# `CombatEffectApply` runs LAST in the spine and settles the erosion there, so the
	# sea's own readings move by the hit and by nothing else — inside the seam, after
	# the snapshot, which is the only ordering that makes `before` mean anything.
	resolver.on_hit = func() -> void:
		sea.turbulence += 0.4
		sea.clarity -= 0.2
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_almost_eq(float(turn["damage"]), 0.0, "ADR 0071's own invariant: no share")
	assert_almost_eq(float(turn["health_lost"]), 1.0, "and the chip floor is paid")
	var rows := (turn["target_state"] as Dictionary).get("sea", {}) as Dictionary
	var turbulence := rows.get("turbulence", {}) as Dictionary
	assert_almost_eq(float(turbulence.get("before", 0.0)), 0.0, "the sea was calm before")
	assert_almost_eq(float(turbulence.get("after", 0.0)), 0.4, "and went turbulent")
	assert_almost_eq(float(turbulence.get("delta", 0.0)), 0.4, "which the readback reports")
	var clarity := rows.get("clarity", {}) as Dictionary
	assert_almost_eq(
		float(clarity.get("delta", 0.0)), -0.2, "and the clarity the erosion cost, negative"
	)
	assert_eq(
		bool(turn["target_state"].get("sea", {}) is Dictionary),
		true,
		"so the turn is accounted for even though its damage reads zero"
	)


func test_a_body_cast_reports_each_meridian_it_wounded() -> void:
	# ADR 0070: a body blow lands at a CHANNEL, and `BodyWounds.severity` is a
	# `{meridian_id: float}` map. A readback that flattened it to one number would lose
	# the location, which is the whole of the body path.
	var caster := _actor()
	var ward := _target()
	var wounds := _Wounds.new()
	wounds.severity = {"lung": 0.25}
	ward.set_component(WOUNDS, wounds)
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(
		30.0, 30.0, [{"kind": "body.wound", "meridian_id": "lung", "severity": 0.1}]
	)
	resolver.on_hit = func() -> void:
		# REPLACE the map, never mutate it in place — and the reason is the real
		# `BodyWounds`, not a stylistic one. `BodyWounds.severity` is a `var
		# severity: Dictionary` and `add` writes `severity[key] = ...`
		# (`combat_engine/body_wounds.gd:126`), so a long-lived ledger's map is mutated
		# IN PLACE. `TechniqueCastView._wounds_now` returns that live map by reference,
		# and so does `snapshot`. An in-place `severity["lung"] = 0.35` would therefore
		# rewrite the SNAPSHOT too — `before == after`, `delta == 0.0`, and the test would
		# pass for a readback that reports nothing. Assigning a new dictionary is exactly
		# what a component REPLACEMENT (a status effect remounting the ledger) does, and
		# it is the only shape under which `before` can mean anything.
		wounds.severity = {"lung": 0.35, "heart": 0.1}
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	var rows := (turn["target_state"] as Dictionary).get("wounds", {}) as Dictionary
	var lung := rows.get("lung", {}) as Dictionary
	assert_almost_eq(float(lung.get("before", 0.0)), 0.25, "the meridian's prior severity")
	assert_almost_eq(float(lung.get("after", 0.0)), 0.35, "and this after the blow")
	assert_almost_eq(float(lung.get("delta", 0.0)), 0.1, "so the wound accrued 0.1 there")
	assert_eq(
		rows.keys().has("heart"),
		false,
		"a meridian the snapshot never recorded is omitted, not reported as unchanged"
	)


func test_a_target_with_no_state_components_reports_none_rather_than_zeroes() -> void:
	var caster := _actor()
	var ward := _target()
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(15.0, 15.0)
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_eq(
		(turn["target_state"] as Dictionary).is_empty(),
		true,
		"no sea and no ledger is an empty map, which is not the same as a zero sea"
	)


# --- S12's verdict, and what must NOT read as one -------------------------------


func test_a_wound_is_not_mistaken_for_a_status_and_a_status_is_reported() -> void:
	# ADR 0087 put S12's result INSIDE `effects[]`, so a body wound, a mind erosion and
	# a status are all rows in one array. Only the S12 keys discriminate them, which is
	# why this readback keys on those and not on the presence of a row.
	var caster := _actor()
	var ward := _target()
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(
		30.0, 30.0, [{"kind": "body.wound", "meridian_id": "lung", "severity": 0.1}]
	)
	var wound_only := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_eq(bool(wound_only["status_applied"]), false, "a wound is not a status")
	assert_eq(String(wound_only["status_refused"]), "", "and carries no refusal either")
	assert_eq(int(wound_only["effect_count"]), 1, "though the row is counted honestly")

	var caster2 := _actor()
	var ward2 := _target()
	var resolver2 := _Resolver.new()
	resolver2.descriptor = _descriptor(
		30.0, 30.0, [{"kind": "status.apply", "applied": true, "status_id": "burning"}]
	)
	var applied := _fire(caster2, ward2, _active(caster2), resolver2.resolve)
	assert_eq(bool(applied["status_applied"]), true, "a real S12 entry is reported")


func test_a_refused_status_reports_which_gate_refused_it() -> void:
	# S12's own reason strings travel, so a balance pass learns WHICH gate closed
	# rather than only that one did.
	var caster := _actor()
	var ward := _target()
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(30.0, 30.0, [{"refused": "resisted"}])
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_eq(String(turn["status_refused"]), "resisted", "named, not flattened to a bool")
	assert_eq(bool(turn["status_applied"]), false, "and it applied nothing")


# --- Refusals, absences and degenerate inputs -----------------------------------


func test_a_refused_activation_reports_no_activity_at_all() -> void:
	# The four states must stay distinguishable: a refusal, a fire with no target, a
	# strike that missed, and a strike that landed. Collapsing the first two is how a
	# missing resolver came to read as "the strike missed".
	var caster := _actor()
	var refused := _casting(caster).activate(caster, &"no_such_technique")
	var turn := TechniqueCastView.of(refused, TechniqueCastView.snapshot(caster), caster, null)
	assert_eq(bool(turn["fired"]), false, "nothing fired")
	assert_eq(String(turn["activity"]), "none", "so there is no activity to report")
	assert_eq(bool(turn["landed"]), false, "and nothing landed")
	assert_almost_eq(float(turn["health_lost"]), 0.0, "and no health was spent")


func test_a_cast_with_no_target_still_reports_what_it_cost() -> void:
	# `activate` pays and starts the cooldown whether or not a target was supplied —
	# that is the module's rule, and a readback that reported nothing here would make
	# an unaffordable-by-nothing cast look free.
	var caster := _actor(500.0, 100.0)
	var def := _active(caster, 30.0, 25.0)
	# Through `_fire`, so this case is measured by the SAME snapshot the cast happened
	# inside. Hand-rolling `snapshot`/`activate`/`of` here is what left the delta at
	# zero: the caller's own snapshot is only `target`'s, so `of`'s
	# `before.get("actor", {})` read `{}` and the actor's qi row was correctly reported
	# as "not measured" — an absent measurement, not a broken diff.
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(20.0, 20.0)
	var turn := _fire(caster, null, def, resolver.resolve)
	assert_eq(bool(turn["fired"]), true, "it fired")
	assert_eq(String(turn["activity"]), "none", "with no target there is no descriptor")
	assert_eq(bool(turn["spent"]), true, "and it still spent what it owed")
	assert_almost_eq(
		float(((turn["actor_pools"] as Dictionary).get("qi", {}) as Dictionary).get("delta", 0.0)),
		-30.0,
		"measured off the caster's own pool"
	)


func test_a_miss_degrades_to_the_no_activity_shape_and_says_so() -> void:
	# `CombatOutcome.to_dict` is `{}` for a miss, by its OWN contract
	# (`combat_engine/outcome.gd:108-110`: `if missed: return {}`) — "a miss has
	# nothing to say and a panel that renders `0` for a swing that never landed teaches
	# the reader that a whiff and a gut-punch are the same event". So the readback
	# CANNOT tell "resolved, nothing landed" from "no resolver was installed": both are
	# a `{}` descriptor, and `_descriptor_of` maps both to `none`.
	#
	# Asserting otherwise would be asserting a spine that does not exist. So this pins
	# what the technique side genuinely owes its caller here: it distinguishes the
	# refusal-shaped no-activity (`fired == false`) from the cast-shaped one
	# (`fired == true`), so "the strike missed" and "no resolver was installed" stay two
	# different messages rather than one empty descriptor, and it reports NO amount and
	# NO health loss rather than inventing a zero-damage hit.
	var caster := _actor()
	var ward := _target()
	var resolver := _Resolver.new()
	resolver.descriptor = {}
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_eq(resolver.calls, 1, "the seam ran")
	assert_eq(bool(turn["fired"]), true, "and the cast really happened")
	assert_eq(String(turn["activity"]), "none", "so a `{}` descriptor is the no-activity shape")
	assert_eq(bool(turn["landed"]), false, "and nothing landed")
	assert_almost_eq(float(turn["damage"]), 0.0, "with no amount claimed")
	assert_almost_eq(float(turn["health_lost"]), 0.0, "and no health claimed either")

	# The pairing that makes the degradation readable: a REFUSAL is the other `none`,
	# and it is separable exactly because `fired` is false there and true here.
	var refused := TechniqueCastView.of(
		_casting(caster).activate(caster, &"no_such_technique"),
		TechniqueCastView.snapshot(caster),
		caster,
		null
	)
	assert_eq(String(refused["activity"]), "none", "a refusal is the same shape")
	assert_eq(bool(refused["fired"]), false, "and is told apart by `fired` alone")


func test_an_installed_resolver_with_no_target_reads_as_no_activity_not_a_miss() -> void:
	# The other producer of an empty descriptor, and the one the seam control above
	# exists to pin: the cast DID pay, so `fired` is true and `spent` holds a real
	# charge, while `_resolve`'s own `target == null` guard returns `{}` without the
	# seam ever running. Same `none`, opposite reason — and with a resolver INSTALLED
	# that guard is the only thing that can produce it, which is what makes this the
	# guard's test rather than a restatement of the one above.
	var caster := _actor(500.0, 100.0)
	var resolver := _Resolver.new()
	resolver.descriptor = _descriptor(20.0, 20.0)
	# Installed as well as passed, so the `null` here and the `Callable()` in the case
	# above are the ONLY reasons the seam stayed silent.
	TechniqueCasting.set_resolver(resolver.resolve)
	var before := TechniqueCastView.snapshot(caster)
	var fired := _casting(caster).activate(caster, _active(caster, 30.0), null, Callable())
	var turn := TechniqueCastView.of(fired, before, caster, null)
	assert_eq(resolver.calls, 0, "the seam never ran, because there was no target")
	assert_eq(bool(turn["fired"]), true, "and the cast was paid for regardless")
	assert_eq(String(turn["activity"]), "none", "so nothing is claimed to have resolved")
	assert_almost_eq(
		float((turn["paid"] as Dictionary).get("qi", 0.0)), 30.0, "while the charge still stands"
	)


func test_an_unmeasured_turn_publishes_no_deltas_rather_than_zeroes() -> void:
	# `measured` is the load-bearing refusal: a caller that needs the deltas can see
	# they were not taken. A fabricated `before` would be worse than an absent one,
	# because it would be indistinguishable from a measured one.
	var caster := _actor(500.0)
	var ward := _target()
	var resolver := _moving(_descriptor(20.0, 20.0), &"health", -20.0, ward)
	var fired := _casting(caster).activate(caster, _active(caster, 10.0), ward, resolver.resolve)
	# NO snapshot was taken — this is the caller who never measured. The target moved,
	# and the readback must say so rather than reporting a zero it did not observe.
	var turn := TechniqueCastView.of(fired, {}, caster, ward)
	assert_eq(resolver.calls, 1, "the seam ran, so something did move")
	assert_eq(bool(turn["measured"]), false, "but nothing was measured")
	assert_eq((turn["target_pools"] as Dictionary).is_empty(), true, "so no target delta")
	assert_eq((turn["actor_pools"] as Dictionary).is_empty(), true, "and no actor delta")
	# The ABSOLUTE values are still correct without a snapshot, which is what makes a
	# caller able to work at all without one.
	assert_almost_eq(float(turn["health_lost"]), 20.0, "the damage is still reported")
	assert_almost_eq(float(turn["remaining_health"]), 80.0, "and so is what is left")
	assert_almost_eq(float((turn["paid"] as Dictionary).get("qi", 0.0)), 10.0, "and the charge")


func test_an_unreadable_descriptor_degrades_rather_than_raising() -> void:
	# Every read is `get` with a default because the descriptor belongs to
	# `combat_engine` and this module may not have a compile-time edge to it. A field
	# that does not exist yet must read its zero rather than crash a cast that has
	# already been PAID — the qi is gone by the time the readback runs.
	var bare := TechniqueCastView.of({"id": "x", "fired": true, "damage": {"amount": 9.0}})
	assert_eq(String(bare["activity"]), "resolved", "a partial descriptor still resolves")
	assert_almost_eq(float(bare["damage"]), 9.0, "the one key it had was read")
	assert_almost_eq(float(bare["health_lost"]), 0.0, "and the absent one read its zero")
	assert_eq(bool(bare["landed"]), false, "rather than raising on the missing key")


func test_an_empty_outcome_is_total_for_every_legal_call_shape() -> void:
	for fired in [
		{},
		{"damage": 12.0},
		{"damage": null},
		{"paid": null},
		{"effects": "not an array"},
	]:
		var turn := TechniqueCastView.of(fired as Dictionary)
		assert_eq(String(turn["activity"]), "none", "degrades for %s" % str(fired))
		assert_almost_eq(float(turn["damage"]), 0.0, "and reports zero damage")
	assert_eq(TechniqueCastView.snapshot(null, null), {}, "a snapshot of nothing is {}")


# --- The facade is still twelve, and this reached no new verb -------------------


func test_the_facade_is_still_twelve_public_methods() -> void:
	# The readback cost no verb. The constant below is what names it, exactly as
	# `CASTING_COMPONENT` names the casting table and `DELIVERY` names the seam.
	var published: Array[String] = []
	for method in TechniquesApi.new().get_script().get_script_method_list():
		var method_name := String(method.get("name", ""))
		if not method_name.begins_with("_") and not published.has(method_name):
			published.append(method_name)
	assert_eq(published.size(), 12, "exactly twelve public methods, found %d" % published.size())
	for verb in ["cast", "cast_view", "damage", "resolve", "outcome"]:
		assert_eq(published.has(verb), false, "and no '%s' verb" % verb)
	assert_eq(String(TechniquesApi.CAST_VIEW), "technique_cast_view", "the id is spelled once")


func test_the_readback_writes_no_pool_of_its_own() -> void:
	# The spine already charged the target's health inside `activate`. A readback that
	# wrote a pool would be a second charge for one cast, so this asserts that firing
	# the whole three-call sequence moves health exactly once and no more — the seam
	# moves it, and `of` only reads.
	var caster := _actor()
	var ward := _target(100.0)
	var resolver := _moving(_descriptor(40.0, 40.0), &"health", -40.0, ward)
	var turn := _fire(caster, ward, _active(caster), resolver.resolve)
	assert_almost_eq(
		float(ward.resource(&"health").current), 60.0, "charged exactly once, by the seam"
	)
	assert_almost_eq(
		float(turn["remaining_health"]),
		60.0,
		"and the readback observed that rather than moving it again"
	)
