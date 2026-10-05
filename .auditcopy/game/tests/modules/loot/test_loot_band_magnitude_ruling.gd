extends TestCase

## ADR 0166: a drop pays its item's OWN rung, so the band stops paying magnitude and a
## rolled relic does not move.
##
## The decision this pins has two halves that pull in opposite directions, so both are
## guarded here. A value comparison cannot guard either: after the mechanism lands, a
## corpus scan for mis-payments is trivially satisfied and proves nothing, and before it
## lands the same scan is red on 6310 entries for reasons that say nothing about the
## decision. So these checks read SOURCE and one directory listing, the way
## `tests/core/test_realm_rate.gd` does, because a numerically identical reversal — a
## second seam that copies a band realm onto a definition, or a magnitude read keyed on
## the tier — stays green under every value assertion ever written.
##
## What the decision actually rules out, and what each assertion is for:
##
##   - **The band is not the magnitude authority.** Exactly one place may write a
##     drop's realm onto an `ItemDef`, and it is `LootRewards.contextualize`. A second
##     seam means the blast radius ADR 0166 claims ("one function") is a lie.
##   - **The item's authored rung is the magnitude.** `ItemGenerator` hands `def.realm`
##     to `OptionCatalog`, never a tier or context realm.
##   - **The resolver still reports the band.** The fix belongs at REALIZATION. A change
##     in `LootResolver._plan` would delete the band's difficulty meaning, which
##     `design.py` calls "a statement about difficulty".
##   - **The corpus is not silently migrated.** A rolled migration needs 4380 pools
##     (measured: 4380 `(table, owed realm)` groups, 488 of which already exist), so the
##     shipped pool-table count is CEILINGED. ADR 0166 rejects that route on four
##     measured blockers; landing it anyway must fail the build rather than quietly
##     truncate 279 of 333 tables behind `MAX_PLANS_PER_RESOLVE = 12`.
##
## Loop safety: every loop is a `for` over `DirAccess.get_files()`, which is a finite
## snapshot taken once; there is no `while`, no recursion and no bound the loop grows.

## The two directories that own a drop's realm and a drop's magnitude, enumerated so a
## THIRD module that grows one cannot join without a decision.
const REALM_OWNER_DIRS := ["modules/loot", "modules/items"]

const REALM_OWNER_TABLE := "res://src/modules/loot/loot_rewards.gd"
const REALM_OWNER_FUNC := "func contextualize("
const GENERATOR := "res://src/modules/items/item_generator.gd"
const RESOLVER := "res://src/modules/loot/loot_resolver.gd"
const TABLE_DIR := "res://data/loot/tables"
const POOL_MARKER := "_pool_"

## Measured 2026-10-04: 1086 `_pool_` files in the tables directory (1083 of which the
## tool parses into tables). ADR 0166 measures a rolled migration at 4380 pools, so
## executing it lands near 4978. A CEILING, not an equality, so an ordinary content wave
## that adds a pool still passes — and the label names the count so a failure says which
## number it saw.
const POOL_TABLE_CEILING := 1200


## A definition's realm written from a drop context. `.realm` on `out` is the
## resolver's context dictionary and is the band doing its job, so only a copy of a
## definition counts as the override.
##
## Assembled from `String.chr(92)` rather than written as a literal: GDScript runs
## escape processing inside single quotes too, so a bare `\.` in the source is a parse
## error and the whole suite fails to load.
func _override_pattern() -> String:
	var bs := String.chr(92)
	return "(?:^|[^." + bs + "w])(copy|contextual|contextualized)" + bs + ".realm" + bs + "s*="


## At most one place may write a drop's realm onto an `ItemDef`, and it is
## `LootRewards.contextualize`. Zero is the state ADR 0166 asks for; one is the state
## it supersedes. Two is the reversal the ADR's one-function blast radius forbids.
func test_the_drop_realm_override_has_at_most_one_owner() -> void:
	var sites := 0
	var owners := ""
	for path_dir in REALM_OWNER_DIRS:
		for file_name in _gd_files("res://src/%s" % path_dir):
			var path := "res://src/%s/%s" % [path_dir, file_name]
			var hits := _pattern_hits(path, _override_pattern())
			if hits == 0:
				continue
			sites += hits
			owners += "%s " % path.get_file()
	assert_eq(
		sites <= 1,
		true,
		"at most one definition-realm override exists, found %d in: %s" % [sites, owners]
	)
	for owner in owners.split(" ", false):
		assert_eq(owner, REALM_OWNER_TABLE.get_file(), "%s owns it" % owner)


## The seam is named, so a fix that moves it has to move it deliberately rather than by
## renaming a variable. `contextualize` is the function ADR 0166 names as the whole
## mechanism behind 6310 mis-payments.
func test_the_override_seam_is_named_and_reachable() -> void:
	var source := FileAccess.get_file_as_string(REALM_OWNER_TABLE)
	assert_ne(source, "", "the rewards module is readable")
	assert_eq(
		source.contains(REALM_OWNER_FUNC),
		true,
		"%s declares the seam ADR 0166 names" % REALM_OWNER_TABLE.get_file()
	)
	assert_eq(
		source.contains("contextualize(def, realm, rarity)"),
		true,
		"and the drop's realm is still routed through it"
	)


## The item's authored rung is the magnitude. `ItemGenerator.roll` reads `def.realm` and
## hands it to `OptionCatalog`; a band or context realm in that call is the reversal.
func test_the_item_def_is_the_magnitude_authority() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_ne(source, "", "the generator is readable")
	assert_eq(source.contains("def.realm"), true, "the generator reads the definition's own realm")
	for banned in ['context.get("realm"', "tier.realm", "context.realm", "band.realm"]:
		assert_eq(
			source.contains(banned),
			false,
			"the generator never derives a magnitude from %s" % banned
		)


## The resolver keeps reporting the band on the plan, because the fix belongs at
## realization. `test_loot_resolver.gd` pins the value; this pins WHY it stays, so the
## plan's realm is not deleted as a "duplicate source of truth" without reading
## ADR 0166 first.
func test_the_resolver_still_reports_the_band_realm_on_the_plan() -> void:
	var source := FileAccess.get_file_as_string(RESOLVER)
	assert_ne(source, "", "the resolver is readable")
	assert_eq(
		source.contains('context.get("realm", &"")'), true, "the plan still carries the band realm"
	)
	assert_eq(
		source.contains('if realm == &"":'),
		true,
		"with the table's own realm as the fallback the ADR calls a fallback"
	)


## The corpus canary. A rolled migration is the alternative ADR 0166 rejects; it needs
## 4380 pools and would truncate 279 of 333 tables. The count is read from the directory
## rather than from `LootContent`, so it is the same 1083 `tools/cultivation` measured
## and cannot drift by which tables happen to be bound.
func test_the_shipped_pool_table_count_is_ceilinged() -> void:
	var names := _files(TABLE_DIR)
	var pools := 0
	for file_name in names:
		if file_name.contains(POOL_MARKER):
			pools += 1
	assert_eq(
		pools <= POOL_TABLE_CEILING,
		true,
		"%d pool table(s), at or under the ADR 0166 ceiling of %d" % [pools, POOL_TABLE_CEILING]
	)


func _files(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	if dir == null:
		return []
	return dir.get_files()


func _gd_files(path: String) -> Array[String]:
	var out: Array[String] = []
	for file_name in _files(path):
		if file_name.ends_with(".gd"):
			out.append(file_name)
	return out


## How many times `pattern` matches a file, read whole. Bounded by the file's own size,
## which is finite, so the walk terminates whatever the file contains.
func _pattern_hits(path: String, pattern: String) -> int:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return 0
	var hits := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if regex.search(line) != null:
			hits += 1
	return hits
