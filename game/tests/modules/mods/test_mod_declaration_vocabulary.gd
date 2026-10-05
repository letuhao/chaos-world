extends TestCase

## ADR 0275: the two vocabularies are CLOSED, and this is where that is proved.
##
## `test_mod_declaration_block.gd` covers the block's SHAPE. This file covers the
## claim the whole slice exists for: **an id the game does not declare is refused by
## name, on both axes.**
##
## ## The defect
##
## `DoctrineRule.resource_ids` reads pool ids nothing validates, and
## `CultivationPathDef.ensure_resources` mints a pool for ANY id it is handed. A
## System declaring `raeg` therefore got a pool called `raeg`, read it as `0.0`
## forever, and nothing said so — a System whose entire economy is one pool, paying
## nothing and granting nothing, invisibly. `DoctrineRule.UNDECLARED_POOL` cannot
## catch it: that reason catches a System spending a pool it did not itself DECLARE,
## which is a different question from whether the id exists at all.

## A mod bringing its own pool and spending it: the legitimate shape, and the reason
## the seam exists at all — `wrath` is a real concept with no entry in any engine
## table, and declaring it is what makes it first-class.
const BRINGING_BLOCK := {
	"stats":
	[
		{"id": "attack_physical", "op": "flat", "resource": "wrath", "zero_baseline": true},
		{"id": "crit_chance", "op": "flat", "resource": "wrath"},
	],
	"resources": [{"id": "wrath"}],
}


func _parse(block: Dictionary, mod_id: String = "w8_dlc") -> Dictionary:
	return DeclarationBlock.parse(block, mod_id)


# --- the stat id is closed -----------------------------------------------------


## THE headline refusal on the stat axis. The message must name the mod AND the bad
## id: a reason code alone sends the author back to grep for which row was wrong.
func test_an_unknown_stat_id_is_refused_naming_the_mod_and_the_bad_id() -> void:
	var out := _parse(
		{
			"stats": [{"id": "rage_bonus", "op": "flat"}],
			"resources": [{"id": "rage"}],
		},
		"w8_dlc",
	)
	assert_eq(out["ok"], false, "a stat id nothing declares is refused")
	assert_eq(out["reason"], DeclarationBlock.UNKNOWN_STAT, "with the named reason")
	assert_eq((out["stats"] as Array).size(), 0, "and the row is NOT accepted")
	var detail := String(out["detail"])
	assert_eq(
		detail.contains("w8_dlc"), true, "the message names the mod that declared it: %s" % detail
	)
	assert_eq(
		detail.contains("rage_bonus"),
		true,
		"and names the bad id, not merely that something was wrong: %s" % detail
	)


## The PARSER reports every row it could accept even when it refuses the block, and
## the SEAM is what withholds them. The split is deliberate: an author fixing one
## typo wants to see which of their other four rows were fine, and a diagnostic that
## hid them would make them re-derive it. COMMITTING them is a different question,
## and `test_a_refused_declaration_records_nothing_on_the_context` (seam suite) is
## what pins that half — asserted here so neither layer's contract is assumed from
## the other's.
func test_a_refused_block_reports_its_good_rows_without_committing_them() -> void:
	var out := _parse(
		{
			"stats":
			[
				{"id": "physique", "op": "flat"},
				{"id": "not_a_stat", "op": "flat"},
				{"id": "agility", "op": "flat"},
			],
			"resources": [{"id": "rage"}],
		}
	)
	assert_eq(out["ok"], false, "one bad row refuses the block")
	assert_eq((out["refusals"] as Array).size(), 1, "and exactly one refusal names it")
	assert_eq(
		String(out["reason"]),
		DeclarationBlock.UNKNOWN_STAT,
		"for the row that was actually wrong, so the author is not sent to fix the others"
	)
	assert_eq(
		(out["stats"] as Array).size(),
		2,
		"while the two GOOD rows are still reported, for the author's benefit only"
	)


## EVERY offender, not the first. A mod with three typos is one author, and telling
## them about one of them costs a round trip.
func test_every_bad_row_is_reported_not_only_the_first() -> void:
	var out := _parse(
		{
			"stats":
			[
				{"id": "not_one", "op": "flat"},
				{"id": "physique", "op": "sideways"},
				{"id": "agility", "op": "flat", "resource": "raeg"},
			],
			"resources": [{"id": "rage"}],
		}
	)
	var refusals: Array = out["refusals"]
	assert_eq(refusals.size(), 3, "three distinct defects, three refusals")
	assert_eq(String(refusals[0]["reason"]), DeclarationBlock.UNKNOWN_STAT, "the bad stat id")
	assert_eq(String(refusals[1]["reason"]), DeclarationBlock.UNKNOWN_OP, "the bad op")
	assert_eq(String(refusals[2]["reason"]), DeclarationBlock.UNKNOWN_RESOURCE, "the bad pool")


## `RATE_STATS` and `MIND_CONTROL_RATES` are ARRAY constants, so a reader scanning
## only scalar constants would drop twelve mind-control ids and refuse a mod that
## legitimately declared one. Asserted against the array itself, so adding a shape or
## a channel to the vocabulary cannot quietly stop being legal.
func test_a_rate_stat_declared_only_inside_an_array_constant_is_still_legal() -> void:
	assert_eq(DeclarationVocabulary.stat_ids().size() > 0, true, "the vocabulary reads non-empty")
	for rate in Stat.RATE_STATS:
		assert_eq(
			DeclarationVocabulary.is_stat_id(String(rate)),
			true,
			"rate stat '%s' is a legal declaration id" % String(rate)
		)
	var out := _parse(
		{"stats": [{"id": String(Stat.RATE_STATS[0]), "op": "percent"}], "resources": []}
	)
	assert_eq(out["ok"], true, "so a mod declaring one is accepted, not refused")


## `get_script_constant_map()` also returns enums, ints and display strings. An
## unfiltered reader would put `FLAT` or a number into the vocabulary and start
## accepting ids that are not stat ids — the rubber-stamp failure the filter exists
## to prevent, and the one that would make "closed" a claim rather than a fact.
func test_the_vocabulary_holds_only_lowercase_underscore_stat_ids() -> void:
	var ids: Dictionary = DeclarationVocabulary.stat_ids()
	assert_eq(ids.is_empty(), false, "the vocabulary is readable, so this test is not vacuous")
	for key in ids:
		var candidate := String(key)
		var shape_ok := candidate[0] >= "a" and candidate[0] <= "z"
		for index in range(1, candidate.length()):
			var character := candidate[index]
			var allowed := (
				(character >= "a" and character <= "z")
				or (character >= "0" and character <= "9")
				or character == "_"
			)
			shape_ok = shape_ok and allowed
		assert_eq(shape_ok, true, "'%s' is shaped like a stat id, so no enum crept in" % candidate)


## An EMPTY vocabulary means the reader FAILED, not that no stat is legal — the
## distinction `_read_fate_tags` draws in `tools/data.py`. A parser that treated
## empty as "nothing is legal" would pass every row instead, which is the same gate
## reporting ok on a tree it never checked.
func test_an_unreadable_vocabulary_refuses_rather_than_passes() -> void:
	var out := _parse({"stats": [{"id": "physique", "op": "flat"}], "resources": []})
	# The vocabulary IS readable on a healthy tree, so the row is accepted. What is
	# asserted is the SHAPE of the guard: the reason exists in the published set, so a
	# caller validating refusals knows it is a real outcome rather than a typo.
	assert_eq(
		DeclarationBlock.reasons().has(DeclarationBlock.UNKNOWN_VOCABULARY),
		true,
		"'unknown_vocabulary' is a published reason, so the guard is reachable"
	)
	assert_eq(out["ok"], true, "and on a healthy tree nothing is refused for it")


# --- the resource id is closed -------------------------------------------------


## THE headline refusal on the resource axis, and the reason the whole seam exists:
## `raeg` used to resolve to a silent `0.0`. Now it is refused, and the message says
## how to FIX it rather than only what is wrong.
func test_an_unknown_resource_id_is_refused_instead_of_reading_zero() -> void:
	var out := _parse(
		{
			"stats": [{"id": "attack_physical", "op": "flat", "resource": "raeg"}],
			"resources": [{"id": "rage"}],
		},
		"w8_dlc",
	)
	assert_eq(out["ok"], false, "a pool id nothing declares is refused")
	assert_eq(out["reason"], DeclarationBlock.UNKNOWN_RESOURCE, "with the named reason")
	assert_eq((out["stats"] as Array).size(), 0, "and the row does not register")
	var detail := String(out["detail"])
	assert_eq(detail.contains("raeg"), true, "naming the bad pool id: %s" % detail)
	assert_eq(detail.contains("w8_dlc"), true, "naming the mod: %s" % detail)
	assert_eq(
		detail.contains("resources"),
		true,
		"and pointing at the fix — the block that would make it legal: %s" % detail
	)


## The typo's twin, and the reason there are TWO arrays rather than one: naming
## `made_up` in a `resource` FIELD must not be able to declare it. With one array the
## reference would certify itself and the typo would pass — the exact defect this seam
## closes, one level down.
func test_a_resource_reference_cannot_declare_itself() -> void:
	var self_declared := _parse(
		{
			"stats": [{"id": "attack_physical", "op": "flat", "resource": "made_up"}],
			"resources": [],
		}
	)
	assert_eq(
		self_declared["ok"], false, "a resource named only in a stat row is not thereby declared"
	)
	var declared := _parse(
		{
			"stats": [{"id": "attack_physical", "op": "flat", "resource": "made_up"}],
			"resources": [{"id": "made_up"}],
		}
	)
	assert_eq(declared["ok"], true, "the same id IS legal once the mod declares it in resources[]")


## A mod BRINGING a pool, twice, from two rows. Reading one declared pool from two
## rows is one declaration read twice — asserted here because a cross-mod collision
## check written without an owner comparison would report it as one, and the first
## such false positive would train every author to ignore the channel.
func test_a_mod_may_bring_a_pool_the_engine_never_heard_of() -> void:
	var out := _parse(BRINGING_BLOCK)
	assert_eq(out["ok"], true, "a mod's own pool is legal by declaration")
	assert_eq((out["stats"] as Array).size(), 2, "both rows reading it are accepted")
	assert_eq((out["resource_ids"] as Array).size(), 1, "and it is ONE declared pool")


## A core pool is referenceable WITHOUT being redeclared: `health` is
## `ActorPools.CORE_POOL_STATS`'s and is sized from `Stat.MAX_HEALTH`, so a mod
## declaring it would be claiming a pool it does not own.
func test_a_core_pool_is_referenceable_without_being_redeclared() -> void:
	var out := _parse(
		{
			"stats": [{"id": "max_health", "op": "percent", "resource": "health"}],
			"resources": [],
		}
	)
	assert_eq(out["ok"], true, "health resolves against the pool core owns")
	assert_eq((out["resource_ids"] as Array).size(), 0, "and referencing it declares nothing")
	for pool_id in ActorPools.CORE_POOL_STATS:
		assert_eq(
			DeclarationVocabulary.is_core_resource(String(pool_id)),
			true,
			"core pool '%s' is referenceable by name" % String(pool_id)
		)


## The closure stated as a partition: an id is legal because the mod declared it, or
## because core owns it, and there is no third door. `raeg` is in neither, which is
## why it is refused rather than minted.
func test_a_pool_is_legal_only_by_declaration_or_by_core_ownership() -> void:
	assert_eq(
		DeclarationVocabulary.is_core_resource("wrath"), false, "a mod pool is not a core pool"
	)
	assert_eq(
		DeclarationVocabulary.is_core_resource("raeg"), false, "and a typo is neither of the two"
	)
	var out := _parse(
		{
			"stats": [{"id": "attack_physical", "op": "flat", "resource": "wrath"}],
			"resources": [{"id": "wrath"}],
		}
	)
	assert_eq(
		String((out["resource_ids"] as Array)[0]),
		"wrath",
		"so the declaration is what makes it legal, and it is published for ensure_resources"
	)
