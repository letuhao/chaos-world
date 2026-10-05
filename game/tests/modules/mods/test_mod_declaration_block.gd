extends TestCase

## ADR 0275: ONE declaration block carries a mod's STATS and RESOURCES together —
## `{stats: [...], resources: [...]}` beside `mod.json`.
##
## ## What this file pins, and what it does not
##
## The block's SHAPE: what a well-formed declaration looks like, what an empty or
## absent one means, which key sets are closed, and how a refusal is published. The
## two vocabularies themselves — is `raeg` legal, is `rage_bonus` legal — are proved
## CLOSED in `test_mod_declaration_vocabulary.gd`, and the seam as a whole is driven
## end to end through the loader in `test_mod_stat_declaration_seam.gd`.
##
## ## Closed key sets, and why that is not fussiness
##
## A row carrying `resorce` instead of `resource` is a declaration that reads as
## working and governs nothing — the same defect as a typo'd pool id, one level down.
## Silently ignoring the key would be a silent acceptance, which is the thing this
## whole seam was added to stop.
##
## ## Absent is not malformed
##
## `{}` is what a declaration file with no content parses to, and ADR 0083's
## three-state vocabulary says "does not exist" and "exists and its value is refused"
## are DIFFERENT answers. So an absent block is legal and an empty array is legal, and
## neither produces a refusal for an author to act on.

## A well-formed block: a plain stat, a stat reading the mod's own pool, and a stat
## reading a pool core owns.
const GOOD_BLOCK := {
	"stats":
	[
		{"id": "physique", "op": "flat"},
		{"id": "attack_physical", "op": "percent", "resource": "rage", "zero_baseline": true},
		{"id": "qi_absorption", "op": "mult", "resource": "health"},
	],
	"resources": [{"id": "rage"}],
}


func _parse(block: Dictionary, mod_id: String = "w8_dlc") -> Dictionary:
	return DeclarationBlock.parse(block, mod_id)


# --- a well-formed mod ---------------------------------------------------------


func test_a_well_formed_block_accepts_every_row() -> void:
	var out := _parse(GOOD_BLOCK)
	assert_eq(out["ok"], true, "a block naming only declared ids is accepted")
	assert_eq(out["reason"], "", "and carries no refusal reason")
	assert_eq((out["stats"] as Array).size(), 3, "all three stat rows accepted")
	assert_eq((out["refusals"] as Array).size(), 0, "no refusals recorded")


## The rows come back NORMALISED, not echoed: an `op` is lowercased and the ids are
## StringName, so a consumer comparing against `Stat` constants gets a hit rather
## than a string comparison that happens to work until the casing drifts.
func test_accepted_rows_are_normalised_to_the_shape_a_consumer_compares() -> void:
	var first: Dictionary = (_parse(GOOD_BLOCK)["stats"] as Array)[0]
	assert_eq(first["id"], Stat.PHYSIQUE, "the id is a StringName equal to the Stat constant")
	assert_eq(String(first["op"]), "flat", "the op is the lowercased spelling")
	assert_eq(first["resource"], StringName(""), "and a row with no pool reads as empty, not null")
	assert_eq(first["zero_baseline"], false, "zero_baseline defaults to false, never to true")


func test_the_declared_pools_are_published_in_declaration_order() -> void:
	var out := _parse(GOOD_BLOCK)
	assert_eq((out["resource_ids"] as Array).size(), 1, "the mod brought one pool")
	assert_eq(String((out["resource_ids"] as Array)[0]), "rage", "and it is the one it declared")


## Every op `Stat.Op` declares is accepted, spelled either case. Read rather than
## restated, so a fourth op added to the enum becomes legal here with no code change
## on this side — and a typo stays refused.
func test_every_declared_op_is_accepted_and_a_typo_is_not() -> void:
	for key in Stat.Op.keys():
		var op := String(key).to_lower()
		var out := _parse({"stats": [{"id": "physique", "op": op}], "resources": []})
		assert_eq(out["ok"], true, "op '%s' is legal" % op)
	var shouted := _parse({"stats": [{"id": "physique", "op": "FLAT"}], "resources": []})
	assert_eq(
		shouted["ok"], true, "and the spelling is case-insensitive, because it is lowered on read"
	)
	var typo := _parse({"stats": [{"id": "physique", "op": "multiply"}], "resources": []})
	assert_eq(
		typo["ok"], false, "while a near-miss no enum declares is refused — MULT is not MULTIPLY"
	)
	assert_eq(typo["reason"], DeclarationBlock.UNKNOWN_OP, "by name")


func test_a_stat_row_with_no_op_is_refused_rather_than_defaulted() -> void:
	var out := _parse({"stats": [{"id": "physique"}], "resources": []})
	assert_eq(out["ok"], false, "an op is not optional: a default would be a guess")
	assert_eq(out["reason"], DeclarationBlock.BAD_OP, "with its own reason")


func test_a_stat_row_with_no_id_is_refused() -> void:
	var out := _parse({"stats": [{"op": "flat"}], "resources": []})
	assert_eq(out["ok"], false, "an idless row names no stat and cannot be checked")
	assert_eq(out["reason"], DeclarationBlock.BAD_ID, "with its own reason")


# --- zero_baseline, both ways -------------------------------------------------


## TRUE says an absent pool reads as `0.0` and that is INTENDED; FALSE (the default)
## says an absent pool is an error. Both are recorded, and the flag rides the row, so
## a consumer knows which of the two answers a missing pool is owed.
func test_zero_baseline_is_recorded_true_and_the_read_is_intended() -> void:
	var out := _parse(
		{
			"stats":
			[{"id": "attack_physical", "op": "percent", "resource": "rage", "zero_baseline": true}],
			"resources": [{"id": "rage"}],
		}
	)
	assert_eq(out["ok"], true, "an absent-pool read the mod asked for is accepted")
	assert_eq((out["stats"] as Array)[0]["zero_baseline"], true, "and the flag is recorded")


func test_zero_baseline_defaults_to_false_so_an_absent_pool_is_an_error() -> void:
	var out := _parse(
		{
			"stats": [{"id": "attack_physical", "op": "percent", "resource": "rage"}],
			"resources": [{"id": "rage"}],
		}
	)
	assert_eq(
		(out["stats"] as Array)[0]["zero_baseline"],
		false,
		"the DEFAULT is the strict answer; opting into a silent 0.0 has to be authored"
	)


## The flag is about a POOL, so a row carrying it with nothing to apply it to is a
## declaration that reads as working and governs nothing.
func test_zero_baseline_with_no_resource_is_refused() -> void:
	var out := _parse({"stats": [{"id": "physique", "op": "flat", "zero_baseline": true}]})
	assert_eq(out["ok"], false, "the flag with no pool to govern is refused")
	assert_eq(
		out["reason"],
		DeclarationBlock.ZERO_BASELINE_WITHOUT_RESOURCE,
		"with its own named reason rather than a generic one"
	)


func test_a_non_bool_zero_baseline_is_refused() -> void:
	var out := _parse(
		{
			"stats": [{"id": "physique", "op": "flat", "resource": "rage", "zero_baseline": "yes"}],
			"resources": [{"id": "rage"}],
		}
	)
	assert_eq(out["ok"], false, "a truthy STRING is not the bool the flag is")
	assert_eq(out["reason"], DeclarationBlock.BAD_ZERO_BASELINE, "and it says so by name")


# --- empty and absent ----------------------------------------------------------


func test_an_absent_declaration_block_is_not_a_refusal() -> void:
	var out := _parse({})
	assert_eq(out["ok"], true, "declaring nothing is legal")
	assert_eq((out["stats"] as Array).size(), 0, "and contributes no rows")
	assert_eq((out["resource_ids"] as Array).size(), 0, "and brings no pools")


func test_an_explicitly_empty_block_is_also_not_a_refusal() -> void:
	var out := _parse({"stats": [], "resources": []})
	assert_eq(out["ok"], true, "an author who wrote the keys and left them empty meant that")
	assert_eq((out["refusals"] as Array).size(), 0, "and gets no refusal to act on")


## A block carrying NEITHER key is a different answer again: it is not declaring
## nothing, it is a file this parser cannot interpret — a renamed key, or a block
## authored against a future shape. Refused rather than read as empty, because an
## unreadable file that reads as "declares nothing" is a gate passing a tree it never
## looked at.
func test_a_block_with_neither_key_is_refused_as_unreadable() -> void:
	var out := _parse({"nope": true})
	assert_eq(out["ok"], false, "neither key present is not the same answer as an empty block")
	assert_eq(out["reason"], DeclarationBlock.BAD_BLOCK, "with the block reason")
	assert_eq(
		String(out["detail"]).contains("stats"),
		true,
		"and the message names the keys it was looking for"
	)


# --- closed key sets -----------------------------------------------------------


func test_a_typo_d_key_is_refused_rather_than_ignored() -> void:
	var out := _parse(
		{
			"stats": [{"id": "physique", "op": "flat", "resource": "rage", "resorce": "rage"}],
			"resources": [{"id": "rage"}],
		}
	)
	assert_eq(out["ok"], false, "an unknown key is not silently dropped")
	assert_eq(out["reason"], DeclarationBlock.UNKNOWN_KEY, "with its own reason")
	assert_eq(
		String(out["detail"]).contains("resorce"),
		true,
		"naming the key, so the author knows which field to fix"
	)


func test_an_unknown_key_on_a_resources_row_is_refused() -> void:
	var out := _parse({"stats": [], "resources": [{"id": "rage", "maximum": 10.0}]})
	assert_eq(out["ok"], false, "the resource key set is closed too")
	assert_eq(String(out["detail"]).contains("maximum"), true, "naming the offending key")


func test_a_mistyped_array_is_refused_as_a_block_shape_problem() -> void:
	var out := _parse({"stats": {"id": "physique"}, "resources": []})
	assert_eq(out["ok"], false, "an object where an array belongs is refused")
	assert_eq(out["reason"], DeclarationBlock.BAD_BLOCK, "as a block-shape problem")
	var other := _parse({"stats": [], "resources": {"id": "rage"}})
	assert_eq(other["ok"], false, "and the same on the resources side")
	assert_eq(other["reason"], DeclarationBlock.BAD_BLOCK, "under the same named reason")


func test_a_row_that_is_not_an_object_is_refused() -> void:
	var out := _parse({"stats": ["physique"], "resources": []})
	assert_eq(out["ok"], false, "a bare string is not a declaration row")
	assert_eq(out["reason"], DeclarationBlock.BAD_ROW, "with the row reason")


func test_a_resources_row_needs_a_non_empty_id() -> void:
	var out := _parse({"stats": [], "resources": [{"id": ""}]})
	assert_eq(out["ok"], false, "an empty pool id declares nothing and must not pass as declaring")
	assert_eq(out["reason"], DeclarationBlock.BAD_RESOURCE, "with the resource reason")


# --- the refusal vocabulary is published, not restated -------------------------


## A caller that must VALIDATE a refusal reads one list. It is COPIED rather than
## exposed because a caller appending to the returned array would otherwise be
## editing the parser's own set — the decay BL-0619 is about.
func test_the_reason_list_is_published_and_is_a_copy() -> void:
	var reasons := DeclarationBlock.reasons()
	assert_eq(reasons.size(), DeclarationBlock.REASONS.size(), "every reason is published")
	for reason in DeclarationBlock.REASONS:
		assert_eq(reasons.has(reason), true, "'%s' is in the published set" % reason)
	reasons.append("scratch")
	assert_eq(
		reasons.size() == DeclarationBlock.REASONS.size(),
		false,
		"and the returned array is a copy, so editing it cannot corrupt the set"
	)
	assert_eq(
		DeclarationBlock.REASONS.has("scratch"),
		false,
		"the parser's own set is untouched by a caller's edit"
	)


## Every reason the other two suites assert on must be in the published set, or a
## caller validating a refusal would not recognise a real one. This is the list those
## two files lean on, restated ONCE and here — deliberately not per-file, because a
## per-file copy is a second set of strings that can drift from the parser's.
func test_every_reason_the_suite_asserts_on_is_published() -> void:
	var reasons := DeclarationBlock.reasons()
	for asserted in [
		DeclarationBlock.UNKNOWN_STAT,
		DeclarationBlock.UNKNOWN_RESOURCE,
		DeclarationBlock.UNKNOWN_OP,
		DeclarationBlock.BAD_OP,
		DeclarationBlock.BAD_ID,
		DeclarationBlock.BAD_ROW,
		DeclarationBlock.BAD_BLOCK,
		DeclarationBlock.BAD_RESOURCE,
		DeclarationBlock.BAD_ZERO_BASELINE,
		DeclarationBlock.ZERO_BASELINE_WITHOUT_RESOURCE,
		DeclarationBlock.UNKNOWN_KEY,
		DeclarationBlock.UNKNOWN_VOCABULARY,
	]:
		assert_eq(reasons.has(asserted), true, "'%s' is published" % asserted)
