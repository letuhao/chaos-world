extends TestCase

## ADR 0129: difficulty scales a fraction of what is carried, never a magnitude the game
## computes.
##
## ## The invariants that matter most
##
## **The shipped default is exactly 1.0 on every scalar.** If it were not, choosing the middle
## option would silently retune every number in the game, and nothing would fail. This is the
## "R1 at exactly 1.0" rule of the realm power table applied to a preset axis.
##
## **An unknown preset resolves to the neutral row, never to a zero.** A difficulty that reads
## as absent must not delete a player's numbers — it must be inert.

var _actor: Actor


func setup() -> void:
	_actor = Actor.new()
	_actor.id = &"difficulty_bearer"
	DifficultyApi.attach(_actor)


# --- Selection --------------------------------------------------------------


func test_an_actor_with_no_choice_reads_the_neutral_preset() -> void:
	# An old save with no difficulty key must resolve to the shipped baseline, not to the
	# easiest setting: a save that cannot say what it was playing under still has to be a
	# fair fight.
	assert_eq(
		String(DifficultyApi.current_id(_actor)),
		String(DifficultyTable.NEUTRAL),
		"no choice reads as the shipped baseline"
	)


func test_select_refuses_an_unknown_preset_by_name_rather_than_silently_accepting_it() -> void:
	var out := DifficultyApi.select(_actor, &"nightmare")
	assert_eq(bool(out["ok"]), false, "an unauthored preset is refused")
	assert_eq(String(out["reason"]), "unknown_difficulty", "the refusal is named")
	assert_eq(
		String(DifficultyApi.current_id(_actor)),
		String(DifficultyTable.NEUTRAL),
		"a refused select leaves the run where it was"
	)


func test_select_persists_through_an_actor_round_trip() -> void:
	# The id is the only thing stored, so a save remembers what it was playing under without
	# freezing today's numbers into an old file.
	DifficultyApi.select(_actor, &"hard")
	var restored := Actor.from_dict(_actor.to_dict())
	DifficultyApi.attach(restored)
	assert_eq(String(DifficultyApi.current_id(restored)), "hard", "the choice survives a save")


func test_attach_is_idempotent() -> void:
	DifficultyApi.attach(_actor)
	DifficultyApi.attach(_actor)
	assert_eq(
		String(DifficultyApi.current_id(_actor)),
		String(DifficultyTable.NEUTRAL),
		"two attaches leave one selection"
	)


# --- The scalars ------------------------------------------------------------


func test_the_shipped_default_is_the_neutral_baseline_on_every_scalar() -> void:
	# The whole reason the default row exists: selecting it is arithmetically a no-op.
	for scalar in DifficultyTable.SCALARS:
		assert_eq(float(DifficultyApi.scalars(_actor)[scalar]), 1.0, "%s is neutral" % scalar)


func test_a_harder_preset_costs_more_and_a_softer_one_costs_less() -> void:
	var neutral := float(DifficultyApi.scalars(_actor)["soul_damage_share"])
	DifficultyApi.select(_actor, &"hard")
	var hard := float(DifficultyApi.scalars(_actor)["soul_damage_share"])
	DifficultyApi.select(_actor, &"story")
	var story := float(DifficultyApi.scalars(_actor)["soul_damage_share"])
	assert_eq(hard > neutral, true, "hard costs more than standard")
	assert_eq(story < neutral, true, "story costs less than standard")


func test_an_unknown_id_reads_neutral_rather_than_a_zero() -> void:
	# Reached through the catalog rather than through `select`, because `select` refuses an
	# unknown id. A zero here would delete the player's numbers instead of leaving them alone.
	var row := DifficultyCatalog.instance().scalars_for(&"never_authored")
	assert_eq(float(row["soul_damage_share"]), 1.0, "an unknown preset is inert, not zero")


func test_the_scalar_set_is_closed_so_a_fifth_column_cannot_appear_silently() -> void:
	# A fifth scalar would be a fourth power curve wearing a difficulty label (ADR 0050). The
	# set shrank from five to four (BL-0779): `loot_ceiling` was cut because a `LootTier` is
	# ORDINAL, and the fourth that remains is wired to `Tribulation` through an injected
	# Callable so `core` need not name `difficulty`.
	var expected := [
		"soul_damage_share",
		"death_loss_cap",
		"guardian_effectiveness",
		"tribulation_preparation_credit",
	]
	assert_eq(DifficultyTable.SCALARS.size(), expected.size(), "exactly four scalars")
	for scalar in expected:
		assert_eq(DifficultyTable.SCALARS.has(scalar), true, "%s is in the set" % scalar)
	assert_eq(
		DifficultyTable.SCALARS.has("loot_ceiling"),
		false,
		"a cut scalar cannot reappear in the vocabulary"
	)


func test_no_scalar_is_left_authored_with_nothing_reading_it() -> void:
	# ADR 0129's rule that a scalar with no consumer is REMOVED, not left authored: a column
	# nobody reads is a preset that changes nothing a player can observe (BL-0779). This reads
	# the shipped module sources and fails if any scalar in the closed set is named nowhere but
	# in `difficulty`'s own table — the measurement that classified BL-0779 vacuous.
	var sources := {
		"soul_damage_share": "res://src/app/soul_death.gd",
		"death_loss_cap": "res://src/app/soul_death.gd",
		"guardian_effectiveness": "res://src/app/soul_death.gd",
		"tribulation_preparation_credit": "res://src/modules/difficulty/api.gd",
	}
	for scalar in DifficultyTable.SCALARS:
		assert_eq(sources.has(scalar), true, "%s names the file that consumes it" % scalar)
		var consumer := String(sources[scalar])
		assert_eq(
			_code_only(FileAccess.get_file_as_string(consumer)).contains(scalar),
			true,
			"%s is read by %s" % [scalar, consumer]
		)


func test_scalars_is_empty_without_an_actor_rather_than_defaulting() -> void:
	# `{}` is the UI standard's answer for "no actor", and a row of 1.0s for a null actor
	# would let a caller scale against a player who does not exist.
	assert_eq(DifficultyApi.scalars(null), {}, "no actor, no scalars")


# --- Content ----------------------------------------------------------------


func test_the_authored_table_is_shaped_correctly() -> void:
	assert_eq(DifficultyApi.validate(), [], "every preset carries every bounded scalar")


func test_the_authored_table_has_no_scalar_named_after_a_realm() -> void:
	# The same category error ADR 0050 removed, one layer down: a difficulty that scales by
	# how deep the player is has become a second power curve.
	var rows := DifficultyCatalog.instance().rows()
	for difficulty_id in rows.keys():
		for key in (rows[difficulty_id] as Dictionary).keys():
			var name := String(key).to_lower()
			assert_eq(
				name.contains("realm") or name.contains("tier") or name.contains("ordinal"),
				false,
				"%s carries a realm-shaped column %s" % [difficulty_id, key]
			)


func test_no_difficulty_column_is_named_after_a_power_table() -> void:
	# Structural: difficulty must never grow a reference to a power-shaped table, because
	# scaling one by the other is the second curve ADR 0050 forbids. `tools arch` cannot see a
	# module-to-module call with no `res://` in it, so this reads the source.
	#
	# Read from CODE: this file's own docstring names the very tables the guard forbids, so
	# scanning raw text matches the prose and fails on correct code.
	var source := _code_only(FileAccess.get_file_as_string("res://src/modules/difficulty/api.gd"))
	for forbidden in ["RealmPowerTable", "RealmRate", "realm_power", "pow("]:
		assert_eq(source.contains(forbidden), false, "difficulty names no %s" % forbidden)


## `source` with every comment line removed, so a structural guard reads CODE and not the prose
## describing what the code must not do.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
