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
##
## ## Why a fight is a fight here, not a formality
##
## `TribulationFight.fight_to_verdict` is bound by `WAVE_GUARD`, so a fight whose wave
## count the record cannot reach is REFUSED rather than decided — and it returns that
## refusal, which has no `survived` and no `blessing` key. That is what every "invalid
## access to property or key 'blessing'" in this file's history was: a fixture that
## could not start the fight, not a broken producer. `_begin_as` below therefore goes
## through the module's own `begin`, which prices the fight the same way a player's does,
## and reports what it is told rather than assuming a verdict.

## The three CULTIVATION-scope defs the producer is expected to reach.
const CULTIVATION_IDS: Array[StringName] = [&"earth_bulwark", &"light_halo", &"wood_bloom"]


func _gate_index() -> int:
	# Read from core rather than pinned: the ladder is append-only, and a test that
	# hardcoded an index broke the moment a realm was inserted — exactly the coupling
	# ADR 0050 removed from the power table.
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


## The realm the fixture stands at: one BELOW the gate, which is the only position from
## which the next realm is the Immortal one a tribulation is owed for. `realm.index` is
## the ladder's own value, so an inserted realm moves the fixture with it.
func _owed_realm() -> RealmDef:
	return RealmDefaults.ladder().realms()[_gate_index() - 1]


func _hero() -> Actor:
	# A factory actor, so the pools and providers a real one has are present. The path and
	# realm are what make a tribulation OWED.
	var realm_id := _owed_realm().id
	var actor := ActorFactory.build(&"blessing_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## Drive a fight to a verdict through `TribulationFight` — the module that OWNS the fight
## and is where the blessing is paid. Returns that call's answer.
func _fight_to_verdict(actor: Actor, survived: bool = true) -> Dictionary:
	return TribulationFight.fight_to_verdict(actor, _rng_for(survived))


## Begin the owed fight, through the MODULE'S OWN verb rather than by reaching past it
## into core. `TribulationFight.begin` asks `Breakthrough.owed_index` which realm is owed
## and charges nothing, so this is the same entry a player's screen takes — and it names
## what it refused instead of leaving a null record behind for the next read to trip over.
##
## The type is written AFTER the record is rated, on purpose: `Tribulation.start` takes
## `difficulty` from `rate(actor)`, and `rate` reads `TYPE_PRESSURE[type]`, so a type set
## before `start` would price the fight against a pressure the fight is not then fought
## at. Rewriting the type afterwards means the ENDURANCE the fixture reasons about is the
## one the record is actually rated at.
func _begin_as(actor: Actor, trial_type: StringName) -> Dictionary:
	var started := TribulationFight.begin(actor)
	if not bool(started.get("ok", false)):
		return started
	actor.tribulation.type = trial_type
	return started


## A generator whose first draw decides the fight by BOUND rather than by hope.
##
## `TribulationEndurance.endurance` CLAMPS its answer into `[MIN_ENDURANCE,
## MAX_ENDURANCE]`, so a draw below `MIN_ENDURANCE` survives whatever the fight did and a
## draw at or above `MAX_ENDURANCE` always fails. That clamp is what makes the seed
## decisive for the WHOLE fight rather than for a single wave: `fight_wave` charges
## `WAVE_TOLL` (dao heart) before each wave and endurance falls as comprehension falls, so
## a seed chosen for the endurance the hero started with would stop being decisive part way
## through — which is how a "surviving" fixture used to reach a loss three waves in.
##
## Found by search rather than seeded by hand, so neither outcome can be a coincidence of
## one particular seed.
##
## ## Why the seed is REWOUND before it is handed back
##
## The search above has to DRAW to know whether a seed is decisive, and that draw advances
## the generator. Returning it as it stood would make the fight's own first `randf()` the
## SECOND value for that seed — a different number from the one the search accepted, so a
## hero the fixture had proven would survive came back defeated (`"not_a_survivor"`).
## PCG state is fully determined by the seed, so setting `rng.seed` again rewinds it and
## the fight draws exactly the value that was searched for.
func _rng_for(survived: bool) -> RandomNumberGenerator:
	var threshold := (
		TribulationEndurance.MIN_ENDURANCE if survived else TribulationEndurance.MAX_ENDURANCE
	)
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if (rng.randf() >= threshold) == (not survived):
			rng.seed = seed_value
			return rng
	rng.seed = 1
	return rng


## The trial types whose producer row resolves to `status_id`.
func _types_paying(status_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for trial_type in TribulationBlessing.REWARD_TABLE.keys():
		var element := TribulationBlessing.REWARD_TABLE[trial_type] as StringName
		if TribulationBlessing.blessing_for(element) == status_id:
			out.append(trial_type)
	return out


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
	assert_eq(bool(_begin_as(hero, Tribulation.ELEMENTAL)["ok"]), true, "a fight was owed")
	var outcome := _fight_to_verdict(hero, true)
	assert_eq(
		bool(outcome["ok"]), true, "the fight resolved: %s" % String(outcome.get("reason", ""))
	)
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
	assert_eq(bool(_begin_as(hero, Tribulation.ELEMENTAL)["ok"]), true, "a fight was owed")
	var outcome := _fight_to_verdict(hero, true)
	assert_eq(bool(outcome["ok"]), true, "the fight resolved")
	var status_id := StringName((outcome["blessing"] as Dictionary)["id"])
	var loop := StatusLoop.new(hero)
	# Sixty frames at 0.25s is 15 seconds — well past every COMBAT status in the tree.
	for _frame in 60:
		loop.tick(0.25)
	assert_eq(hero.has_status(status_id), true, "still live after 15s of production ticks")
	# The COMBAT contrast goes on BEFORE combat exit, which is the only order the purge
	# can act on: `clear_combat_scope` walks the statuses the actor is carrying AT THAT
	# MOMENT and returns the ids it cleared, so a burn applied afterwards is never in
	# `purged` no matter how correct the purge is. Read as "the purge cleared nothing",
	# which is exactly what it reported.
	StatusApi.apply(hero, &"fire_immolation", 1.0)
	# And combat exit must not clear the CULTIVATION gift.
	var purged := loop.exit_combat()
	assert_eq(hero.has_status(status_id), true, "combat exit left the CULTIVATION gift alone")
	assert_eq(
		CULTIVATION_IDS.has(status_id),
		true,
		"and only cultivation ids survive — %s was kept" % String(status_id)
	)
	# The contrast, so the assertion above is not vacuous on a purge that clears nothing.
	assert_eq(purged.has(String(&"fire_immolation")), true, "the combat status WAS purged")
	assert_eq(hero.has_status(&"fire_immolation"), false, "and is gone from the actor")


func test_the_blessing_is_paid_once_and_a_loss_pays_nothing() -> void:
	# A blessing farmable by re-fighting one trial is not a reward (ADR 0061's shape). And
	# a loss must pay nothing at all.
	var hero := _hero()
	assert_eq(bool(_begin_as(hero, Tribulation.ELEMENTAL)["ok"]), true, "a fight was owed")
	var first := _fight_to_verdict(hero, true)
	assert_eq(bool(first["ok"]), true, "the first fight resolved")
	assert_eq(bool((first["blessing"] as Dictionary)["ok"]), true, "the first fight pays")
	var id := StringName((first["blessing"] as Dictionary)["id"])
	# The record is decided, so the module REFUSES a re-fight rather than re-deciding it.
	var again := TribulationFight.fight_to_verdict(hero, _rng_for(true))
	assert_eq(bool(again["ok"]), false, "a decided fight cannot be re-fought")
	assert_eq(hero.has_status(id), true, "and the blessing is still the one status present")

	var loser := _hero()
	assert_eq(bool(_begin_as(loser, Tribulation.ELEMENTAL)["ok"]), true, "the second hero owes one")
	var lost := _fight_to_verdict(loser, false)
	assert_eq(bool(lost["ok"]), true, "the second fight resolved")
	assert_eq(bool(lost["survived"]), false, "and the second hero lost")
	assert_eq(bool((lost["blessing"] as Dictionary)["ok"]), false, "and was paid no blessing")
	# The refusal is NAMED, so "paid nothing" and "paid something unrecognised" are
	# different verdicts rather than the same absence.
	assert_eq(
		String((lost["blessing"] as Dictionary)["reason"]),
		String(TribulationBlessing.NO_SURVIVOR),
		"and the refusal says why"
	)
	assert_eq(loser.statuses.size(), 0, "with no cultivation status on them")


# --- each of the three is reachable through the producer -------------------------


func test_each_cultivation_status_is_reachable_through_the_producer() -> void:
	# The claim the audit could not make: all THREE authored cultivation defs have a
	# producer row, so none is orphaned. Each is driven through the SAME production path
	# — a real fight decided by the module's own verb — rather than by calling
	# `apply_cultivation` directly, which would prove only that the verb exists.
	#
	# The fixture must produce AT LEAST ONE trial type per status; when it produces none,
	# the loop below would pass silently on an empty set and the suite would go green with
	# all three statuses unreachable. That is asserted FIRST, and it is the assertion the
	# original file got backwards.
	for status_id in CULTIVATION_IDS:
		var trial_types := _types_paying(status_id)
		# `assert_eq(is_empty(), false)`, NOT `assert_ne(is_empty(), false)`. `assert_ne`
		# passes when its first argument DIFFERS from the second, so `assert_ne(x, false)`
		# succeeds only when `x` is true — it asserted "this status has NO producer row"
		# under a label reading "has at least one producer row". It passed for every one of
		# the three ids that DO have rows, and would have passed just as happily against an
		# orphaned `.tres`, which is the exact defect this assertion exists to catch.
		assert_eq(
			trial_types.is_empty(),
			false,
			"%s has at least one producer row in REWARD_TABLE" % String(status_id)
		)
	for status_id in CULTIVATION_IDS:
		var paid_through := 0
		for trial_type in _types_paying(status_id):
			var hero := _hero()
			var began := _begin_as(hero, trial_type)
			assert_eq(
				bool(began["ok"]),
				true,
				(
					"%s: a %s fight was owed (%s)"
					% [String(status_id), String(trial_type), String(began.get("reason", ""))]
				)
			)
			var outcome := _fight_to_verdict(hero, true)
			assert_eq(
				bool(outcome["ok"]),
				true,
				(
					"%s: the fight resolved (%s)"
					% [String(trial_type), String(outcome.get("reason", ""))]
				)
			)
			var granted := outcome["blessing"] as Dictionary
			assert_eq(
				bool(granted["ok"]),
				true,
				"%s: the fight paid (%s)" % [String(trial_type), str(granted)]
			)
			assert_eq(
				StringName(granted["id"]),
				status_id,
				"a %s trial pays %s" % [String(trial_type), String(status_id)]
			)
			assert_eq(hero.has_status(status_id), true, "%s is on the actor" % String(status_id))
			paid_through += 1
		assert_eq(
			paid_through > 0,
			true,
			"%s was paid by at least one real trial type" % String(status_id)
		)


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
	# And the refusal reaches the CALLER with its reason intact. `award` is driven
	# through an AUTHORED row that names a real element, so this exercises the
	# survived/decided path rather than the table-lookup refusal above — a status the
	# player earned must never be silently dropped, and one nobody earned must never be
	# silently invented.
	var hero := _hero()
	var began := _begin_as(hero, Tribulation.ELEMENTAL)
	assert_eq(bool(began["ok"]), true, "a fight was owed (%s)" % String(began.get("reason", "")))
	var granted := _fight_to_verdict(hero, true).get("blessing", {}) as Dictionary
	assert_eq(granted.has("ok"), true, "the caller receives a decision dictionary")
	# `reason` names a REFUSAL, and the caller has to be able to tell the two verdicts
	# apart. `StatusApi.apply_cultivation` answers a SUCCESS as
	# `{ok, id, magnitude, duration, permanent, mechanic}` — there is nothing to refuse,
	# so it carries no `reason` — while `TribulationBlessing._refused` always answers
	# `{ok: false, reason, id}`. Asserting `has("reason")` unconditionally demanded the
	# refusal shape from a paid blessing, which is the shape the contract forbids.
	if bool(granted.get("ok", false)):
		assert_eq(granted.has("id"), true, "a paid blessing names WHICH status it paid")
		assert_eq(granted.has("reason"), false, "and names no refusal, because none happened")
	else:
		assert_eq(granted.has("reason"), true, "an unpaid blessing names why")
		assert_eq(
			String(granted["reason"]),
			String(TribulationBlessing.NO_BLESSING),
			"and names NO_BLESSING rather than a silent nothing"
		)
	# The positive control, so the refusals above are not satisfied by a producer that pays
	# nothing at all.
	var other := _hero()
	assert_eq(bool(_begin_as(other, Tribulation.ELEMENTAL)["ok"]), true, "a fight was owed")
	var paid := _fight_to_verdict(other, true)["blessing"] as Dictionary
	assert_eq(bool(paid["ok"]), true, "an element that DOES ship a blessing pays")


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
	#
	## `tools/arch/registry.json` is OUTSIDE `res://`, so it is reached by GLOBALIZING
	## `res://..` — a `res://../tools/...` resource path resolves to nothing, and
	# `FileAccess.get_file_as_string` on a missing file answers an empty string with no
	## error, so the old body asserted `is_empty() == true` and passed for the wrong reason
	## (it was asserting that a read had failed). `res://..` must also be SIMPLIFIED before
	## it reaches any path comparison, which is the rule `tests/arch_rules` states by name
	## and the precedent `tests/modules/fertility/test_seduction.gd` follows.
	assert_eq(
		_declared_deps(&"heavenly_tribulation").has(&"status"),
		true,
		"heavenly_tribulation declares the status edge it calls through"
	)
	# And it is a one-way edge: `status` cannot call back, so the award cannot become a
	# cycle the gate would report as an undeclared dependency.
	assert_eq(
		_declared_deps(&"status").has(&"heavenly_tribulation"),
		false,
		"and status does not declare a back edge to the module that pays"
	)


## `tools/arch/registry.json`'s declared deps for `module_name`, read from disk.
##
## Empty when the file cannot be read, so a suite that cannot see the registry fails the
## edge assertion above rather than passing it on an empty set.
func _declared_deps(module_name: StringName) -> Array:
	var root := ProjectSettings.globalize_path("res://..").replace("\\", "/")
	var path := root.simplify_path().path_join("tools/arch/registry.json")
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return []
	var modules: Variant = (parsed as Dictionary).get("modules", {})
	if not (modules is Dictionary):
		return []
	var entry: Variant = (modules as Dictionary).get(String(module_name), {})
	if not (entry is Dictionary):
		return []
	return (entry as Dictionary).get("deps", []) as Array
