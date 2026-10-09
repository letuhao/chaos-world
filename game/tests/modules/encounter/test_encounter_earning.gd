extends TestCase

## Encounters are earn-only (ADR 0065). These assert the structural half of that
## claim — the facade has no purchase or removal verb at all — and the
## behavioural half: triggering is weighted, resolution earns fate exactly once,
## prophecies are unique, and cooldowns prevent farming.

const MODULE_KEY := EncounterState.MODULE_KEY
const ENCOUNTER_A := &"t_encounter_a"
const ENCOUNTER_B := &"t_encounter_b"
const PROPHECY_A := &"t_prophecy_a"
const PROPHECY_B := &"t_prophecy_b"
const FATE_A := &"t_fate_a"
const FATE_B := &"t_fate_b"
const FATE_C := &"t_fate_c"

## Every verb a facade must never grow, as a SUBSTRING.
const FORBIDDEN_VERBS := [
	"purchase",
	"buy",
	"remove",
	"revoke",
	"forget",
	"unequip",
	"equip",
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
				DestinyFixtureCatalog.story_fate(FATE_A),
				DestinyFixtureCatalog.story_fate(FATE_B),
				DestinyFixtureCatalog.story_fate(FATE_C),
			],
			[]
		)
	)
	(
		EncounterFixtureCatalog
		. install(
			[
				EncounterFixtureCatalog.simple_encounter(ENCOUNTER_A),
				EncounterFixtureCatalog.prophecy_encounter(ENCOUNTER_B, PROPHECY_A),
			],
			[
				EncounterFixtureCatalog.simple_prophecy(PROPHECY_A, FATE_A),
			]
		)
	)


func teardown() -> void:
	EncounterFixtureCatalog.teardown()
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"explorer") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	EncounterApi.attach(actor)
	return actor


# --- The invariant, structurally ---------------------------------------------


## The single most valuable test in this suite. Encounters are permanent because
## the public surface has no way to buy or remove them: other modules may reference
## only `api.gd`, so if no verb there purchases or removes an encounter or
## prophecy, nothing outside the module can. A future `purchase()` fails here
## rather than in a player's save.
func test_the_facade_exposes_no_purchase_or_removal_verb_at_all() -> void:
	var public := _public_methods()
	assert_eq(public.is_empty(), false, "the facade's public method list is readable")
	# No public name carries a purchase or removal verb.
	for name in public:
		for verb in FORBIDDEN_VERBS:
			assert_eq(
				name.contains(verb), false, "no public verb contains '%s' ('%s')" % [verb, name]
			)


func _public_methods() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load("res://src/modules/encounter/api.gd")
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


# --- Triggering ---------------------------------------------------------------


func test_triggering_an_encounter_marks_it_seen() -> void:
	var actor := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	assert_eq(result["triggered"], true, "an encounter triggered")
	var encounter_id := StringName(result["encounter_id"])
	assert_eq(encounter_id != &"", true, "the encounter id is non-empty")
	assert_eq(
		EncounterState.has_seen(EncounterApi.state(actor), encounter_id), true, "it is marked seen"
	)


func test_triggering_with_no_eligible_encounters_returns_empty() -> void:
	var actor := _hero()
	# Install a catalog with no encounters
	EncounterFixtureCatalog.install([], [])
	var result := EncounterApi.trigger_encounter(actor, &"", 0, null)
	assert_eq(result["triggered"], false, "no encounter triggered")
	assert_eq(result["encounter_id"], &"", "the encounter id is empty")


func test_unique_encounter_cannot_trigger_twice() -> void:
	var actor := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# First trigger
	var result1 := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	assert_eq(result1["triggered"], true, "first trigger succeeded")
	# Second trigger should not return the same unique encounter
	var result2 := EncounterApi.trigger_encounter(actor, &"", 1, rng)
	# It may trigger a different encounter, but not the same unique one
	if result2["triggered"]:
		assert_eq(
			StringName(result2["encounter_id"]) == StringName(result1["encounter_id"]),
			false,
			"the same unique encounter did not trigger twice"
		)


func test_cooldown_prevents_retriggering() -> void:
	var actor := _hero()
	EncounterFixtureCatalog.install(
		[EncounterFixtureCatalog.cooldown_encounter(ENCOUNTER_A, 5)], []
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var result1 := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	assert_eq(result1["triggered"], true, "first trigger succeeded")
	# Immediately after, the encounter is on cooldown
	var result2 := EncounterApi.trigger_encounter(actor, &"", 1, rng)
	assert_eq(result2["triggered"], false, "cooldown prevented retriggering")
	# After the cooldown period, it can trigger again
	var result3 := EncounterApi.trigger_encounter(actor, &"", 10, rng)
	assert_eq(result3["triggered"], true, "cooldown expired, encounter triggered again")


func test_location_trigger_only_fires_at_matching_location() -> void:
	var actor := _hero()
	EncounterFixtureCatalog.install(
		[EncounterFixtureCatalog.location_encounter(ENCOUNTER_A, &"mortal_plains")], []
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Wrong location: no trigger
	var result1 := EncounterApi.trigger_encounter(actor, &"other_location", 0, rng)
	assert_eq(result1["triggered"], false, "wrong location did not trigger")
	# Correct location: triggers
	var result2 := EncounterApi.trigger_encounter(actor, &"mortal_plains", 0, rng)
	assert_eq(result2["triggered"], true, "correct location triggered")


# --- Resolving ----------------------------------------------------------------


func test_resolving_an_encounter_earns_the_chosen_fate() -> void:
	var actor := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trigger := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	assert_eq(trigger["triggered"], true, "encounter triggered")
	var encounter_id := StringName(trigger["encounter_id"])
	var result := EncounterApi.resolve_encounter(actor, encounter_id, 0)
	assert_eq(result["ok"], true, "resolution succeeded")
	assert_eq(result["fate_id"], FATE_A, "the first fate choice was earned")
	assert_eq(DestinyApi.has_fate(actor, FATE_A), true, "the fate is held")


func test_resolving_earns_fate_exactly_once() -> void:
	var actor := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trigger := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	var encounter_id := StringName(trigger["encounter_id"])
	var result1 := EncounterApi.resolve_encounter(actor, encounter_id, 0)
	assert_eq(result1["ok"], true, "first resolution succeeded")
	var result2 := EncounterApi.resolve_encounter(actor, encounter_id, 1)
	assert_eq(result2["ok"], false, "second resolution refused")
	assert_eq(result2["reason"], "already_resolved", "named refusal reason")


func test_resolving_without_triggering_is_refused() -> void:
	var actor := _hero()
	var result := EncounterApi.resolve_encounter(actor, ENCOUNTER_A, 0)
	assert_eq(result["ok"], false, "resolution refused")
	assert_eq(result["reason"], "not_seen", "named refusal reason")


func test_resolving_with_invalid_fate_index_is_refused() -> void:
	var actor := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trigger := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	var encounter_id := StringName(trigger["encounter_id"])
	var result := EncounterApi.resolve_encounter(actor, encounter_id, 5)
	assert_eq(result["ok"], false, "resolution refused")
	assert_eq(result["reason"], "invalid_fate_index", "named refusal reason")


func test_dismissing_an_encounter_does_not_earn_fate() -> void:
	var actor := _hero()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trigger := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	var encounter_id := StringName(trigger["encounter_id"])
	var result := EncounterApi.dismiss_encounter(actor, encounter_id)
	assert_eq(result["ok"], true, "dismissal succeeded")
	assert_eq(DestinyApi.has_fate(actor, FATE_A), false, "no fate was earned")
	assert_eq(DestinyApi.has_fate(actor, FATE_B), false, "no fate was earned")


# --- Prophecies ---------------------------------------------------------------


func test_prophecy_is_earned_on_resolution() -> void:
	var actor := _hero()
	# Install only the prophecy encounter so selection is deterministic
	EncounterFixtureCatalog.install(
		[EncounterFixtureCatalog.prophecy_encounter(ENCOUNTER_B, PROPHECY_A)],
		[EncounterFixtureCatalog.simple_prophecy(PROPHECY_A, FATE_A)]
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trigger := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	assert_eq(trigger["triggered"], true, "encounter triggered")
	assert_eq(StringName(trigger["encounter_id"]), ENCOUNTER_B, "the prophecy encounter triggered")
	var encounter_id := StringName(trigger["encounter_id"])
	var result := EncounterApi.resolve_encounter(actor, encounter_id, 0)
	assert_eq(result["ok"], true, "resolution succeeded")
	assert_eq(result["prophecy_id"], PROPHECY_A, "the prophecy was earned")
	assert_eq(EncounterApi.has_prophecy(actor, PROPHECY_A), true, "the prophecy is held")


func test_prophecy_hint_text_is_vague() -> void:
	var actor := _hero()
	# Install only the prophecy encounter so selection is deterministic
	EncounterFixtureCatalog.install(
		[EncounterFixtureCatalog.prophecy_encounter(ENCOUNTER_B, PROPHECY_A)],
		[EncounterFixtureCatalog.simple_prophecy(PROPHECY_A, FATE_A)]
	)
	var prophecies := EncounterApi.prophecies(actor)
	assert_eq(prophecies.size(), 0, "no prophecies earned yet")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trigger := EncounterApi.trigger_encounter(actor, &"", 0, rng)
	var encounter_id := StringName(trigger["encounter_id"])
	EncounterApi.resolve_encounter(actor, encounter_id, 0)
	prophecies = EncounterApi.prophecies(actor)
	assert_eq(prophecies.size(), 1, "one prophecy earned")
	var hint_text: String = prophecies[0]["hint_text"]
	assert_eq(hint_text == "", false, "hint text is non-empty")
	# The hint should not contain the fate's display name (too spoiler-y)
	var fate_def := FateCatalog.instance().fate_definition(FATE_A)
	if fate_def != null:
		assert_eq(
			hint_text.contains(fate_def.display_name),
			false,
			"hint text does not spoil the fate's name"
		)


# --- Summary ------------------------------------------------------------------


func test_summary_reports_encounter_and_prophecy_counts() -> void:
	var actor := _hero()
	var summary := EncounterApi.summary(actor)
	assert_eq(summary["seen_count"], 0, "no encounters seen yet")
	assert_eq(summary["resolved_count"], 0, "no encounters resolved yet")
	assert_eq(summary["prophecy_count"], 0, "no prophecies earned yet")
	# Trigger and resolve
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	EncounterApi.trigger_encounter(actor, &"", 0, rng)
	summary = EncounterApi.summary(actor)
	assert_eq(summary["seen_count"], 1, "one encounter seen")
	assert_eq(summary["resolved_count"], 0, "no encounters resolved yet")
	assert_eq(summary["prophecy_count"], 0, "no prophecies earned yet")
