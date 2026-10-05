extends TestCase

## Fate is earned, never chosen and never equipped (ADR 0065). These assert the
## structural half of that claim — the facade has no removal verb at all — and the
## behavioural half: earning is exactly-once, the stat projection is derived and
## idempotent, counters only ever rise, and an earn the module cannot read is
## refused rather than recorded.

const MODULE_KEY := DestinyState.MODULE_KEY
const OATH := &"t_oath_breaker"
const PLEDGE := &"t_blood_pledge"
const AWAKENED := &"t_awakened"
const CHOSEN := &"t_chosen_one"
const UNCHOSEN := &"t_chosen_of_nobody"
const DUELS := &"duels_won"

## `contribution()` answers with a pair, never one number: a magnitude and a rate
## are different kinds of quantity and adding them yields a number that means
## neither. Held here so every assertion names the same two channels.
const NOTHING_CONTRIBUTED := {"flat": 0.0, "percent": 0.0}

## Every verb a facade must never grow, as a SUBSTRING: a name is refused wherever
## the verb appears in it, so `revoke_fate`, `equip_destiny` and a bare `select`
## are all caught. If one of these reaches `DestinyApi`'s public surface, the
## earn-only invariant has been broken and a player can lose fate.
const FORBIDDEN_VERBS := [
	"remove",
	"revoke",
	"forget",
	"unequip",
	"equip",
	"choose",
	"select",
	"clear",
	"drop",
	"consume",
	"spend",
	"discard",
	"reset",
	"undo",
]


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(PLEDGE, Stat.ATTACK_PHYSICAL, 2.0),
				DestinyFixtureCatalog.flat_fate(AWAKENED, Stat.MAX_HEALTH, 25.0),
				DestinyFixtureCatalog.story_fate(&"t_whisper"),
			],
			[
				DestinyFixtureCatalog.plain_destiny(CHOSEN),
				DestinyFixtureCatalog.plain_destiny(UNCHOSEN)
			]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


# --- The invariant, structurally ---------------------------------------------


## The single most valuable test in this suite. Fate is permanent because the
## public surface has no way to take it back: other modules may reference only
## `api.gd`, so if no verb there removes or selects a fate or a destiny, nothing
## outside the module can remove one. A future `revoke()` fails here rather than
## in a player's save.
##
## The check is on the PUBLIC surface, so the split matters: `get_script_method_
## list()` also returns this module's own `_`-prefixed helpers and everything
## inherited from `Object`. Asserting over that whole list would either pass for
## the wrong reason or fail on `_persist`, which is exactly what it is for. So the
## surface is split first, and only the public half is held to the invariant.
func test_the_facade_exposes_no_removal_or_choice_verb_at_all() -> void:
	var public := _public_methods()
	assert_eq(public.is_empty(), false, "the facade's public method list is readable")
	# 1. The public set is EXACTLY the earn-and-read surface ADR 0065 describes,
	#    plus the two starter-pack verbs. Naming every verb means an unlisted one
	#    added later fails here instead of slipping past the word list below.
	#
	#    The starter pair is here rather than behind a narrower door because the
	#    facade WIDTH cap is deleted (`rules.MAX_FACADE_PUBLIC_METHODS` is gone;
	#    coupling is measured by `MAX_FACADE_FAN_IN` instead), and both verbs are
	#    earn-adjacent in the sense that matters here: `register_starter_pack`
	#    writes a module-level registry and `starter_pack` reads it. Neither
	#    grants nor revokes a fate or a destiny, which is what check 2 measures —
	#    and the registry is CONTENT, reset by nulling the singleton exactly as
	#    `FateCatalog` is, not player state a save could carry.
	assert_eq(
		public,
		[
			"attach",
			"destinies",
			"difficulty_events",
			"difficulty_modifier",
			"earn_destiny",
			"earn_fate",
			"eligible_choices",
			"events",
			"fates",
			"gate",
			"has_choice",
			"has_destiny",
			"has_fate",
			"probability_modifier",
			"probability_modifiers",
			"record",
			"register_starter_pack",
			"starter_pack",
			"state",
			"summary",
		],
		(
			"the facade is the earn-and-read surface ADR 0065 describes plus the starter"
			+ " pack pair, the difficulty event pair, and the fate choice pair, and nothing else"
		)
	)
	# 2. No public name carries a removal or selection verb, in any position and
	#    under any prefix. This is the part that catches a *renamed* verb, which
	#    the exact-set check above catches too — but it states the invariant in
	#    its own terms, so the reason survives even if the surface is reordered.
	for name in public:
		for verb in FORBIDDEN_VERBS:
			assert_eq(
				name.contains(verb), false, "no public verb contains '%s' ('%s')" % [verb, name]
			)


## The methods `DestinyApi` publishes to other modules — everything the facade
## script declares that is not `_`-prefixed.
##
## Read from the script's OWN declarations rather than `get_script_method_list()`,
## which would also return every inherited `Object` method and drown the surface
## in names the module did not choose. A facade is all static functions and
## GDScript refuses a non-static call on a class reference, so `load()` is the one
## way in. An unreadable facade hands back an empty list, which the callers above
## fail on rather than quietly accept.
func _public_methods() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load("res://src/modules/destiny/api.gd")
	if script == null:
		return out
	for line in script.source_code.split("\n"):
		# The same line test `tools arch` counts the facade cap with, so this is the
		# same number the gate enforces rather than a second, looser definition.
		if not line.begins_with("static func "):
			continue
		var name := line.substr("static func ".length())
		name = name.substr(0, name.find("(")).strip_edges()
		# A `_`-prefixed name is a helper, not a published verb: the module keeps
		# its internals and other modules see only the earn-and-read surface.
		if name.begins_with("_"):
			continue
		out.append(name)
	out.sort()
	return out


# --- The earn path -----------------------------------------------------------


func test_earning_a_fate_applies_its_flat_modifiers_to_the_derived_stat() -> void:
	var actor := _hero()
	var defense_before := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	assert_eq(
		DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		NOTHING_CONTRIBUTED,
		"nothing owed yet"
	)
	DestinyApi.earn_fate(actor, OATH, "combat")
	assert_eq(DestinyApi.has_fate(actor, OATH), true, "the fate is held")
	# A magnitude and a rate are separate channels, so the contribution is read as
	# a pair: the fixture grants 3.0 flat and 3.0/10.0 percent, and neither is
	# folded into the other.
	assert_eq(
		DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		{"flat": 3.0, "percent": 0.3},
		"the authored flat and percent contributions are kept apart"
	)
	# Fate reuses the single stat-modifier pipeline, so `derived =
	# (base + flat) * (1 + percent)` applies both channels. The fixture grants
	# 3.0 flat AND 0.3 percent, so the expected value is the composed one — there
	# is no state in which the stat equals `before + 3.0` and also
	# `(before + 3.0) * 1.3`.
	assert_almost_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		(defense_before + 3.0) * 1.3,
		"both channels land through the one pipeline"
	)


func test_earning_the_same_fate_twice_is_exactly_once() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	var after_first := DestinyApi.state(actor)
	var health_after_first := actor.stats.derived(Stat.MAX_HEALTH)
	var defense_after_first := DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL)
	var ledger := DestinyApi.earn_fate(actor, OATH, "combat")
	assert_eq(
		ledger["fates"] as Dictionary, after_first["fates"] as Dictionary, "nothing was appended"
	)
	assert_eq(
		DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		defense_after_first,
		"and nothing was re-projected"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH), health_after_first, "no derived stat moved either"
	)
	# The earned order is stamped once. A second earn must not extend the trail.
	# Fetched through `.get()` with the shape checked first: a typed local assigned
	# an unvalidated subscript aborts the whole function, and the runner's
	# `suite.call(name)` cannot tell an aborted test from a finished one, so this
	# assertion below would be skipped while the suite still reported green.
	var fates := ledger["fates"] as Dictionary
	var entry = fates.get(String(OATH), null)
	if entry is Dictionary and (entry as Dictionary).has("sequence"):
		assert_eq(int((entry as Dictionary)["sequence"]), 1, "the sequence is stamped exactly once")
	else:
		assert_eq(
			entry is Dictionary and (entry as Dictionary).has("sequence"),
			true,
			"the ledger holds a sequenced entry for '%s'" % OATH
		)


func test_earning_an_unknown_fate_is_refused_and_records_nothing() -> void:
	var actor := _hero()
	DestinyApi.record(actor, DUELS, 1)
	var before := DestinyApi.state(actor)
	var ledger := DestinyApi.earn_fate(actor, &"t_no_such_fate", "combat")
	assert_eq(ledger, before, "a fate the catalog does not define is not recorded")
	assert_eq(DestinyApi.has_fate(actor, &"t_no_such_fate"), false, "it is not held")
	assert_eq(_destiny_modifiers(actor), 0, "and it projected nothing")
	assert_eq(_history_kinds(ledger), ["counter"], "the refused earn left no trail")
	# Nothing was persisted either, and nothing was announced: a fate the catalog
	# does not define is a content bug, and storing it would create a fate
	# nothing can ever pay out.
	assert_eq(
		actor.get_module_data(MODULE_KEY)["fates"] as Dictionary,
		before["fates"] as Dictionary,
		"the persisted ledger gained nothing"
	)
	assert_eq(
		(actor.get_module_data(MODULE_KEY)["history"] as Array).size(),
		1,
		"and the stored trail still holds only the counter"
	)


## The signal bus is an INSTANCE held at `DestinyProjection.events()`, not a class
## of static constants: a GDScript signal belongs to an object, and a facade is a
## namespace of statics. So a consumer connects through `events()`, and an earn
## announces itself exactly once — including the replay, which must stay silent.
func test_an_earn_announces_itself_once_through_the_instance_bus() -> void:
	var actor := _hero()
	var bus := DestinyProjection.events()
	assert_eq(bus, DestinyProjection.events(), "the bus is one shared instance")
	var earned: Array = []
	var fate_handler := func(actor_id: String, fate_id: StringName, source: String) -> void:
		earned.append("%s/%s/%s" % [actor_id, fate_id, source])
	bus.fate_earned.connect(fate_handler)
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, OATH, "combat")
	assert_eq(earned.size(), 1, "the replay announces nothing")
	assert_eq(
		earned[0],
		"%s/t_oath_breaker/combat" % String(actor.id),
		"naming the actor, fate and source"
	)
	bus.fate_earned.disconnect(fate_handler)


## The other two earn announcements, and the shape each one carries. `fate_earned`
## is the only signal any suite connected before this one, so `destiny_earned` and
## `counter_changed` shipped unobserved — a signature change in either would have
## reached a consumer as a silent no-op.
func test_a_destiny_earn_announces_itself_once_through_the_instance_bus() -> void:
	var actor := _hero()
	var bus := DestinyProjection.events()
	var earned: Array = []
	var handler := func(actor_id: String, destiny_id: StringName, source: String) -> void:
		earned.append("%s/%s/%s" % [actor_id, destiny_id, source])
	bus.destiny_earned.connect(handler)
	DestinyApi.earn_fate(actor, OATH, "combat")
	assert_eq(earned.is_empty(), true, "earning a fate says nothing about a destiny")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	assert_eq(earned.size(), 1, "the replay announces nothing")
	assert_eq(
		earned[0],
		"%s/t_chosen_one/story" % String(actor.id),
		"naming the actor, destiny and source"
	)
	bus.destiny_earned.disconnect(handler)


## `DestinyEvents` declares `amount` as the applied DELTA and `total` as the value
## after it — a consumer reacting to "one more duel" needs the delta, and one
## drawing a progress bar needs the total. Emitting the total in both slots is
## invisible to a consumer that only reads `total`, so it is asserted here against
## the declared contract rather than against whatever the emit site passes.
func test_a_counter_record_announces_the_delta_and_the_running_total() -> void:
	var actor := _hero()
	var bus := DestinyProjection.events()
	var heard: Array = []
	var handler := func(actor_id: String, counter_id: StringName, amount: int, total: int) -> void:
		heard.append(
			{"actor": actor_id, "counter": String(counter_id), "amount": amount, "total": total}
		)
	bus.counter_changed.connect(handler)
	DestinyApi.record(actor, DUELS, 1)
	DestinyApi.record(actor, DUELS, 2)
	assert_eq(heard.size(), 2, "one announcement per real movement")
	assert_eq(String(heard[0]["actor"]), String(actor.id), "naming the actor")
	assert_eq(String(heard[0]["counter"]), String(DUELS), "and the counter")
	assert_eq(int(heard[0]["amount"]), 1, "the first announcement carries the delta, not the total")
	assert_eq(int(heard[0]["total"]), 1, "and the value after it")
	# The case that distinguishes the two: the second record makes delta 2 and
	# total 3, so an emitter that passed `total` in both slots reports 3/3 here.
	assert_eq(int(heard[1]["amount"]), 2, "the second announcement carries the delta it applied")
	assert_eq(int(heard[1]["total"]), 3, "and the running total, which is not the same number")
	# A refused movement announces nothing at all, so a consumer cannot be told a
	# counter moved when it did not.
	DestinyApi.record(actor, DUELS, -5)
	DestinyApi.record(actor, DUELS, 0)
	assert_eq(heard.size(), 2, "a record that moves nothing announces nothing")
	bus.counter_changed.disconnect(handler)


## The gate refusal is an observation, never a veto: the caller has ALREADY been
## refused and is not waiting on the signal. It exists so a content designer can
## see a gate nobody can reach, so it has to name the actor, the reason and the
## requirement that was refused.
func test_a_failed_gate_announces_the_actor_the_reason_and_the_requirement() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	var bus := DestinyProjection.events()
	var heard: Array = []
	var handler := func(actor_id: String, reason: String, requirement: Dictionary) -> void:
		heard.append({"actor": actor_id, "reason": reason, "requirement": requirement})
	bus.gate_failed.connect(handler)
	var requirement := {"verb": &"has_fate", "id": String(PLEDGE)}
	assert_eq(
		bool(DestinyApi.gate(actor, requirement)["ok"]),
		false,
		"the gate really did refuse, so the announcement means something"
	)
	assert_eq(heard.size(), 1, "one announcement per refusal")
	assert_eq(String(heard[0]["actor"]), String(actor.id), "naming the actor")
	assert_eq(String(heard[0]["reason"]), "unmet", "and the reason")
	assert_eq(
		(heard[0]["requirement"] as Dictionary)["id"],
		String(PLEDGE),
		"carrying the requirement exactly as authored"
	)
	# An open gate is not a failure, and an unreadable one refuses with its own
	# distinct reason rather than the same 'unmet'. A refusal a content designer
	# cannot tell apart from a player being told no is the whole reason this signal
	# carries the reason string.
	DestinyApi.gate(actor, {"verb": &"has_fate", "id": String(OATH)})
	assert_eq(heard.size(), 1, "an open gate announces nothing")
	DestinyApi.gate(actor, {"verb": &"teleported"})
	assert_eq(heard.size(), 2, "but an unreadable gate is still a refusal")
	assert_eq(String(heard[1]["reason"]), "unknown_verb", "and it names its own cause")
	assert_eq(
		String(heard[1]["actor"]),
		String(actor.id),
		"so a designer can tell WHICH gate is unreadable"
	)
	bus.gate_failed.disconnect(handler)


## The module gate is also reachable through the facade, and it is the facade
## method that emits `gate_failed`. `DestinyGate.evaluate` — which every suite in
## this module calls directly — is the inner half and emits nothing: an observer
## sees one announcement per refusal a caller actually experienced.
func test_only_the_facade_announces_a_gate_failure_not_the_inner_evaluation() -> void:
	var actor := _hero()
	var bus := DestinyProjection.events()
	var heard: Array = []
	var handler := func(actor_id: String, reason: String, requirement: Dictionary) -> void:
		heard.append(reason)
	bus.gate_failed.connect(handler)
	var requirement := {"verb": &"has_destiny", "id": String(UNCHOSEN)}
	assert_eq(
		bool(DestinyGate.evaluate(actor, requirement)["ok"]),
		false,
		"the inner evaluation refuses too"
	)
	assert_eq(heard.is_empty(), true, "but evaluating is not a caller's refusal to announce")
	DestinyApi.gate(actor, requirement)
	assert_eq(heard, ["unmet"], "the facade announces exactly once")
	bus.gate_failed.disconnect(handler)


func test_the_trait_mirror_carries_a_namespaced_id_for_everything_held() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	assert_eq(actor.traits.has(DestinyState.trait_for(OATH)), true, "the fate is mirrored")
	assert_eq(actor.traits.has(DestinyState.trait_for(CHOSEN)), true, "so is the destiny")
	assert_eq(actor.traits.has(OATH), false, "under the namespaced id, never the bare one")
	assert_eq(actor.traits.has(CHOSEN), false, "neither destiny is bare")
	# A fate with no stat contribution is still mirrored: the mirror is what a
	# gate or a panel reads cheaply.
	DestinyApi.earn_fate(actor, &"t_whisper", "story")
	assert_eq(
		actor.traits.has(DestinyState.trait_for(&"t_whisper")), true, "a story fate is mirrored too"
	)
	assert_eq(actor.traits.to_array().size(), 3, "one id per held entry")


# --- Counters only ever rise -------------------------------------------------


func test_recording_raises_a_counter_and_returns_the_value_after_the_delta() -> void:
	var actor := _hero()
	assert_eq(_counter(actor, DUELS), 0, "a counter that was never recorded is zero")
	assert_eq(DestinyApi.record(actor, DUELS), 1, "the first record is worth one")
	assert_eq(DestinyApi.record(actor, DUELS, 2), 3, "the second adds its amount")
	assert_eq(_counter(actor, DUELS), 3, "and the value is what the caller was handed")
	assert_eq(_counter(actor, &"never_recorded"), 0, "an untouched counter stays zero")


func test_a_counter_can_never_be_lowered() -> void:
	var actor := _hero()
	DestinyApi.record(actor, DUELS, 3)
	assert_eq(DestinyApi.record(actor, DUELS, -5), 3, "a negative amount moves nothing")
	assert_eq(_counter(actor, DUELS), 3, "and the counter did not fall")
	assert_eq(DestinyApi.record(actor, DUELS, 0), 3, "a zero amount moves nothing either")
	assert_eq(_counter(actor, DUELS), 3, "still three")
	# Nothing was recorded on a refused movement, so there is no trail of a
	# counter that tried to go backwards.
	var ledger := DestinyState.normalize(actor.get_module_data(MODULE_KEY))
	assert_eq(_counter_records(ledger), ["3"], "the one real record is the only one in the trail")
	# And the gate reads the same monotonic value the facade reports.
	var verdict := DestinyGate.evaluate(actor, {"verb": &"counter", "id": String(DUELS), "need": 3})
	assert_eq(bool(verdict["ok"]), true, "the gate agrees three is three")


func test_a_record_that_moves_nothing_does_not_persist() -> void:
	var actor := _hero()
	DestinyApi.record(actor, DUELS, 2)
	var before := DestinyApi.state(actor)
	DestinyApi.record(actor, DUELS, -1)
	DestinyApi.record(actor, &"never_recorded", 0)
	assert_eq(DestinyApi.state(actor), before, "the persisted ledger is untouched")


## The recorded value of one counter, read off the ledger [method DestinyApi.state]
## publishes rather than off a facade verb. `counter(actor, id)` was retired when
## the twelve-method cap forced a choice to pay for `events()`: it was the one
## public verb with no caller in `game/src` at all, so what it answered was already
## one dictionary key away from every one of its twenty read sites.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


# --- The projection is derived, so it is idempotent ---------------------------


func test_applying_the_projection_twice_leaves_the_same_modifier_stack() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, AWAKENED, "path")
	var before := _fingerprint(actor)
	# A replayed projection — the shape a restored save, a re-attached module or
	# a re-derived codex all take. It must reproduce the stack, never double it.
	for cycle in 3:
		DestinyProjection.apply(actor, DestinyApi.state(actor))
		assert_eq(_fingerprint(actor), before, "cycle %d leaves the stack identical" % cycle)
	assert_eq(DestinyProjection.modifier_count(actor), 4, "two fates, two modifiers each")
	assert_eq(
		DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		{"flat": 3.0, "percent": 0.3},
		"one flat and one percent, once each"
	)


## The idempotence criterion in its own right: `modifier_count()` is the module's
## own count of what it owns, so projecting again is asserted against that number
## rather than against a hand-rolled walk over the private modifier stack.
func test_reapplying_the_projection_leaves_the_modifier_count_unchanged() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, PLEDGE, "oath")
	DestinyApi.earn_fate(actor, AWAKENED, "path")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	var first := DestinyProjection.modifier_count(actor)
	assert_eq(first, 6, "three fates at two modifiers each")
	for cycle in 4:
		DestinyProjection.apply(actor, DestinyApi.state(actor))
		assert_eq(
			DestinyProjection.modifier_count(actor),
			first,
			"re-projecting cycle %d neither stacks nor drops a modifier" % cycle
		)
	# The count is the module's own: a stripped ledger owns nothing.
	DestinyProjection.apply(actor, DestinyState.empty())
	assert_eq(DestinyProjection.modifier_count(actor), 0, "an empty ledger owns nothing")
	assert_eq(DestinyProjection.modifier_count(null), 0, "and no actor owns nothing")


func test_earning_across_many_fates_accumulates_once_each_and_strips_cleanly() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, PLEDGE, "oath")
	DestinyApi.earn_fate(actor, AWAKENED, "path")
	var stacked := DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL)
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, PLEDGE, "oath")
	assert_eq(
		DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		stacked,
		"replays stack nothing"
	)
	assert_eq(DestinyProjection.modifier_count(actor), 6, "three fates, two modifiers each")
	# An empty ledger projects nothing: the strip half of apply() is what makes
	# the rebuild half safe, and a rebuilt-from-empty ledger has nothing to keep.
	DestinyProjection.apply(actor, DestinyState.empty())
	assert_eq(DestinyProjection.modifier_count(actor), 0, "an empty ledger leaves nothing behind")
	assert_eq(actor.traits.has(DestinyState.trait_for(OATH)), false, "and no trait mirror")
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH), 150.0, "the actor is back to its base total"
	)


## Everything a projection assertion needs: the modifier sources, their count, the
## trait mirror, and the derived totals the fixture fates move.
func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"sources": _destiny_sources(actor),
		"modifiers": _destiny_modifiers(actor),
		"traits": actor.traits.to_array(),
		"defense": DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		"attack": DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL),
		"max_health": DestinyProjection.contribution(actor, Stat.MAX_HEALTH),
		"derived_defense": actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		"derived_health": actor.stats.derived(Stat.MAX_HEALTH),
	}


## Every stat-modifier source this module currently owns, sorted.
func _destiny_sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		if DestinyState.is_own_source(modifier.source):
			out.append(String(modifier.source))
	out.sort()
	return out


## How many stat modifiers this module currently owns.
func _destiny_modifiers(actor: Actor) -> int:
	return DestinyProjection.modifier_count(actor)


## The detail of every history record of one kind, in order.
func _history_kinds(ledger: Dictionary) -> Array:
	var out: Array = []
	for record in ledger["history"] as Array:
		out.append(String(record["kind"]))
	return out


func _counter_records(ledger: Dictionary) -> Array:
	var out: Array = []
	for record in ledger["history"] as Array:
		if String(record["kind"]) == "counter":
			out.append(String(record["detail"]))
	return out
