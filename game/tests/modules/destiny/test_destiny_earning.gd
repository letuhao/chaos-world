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
			[DestinyFixtureCatalog.plain_destiny(CHOSEN)]
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
	# 1. The public set is EXACTLY the earn-and-read surface ADR 0065 describes.
	#    Naming all twelve means an unlisted verb added later fails here instead of
	#    slipping past the word list below.
	assert_eq(
		public,
		[
			"attach",
			"counter",
			"destinies",
			"earn_destiny",
			"earn_fate",
			"fates",
			"gate",
			"has_destiny",
			"has_fate",
			"record",
			"state",
			"summary",
		],
		"the facade is the earn-and-read surface ADR 0065 describes, and nothing else"
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


## The earn-only invariant also forbids reaching past the earn verbs: a public
## method that MUTATES an entry without earning it would be a selection or a
## revoke in disguise, and the twelve-name check cannot see through a rename into
## something that reads innocently (`set_*`, `apply_*`, `grant_*`). Every public
## verb therefore has to be one this module can justify: earn, record, attach, or
## read.
func test_every_public_verb_either_earns_or_attaches_or_reads() -> void:
	var public := _public_methods()
	assert_eq(public.is_empty(), false, "the facade's public method list is readable")
	for name in public:
		var is_earn := name == "earn_fate" or name == "earn_destiny" or name == "record"
		var is_attach := name == "attach"
		var is_read := (
			name
			in [
				"counter",
				"destinies",
				"fates",
				"state",
				"summary",
				"gate",
				"has_destiny",
				"has_fate"
			]
		)
		assert_eq(is_earn or is_attach or is_read, true, "'%s' either earns or reads" % name)


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
	var entry: Dictionary = (ledger["fates"] as Dictionary)[String(OATH)]
	assert_eq(int(entry["sequence"]), 1, "the sequence is stamped exactly once")


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
	assert_eq(DestinyApi.counter(actor, DUELS), 0, "a counter that was never recorded is zero")
	assert_eq(DestinyApi.record(actor, DUELS), 1, "the first record is worth one")
	assert_eq(DestinyApi.record(actor, DUELS, 2), 3, "the second adds its amount")
	assert_eq(DestinyApi.counter(actor, DUELS), 3, "and the value is what the caller was handed")
	assert_eq(DestinyApi.counter(actor, &"never_recorded"), 0, "an untouched counter stays zero")


func test_a_counter_can_never_be_lowered() -> void:
	var actor := _hero()
	DestinyApi.record(actor, DUELS, 3)
	assert_eq(DestinyApi.record(actor, DUELS, -5), 3, "a negative amount moves nothing")
	assert_eq(DestinyApi.counter(actor, DUELS), 3, "and the counter did not fall")
	assert_eq(DestinyApi.record(actor, DUELS, 0), 3, "a zero amount moves nothing either")
	assert_eq(DestinyApi.counter(actor, DUELS), 3, "still three")
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
