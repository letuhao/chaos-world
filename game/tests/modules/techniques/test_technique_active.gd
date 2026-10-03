extends TestCase

## Active execution and cooldowns (DEF-0125): what an activation pays, what it
## refuses, and what it must not touch.
##
## The damage pipeline is INJECTED — every case here passes its own `resolver`
## rather than naming `combat_engine`, because that seam belongs to the composition
## root and `modules/techniques` may not depend on `combat_engine` (its
## `registry.json` deps are `contracts`, `core`, `items`). A test that reached in
## would be asserting through an edge production code is forbidden to have.

const MORTAL := &"qi_refining"

## `cult_qi_control` is one of the 36 technique-legal pool options (ADR 0054), so it
## is a real contribution rather than a fixture that happens to parse.
const PASSIVE_OPTION := &"cult_qi_control"

## comprehension 100.0 derives `Stat.COOLDOWN_REDUCTION = 0.2` at the core formula
## `minf(0.4, comprehension * 0.002)`.
const REDUCED := {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0, Stat.COMPREHENSION: 100.0}
## No comprehension at all: the reduction reads 0.0, so these actors pay full price.
const PLAIN := {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0}

## `TechniqueCatalog` is process-wide, and a suite that registered the same id twice
## would have its second def silently replace the first. A serial makes every fixture
## id unique, so no two defs in this file can be the same row.
static var _serial: int = 0


## The shape the composition root binds the spine to: three actors in, one primitive
## descriptor out. A named class rather than a lambda because `Callable` is a
## built-in and cannot carry a meta slot for the calls it recorded.
class _Resolver:
	extends RefCounted

	var amount: float = 42.0
	var calls: Array = []

	func resolve(attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		calls.append([attacker.id, target.id, def.id])
		return {"amount": amount}


func _actor(base: Dictionary = PLAIN, qi: float = 500.0, stamina: float = 100.0) -> Actor:
	var actor := Actor.new(&"practitioner", base)
	actor.add_resource(ResourcePool.new(&"qi", qi))
	actor.add_resource(ResourcePool.new(&"stamina", stamina))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	TechniquesApi.attach(actor)
	return actor


func _casting(actor: Actor) -> TechniqueCasting:
	return actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting


## An active technique on the qi path, learned and equipped, so the only gate left
## is the one under test.
func _active(
	actor: Actor, qi_cost: float = 0.0, stamina_cost: float = 0.0, cooldown: float = 0.0
) -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("active_suite_%d" % _serial)
	def.display_name = "Strike"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = PathState.QI
	def.qi_cost = qi_cost
	def.stamina_cost = stamina_cost
	def.cooldown = cooldown
	def.magnitude = 100.0
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


## A passive carrying one real option, so "the passives did not move" is an assertion
## about an actual contribution rather than about an empty list.
func _passive(actor: Actor) -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("active_suite_passive_%d" % _serial)
	def.display_name = "Manual"
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	def.passive_options = [{"option_id": PASSIVE_OPTION, "value": 4.0}]
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


# --- Attaching and reaching the action -----------------------------------------


func test_attach_publishes_a_casting_component_the_facade_names() -> void:
	var actor := _actor()
	assert_ne(_casting(actor), null, "the casting table is attached")
	# Reachable exactly the way `TechniqueUpkeep` is: a component id published as a
	# constant, never a facade method.
	assert_eq(
		String(TechniquesApi.CASTING_COMPONENT), "technique_casting", "and the id is spelled once"
	)
	TechniquesApi.attach(actor)
	assert_ne(_casting(actor), null, "attach stays idempotent on the component it owns")


func test_the_facade_still_exposes_exactly_twelve_public_methods() -> void:
	# ADR 0056: the cap binds immediately, so the activation action had to go on the
	# component. Read the facade's own declared surface rather than restating a
	# number, so a future 13th method fails here rather than only at `tools arch`.
	var script: Script = TechniquesApi.new().get_script()
	var published: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method.get("name", ""))
		if method_name.begins_with("_") or published.has(method_name):
			continue
		published.append(method_name)
	# Presence pins the list, the ceiling pins the cap: both are needed, because an
	# empty method list would otherwise satisfy the ceiling alone.
	for name in [
		"attach",
		"codex",
		"slots",
		"learn",
		"equip",
		"unequip",
		"rebuild",
		"settle_upkeep",
		"raise_mastery",
		"summary",
		"inspect",
		"technique_state",
	]:
		assert_eq(published.has(name), true, "'%s' is still on the facade" % name)
	assert_eq(published.size(), 12, "exactly twelve public methods, found %d" % published.size())


# --- Firing and refusing -------------------------------------------------------


func test_a_free_active_technique_fires_and_resolves_through_the_injected_spine() -> void:
	var actor := _actor()
	var def := _active(actor)
	var target := Actor.new(&"target")
	# No target and no resolver still fires: the qi is spent and the cooldown starts
	# whether or not anything was hit, so a preview can afford-check without a fight.
	var fired := _casting(actor).activate(actor, def)
	assert_eq(bool(fired["ok"]), true, "a free technique fires")
	assert_eq(bool(fired["fired"]), true, "and says it fired")
	assert_eq(bool(fired["damage"].is_empty()), true, "with no target there is no descriptor")

	var resolver := _Resolver.new()
	var resolved := _casting(actor).activate(actor, def, target, resolver.resolve)
	assert_eq(bool(resolved["ok"]), true, "and it fires again when nothing blocks it")
	assert_eq(resolver.calls.size(), 1, "the injected resolver ran exactly once")
	assert_eq(resolver.calls[0][0], actor.id, "with the actor as the attacker")
	assert_eq(resolver.calls[0][1], target.id, "and the target as the target")
	assert_eq(resolver.calls[0][2], def.id, "and the technique itself")
	# The descriptor is handed back verbatim: this module computes no damage.
	assert_almost_eq(float(resolved["damage"]["amount"]), 42.0, "the spine's own number")


func test_a_cost_he_cannot_pay_is_refused_and_pays_nothing() -> void:
	var actor := _actor(PLAIN, 40.0, 100.0)
	var def := _active(actor, 50.0, 0.0, 0.0)
	var qi_before := actor.resource(&"qi").current
	var refused := _casting(actor).activate(actor, def)
	assert_eq(bool(refused["ok"]), false, "40 qi cannot pay 50")
	assert_eq(String(refused["reason"]), "insufficient_resources", "and names the cause")
	assert_eq(String(refused["id"]), String(def.id), "and which technique")
	assert_eq((refused["short"] as Array).size(), 1, "and which pool was short")
	assert_almost_eq(
		float((refused["short"][0] as Dictionary)["current"]), qi_before, "reporting what it held"
	)
	# NOTHING moved: no partial payment, no cooldown, no mastery.
	assert_almost_eq(actor.resource(&"qi").current, qi_before, "the qi pool is untouched")
	assert_eq(_casting(actor).is_ready(def.id), true, "and no cooldown was started")
	assert_eq(
		int(TechniquesApi.codex(actor).row(def.id).get("rung", 0)),
		0,
		"and a refusal teaches nothing"
	)


func test_a_cost_he_can_pay_is_deducted_from_the_real_pools() -> void:
	var actor := _actor(PLAIN, 500.0, 100.0)
	var def := _active(actor, 30.0, 25.0, 0.0)
	var fired := _casting(actor).activate(actor, def)
	assert_eq(bool(fired["ok"]), true, "both pools could pay")
	assert_almost_eq(actor.resource(&"qi").current, 470.0, "30 qi drained")
	assert_almost_eq(actor.resource(&"stamina").current, 75.0, "25 stamina drained")
	assert_almost_eq(
		float((fired["paid"] as Dictionary)[&"qi"]), 30.0, "and it reports the qi it paid"
	)
	assert_almost_eq(
		float((fired["paid"] as Dictionary)[&"stamina"]), 25.0, "and the stamina it paid"
	)


func test_the_payment_is_all_or_nothing_across_pools() -> void:
	# The hazard `EquipmentUpkeep._pay` is shaped around: qi affordable, stamina not.
	# Draining qi and then discovering the shortfall would leave the actor poorer with
	# no technique fired.
	var actor := _actor(PLAIN, 500.0, 10.0)
	var def := _active(actor, 30.0, 25.0, 0.0)
	var qi_before := actor.resource(&"qi").current
	var refused := _casting(actor).activate(actor, def)
	assert_eq(String(refused["reason"]), "insufficient_resources", "refused")
	assert_almost_eq(
		actor.resource(&"qi").current, qi_before, "the affordable pool was NOT touched"
	)
	assert_almost_eq(actor.resource(&"stamina").current, 10.0, "nor the short one")


func test_an_unaffordable_qi_pool_counts_as_short_rather_than_crashing() -> void:
	# No qi pool at all is a legitimate state for an actor who has never cultivated.
	var actor := Actor.new(&"uncultivated", PLAIN)
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	TechniquesApi.attach(actor)
	var def := _active(actor, 10.0, 0.0, 0.0)
	var refused := _casting(actor).activate(actor, def)
	assert_eq(String(refused["reason"]), "insufficient_resources", "a missing pool is a refusal")
	assert_almost_eq(
		float((refused["short"][0] as Dictionary)["current"]), 0.0, "and it held nothing"
	)


func test_a_passive_is_refused_as_not_active() -> void:
	var actor := _actor()
	var def := _passive(actor)
	assert_eq(def.is_passive(), true, "the fixture really is a passive (ADR 0054)")
	var refused := _casting(actor).activate(actor, def)
	assert_eq(bool(refused["ok"]), false, "a passive has no action")
	assert_eq(String(refused["reason"]), "not_active", "and says so")
	assert_eq(
		int(TechniquesApi.codex(actor).row(def.id).get("rung", 0)), 0, "with no mastery for asking"
	)


func test_a_technique_that_was_never_equipped_is_refused() -> void:
	var actor := _actor()
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("active_suite_loose_%d" % _serial)
	def.active = true
	def.path = PathState.QI
	TechniqueCatalog.instance().register(def)
	var refused := _casting(actor).activate(actor, def)
	assert_eq(String(refused["reason"]), "not_equipped", "ADR 0053: a slot is what makes it usable")
	assert_eq(TechniquesApi.codex(actor).count(), 0, "and using it never taught it")


func test_an_unknown_definition_is_refused_rather_than_firing_nothing() -> void:
	var actor := _actor()
	var refused := _casting(actor).activate(actor, &"no_such_technique")
	assert_eq(String(refused["reason"]), "unknown_definition", "no silent no-op")
	var null_actor := _casting(actor).activate(null, &"no_such_technique")
	assert_eq(bool(null_actor["ok"]), false, "and a null actor is refused too")


# --- Cooldowns ------------------------------------------------------------------


func test_a_cooldown_blocks_the_second_activation_and_reports_the_seconds_left() -> void:
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 10.0)
	var first := _casting(actor).activate(actor, def)
	assert_eq(bool(first["ok"]), true, "the first activation fires")
	assert_almost_eq(float(first["cooldown"]), 10.0, "and starts the authored cooldown")
	assert_almost_eq(_casting(actor).remaining(def.id), 10.0, "which the table now owes")

	var blocked := _casting(actor).activate(actor, def)
	assert_eq(bool(blocked["ok"]), false, "the second cannot fire")
	assert_eq(String(blocked["reason"]), "on_cooldown", "and says why")
	assert_almost_eq(float(blocked["cooldown_remaining"]), 10.0, "with the seconds still owed")
	# The duration it reports is the one it STARTED, not one re-derived from the rung
	# the firing just earned: a cooldown is the price paid at cast time, and reading
	# it back through a moving mastery rung would report a number that was never owed.
	assert_almost_eq(float(blocked["cooldown_duration"]), 10.0, "against the duration it started")


func test_the_cooldown_is_ticked_by_an_explicit_delta_and_never_by_a_clock() -> void:
	# `tick` takes seconds from its caller. A module that read `Time.get_ticks_*`
	# would be untestable between two assertions and would not survive a pause.
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 10.0)
	_casting(actor).activate(actor, def)
	_casting(actor).tick(actor, 4.0)
	assert_almost_eq(_casting(actor).remaining(def.id), 6.0, "four seconds of ten spent")
	_casting(actor).tick(actor, 4.0)
	assert_almost_eq(_casting(actor).remaining(def.id), 2.0, "and four more")
	assert_eq(_casting(actor).is_ready(def.id), false, "still cooling")

	var expired := _casting(actor).tick(actor, 2.0)
	assert_almost_eq(_casting(actor).remaining(def.id), 0.0, "the tenth second clears it")
	assert_eq(expired.has(def.id), true, "and the caller is told which ones came off")
	assert_eq(_casting(actor).is_ready(def.id), true, "so it is ready again")
	assert_eq(bool(_casting(actor).activate(actor, def)["ok"]), true, "and fires again")


func test_a_tick_of_zero_or_negative_time_is_ignored() -> void:
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 5.0)
	_casting(actor).activate(actor, def)
	_casting(actor).tick(actor, 0.0)
	_casting(actor).tick(actor, -3.0)
	assert_almost_eq(
		_casting(actor).remaining(def.id), 5.0, "time cannot run backwards through this table"
	)


func test_an_over_sized_tick_clears_the_table_rather_than_going_negative() -> void:
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 2.0)
	_casting(actor).activate(actor, def)
	_casting(actor).tick(actor, 100.0)
	assert_almost_eq(_casting(actor).remaining(def.id), 0.0, "clamped at zero")
	assert_eq(_casting(actor).is_ready(def.id), true, "and ready, never negative")


func test_cooldown_reduction_shortens_the_cooldown_and_is_clamped_at_zero_point_four() -> void:
	# `Stat.COOLDOWN_REDUCTION` is a RATE with a 0.0 baseline, so a FLAT modifier is
	# the only form that moves it (`contracts/stat.gd`) — and the clamp is the core
	# formula's own 0.4, re-applied here because PERCENT and MULT compose past it.
	var plain := _actor(PLAIN)
	var reduced := _actor(REDUCED)
	var def_plain := _active(plain, 0.0, 0.0, 10.0)
	var def_reduced := _active(reduced, 0.0, 0.0, 10.0)
	assert_almost_eq(
		_casting(plain).duration_for(plain, def_plain), 10.0, "no reduction, full price"
	)
	assert_almost_eq(TechniqueCasting.reduction_of(reduced), 0.2, "comprehension 100.0 gives 0.2")
	assert_almost_eq(
		_casting(reduced).duration_for(reduced, def_reduced), 8.0, "20% off a ten second cooldown"
	)
	# Over the cap: comprehension 1000.0 derives 2.0, and the clamp holds it at 0.4 —
	# an unclamped 2.0 would make the cooldown negative and the technique permanently
	# ready, which is not a defensive stat.
	var capped := _actor({Stat.COMPREHENSION: 1000.0})
	var def_capped := _active(capped, 0.0, 0.0, 10.0)
	assert_almost_eq(TechniqueCasting.reduction_of(capped), 0.4, "clamped at 0.4")
	assert_almost_eq(
		_casting(capped).duration_for(capped, def_capped),
		6.0,
		"never below 0.6 of the authored cost"
	)


func test_cooldown_reduction_reads_the_derived_stat_and_not_a_bare_attribute() -> void:
	# A technique that granted comprehension could fund its own cooldown cut, so this
	# is the DERIVED value on the actor — the same discipline the upkeep pays and the
	# realm gates follow.
	var actor := _actor(PLAIN)
	var def := _active(actor, 0.0, 0.0, 10.0)
	var before := _casting(actor).duration_for(actor, def)
	actor.stats.add_modifier(
		StatModifier.new(Stat.COMPREHENSION, Stat.Op.FLAT, 50.0, &"active_suite_comprehension")
	)
	actor.mark_stats_dirty()
	assert_almost_eq(TechniqueCasting.reduction_of(actor), 0.1, "50 points is 0.1")
	assert_almost_eq(_casting(actor).duration_for(actor, def), before * 0.9, "so it is 10% shorter")


func test_mastery_scales_the_cooldown_and_the_qi_cost_per_adr_0055() -> void:
	var actor := _actor()
	var def := _active(actor, 100.0, 0.0, 10.0)
	# rung 0 is the authored price.
	assert_almost_eq(_casting(actor).duration_for(actor, def), 10.0, "rung 0 cooldown")
	assert_almost_eq(_casting(actor).qi_cost_for(actor, def), 100.0, "rung 0 qi cost")
	TechniquesApi.codex(actor).learn(def.id, 4)
	TechniquesApi.raise_mastery(actor, def.id, 4)
	var rung_four := TechniqueScales.multipliers_at(4, def.mastery_rungs)
	assert_almost_eq(
		_casting(actor).duration_for(actor, def),
		10.0 * float(rung_four["cooldown"]),
		"rung 4 cooldown is ADR 0055's 0.849 of the authored seconds"
	)
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		100.0 * float(rung_four["qi_cost"]),
		"and its qi cost is 0.781"
	)
	# ADR 0055's own trap-rung guard, on the ACTUAL activation rather than the table:
	# at the 0.4 cap a rung-4 technique still clears 0.5 of its authored cooldown.
	var capped := _actor({Stat.COMPREHENSION: 1000.0})
	var capped_def := _active(capped, 0.0, 0.0, 10.0)
	TechniquesApi.codex(capped).learn(capped_def.id, 4)
	TechniquesApi.raise_mastery(capped, capped_def.id, 4)
	var worst := _casting(capped).duration_for(capped, capped_def)
	assert_almost_eq(worst, 10.0 * float(rung_four["cooldown"]) * 0.6, "rung 4 at the cap")
	assert_eq(worst > 5.0, true, "and no rung is ever a trap rung")


func test_a_technique_with_no_authored_cooldown_is_always_ready() -> void:
	# Zero is a legal authored value, not a missing field: it must not become a
	# permanently-locked technique nor a NaN in the ratio a bar renders.
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 0.0)
	var fired := _casting(actor).activate(actor, def)
	assert_eq(bool(fired["ok"]), true, "the first fires")
	assert_almost_eq(float(fired["cooldown"]), 0.0, "and starts nothing")
	for repeat in 3:
		assert_eq(
			bool(_casting(actor).activate(actor, def)["ok"]), true, "repeat %d also fires" % repeat
		)
	assert_almost_eq(_casting(actor).ratio(actor, def), 0.0, "and the ratio is 0.0, not NaN")


func test_the_cooldown_ratio_is_the_share_of_the_running_cooldown_still_owed() -> void:
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 8.0)
	assert_almost_eq(_casting(actor).ratio(actor, def), 0.0, "ready is 0.0")
	_casting(actor).activate(actor, def)
	assert_almost_eq(_casting(actor).ratio(actor, def), 1.0, "just used is 1.0")
	# Six seconds off EIGHT. Drawn against the cooldown that is actually running
	# rather than a re-derived one: the firing just earned rung 1, so `duration_for`
	# now answers 8 * 0.96 and dividing by that would report the wrong share.
	_casting(actor).tick(actor, 6.0)
	assert_almost_eq(_casting(actor).remaining(def.id), 2.0, "two seconds left")
	assert_almost_eq(_casting(actor).ratio(actor, def), 0.25, "two of eight seconds owed")
	assert_almost_eq(
		_casting(actor).running_total(def.id),
		8.0,
		"and the running cooldown is the one that was charged"
	)
	assert_almost_eq(
		_casting(actor).duration_for(actor, def),
		8.0 * 0.96,
		"while the NEXT cast costs the rung-1 price"
	)


# --- Mastery accrues through use, and only through use -------------------------


func test_mastery_increments_only_on_an_activation_that_actually_fired() -> void:
	var actor := _actor()
	var def := _active(actor, 20.0, 0.0, 0.0)

	var fired := _casting(actor).activate(actor, def)
	assert_eq(int(fired["rung"]), 1, "the first firing raises mastery to rung 1")
	assert_eq(
		int(TechniquesApi.codex(actor).row(def.id).get("rung", 0)), 1, "and the codex says so"
	)

	# A cooldown refusal, on a technique that has fired once.
	var cooling := _active(actor, 0.0, 0.0, 60.0)
	_casting(actor).activate(actor, cooling)
	assert_eq(
		int(TechniquesApi.codex(actor).row(cooling.id).get("rung", 0)), 1, "one firing, one rung"
	)
	assert_eq(
		String(_casting(actor).activate(actor, cooling)["reason"]),
		"on_cooldown",
		"the second cannot fire"
	)
	assert_eq(
		int(TechniquesApi.codex(actor).row(cooling.id).get("rung", 0)),
		1,
		"and a cooldown refusal leaves the rung where it was"
	)

	# A cost refusal on a technique that never fired at all.
	var broke := _actor(PLAIN, 5.0, 100.0)
	var dear := _active(broke, 500.0, 0.0, 0.0)
	assert_eq(
		String(_casting(broke).activate(broke, dear)["reason"]),
		"insufficient_resources",
		"and the refusal is about the cost"
	)
	assert_eq(
		int(TechniquesApi.codex(broke).row(dear.id).get("rung", 0)), 0, "a refusal teaches nothing"
	)


func test_mastery_never_climbs_past_the_authored_rung_count() -> void:
	var actor := _actor()
	var def := _active(actor)
	def.mastery_rungs = 2
	for use_index in 6:
		var rung := int(_casting(actor).activate(actor, def)["rung"])
		assert_eq(rung <= 2, true, "use %d stays inside the authored two" % use_index)
	assert_eq(int(TechniquesApi.codex(actor).row(def.id).get("rung", 0)), 2, "and stops at two")
	# `mastery_rungs` is authorable downward only, so a def lowered to zero accrues
	# nothing rather than banking a rung it cannot spend.
	var flat := _active(actor)
	flat.mastery_rungs = 0
	assert_eq(int(_casting(actor).activate(actor, flat)["rung"]), 0, "zero rungs accrue nothing")


func test_mastery_is_persisted_with_the_codex_rather_than_beside_it() -> void:
	var actor := _actor()
	var def := _active(actor)
	_casting(actor).activate(actor, def)
	var payload := TechniquesApi.technique_state(actor)
	assert_eq(int((payload["entries"][0] as Dictionary)["rung"]), 1, "the codex payload moved")


# --- The cooldown survives a save/reload round trip ----------------------------


func test_the_cooldown_survives_a_save_and_reload_round_trip() -> void:
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 30.0)
	_casting(actor).activate(actor, def)
	_casting(actor).tick(actor, 10.0)
	assert_almost_eq(_casting(actor).remaining(def.id), 20.0, "twenty seconds left")

	# ADR 0056: persist ids and numbers. `Actor.to_dict`/`from_dict` carries
	# `module_data` verbatim, so a full round trip through core is the real test.
	var restored := Actor.from_dict(actor.to_dict())
	TechniquesApi.attach(restored)
	# The BINDING comes back too. An earlier version of this case asserted the
	# opposite — "the slot table is SESSION state and is deliberately not
	# persisted" — and had to re-equip by hand, which papered over DEF-0154: a
	# reload kept the technique and the cooldowns but silently emptied the loadout.
	# ADR 0053 makes all three states persistent.
	var casting := _casting(restored)
	assert_ne(casting, null, "the restored actor carries a casting table")
	assert_almost_eq(casting.remaining(def.id), 20.0, "the cooldowns came back with it")
	assert_eq(TechniquesApi.slots(restored).is_equipped(def.id), true, "and so did the binding")
	assert_eq(bool(casting.activate(restored, def)["ok"]), false, "so it is still cooling")
	casting.tick(restored, 20.0)
	assert_almost_eq(casting.remaining(def.id), 0.0, "the full twenty seconds clear it")
	assert_eq(bool(casting.activate(restored, def)["ok"]), true, "and fires once it clears")
	# And the rung the first firing earned is still there after the round trip.
	assert_eq(
		int(TechniquesApi.codex(restored).row(def.id).get("rung", 0)), 2, "mastery persisted too"
	)


func test_the_payload_stores_ids_and_numbers_and_never_a_definition() -> void:
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 30.0)
	_casting(actor).activate(actor, def)
	var payload := _casting(actor).to_dict()
	assert_eq(int(payload["version"]), 1, "the payload is versioned")
	var row: Dictionary = payload["entries"][0]
	assert_eq(String(row["id"]), String(def.id), "the technique id")
	assert_almost_eq(float(row["remaining"]), 30.0, "and the seconds it had left")
	assert_almost_eq(float(row["total"]), 30.0, "against the cooldown it was charged")
	# A designer retuning `cooldown` on the `.tres` must not rewrite every existing
	# save, so nothing but the id and the two charged numbers is ever written.
	for key in row.keys():
		assert_eq(
			key in ["id", "remaining", "total"], true, "'%s' is not authored content" % String(key)
		)
	# And it rides beside the codex under its own key rather than inside it.
	assert_eq(
		TechniquesApi.technique_state(actor).has("cooldowns"), false, "the codex shape is untouched"
	)
	assert_eq(
		String(TechniqueCasting.STATE_KEY) != String(TechniquesApi.STATE_KEY),
		true,
		"and the two payloads have separate keys"
	)


func test_a_save_written_before_cooldowns_existed_loads_as_all_ready() -> void:
	var actor := _actor()
	# A v1 payload from a build that never ran an activation.
	TechniquesApi.attach(actor)
	actor.set_module_data(TechniqueCasting.STATE_KEY, {"version": 1, "entries": []})
	var def := _active(actor)
	assert_almost_eq(_casting(actor).remaining(def.id), 0.0, "no entries means nothing owed")
	assert_eq(bool(_casting(actor).activate(actor, def)["ok"]), true, "and the technique fires")


func test_a_corrupt_cooldown_row_is_dropped_rather_than_armed() -> void:
	var actor := _actor()
	# Malformed content must not leave a technique permanently locked: an entry with
	# no id, or with a negative remainder, loads as ready.
	(
		actor
		. set_module_data(
			TechniqueCasting.STATE_KEY,
			{
				"version": 1,
				"entries": [{"id": "", "remaining": 9.0}, {"id": "ghost", "remaining": -4.0}],
			}
		)
	)
	var reloaded := Actor.from_dict(actor.to_dict())
	TechniquesApi.attach(reloaded)
	assert_almost_eq(_casting(reloaded).remaining(&"ghost"), 0.0, "a negative remainder is dropped")
	assert_eq((_casting(reloaded).to_dict()["entries"] as Array).size(), 0, "nothing is kept")


# --- The three states stay three states ----------------------------------------


func test_the_activation_path_changes_none_of_the_other_two_states() -> void:
	# ADR 0053's separation, asserted on the state each one owns: the codex's
	# MEMBERSHIP, the slot table's BINDINGS, and the passive's MODIFIERS. Mastery is
	# the one thing an activation does move, and it moves the rung alone.
	var actor := _actor()
	var passive := _passive(actor)
	var active := _active(actor, 15.0, 0.0, 5.0)
	TechniquesApi.rebuild(actor)
	assert_eq(
		TechniqueEffects.applied_count(actor, passive.id), 1, "the passive really contributes"
	)

	var entries_before := _entry_ids(actor)
	var slots_before := _slot_bindings(actor)
	var modifiers_before := actor.stats.modifier_count()
	var passive_value_before := actor.stats.derived(Stat.MAX_QI)

	var fired := _casting(actor).activate(actor, active)
	assert_eq(bool(fired["ok"]), true, "the activation fired")

	assert_eq(_entry_ids(actor), entries_before, "the codex MEMBERSHIP is unchanged")
	assert_eq(_slot_bindings(actor), slots_before, "the slot BINDINGS are unchanged")
	assert_eq(
		actor.stats.modifier_count(), modifiers_before, "and the modifiers were never rebuilt"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI),
		passive_value_before,
		"so the passive's contribution is untouched"
	)
	assert_eq(TechniquesApi.codex(actor).knows(passive.id), true, "the passive is still known")
	assert_eq(TechniqueEffects.applied_count(actor, passive.id), 1, "and still contributing")
	# Only the rung moved, and only on the one technique that was fired.
	assert_eq(
		int(TechniquesApi.codex(actor).row(active.id).get("rung", 0)),
		1,
		"the active technique's mastery is the one thing that changed"
	)
	assert_eq(
		int(TechniquesApi.codex(actor).row(passive.id).get("rung", 0)), 0, "and never the passive's"
	)


func test_unequipping_and_re_equipping_does_not_hand_back_a_second_free_cast() -> void:
	# A cooldown is an ESCAPE timer: swapping a technique out is a build choice, and
	# re-binding it must not refund the seconds the actor already paid for.
	var actor := _actor()
	var def := _active(actor, 0.0, 0.0, 10.0)
	_casting(actor).activate(actor, def)
	TechniquesApi.unequip(actor, def)
	TechniquesApi.equip(actor, def)
	assert_almost_eq(_casting(actor).remaining(def.id), 10.0, "the record outlives the unequip")
	assert_eq(
		String(_casting(actor).activate(actor, def)["reason"]),
		"on_cooldown",
		"so the re-equipped technique is still cooling"
	)


func _entry_ids(actor: Actor) -> Array:
	var out: Array = []
	for entry in TechniquesApi.codex(actor).entries():
		out.append(entry.technique_id)
	return out


func _slot_bindings(actor: Actor) -> Dictionary:
	var slots := TechniquesApi.slots(actor).all()
	var keys: Array = slots.keys()
	keys.sort()
	var out := {}
	for key in keys:
		out[String(key)] = String(slots[key])
	return out
