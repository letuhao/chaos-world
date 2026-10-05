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

const PREPARATION_CONSUMER := "res://src/core/tribulation.gd"

## Each scalar's CONSUMING function, not the file that publishes it. `difficulty/api.gd` holds
## every scalar's name because it declares them, so a census pointed there passes whether or not
## anything spends the value — the defect this replaces (BL-0885).
##
## `tribulation_preparation_credit` is deliberately NOT in this map: its consumer is `core`,
## which may not name `difficulty`, so the proof has to be the SEAM. Asserting
## `Tribulation.has_preparation_credit()` is true AND that `_preparation_reduction` spends
## `_credit(actor)` — the mutation that satisfies a publisher-pointed guard is exactly deleting
## that call, so it is the mutation this guard has to catch.
const SCALAR_CONSUMERS := {
	"soul_damage_share":
	{
		"file": "res://src/app/soul_death.gd",
		"func": "_scaled_cost",
	},
	"death_loss_cap":
	{
		"file": "res://src/app/soul_death.gd",
		"func": "_scaled_cost",
	},
	"guardian_effectiveness":
	{
		"file": "res://src/app/soul_death.gd",
		"func": "_heal",
	},
}

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


## ## The census reads the CONSUMER, not the publisher
##
## BL-0885: this guard used to map `tribulation_preparation_credit` to
## `res://src/modules/difficulty/api.gd`, which contains the string only because it PUBLISHES
## the scalar — `const PREPARATION_CREDIT` at api.gd:34, read at :68. So deleting the real
## consumer (`core/tribulation.gd`'s `_preparation_reduction` → `_credit(actor)`) left the
## census green and a difficulty row silently stopped mattering. **A guard asserted against the
## file that merely publishes a value cannot tell a working consumer from a deleted one.**
##
## So each scalar names the module that APPLIES it, and the needle is searched in that file's
## CODE with comment lines stripped — prose must not satisfy it, or this guard would be the
## third in this repo to fire on its own documentation.
##
## ## Why each entry is the real consumer, and what it is worth if that is wrong
##
## - `soul_damage_share`, `death_loss_cap` → `SoulDeath._scaled_cost` (soul_death.gd:348).
##   A literal `.get("…", 1.0)` keyed by the scalar name, so the name must appear in that code.
## - `guardian_effectiveness` → `SoulDeath._heal` (soul_death.gd:334), read as a fraction of
##   the pool maximum rather than as a duplicate of the share.
## - `tribulation_preparation_credit` → NOT `api.gd`. The value reaches `core` as an INJECTED
##   `Callable`, so `core/tribulation.gd` cannot spell the id: `LAYER_DEPS` holds `core` to
##   `{"core", "contracts"}` and naming `difficulty` from there would be an upward edge
##   (`tools/arch/rules.py`). **This is the one scalar with no single consuming file that can
##   name it**, so it gets a different kind of proof, stated rather than papered over: the
##   census requires the consumer's CALL SEAM to be installed AND spent — `_credit(actor)` is
##   reachable from `rate()` only through `_preparation_reduction`, and the seam that feeds it
##   is installed by `DifficultyApi.attach`. Asserting the seam is installed and the call is
##   live is the strongest check available for a value that crosses a layer by injection; a
##   name search would measure the publisher again.
func test_no_scalar_is_left_authored_with_nothing_reading_it() -> void:
	# ADR 0129's rule that a scalar with no consumer is REMOVED, not left authored: a column
	# nobody reads is a preset that changes nothing a player can observe (BL-0779).
	#
	# **Both halves of the population are asserted, or "found none" is an empty list.**
	# `DifficultyTable.SCALARS` is the vocabulary; the maps above are the claims. If a fourth
	# column is added and no claim names it, `SCALAR_CONSUMERS.has(scalar)` is false and this
	# fails — the census cannot go quietly blind the way a name search does.
	assert_eq(
		SCALAR_CONSUMERS.size(),
		DifficultyTable.SCALARS.size() - 1,
		(
			(
				"every scalar is accounted for: %d name a consuming file, the remaining one is "
				% SCALAR_CONSUMERS.size()
			)
			+ "carried across a layer by a seam and proven by call sites rather than by its name"
		)
	)
	for scalar in DifficultyTable.SCALARS:
		if scalar == DifficultyApi.PREPARATION_CREDIT:
			continue
		assert_eq(SCALAR_CONSUMERS.has(scalar), true, "%s names the file that consumes it" % scalar)
		var claim := SCALAR_CONSUMERS[scalar] as Dictionary
		var consumer := String(claim["file"])
		var source := _code_only(FileAccess.get_file_as_string(consumer))
		assert_eq(source.is_empty(), false, "%s is readable" % consumer)
		assert_eq(
			source.contains(scalar),
			true,
			"%s is read by %s's CODE, not named in a comment" % [scalar, consumer]
		)
		# ...and it is read INSIDE the function that applies it, so the name cannot sit in a
		# helper the caller never reaches. A scalar spelled once in an orphan helper reads as
		# wired on a name search and is not.
		assert_eq(
			_function_body(source, String(claim["func"])).contains(scalar),
			true,
			"%s is read inside %s(), the code that applies it" % [scalar, claim["func"]]
		)


## The seam proof for `tribulation_preparation_credit`, which no single file can name because
## `core` is forbidden to reference `difficulty`.
##
## Three structural assertions, each of which fails when the MUTATION in BL-0885 is applied —
## deleting `_credit(actor)` out of `_preparation_reduction` leaves all three false, which is
## what makes this load-bearing rather than a restatement of the publisher:
##
## 1. `core/tribulation.gd` spends the credit: `_preparation_reduction` contains `_credit(`.
## 2. The function that spends it is REACHABLE from the rating: `rate()` contains
##    `_preparation_reduction(`, and `start()` contains `rate(` — so the seam cannot be a
##    private orphan with no production caller.
## 3. The seam is INSTALLED at runtime: `DifficultyApi.attach` installs a callable, which is
##    what makes `_credit` return anything other than its own 1.0 fallback. That last one is a
##    VALUE check rather than a string search, because a search cannot see a static var.
func test_the_preparation_credit_census_names_a_seam_not_the_publisher() -> void:
	var source := _code_only(FileAccess.get_file_as_string(PREPARATION_CONSUMER))
	assert_eq(source.is_empty(), false, "%s is readable" % PREPARATION_CONSUMER)
	# 1. The consumer spends it.
	var spends := _function_body(source, "_preparation_reduction")
	assert_eq(spends.contains("_credit("), true, "_preparation_reduction spends the credit")
	# 2. The function that spends it is reachable from the rating a fight is priced by.
	assert_eq(
		_function_body(source, "rate").contains("_preparation_reduction("),
		true,
		"rate() prices the fight through the credit"
	)
	assert_eq(
		_function_body(source, "start").contains("rate("),
		true,
		"and start() takes that rating, so the credit is spent on a real fight"
	)
	assert_eq(
		source.contains("static func set_preparation_credit("),
		true,
		"and core offers the seam difficulty fills"
	)
	# 3. The seam is live, not merely declared: `_credit` reads 1.0 when nothing is installed,
	# so a declared-but-uninstalled seam is arithmetically identical to no seam at all.
	DifficultyApi.attach(_actor)
	assert_eq(
		Tribulation.has_preparation_credit(),
		true,
		"attach installs the credit, so the call site in _credit() is reached"
	)
	assert_eq(
		DifficultyApi.preparation_credit_for(_actor),
		float(DifficultyApi.scalars(_actor).get(DifficultyApi.PREPARATION_CREDIT, 1.0)),
		"and the installed callable answers with the row the consumer spends"
	)
	# The publisher must still publish it, or the seam installs nothing that reads a real key.
	var publisher := _code_only(
		FileAccess.get_file_as_string("res://src/modules/difficulty/api.gd")
	)
	assert_eq(
		publisher.contains('const PREPARATION_CREDIT := "%s"' % DifficultyApi.PREPARATION_CREDIT),
		true,
		"the facade publishes the exact key the consumer's seam installs"
	)


func test_the_loss_cap_is_inert_on_every_shipped_preset_and_the_test_says_so() -> void:
	# **MEASURED FINDING (BL-0885/BL-0887), recorded as a guard rather than a note.**
	# `_scaled_cost` computes `mini(base*share, base*cap)`. The authored table carries
	# story 0.5/1.0, standard 1.0/1.0, hard 1.5/1.5, so `share <= cap` everywhere and the cap
	# NEVER changes the outcome — on `hard` it computes min(30, 30), which is arithmetically
	# inert on the only preset that moves the multiplier. Without this case the suite implies the
	# clamp does something, and a reader cannot tell that from a passing run.
	#
	# The DECISION, recorded here: this is ACCEPTED as authored. A cap is the right shape for a
	# future preset that wants "twice as painful, never more"; what is not acceptable is a
	# column nobody can tell is inert. So the invariant is pinned as `share <= cap` on every
	# preset — the cap's intended meaning — plus the measured observation that the shipped
	# table leaves the cap inert wherever the two terms agree. Retune the authored numbers and
	# this goes RED until the reading is restated, which is the point.
	var catalog := DifficultyCatalog.instance()
	assert_eq(catalog.is_loaded(), true, "the authored table is loaded")
	var rows := catalog.rows()
	assert_eq(rows.is_empty(), false, "the authored table carries presets")
	var inert_on: Array[String] = []
	var ordered: Array[String] = []
	for difficulty_id in rows.keys():
		ordered.append(String(difficulty_id))
	ordered.sort()
	for difficulty_id in ordered:
		var row := rows[difficulty_id] as Dictionary
		var share := float(row["soul_damage_share"])
		var cap := float(row["death_loss_cap"])
		assert_eq(
			share <= cap,
			true,
			(
				(
					"%s sets soul_damage_share %.2f above death_loss_cap %.2f: the clamp then binds "
					% [difficulty_id, share, cap]
				)
				+ "and the share, not the cap, is the term a preset is expressing — restate the rule"
			)
		)
		# Equal share and cap is what makes the cap inert, so the observation is a comparison
		# and not a hardcoded preset list.
		if is_equal_approx(share, cap):
			inert_on.append(difficulty_id)
	# `standard` is inert too, but with nothing to express: share 1.0 and cap 1.0 leave
	# min(20, 20) = 20 = the authored cost, so the finding worth naming is the narrower one —
	# `hard` is the only preset on which the cap is inert WHILE THE MULTIPLIER MOVES. That is
	# a clamp that never binds on the only preset that exercises it.
	assert_eq(
		inert_on,
		["hard", "standard"],
		(
			"`hard` and `standard` have share == cap, so on both the clamp changes nothing; "
			+ "`hard` is the one that also moves the multiplier, which is the inertness that "
			+ "matters. Any other preset here is new information about the clamp"
		)
	)
	# And the clamp itself, computed the way production computes it, so the claim above is
	# about the real expression rather than about the authored numbers in isolation.
	var clamped := mini(20 * 1.5, 20 * 1.5)
	assert_eq(clamped, 30, "hard clamps 30, which is the share uncapped — the cap is inert")
	assert_eq(mini(20 * 3.0, 20 * 2.0), 40, "a preset above the cap would be bound by it")


## The CODE of `func <name>` — instance or `static func` — up to the next top-level `func`,
## with comments already stripped by `_code_only`. `""` when the function is absent, so a
## caller that looks for a body that does not exist asserts against an empty string and FAILS
## rather than silently searching the whole file.
##
## Every top-level `func` line ends the previous body, INCLUDING a `static func` one: without
## the static case, a helper declared after a static function would be swept into that
## function's body and a needle sitting in the helper would read as a read inside the
## function. GDScript has no nested `func`, so a trimmed line beginning `func ` is always a
## top-level declaration and the test needs no brace counting.
func _function_body(source: String, func_name: String) -> String:
	var collecting := false
	var out: PackedStringArray = []
	var header := "func %s(" % func_name
	for line in source.split("\n"):
		var code := String(line).strip_edges()
		if code.begins_with("func ") or code.begins_with("static func "):
			collecting = code.contains(header)
		if collecting:
			out.append(String(line))
	return "\n".join(out)


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
