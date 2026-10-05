extends TestCase

## BL-0636: an `active`, weight-5.0 item option that rolled into four pools and
## applied a PERCENT modifier to a stat id no provider has published since ADR
## 0071 renamed `dodge_chance` to `mind_avoidance`. Nothing raised and nothing
## warned: `ActorStats._recompute` backs every leftover modifier bucket at 0.0
## (core/actor_stats.gd:187-189) and reads a PERCENT off a zero baseline as
## `(0.0 + 0.0) * (1.0 + percent) = 0.0`, so the modifier was present on the actor
## and inert forever. That is the whole failure class: correct code, no
## consequence, and nothing pointing at it.
##
## `test_mind_renamed_stat_ids.gd` already owns the rename, but it scans
## `res://src/modules/mind_cultivation` only. The rename was complete in `res://src`
## and never migrated into `res://data`, which is exactly where the residue lived
## and exactly where that guard was not looking. So the retirement is asserted here
## over the AUTHORED side, which is the half that was open.
##
## ## What "it has an effect" is asserted to mean
##
## Every check below that claims an option works asserts that a rolled value
## MOVES the stat it names, by the factor the consumption path defines. A test
## asserting only that the option parses, or that its target id is a member of
## some list, would pass unchanged on the broken line — `dodge_chance` was a
## well-formed `stat` target in a well-formed record. `test_a_percent_on_an_
## unpublished_id_moves_nothing` is the negative control that makes the movement
## assertion mean something: it pins the exact value a no-op produces, so a
## regression to the inert target cannot satisfy the movement assertion.
##
## ## The RATE_STATS blind spot, which this file cannot close
##
## `contracts/stat.gd:73` lists `RATE_STATS` to reject a FLAT on a rate stat, and
## it carries core's `CRIT_CHANCE` and `EVASION` but NEITHER `mind_focus_chance`
## NOR `mind_avoidance`. This option's PERCENT is the VALID case so it is
## unaffected, but the guard's silence about those two ids is not evidence they
## are correct: a FLAT on either would pass every check that exists. Closing it
## means editing `contracts/`, which needs its own ADR, so it is reported
## (BL-0637) and deliberately not patched here.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

const CATALOG_PATH := "res://data/item_options/master_option_pool.jsonl"
const OPTION_POOL_DIRS := ["res://data/item_options", "res://data/item_options/derived"]
const OPTION_ID := &"cult_dodge_chance"

## The names ADR 0071 retired. Literals, and a SECOND copy of the list in
## `test_mind_renamed_stat_ids.gd`, on purpose: that file guards `res://src` and
## this one guards `res://data`, and no constant exists for a name that was
## deleted. Derived from `Stat` it could not be — neither id is a core id, which
## is the whole reason ADR 0071 renamed rather than folded.
const RETIRED := [&"critical_chance", &"dodge_chance"]

const ROLL_REALM := &"qi_refining"
const ROLL_RARITY := 3
const ROLL_SEED := 20261004
const SOURCE := &"bl0636_probe"


## Every mind stat id this module publishes, so a target can be checked against
## the module rather than against a hand-kept list that could drift from it.
func _mind_stat_ids() -> Array:
	return [
		MindStats.PERCEPTION,
		MindStats.MENTAL_CLARITY,
		MindStats.MENTAL_ATTACK,
		MindStats.MENTAL_DEFENSE,
		MindStats.SPIRITUAL_SENSE_RANGE,
		MindStats.MIND_FOCUS_CHANCE,
		MindStats.MIND_AVOIDANCE,
		MindStats.MIND_TECHNIQUE_POWER,
		MindStats.ILLUSION_RESISTANCE,
	]


## A mind actor with the module and the sea attached and nothing earned. The
## `PERCEPTION` floor is load-bearing: `MindProvider` derives `mind_avoidance` as
## `minf(0.6, perception * 0.002 + awareness_ratio * 0.05)`, so a zero-perception
## actor has an identically-zero baseline and a PERCENT on it would be a no-op for
## a reason that has nothing to do with the defect under test.
func _mind_actor() -> Actor:
	var actor := Actor.new(
		&"bl0636_actor",
		{Stat.WILL: 10.0, MindStats.MENTAL_CLARITY: 15.0, MindStats.PERCEPTION: 20.0}
	)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	actor.mark_stats_dirty()
	return actor


## Every record in the master catalog, parsed. The structural half of the guard:
## a raw text scan cannot tell a stat TARGET from the option's own ID, because
## `cult_dodge_chance` contains `dodge_chance` as a substring and the retired name
## survives in the derived pools as part of that id. Reading `target.id` off the
## parsed record is what makes "targets the retired stat" distinguishable from
## "is named after it".
func _catalog_records() -> Array:
	var out: Array = []
	var json := JSON.new()
	for line in FileAccess.get_file_as_string(CATALOG_PATH).split("\n"):
		if String(line).strip_edges().is_empty():
			continue
		if json.parse(String(line)) != OK:
			continue
		if json.data is Dictionary:
			out.append(json.data)
	return out


func _catalog() -> OptionCatalog:
	return OptionCatalog.new()


## The concatenated text of the authored option data, comments irrelevant because
## JSON carries none.
##
## Both loops are `for` over a snapshot `DirAccess` has already read, so each is
## bounded by directory membership and neither grows what it iterates: the hazard
## the repo's loop rules close is a `while` testing a size its own body inserts,
## and a `for` over a materialised list cannot express that. The scan is also
## deliberately non-recursive over two named directories holding four small files,
## because a recursive content walk needs its own depth cap and `OptionCatalog`'s
## three `CATALOG_PATH`/`PROJECTION_PATH`/`SCALE_PATH` constants already name every
## file the runtime reads from here.
func _authored_option_text() -> String:
	var joined := ""
	for dir_path in OPTION_POOL_DIRS:
		var dir := DirAccess.open(String(dir_path))
		if dir == null:
			continue
		for file_name in dir.get_files():
			joined += FileAccess.get_file_as_string(String(dir_path).path_join(String(file_name)))
	return joined


## A seeded generator, so the rolled rate is a fixed value rather than a draw the
## assertion has to tolerate. The roll is deterministic for a given seed; the
## movement assertion reads the value back off the effect either way, so it does
## not depend on WHICH rate was rolled.
func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ROLL_SEED
	return rng


# --- Liveness: this guard is pointed at something real ------------------------


## The scan reads authored content, the retired list is whole, and the option is
## still registered and `active`. Without this, an emptied file, a moved
## directory or a retired option would make every `contains(...) == false` below
## pass on nothing — the vacuous guard this repo has shipped three times.
func test_the_guard_is_pointed_at_a_live_option_and_real_content() -> void:
	var text := _authored_option_text()
	assert_ne(text.strip_edges(), "", "the authored option data returned text to check")
	assert_eq(RETIRED.size(), 2, "both renamed ids are still on the retired list")
	var records := _catalog_records()
	assert_eq(
		records.size() > OPTION_POOL_DIRS.size(),
		true,
		"the catalog parsed into records, so the scan below reads the whole file"
	)
	var record := _catalog().option_record(OPTION_ID)
	assert_eq(record.is_empty(), false, "the dodge-family option is still registered")
	assert_eq(String(record.get("status", "")), "active", "and is still rollable")
	assert_ne(String(record.get("target", {}).get("id", "")), "", "and declares a stat target")


# --- The retirement, asserted over the AUTHORED side --------------------------


## No option record targets a retired mind stat id. Structural, on the parsed
## record's `target.id` — this is the check `test_mind_renamed_stat_ids.gd` could
## not make, because it scans `res://src` where the rename WAS complete and so
## stayed green over a catalog still pointing at the dead name.
func test_no_option_record_targets_a_retired_mind_stat_id() -> void:
	var records := _catalog_records()
	for record in records:
		var target: Variant = record.get("target", {})
		if not (target is Dictionary):
			continue
		var target_id := String((target as Dictionary).get("id", ""))
		for gone in RETIRED:
			assert_eq(
				target_id == String(gone),
				false,
				(
					"option %s does not target the retired id %s"
					% [String(record.get("id", "?")), String(gone)]
				)
			)


## The raw-text half, quote-delimited. `"dodge_chance"` is a fourteen-character
## token that does NOT occur inside `"cult_dodge_chance"` — the option's own id
## keeps the old word, so an undelimited `contains()` would report this fixed
## catalog as broken forever. The quotes are what make the scan mean what it says.
func test_the_retired_id_appears_nowhere_as_a_quoted_token_in_the_option_data() -> void:
	var text := _authored_option_text()
	for gone in RETIRED:
		assert_eq(
			text.contains('"%s"' % String(gone)),
			false,
			"the retired id %s is not authored as a bare id anywhere" % String(gone)
		)
		# And the guard is not passing because the word is absent entirely: the
		# option id that legitimately still contains it must be present.
		assert_eq(
			text.contains("cult_dodge_chance"),
			true,
			"the option id still names the dodge family, so the scan has text to match"
		)


## The positive half of the same rule, so a green no-`contains` cannot be
## satisfied by deleting the option: `cult_dodge_chance` targets an id the mind
## module actually publishes, and a mind actor actually derives it.
func test_the_option_targets_a_stat_the_mind_module_publishes() -> void:
	var record := _catalog().option_record(OPTION_ID)
	var target_id := StringName(record.get("target", {}).get("id", ""))
	assert_eq(
		_mind_stat_ids().has(target_id),
		true,
		"the option targets a mind-module stat id, and it is %s" % String(target_id)
	)
	var actor := _mind_actor()
	assert_eq(
		actor.stats.derived_all().has(target_id),
		true,
		"a mind actor derives the stat the option targets"
	)


# --- It has an EFFECT, through the shipped consumption path -------------------


## Roll the option the way an item does — `OptionCatalog.realize` normalises the
## record, `ItemEffects.stat_modifiers` mints the `StatModifier`, `ActorStats`
## resolves it — and assert the target stat MOVED by the factor that path defines.
##
## `(contributed + flat) * (1 + percent)` for a provider-contributed stat
## (core/actor_stats.gd:116-127) means a PERCENT is only ever visible against a
## non-zero baseline, so this asserts the baseline is non-zero BEFORE measuring,
## rather than reporting a passing `0.0 * 1.0 == 0.0` as a working option.
func test_rolling_the_option_moves_the_stat_it_targets() -> void:
	var catalog := _catalog()
	var record := catalog.option_record(OPTION_ID)
	var effect := catalog.realize(record, ROLL_REALM, ROLL_RARITY, _rng())
	var target_id := StringName(effect.get("target_id", ""))
	var value := float(effect.get("value", 0.0))

	assert_eq(StringName(effect.get("target_type", "")) == OptionTarget.STAT, true, "a stat effect")
	assert_eq(value > 0.0, true, "the rolled value is a real rate, not a zero roll")
	assert_eq(effect.get("op", "") == &"PERCENT", true, "the rolled op is PERCENT")

	var actor := _mind_actor()
	var before := actor.stats.derived(MindStats.MIND_AVOIDANCE)
	assert_eq(before > 0.0, true, "the module publishes a non-zero baseline to scale")
	for modifier in ItemEffects.stat_modifiers([effect], SOURCE):
		actor.stats.add_modifier(modifier)
	var after := actor.stats.derived(MindStats.MIND_AVOIDANCE)

	assert_eq(after > before, true, "the option moved the stat it targets")
	assert_almost_eq(
		after, before * (1.0 + value), "by exactly the rolled rate, on %s" % String(target_id)
	)


## The negative control, and the reason the assertion above can catch anything.
##
## This is what the defect produced: the modifier is accepted, counted by
## `modifier_count`, removable by `remove_modifiers_from`, and reads `0.0` before
## and after. Nothing raises — `add_modifier` performs no id validation
## (core/actor_stats.gd:67-69) and there is no `push_warning`/`push_error` on
## this path — so the ONLY thing that distinguished "applied and had an effect"
## from "applied to nothing" was the value. Pinning the no-op's value here is what
## makes the movement assertion above a real test rather than a tautology.
func test_a_percent_on_an_unpublished_id_moves_nothing() -> void:
	var actor := _mind_actor()
	actor.stats.add_modifier(StatModifier.new(&"dodge_chance", Stat.Op.PERCENT, 5.0, SOURCE))
	assert_eq(
		actor.stats.derived(&"dodge_chance"),
		0.0,
		"a PERCENT on an unpublished id stays 0.0 — the defect, pinned"
	)
	assert_ne(
		actor.stats.modifier_count(),
		0,
		"yet the modifier IS on the actor, which is why nothing ever reported it"
	)


## And the retired name is absent from the module source this very file sits
## beside, so the two halves of the same rename cannot drift: if a later wave
## re-plants the twin, the source guard reds here too rather than leaving the
## catalog pointing at a name nothing publishes.
func test_the_retired_names_are_still_absent_from_the_module_source() -> void:
	var code := Probe.module_code_all()
	assert_ne(code.strip_edges(), "", "the module source scan returned code to check")
	for gone in RETIRED:
		assert_eq(
			code.contains(String(gone)),
			false,
			"the module does not re-plant the retired id %s" % String(gone)
		)
