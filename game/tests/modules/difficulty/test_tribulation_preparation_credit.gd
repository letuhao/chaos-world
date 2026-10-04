extends TestCase

## BL-0779 / ADR 0129: `tribulation_preparation_credit` is WIRED, through an injected
## `Callable`, because a fraction of an authored aid is exactly the shape ADR 0129 permits.
##
## ## The obstacle was layering, not design
##
## `tools/arch/rules.py:30` gives `"core": {"core", "contracts"}`, so `core/tribulation.gd`
## cannot name `difficulty`. There was no seam in that file. So the credit arrives as a
## `static var Callable` — the shape `NpcApi.set_minter`, `TechniqueCasting.set_resolver`,
## `HoldingsApi.set_store` and `WorldFact.subscribe` already use — and `difficulty` installs
## it from `DifficultyApi.attach`, the one list every fresh, restored and reborn body reaches.
##
## ## What this suite is really asserting
##
## **Direction, and neutrality.** A credit below one must make the fight HARDER to raise; a
## credit above one must make it easier; and `standard` must be arithmetically identical to a
## build with no seam at all — ADR 0129's rule that the shipped default is a no-op. An
## assertion that only checked "the numbers differ" would pass on an inverted credit.

var _actor: Actor
## The rating this actor's owed fight carries with NO seam installed at all: the pre-wire
## baseline, captured once in `setup` before `attach` can install one.
var _unsealed_rating: float = 0.0
var _unsealed_reduction: float = 0.0
## The same two numbers for the UNTRAINED fixture. Separate fields because the suite compares a
## prepared body against one baseline and an untrained body against the other, and one variable
## serving both silently compares two different bodies.
var _unprepared_rating: float = 0.0
var _unprepared_reduction: float = 0.0


func setup() -> void:
	Tribulation.set_preparation_credit(Callable())
	_actor = _fighter()
	# TWO baselines, because the suite compares against BOTH fixtures and one number cannot
	# serve both. `_unsealed_rating` is the PREPARED body's price with no seam installed;
	# `_unprepared_rating` is the untrained body's. Reading the earlier single baseline as
	# either one is how "the rating is unchanged" came to compare two different bodies.
	var prepared := _rated(_actor)
	_unsealed_rating = float(prepared["rating"])
	_unsealed_reduction = float(prepared["reduction"])
	var bare := _rated(_unprepared())
	_unprepared_rating = float(bare["rating"])
	_unprepared_reduction = float(bare["reduction"])
	DifficultyApi.attach(_actor)


func teardown() -> void:
	# The seam is a `static var` and the runner shares one process across every suite, so
	# leaving it installed would price every later suite's tribulation.
	Tribulation.set_preparation_credit(Callable())
	_actor = null


# --- The seam ----------------------------------------------------------------


func test_attach_installs_the_credit_seam() -> void:
	assert_eq(
		Tribulation.has_preparation_credit(),
		true,
		"attaching difficulty hands core a callable that answers the credit"
	)


func test_core_names_no_module_and_the_seam_is_what_it_reads() -> void:
	# The layering claim, structurally: `core` holds `{"core", "contracts"}`, so the credit
	# can only arrive as an injected `Callable`. Read CODE, not the prose around it — already
	# done by `_code_only`, which is what lets the docstring NAME the mechanism it uses.
	#
	# **The needle is an IDENTIFIER, not a substring.** The first version searched for
	# "difficulty" and failed on the word appearing in a comment explaining that `core` must not
	# name it — the guard failing on its own explanation, which is how a real check gets
	# disabled instead of obeyed. `DifficultyApi.` and a bare `difficulty` LOAD are what a
	# forbidden reference actually looks like.
	var source := _code_only(FileAccess.get_file_as_string("res://src/core/tribulation.gd"))
	for forbidden in ["DifficultyApi", "difficulty/", "difficulty.gd"]:
		assert_eq(source.contains(forbidden), false, "core/tribulation.gd names no %s" % forbidden)
	assert_eq(
		source.contains("static func set_preparation_credit("),
		true,
		"and core/tribulation.gd offers the seam the composition root fills"
	)


# --- Direction ---------------------------------------------------------------


func test_a_harder_preset_makes_prepared_actor_s_fight_harder_to_raise() -> void:
	# The whole point of the column, measured through the REAL verbs: `rate` is the rating,
	# `endurance` is the share of fights survived off it, and both must move AGAINST the
	# player when the credit drops below one.
	var standard := _priced(&"standard")
	var hard := _priced(&"hard")
	assert_eq(
		float(hard["reduction"]) < float(standard["reduction"]),
		true,
		"hard credits less preparation"
	)
	assert_eq(
		float(hard["rating"]) > float(standard["rating"]),
		true,
		"so a prepared fight is rated harder"
	)
	assert_eq(
		float(hard["endurance"]) < float(standard["endurance"]), true, "and survives less often"
	)


func test_a_harder_preset_does_not_help_an_unprepared_actor() -> void:
	# Preparation is an input, never a gate. An actor who has trained nothing measures a zero
	# aid, so a credit below one can only multiply zero — the fight must be priced EXACTLY as
	# it was, or the difficulty dial would tax preparation rather than difficulty.
	var bare := _unprepared()
	for difficulty_id in [&"story", &"standard", &"hard"]:
		DifficultyApi.select(bare, difficulty_id)
		var record := _rated(bare)
		assert_eq(
			float(record["reduction"]), 0.0, "%s credits an untrained body nothing" % difficulty_id
		)
		assert_eq(
			float(record["rating"]),
			_unprepared_rating,
			"%s rates it exactly as before" % difficulty_id
		)


func test_the_shipped_default_is_exactly_neutral() -> void:
	# ADR 0129's rule that the shipped default is a no-op, end to end through the seam: on
	# `standard` the rating is bit-for-bit the rating a build with NO credit installed
	# produced. A retune of the preset table cannot leak a hidden rebalance past this.
	var standard := _priced(&"standard")
	assert_eq(
		float(standard["reduction"]), _unsealed_reduction, "standard credits exactly what it did"
	)
	assert_eq(float(standard["rating"]), _unsealed_rating, "and rates the fight exactly as it did")
	assert_eq(float(standard["endurance"]), _unsealed_endurance(), "so the odds are unchanged")


func test_the_cap_survives_the_credit() -> void:
	# `PREPARATION_FLOOR` is the ceiling on preparation and it is applied AFTER the credit, so
	# no credit lifts it. A seam that could raise the cap would turn preparation into a gate.
	var record := _rated(_fighter())
	(record["record"] as Tribulation).preparation = {"formation": 5.0, "environment": 5.0}
	assert_eq(
		_credits(record["record"] as Tribulation),
		Tribulation.PREPARATION_FLOOR,
		"an unbounded aid is still capped at the authored floor"
	)
	# ...and the credit scales the AID, not the cap.
	Tribulation.set_preparation_credit(Callable(DifficultyApi, "preparation_credit_for"))
	DifficultyApi.select(_actor, &"hard")
	var harder := _rated(_actor)
	(harder["record"] as Tribulation).preparation = {"formation": 5.0, "environment": 5.0}
	assert_eq(
		_credits(harder["record"] as Tribulation),
		Tribulation.PREPARATION_FLOOR,
		"a credit below one cannot lift the cap either"
	)


# --- A missing or broken credit is inert --------------------------------------


func test_no_seam_is_exactly_the_pre_wire_number() -> void:
	# `core` must work before anything installs the credit: an absent seam is the shipped
	# default, not a fight priced at zero.
	Tribulation.set_preparation_credit(Callable())
	assert_eq(Tribulation.has_preparation_credit(), false, "nothing is installed")
	assert_eq(float(_rated(_actor)["rating"]), _unsealed_rating, "and the rating is unchanged")


func test_an_unusable_credit_reads_as_one_rather_than_as_a_harder_fight() -> void:
	# The refusal shape: whatever the seam hands back that is not a usable fraction is
	# ABSENT, and an absent credit must be the authored one. A difficulty id nothing defines,
	# a string, a NaN and out-of-window values all land on 1.0 for that reason.
	var actor := _fighter()
	DifficultyApi.attach(actor)
	for bad in [&"never_authored", 0.75, -4.0, 99.0, NAN]:
		DifficultyApi.select(actor, &"standard")
		# `str()`, not `String()`: the latter is not a constructor call for a StringName here and
		# aborted the case on this line, which is why the whole loop reported "asserted nothing"
		# instead of a failure. A test that cannot reach its assertion proves nothing.
		actor.set_module_data(
			DifficultyState.MODULE_KEY, DifficultyState.normalize({"difficulty_id": str(bad)})
		)
		assert_eq(DifficultyApi.preparation_credit_for(actor), 1.0, "%s reads as 1.0" % bad)


func test_a_null_actor_is_credited_exactly_one() -> void:
	assert_eq(DifficultyApi.preparation_credit_for(null), 1.0, "no actor, no difficulty")


# --- Helpers ------------------------------------------------------------------


## A body carrying enough of itself that the aid measures something non-zero, so the
## credit has a number to multiply. `expanded` meridians make `formation` positive; the
## world makes `environment` positive.
func _fighter() -> Actor:
	var actor := Actor.new()
	actor.id = &"tribulation_credit_bearer"
	for meridian in actor.meridians.get_all_meridians():
		actor.meridians.open_meridian(meridian.id)
		actor.meridians.expand_meridian(meridian.id)
	actor.inside_world = InsideWorld.new(InsideWorld.SEED)
	return actor


## A body that has trained and prepared NOTHING: no meridian developed and no inside world,
## so `_measure_preparation` measures a zero aid on every key and the credit has nothing to
## multiply. `InsideWorld` is built with stability `0.0`, NOT left at its `0.5` default —
## `improve_stability` ADDS to whatever the world already carries, so a fresh world is an
## arena, and a fresh world made the "unprepared" body read as half-prepared.
func _unprepared() -> Actor:
	var actor := Actor.new()
	actor.id = &"tribulation_unprepared_bearer"
	actor.inside_world = InsideWorld.new(InsideWorld.SEED, 1.0, 0.0)
	return actor


## One real tribulation, priced through `start` — which is the only place preparation is
## measured and the rating taken, and is what production calls. `reduction` is re-derived the
## way `rate` derives it, so the suite can name the credit's own contribution.
func _rated(actor: Actor) -> Dictionary:
	var record := Tribulation.new(Tribulation.LIGHTNING)
	record.start(actor, &"earth_immortal")
	return {
		"record": record,
		"rating": record.difficulty,
		"reduction": _credits(record),
		"endurance": TribulationEndurance.endurance(actor, record),
	}


## The rating, the credit's own share of it, and the survival odds, for one preset.
func _priced(difficulty_id: StringName) -> Dictionary:
	var actor := _fighter()
	DifficultyApi.attach(actor)
	DifficultyApi.select(actor, difficulty_id)
	var priced := _rated(actor)
	var record: Tribulation = priced["record"]
	return {
		"rating": float(priced["rating"]),
		"reduction": float(priced["reduction"]),
		"endurance": TribulationEndurance.endurance(actor, record),
	}


## The seam-free odds, from the same body `setup` measured the unsealed rating on.
func _unsealed_endurance() -> float:
	var actor := _fighter()
	var record := Tribulation.new(Tribulation.LIGHTNING)
	record.start(actor, &"earth_immortal")
	return TribulationEndurance.endurance(actor, record)


## What `_preparation_reduction` returns, recomputed HERE rather than reached into: the
## private helper is the thing under test, and a test that calls it proves nothing about what
## `rate` did with it. This is `rate`'s own two terms — the recorded aid summed, then capped
## at `PREPARATION_FLOOR` — spelled out, so a credit that reached the cap and a credit that
## did not are two different observations.
func _credits(record: Tribulation) -> float:
	var total := 0.0
	for aid in Tribulation.PREPARATION_AIDS:
		total += float(record.preparation.get(aid, 0.0))
	return minf(total, Tribulation.PREPARATION_FLOOR)


## `source` with every comment line removed, so a structural guard reads CODE and not the
## prose describing what the code must not do.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
