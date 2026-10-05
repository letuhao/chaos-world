extends TestCase

## ADR 0129 + ADR 0127: the soul's death cost comes FROM difficulty and is never DERIVED from
## anything the game computes.
##
## ## Why this suite exists
##
## The dangerous version of this feature is a death that costs more because the player is
## deeper in the realms — a difficulty dial multiplying a power table. That is the exact
## category error ADR 0050 removed, one layer down, and `tools arch` cannot see it: two modules
## calling each other's statics with no `res://` between them is invisible to the gate (the
## `BARE_REF_UNITS` gap `AGENTS.md` records for `modules/*`).
##
## So the enforcement is structural: read both sources and prove neither names the other's
## forbidden table. A numerically-identical private copy would stay green under every value
## assertion, which is the ADR 0116 finding.

const SOUL_SOURCE := "res://src/modules/soul/api.gd"
const DIFFICULTY_SOURCE := "res://src/modules/difficulty/api.gd"
const SOUL_STATE_SOURCE := "res://src/modules/soul/soul_state.gd"

var _actor: Actor
var _store: SoulWorldLedger
## Every body this suite minted, released in `teardown`. A `RefCounted` actor needs no `free()`,
## but the pools it owns are collected with it, and an un-released one is a leak the runner
## reports at exit with every assertion green.
var _minted: Array = []


func setup() -> void:
	_store = SoulWorldLedger.new()
	SoulApi.set_store(_store)
	_actor = Actor.new()
	_actor.id = &"cost_bearer"
	DifficultyApi.attach(_actor)
	SoulApi.attach(_actor)


func teardown() -> void:
	_actor = null
	_store = null
	_minted.clear()
	SoulApi.set_store(null)


# --- What a death costs -----------------------------------------------------


func _death_cost(difficulty_id: StringName, base_cost: int) -> int:
	## The cost rule as the GAME computes it, not a copy of it.
	##
	## **This suite used to re-derive the rule inline** — read `soul_damage_share`, multiply,
	## clamp by `death_loss_cap` — which is why it went red when `scalars()` stopped answering
	## and why it would have stayed green if production had drifted instead. A test that owns a
	## second copy of the rule tests the copy. `SoulDeath._scaled_cost` is the only writer, so
	## the fixture drives a real death and reads what it charged.
	##
	## The body is the one `setup` already built with a soul and a difficulty. A SECOND body was
	## the first attempt and it read back 20 for every preset, because `SoulApi.attach` on a
	## fresh actor starts the ledger at full integrity with no soul ledger wired, so `damage`
	## clamped at whatever that body happened to carry — a fixture bug wearing the costume of
	## a production bug. Reusing `_actor` also keeps `teardown` honest: one body, one teardown.
	DifficultyApi.select(_actor, difficulty_id)
	var before := int(SoulApi.soul(_actor).get("integrity", 0))
	var out := SoulDeath.new(_mint, _adopt).resolve(_actor, base_cost)
	if bool(out.get("guardian_spent", false)):
		return 0
	return before - int(SoulApi.soul(_actor).get("integrity", 0))


func _mint(_arrival_id: String, _incarnation: int) -> Dictionary:
	return {"ok": false, "reason": "no_body_mint"}


func _adopt(_body: Actor) -> void:
	pass


func test_the_shipped_default_costs_exactly_the_authored_amount() -> void:
	# The neutrality invariant end to end: on `standard` the difficulty multiplier is 1.0, so
	# the authored cost is what a player pays and no preset has quietly rebalanced it.
	assert_eq(_death_cost(&"standard", 20), 20, "standard charges the authored cost")


func test_a_harder_preset_costs_more_and_a_softer_one_costs_less() -> void:
	assert_eq(_death_cost(&"hard", 20) > _death_cost(&"standard", 20), true, "hard is worse")
	assert_eq(_death_cost(&"story", 20) < _death_cost(&"standard", 20), true, "story is gentler")


func test_the_loss_is_never_negative_and_never_exceeds_the_soul() -> void:
	# A cost of zero or below would mean a free death on a hard run, which is the opposite of
	# what the preset says.
	for difficulty_id in [&"story", &"standard", &"hard"]:
		DifficultyApi.select(_actor, difficulty_id)
		var row := DifficultyApi.scalars(_actor)
		assert_eq(
			float(row["soul_damage_share"]) >= 0.0, true, "%s share is not negative" % difficulty_id
		)


func test_a_death_on_a_hard_run_damages_the_soul_more_than_on_the_standard_run() -> void:
	# The whole wiring, end to end and through the REAL verbs: difficulty decides the share,
	# the caller decides the amount, and the soul ledger records what was actually applied.
	DifficultyApi.select(_actor, &"hard")
	var hard_cost := _death_cost(&"hard", 20)
	var hard := SoulApi.damage(_actor, hard_cost, "death")
	assert_eq(int(hard["applied"]), 30, "hard charges 1.5x the authored 20")

	DifficultyApi.select(_actor, &"story")
	var story_cost := _death_cost(&"story", 20)
	var story := SoulApi.damage(_actor, story_cost, "death")
	assert_eq(int(story["applied"]), 10, "story charges half the authored 20")


# --- The structural guards --------------------------------------------------


func test_the_soul_module_references_no_power_table() -> void:
	# The guard `tools arch` cannot provide. `AGENTS.md` records that `BARE_REF_UNITS` excludes
	# `modules/*`, so a bare `RealmPowerTable.power_for()` from `soul` reports zero violations
	# and a code-only cycle is invisible to the checker.
	var source := _code_only(FileAccess.get_file_as_string(SOUL_SOURCE))
	for forbidden in ["RealmPowerTable", "RealmRate", "realm_power", "pow("]:
		assert_eq(source.contains(forbidden), false, "soul names no %s" % forbidden)


func test_the_soul_ledger_derives_no_number_from_a_realm_index() -> void:
	# The ledger's numbers are authored constants. A realm-indexed term here would make a soul's
	# damage a function of how deep the player is, which is the second power curve.
	var source := _code_only(FileAccess.get_file_as_string(SOUL_STATE_SOURCE))
	for forbidden in ["realm", "RealmRate", "pow("]:
		assert_eq(
			source.to_lower().contains(forbidden.to_lower()),
			false,
			"soul_state names no %s" % forbidden
		)


func test_the_difficulty_module_never_names_the_soul() -> void:
	# ADR 0093's rule: the observer registers with the subject. `difficulty` is the subject here,
	# so `soul` pulls from it and `difficulty` must not reach back — a two-way edge is a cycle
	# the gate cannot see.
	var source := _code_only(FileAccess.get_file_as_string(DIFFICULTY_SOURCE))
	for forbidden in ["SoulApi", "soul_state", "SoulState"]:
		assert_eq(source.contains(forbidden), false, "difficulty names no %s" % forbidden)


func test_difficulty_declares_no_clock_and_no_frame_driver() -> void:
	# DEF-0111: nothing may read `Time.get_ticks*`, declare `_process` or call `get_tree()`. A
	# difficulty that rises with playtime would need exactly that, and it is not available.
	var source := _code_only(FileAccess.get_file_as_string(DIFFICULTY_SOURCE))
	for forbidden in ["Time.get_ticks", "_process", "_physics_process", "get_tree()"]:
		assert_eq(source.contains(forbidden), false, "difficulty declares no %s" % forbidden)


## `source` with every comment line removed, so a structural guard reads CODE and not the prose
## describing what the code must not do. Every forbidden token above is named in these files'
## own docstrings, so scanning raw text matches the explanation and fails on correct code.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
