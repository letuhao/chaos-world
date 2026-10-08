extends TestCase

## `StatPresenter` is where a stat id becomes something a player reads: its label
## and its precision.
##
## The defect these tests exist for: `StatRow` defaulted to zero decimals, so
## `acupoint_quality = 0.5` printed as `1` and `breakthrough_chance = 0.2` printed
## as `0`. A figure that is *wrong* is worse than one that is missing, because the
## player cannot tell it is wrong -- and the suite was green throughout, since every
## test then asked "is this row present?" rather than "is this row true?".
##
## So the load-bearing claim tested here is not "a row exists" but "the text a row
## prints is the number it holds". Every assertion below is written to fail loudly
## on a wrong figure, not merely on a missing one.

## Every id whose value is a fraction or a multiplier, and which therefore must not
## be printed as a bare integer. This is a literal on purpose: the point of the
## table is that a module id cannot be silently absent from it, and a test written
## in terms of the table could not catch the table losing an entry.
const FRACTION_IDS: Array[StringName] = [
	&"acupoint_quality",
	&"attack_speed",
	&"breakthrough_chance",
	&"cooldown_reduction",
	&"crit_chance",
	&"crit_damage",
	&"crit_resist",
	&"crit_resist_damage",
	&"cultivation_rate",
	&"dantian_quality",
	&"damage_reduction",
	&"evasion",
	&"insight_gain",
	&"loot_bonus",
	&"qi_cost_reduction",
	&"sea_turbulence",
	&"status_defense",
]

## Ids that are a 0-or-1 state dressed as a float, and so are whole numbers by
## construction. `dantian_full` and `sea_full` are the pair that caught this test
## over-reaching: they are flags, `0.0` and `1.0`, and rounding them changes
## nothing -- demanding decimals of them would have been the defect, not the fix.
const FLAG_IDS: Array[StringName] = [&"dantian_full", &"sea_full"]

# --- Precision --------------------------------------------------------------


func test_a_fraction_stat_is_never_printed_as_a_bare_integer() -> void:
	for id in FRACTION_IDS:
		var decimals := StatPresenter.decimals_for(id)
		assert_ne(
			decimals, 0, "%s is a fraction or a multiplier, so 0 decimals would round it away" % id
		)


## A flag is the mirror case, and it is why the list above is a literal rather than
## "every id that sounds like a rate". `dantian_full` reads 0.0 or 1.0, so rounding
## it is lossless and demanding decimals of it would be the defect, not the fix.
func test_a_flag_stat_is_declared_as_a_whole_number() -> void:
	for id in FLAG_IDS:
		assert_eq(
			StatPresenter.decimals_for(id),
			0,
			"%s is 0 or 1 by construction, so a whole number loses nothing" % id
		)


## The measured defect, asserted as a figure rather than as a presence.
func test_the_figures_that_were_wrong_are_now_right() -> void:
	var row := StatRow.create()
	assert_ne(row, null, "the panel builds its own scene")
	# Exactly the three rows a player was misled by.
	row.set_state({"stat": &"acupoint_quality", "current": 0.5})
	assert_eq(row.summary().get("text", ""), "0.50", "0.5 must not print as 1")
	row.set_state({"stat": &"breakthrough_chance", "current": 0.2})
	assert_eq(row.summary().get("text", ""), "0.200", "0.2 must not print as 0")
	row.set_state({"stat": &"crit_chance", "current": 0.05})
	assert_eq(row.summary().get("text", ""), "0.050", "0.05 must not print as 0")
	# `crit_damage` was the measured row, but ADR 0877 made it a rate-space magnitude
	# (3 decimals now); `attack_speed` is the multiplier that still reads at 2, and the
	# point is the same: 1.54 must not print as 2.
	row.set_state({"stat": &"attack_speed", "current": 1.54})
	assert_eq(row.summary().get("text", ""), "1.54", "1.54 must not print as 2")
	row.free()


## An id nobody declared must degrade to *exact*, never to rounded. An ugly figure
## is recoverable; a wrong one is not, and there is no way for a reader to tell.
func test_an_undeclared_stat_prints_exact_rather_than_rounded() -> void:
	assert_eq(StatPresenter.decimals_for(&"not_a_real_stat"), StatPresenter.EXACT, "unknown")
	var row := StatRow.create()
	row.set_state({"stat": &"not_a_real_stat", "current": 0.5})
	assert_eq(row.summary().get("text", ""), "0.5", "an undeclared 0.5 must not become 1")
	row.set_state({"stat": &"not_a_real_stat", "current": 0.0525})
	assert_eq(
		row.summary().get("text", ""), "0.0525", "an undeclared rate keeps every digit it was given"
	)
	row.free()


## A count is a whole number and must keep printing as one. The fix for a rate must
## not turn every integer on the sheet into "36.00".
func test_a_count_still_prints_as_a_whole_number() -> void:
	var row := StatRow.create()
	row.set_state({"stat": &"acupoint_count", "current": 36.0})
	assert_eq(row.summary().get("text", ""), "36", "a count is not a rate")
	row.set_state({"stat": &"max_health", "current": 250.0})
	assert_eq(row.summary().get("text", ""), "250", "a pool maximum is not a rate")
	row.free()


# --- Labels -----------------------------------------------------------------


## The second half of the same defect class: a row can render the right number
## under a label no player reads. `acupoint_quality` is what the sheet used to show.
func test_a_declared_stat_is_not_labelled_with_its_own_id() -> void:
	for id in StatPresenter.known_ids():
		var label := StatPresenter.label_for(id)
		assert_ne(label, String(id), "%s needs a label a player can read" % id)
		assert_ne(label.strip_edges(), "", "%s needs a non-empty label" % id)


func test_the_measured_misreadable_ids_are_named() -> void:
	assert_eq(L.t(StatPresenter.label_for(&"acupoint_quality")), "Huyệt quality", "not the id")
	assert_eq(StatPresenter.label_for(&"crit_chance"), "Crit chance", "not the id")
	assert_eq(
		L.t(StatPresenter.label_for(&"breakthrough_chance")), "Breakthrough chance", "not the id"
	)
	assert_eq(StatPresenter.label_for(&"dao_heart"), "Dao heart", "not the id")
	assert_eq(L.t(StatPresenter.label_for(&"qi_cost_reduction")), "Qi cost reduction", "not the id")


## An unknown id falls back to its own id, never to a blank. A blank row reads as a
## stat the hero does not have, which is a different lie from an ugly one.
func test_an_undeclared_stat_falls_back_to_its_id_not_to_nothing() -> void:
	assert_eq(StatPresenter.label_for(&"not_a_real_stat"), "not_a_real_stat", "loud, not blank")
	assert_eq(StatPresenter.is_known(&"not_a_real_stat"), false, "and reported unknown")


# --- Coverage: the table against the live stat surface ----------------------


## The reconciliation that makes the literal ids above safe. Every stat the actor
## actually carries must have a declared label and a declared precision, or the
## sheet is showing a raw id or a rounded figure. This walks the REAL stat surface
## of all three cultivation paths rather than a hand-written list, so a module that
## invents a new id cannot reach a player undeclared without this going red.
func test_every_stat_reaching_a_screen_is_declared() -> void:
	var undeclared: Array[String] = []
	for id in _live_stat_ids():
		if not StatPresenter.is_known(id):
			undeclared.append(String(id))
	assert_eq(
		undeclared, [], "these stats reach a player screen with no label and no declared precision"
	)


## Every stat the three cultivation facades actually put on an actor.
func _live_stat_ids() -> Array:
	var out: Dictionary = {}
	for path_id in PathState.ALL:
		var actor := Actor.new(&"presenter_hero", {Stat.PHYSIQUE: 20.0})
		actor.set_path(PathState.new(path_id, &"qi_refining"))
		match path_id:
			PathState.BODY:
				BodyCultivationApi.attach(actor)
				BodyCultivationApi.attach_acupoints(actor)
			PathState.QI:
				QiCultivationApi.attach(actor)
			PathState.MIND:
				MindCultivationApi.attach(actor)
				MindCultivationApi.attach_sea(actor)
		for id in actor.stats.derived_all().keys():
			out[id] = true
	return out.keys()


## A stat carrying a modifier but no baseline is still backed at `0.0` and still
## reaches the sheet -- `actor_stats.gd` documents that path deliberately. So the
## combat-owned rates are declared too, rather than relying on them never appearing.
func test_the_combat_owned_rates_are_declared() -> void:
	for id in [&"accuracy", &"parry.rate", &"reflect.resist.rate", &"lifesteal.health"]:
		assert_eq(StatPresenter.is_known(id), true, "%s reaches the sheet" % id)
		assert_ne(
			StatPresenter.decimals_for(id),
			0,
			"%s is a rate and must not print as a bare integer" % id
		)


## A stale entry is not free: `EXACT` on a declared id would silently disable the
## declared precision, so the table's own shape is asserted, not just its contents.
func test_the_table_declares_a_non_negative_or_exact_precision_for_every_id() -> void:
	for id in StatPresenter.known_ids():
		var decimals := StatPresenter.decimals_for(id)
		assert_eq(
			decimals == StatPresenter.EXACT or decimals >= 0,
			true,
			"%s has a usable precision (%d)" % [id, decimals]
		)


# --- the aptitude vocabulary (ADR 0890) ---------------------------------------


## DEF-0349: "Aptitude" names the twelve-point SOURCE layer (`core/aptitude.gd`); the
## stored attribute a sheet row printed under that word is shown as "Talent", so a player
## cannot read the two layers as one number.
func test_the_legacy_attribute_is_labelled_talent() -> void:
	assert_eq(StatPresenter.label_for(&"aptitude"), "Talent", "the attribute yields the word")


## The twelve aptitudes are drawn through `StatRow`'s `stat` key, so the sheet needs a
## label for every one of them — a missing entry would print the raw id. `agility` is
## already declared as the attribute's own label; that overlap is the roster's one shared
## spelling, pinned in `tests/core/test_aptitude.gd`.
func test_the_aptitude_ids_are_declared() -> void:
	for id in Aptitude.all_ids():
		assert_eq(StatPresenter.is_known(id), true, "%s reaches the sheet" % String(id))
		assert_ne(StatPresenter.label_for(id), String(id), "%s has a label a player can read" % id)
