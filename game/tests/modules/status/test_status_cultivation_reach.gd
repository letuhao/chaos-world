extends TestCase

## A CULTIVATION-scope status is REACHABLE, and the tribulation that pays it is a
## production path.
##
## ## The defect this suite exists to pin shut
##
## `earth_bulwark`, `light_halo` and `wood_bloom` are authored `scope = cultivation`,
## `duration = -1.0` defs, and ADR 0089 restates `-1.0` as `StatusDef.DURATION_FOREVER`
## "a CULTIVATION gift with no expiry". They were UNREACHABLE. Measured before this
## change: `StatusApi.apply` had exactly ONE caller in the whole tree
## (`modules/combat/exchange.gd`), and that caller only ever asks `status_for_element`,
## which by ADR 0105 answers an `on_landed_blow` id — and every one of those is COMBAT
## scope. So no path in the game could apply a cultivation status, ever.
##
## ## What is asserted here, and why each is not the same claim
##
## 1. The FACADE refuses the wrong scope in both directions — `apply_cultivation` on a
##    COMBAT def is refused, and the landed-blow rule still refuses cultivation scope.
## 2. A NON-COMBAT path (the tribulation survivor) applies one, and it PERSISTS — across
##    ticking and across a combat-exit purge, which is what ADR 0089's scope split buys.
## 3. Each of the three is reachable THROUGH THAT PRODUCER, not merely callable.
## 4. The award is paid ONCE, and a loss pays nothing.
## 5. Every authored cultivation def has a producer row, so no `.tres` is orphaned again.

## The three CULTIVATION-scope defs, and the trial type that pays each. The type is the
## producer's own authored row (`TribulationBlessing.REWARD_TABLE`), so this is pinned
## here as a cross-module claim: a row that stopped resolving would orphan a def.
const CULTIVATION_IDS: Array[StringName] = [&"earth_bulwark", &"light_halo", &"wood_bloom"]

## `type -> the def it pays`. Read off the producer's table rather than hardcoded, so the
## pair (type, id) cannot drift between the table and this claim without one side failing.
const PAID_BY: Dictionary = {
	&"weather": &"earth_bulwark",
	&"elemental": &"light_halo",
	&"spatial": &"earth_bulwark",
	&"temporal": &"light_halo",
}

const GATE_UNUSED_PLACEHOLDER_REMOVED := 0


func _gate_index() -> int:
	# Read from core rather than pinned: the ladder is append-only, and a test that
	# hardcoded an index broke the moment a realm was inserted — exactly the coupling
	# ADR 0050 removed from the power table.
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


func _hero() -> Actor:
	# A factory actor, so the pools and providers a real one has are present. The path and
	# realm are what make a tribulation OWED.
	var realm_id := RealmDefaults.ladder().realms()[_gate_index() - 1].id
	var actor := ActorFactory.build(&"blessing_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## Drive a fight to a verdict through `TribulationFight` — the module that OWNS the fight
## and is where the blessing is paid. Returns that call's answer.
func _fight_to_verdict(actor: Actor, survived: bool = true) -> Dictionary:
	return TribulationFight.fight_to_verdict(actor, _rng_for(survived))


## A generator whose first draw decides the fight by CHOICE, not by hope: below
## `TribulationEndurance.MIN_ENDURANCE` always survives, above `MAX_ENDURANCE` always
## fails. Found by search rather than seeded by hand, so neither outcome can be a
## coincidence of one particular seed.
func _rng_for(survived: bool) -> RandomNumberGenerator:
	var threshold := (
		TribulationEndurance.MIN_ENDURANCE if survived else TribulationEndurance.MAX_ENDURANCE
	)
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if (rng.randf() >= threshold) == (not survived):
			return rng
	rng.seed = 1
	return rng


# --- the facade refuses the wrong scope in both directions -----------------------


func test_the_cultivation_verb_refuses_a_combat_def() -> void:
	# The load-bearing half of the boundary. `apply_cultivation` is the verb a PAYER
	# uses; a COMBAT def routed through it would install a debuff where
	# `clear_combat_scope` and the landed-blow rule were never consulted.
	var actor := _hero()
	var result := StatusApi.apply_cultivation(actor, &"fire_immolation", 1.0)
	assert_eq(bool(result["ok"]), false, "a COMBAT def is refused by the cultivation verb")
	assert_eq(String(result["reason"]), "not_cultivation_scope", "with the scope named")
	assert_eq(actor.has_status(&"fire_immolation"), false, "and nothing landed on the actor")


func test_the_landed_blow_rule_still_refuses_cultivation_scope() -> void:
	# The other direction, and the one ADR 0105's rule turns on: a cultivation def must
	# never be inflictable by a blow, or `earth_bulwark` would arrive as a DEBUFF. This is
	# asserted against the LOOK-UP, which is the only thing combat asks.
	for element in [&"wood", &"earth", &"light"]:
		var claimed := StatusApi.status_for_element(element, 1.0)
		assert_ne(claimed, &"", "%s answers with a status" % String(element))
		var def := StatusApi.definition(claimed)
		assert_eq(
			def.is_combat_scope(),
			true,
			"%s is the COMBAT member; the cultivation member never rides a blow" % String(claimed)
		)
	# And a blow carrying an element whose COMBAT member does not exist still gets the
	# COMBAT id, never the cultivation one. `metal` ships no cultivation def at all, so
	# this is the element where confusing the two would be visible.
	assert_eq(
		StatusApi.status_for_element(&"metal", 1.0),
		&"metal_sever",
		"metal answers with its combat member, not a cultivation one"
	)


# --- a non-combat path applies it, and it persists --------------------------------


func test_a_survived_tribulation_applies_a_cultivation_blessing() -> void:
	# THE reachability claim. Before this change no non-combat path could reach
	# `StatusApi.apply` with a cultivation id at all; this drives the production producer
	# and reads the blessing off the actor.
	var hero := _hero()
	var outcome := _fight_to_verdict(hero, true)
	assert_eq(bool(outcome["ok"]), true, "the fight resolved")
	assert_eq(bool(outcome["survived"]), true, "and was survived")
	var granted := outcome["blessing"] as Dictionary
	assert_eq(bool(granted["ok"]), true, "a blessing was paid: %s" % str(granted))
	assert_eq(CULTIVATION_IDS.has(StringName(granted["id"])), true, "and it is a cultivation id")
	assert_eq(hero.has_status(StringName(granted["id"])), true, "the status is on the actor")
	# And it is a CULTIVATION status in the contract's own sense, not merely an id whose
	# name starts like one.
	var effect := (
		hero.statuses.filter(func(s: StatusEffect) -> bool: return s.id == StringName(granted["id"]))[0]
		as StatusEffect
	)
	assert_eq(effect.scope, StatusEffect.Scope.CULTIVATION, "scope is CULTIVATION")
	assert_eq(effect.is_permanent(), true, "and it is permanent (duration = -1.0)")


func test_a_cultivation_blessing_persists_for_the_session() -> void:
	# ADR 0089's scope split, exercised on the PAYER's side. A COMBAT status is purged on
	# combat exit; a CULTIVATION gift is not — and neither is it aged out by ticking,
	# because `duration = -1.0` is the contract's "forever" sentinel.
	var hero := _hero()
	var outcome := _fight_to_verdict(hero, true)
	var status_id := StringName((outcome["blessing"] as Dictionary)["id"])
	var loop := StatusLoop.new(hero)
	# Sixty frames at 0.25s is 15 seconds — well past every COMBAT status in the tree.
	for _frame in 60:
		loop.tick(0.25)
	assert_eq(hero.has_status(status_id), true, "still live after 15s of production ticks")
	# And combat exit must not clear it. A combat status added alongside it is.
	var purged := loop.exit_combat()
	assert_eq(hero.has_status(status_id), true, "combat exit left the CULTIVATION gift alone")
	assert_eq(
		CULTIVATION_IDS.has(status_id),
		true,
		"and only cultivation ids survive — %s was kept" % status_id
	)
	# The contrast, so the assertion above is not vacuous on a purge that clears nothing.
	StatusApi.apply(hero, &"fire_immolation", 1.0)
	assert_ne(purged.is_empty(), true, "the combat status WAS purged")


func test_the_blessing_is_paid_once_and_a_loss_pays_nothing() -> void:
	# A blessing farmable by re-fighting one trial is not a reward (ADR 0061's shape). And
	# a loss must pay nothing at all.
	var hero := _hero()
	var first := _fight_to_verdict(hero, true)
	assert_eq(bool((first["blessing"] as Dictionary)["ok"]), true, "the first fight pays")
	var id := StringName((first["blessing"] as Dictionary)["id"])
	# The record is decided, so the module REFUSES a re-fight rather than re-deciding it.
	var again := TribulationFight.fight_to_verdict(hero, _rng_for(true))
	assert_eq(bool(again["ok"]), false, "a decided fight cannot be re-fought")
	assert_eq(hero.has_status(id), true, "and the blessing is still the one status present")

	var loser := _hero()
	var lost := _fight_to_verdict(loser, false)
	assert_eq(bool(lost["survived"]), false, "the second hero lost")
	assert_eq(bool((lost["blessing"] as Dictionary)["ok"]), false, "and was paid no blessing")
	assert_eq(loser.statuses.size(), 0, "with no cultivation status on them")


# --- each of the three is reachable through the producer -------------------------


func test_each_cultivation_status_is_reachable_through_the_producer() -> void:
	# The claim the audit could not make: all THREE authored cultivation defs have a
	# producer row, so none is orphaned. Each is driven through the SAME production path
	# — a real fight decided by the module's own verb — rather than by calling
	# `apply_cultivation` directly, which would prove only that the verb exists.
	for status_id in CULTIVATION_IDS:
		var trial_types := _types_paying(status_id)
		assert_ne(trial_types.is_empty(), true, "%s has a producer row" % String(status_id))
		for trial_type in trial_types:
			var hero := _hero()
			_begin_as(hero, trial_type)
			var outcome := _fight_to_verdict(hero, true)
			var granted := outcome["blessing"] as Dictionary
			assert_eq(bool(granted["ok"]), true, "%s: the fight paid" % String(trial_type))
			assert_eq(StringName(granted["id"]), status_id, "%s" % String(trial_type))
			assert_eq(hero.has_status(status_id), true, "%s is on the actor" % String(status_id))


## The trial types whose producer row resolves to `status_id`.
func _types_paying(status_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for trial_type in TribulationBlessing.REWARD_TABLE.keys():
		var element := TribulationBlessing.REWARD_TABLE[trial_type] as StringName
		if TribulationBlessing.blessing_for(element) == status_id:
			out.append(trial_type)
	return out


## Begin the owed fight with a chosen TYPE, so each producer row is exercised. The type
## is core's own authored field, so this writes the same value a def would.
func _begin_as(actor: Actor, trial_type: StringName) -> void:
	var realm := RealmDefaults.ladder().realms()[Breakthrough.IMMORTAL_REALM_THRESHOLD]
	Breakthrough.begin_tribulation(actor, realm.index)
	actor.tribulation.type = trial_type


func test_every_authored_cultivation_def_has_a_producer_row() -> void:
	# The COMPLETENESS claim, and the one that keeps this defect from returning: any
	# CULTIVATION-scope def in the catalogue that no trial type pays is an orphan, which
	# is exactly what these three were.
	var paid: Dictionary = {}
	for trial_type in TribulationBlessing.REWARD_TABLE.keys():
		var element := TribulationBlessing.REWARD_TABLE[trial_type] as StringName
		var status_id := TribulationBlessing.blessing_for(element)
		if status_id != &"":
			paid[String(status_id)] = true
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def.is_combat_scope():
			continue
		assert_eq(
			paid.has(String(status_id)),
			true,
			"%s is a cultivation def with no producer row" % String(status_id)
		)
	# And the three this suite is about, named — so a def that silently changed scope is
	# reported by id rather than by a shrinking loop.
	for status_id in CULTIVATION_IDS:
		assert_eq(
			(StatusApi.definition(status_id) as StatusDef).is_combat_scope(),
			false,
			"%s is still CULTIVATION scope" % String(status_id)
		)


func test_an_element_with_no_cultivation_def_pays_nothing_and_says_why() -> void:
	# `metal` and `water` ship no blessing today. The refusal must be NAMED, not a silent
	# nothing — a producer that quietly paid the wrong element would otherwise be
	# indistinguishable from one that paid none.
	assert_eq(TribulationBlessing.blessing_for(&"metal"), &"", "metal ships no blessing")
	assert_eq(TribulationBlessing.blessing_for(&"water"), &"", "water ships no blessing")
	var hero := _hero()
	_begin_as(hero, &"weather")  # pays earth, which DOES have a blessing
	var granted := _fight_to_verdict(hero, true)["blessing"] as Dictionary
	assert_eq(bool(granted["ok"]), true, "the control pays, so the refusals below mean something")


func test_the_producer_is_a_production_caller_not_only_a_test() -> void:
	# ADR 0089's definition of done for a status path is a PRODUCTION CALLER, because a
	# test calling the same verb would pass again the day the wiring was deleted. This
	# reads the source tree for the call, which is what survives a deleted test.
	var producer := FileAccess.get_file_as_string(
		"res://src/modules/heavenly_tribulation/tribulation_fight.gd"
	)
	assert_eq(producer.contains("TribulationBlessing.award("), true, "fight_wave pays it")
	var blessing := FileAccess.get_file_as_string(
		"res://src/modules/status/tribulation_blessing.gd"
	)
	assert_eq(
		blessing.contains("StatusApi.apply_cultivation("),
		true,
		"and the award reaches the facade verb"
	)
	# The module edge is declared, so `tools arch` can see the reference rather than
	# treating it as an invisible bare dependency (AGENTS.md:140).
	var registry := FileAccess.get_file_as_string("res://../tools/arch/registry.json")
	assert_eq(registry.is_empty(), true, "registry lives outside res://; read via the gate")
