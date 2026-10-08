extends TestCase

## Fate-triggered difficulty events (ADR 0404). The yin-yang counterpart to a
## fate advantage: every +power fate declares a +difficulty event, and the
## engine computes the total modifier from all held fates.

const OATH := &"t_oath_breaker"
const PLEDGE := &"t_blood_pledge"
const AWAKENED := &"t_awakened"
const WHISPER := &"t_whisper"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.fated_fate(
					OATH, Stat.ATTACK_PHYSICAL, 5.0, &"enemy_spawn", 0.5
				),
				DestinyFixtureCatalog.fated_fate(
					PLEDGE, Stat.DEFENSE_PHYSICAL, 3.0, &"combat_difficulty", 0.3
				),
				DestinyFixtureCatalog.fated_fate(
					AWAKENED, Stat.MAX_HEALTH, 25.0, &"social_difficulty", 0.2
				),
				DestinyFixtureCatalog.story_fate(WHISPER),
			],
			[]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


# --- The yin-yang pairing gate -------------------------------------------------


## Every fate with positive stat modifiers MUST declare at least one difficulty
## event. A fate with no modifiers needs no event. This is the yin-yang rule:
## every advantage carries its counterpart.
func test_every_fate_with_modifiers_declares_a_difficulty_event() -> void:
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		if def.has_modifiers() or def.has_probability_modifiers():
			assert_eq(
				def.has_difficulty_events(),
				true,
				"fate '%s' grants power but declares no difficulty event (ADR 0404)" % fate_id
			)


## A fate with no modifiers needs no difficulty event. Pure-narrative fates are
## legitimate.
func test_a_fate_with_no_modifiers_needs_no_difficulty_event() -> void:
	var def := DestinyFixtureCatalog.story_fate(WHISPER)
	assert_eq(def.has_modifiers(), false, "the fixture fate grants nothing")
	assert_eq(def.has_difficulty_events(), false, "and declares no event")


# --- The difficulty event engine -----------------------------------------------


## The engine returns an empty array when no fate is held.
func test_no_fate_held_means_no_difficulty_events() -> void:
	var actor := _hero()
	assert_eq(DestinyApi.difficulty_events(actor), [], "no fate, no events")
	assert_eq(DestinyApi.difficulty_modifier(actor), {}, "no fate, no modifier")


## Earning a fate activates its difficulty events.
func test_earning_a_fate_activates_its_difficulty_events() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	var events := DestinyApi.difficulty_events(actor)
	assert_eq(events.size(), 1, "one event from one fate")
	assert_eq(String(events[0]["event_type"]), "enemy_spawn", "the event type")
	assert_eq(float(events[0]["magnitude"]), 0.5, "the magnitude")
	assert_eq(String(events[0]["fate_id"]), String(OATH), "the source fate")


## The modifier is the sum of all held fates' events for that type.
func test_modifier_sums_across_held_fates() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_fate(actor, PLEDGE, "oath")
	DestinyApi.earn_fate(actor, AWAKENED, "path")
	var modifier := DestinyApi.difficulty_modifier(actor)
	assert_eq(float(modifier.get("enemy_spawn", 0.0)), 0.5, "one enemy_spawn event")
	assert_eq(float(modifier.get("combat_difficulty", 0.0)), 0.3, "one combat_difficulty event")
	assert_eq(float(modifier.get("social_difficulty", 0.0)), 0.2, "one social_difficulty event")


## A fate with no difficulty events contributes nothing to the modifier.
func test_a_fate_with_no_events_contributes_nothing() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, WHISPER, "story")
	assert_eq(DestinyApi.difficulty_events(actor), [], "no events")
	assert_eq(DestinyApi.difficulty_modifier(actor), {}, "no modifier")


## The engine is a pure read: calling it twice returns the same result.
func test_the_engine_is_a_pure_read() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	var first := DestinyApi.difficulty_modifier(actor)
	var second := DestinyApi.difficulty_modifier(actor)
	assert_eq(first, second, "the modifier is deterministic")


## The engine reads from the ledger, so a re-attach reproduces the same result.
func test_the_engine_reads_from_the_ledger() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	var before := DestinyApi.difficulty_modifier(actor)
	# Re-attach: the ledger is the source of truth, not the engine.
	DestinyApi.attach(actor)
	var after := DestinyApi.difficulty_modifier(actor)
	assert_eq(before, after, "the modifier survives a re-attach")


# --- The earn-only invariant ---------------------------------------------------


## Difficulty events are earned, not selected. There is no verb to remove or
## deactivate them. The facade exposes only reads.
func test_difficulty_events_are_earned_not_selected() -> void:
	var public := _public_methods()
	for name in public:
		for verb in ["remove", "revoke", "deactivate", "clear", "reset"]:
			assert_eq(
				name.contains(verb), false, "no public verb contains '%s' ('%s')" % [verb, name]
			)


## Earning the same fate twice does not double the difficulty modifier.
func test_earning_the_same_fate_twice_does_not_double_the_modifier() -> void:
	var actor := _hero()
	DestinyApi.earn_fate(actor, OATH, "combat")
	var first := DestinyApi.difficulty_modifier(actor)
	DestinyApi.earn_fate(actor, OATH, "combat")
	var second := DestinyApi.difficulty_modifier(actor)
	assert_eq(first, second, "the modifier is exactly-once")


# --- Internals -----------------------------------------------------------------


func _public_methods() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load("res://src/modules/destiny/api.gd")
	if script == null:
		return out
	for line in script.source_code.split("\n"):
		if not line.begins_with("static func "):
			continue
		var name := line.substr("static func ".length())
		name = name.substr(0, name.find("(")).strip_edges()
		if name.begins_with("_"):
			continue
		out.append(name)
	out.sort()
	return out
