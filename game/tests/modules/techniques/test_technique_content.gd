extends TestCase

## The authored technique content tree, held against the rules the codex gates on
## (ADR 0053/0054/0055/0056/0059).
##
## This is DEF-0091's regression guard. The 1363 `game/data/items/technique/`
## manuals are interchangeable by construction — identical fields, ids concatenated
## from stat names, and every item drawing from the same option pool as equipment.
## The fix is a real content tree whose passives carry distinct identities, so the
## load-bearing case below asserts that NO TWO techniques grant the same option pair
## at the same values. Everything else in this file exists so that guard cannot be
## satisfied by trivial, malformed, or unreachable rows.
##
## Deliberately NOT isolated with a fixture catalog: the point is to hold the
## `.tres` files that ship, so the real catalog and the real option pool are what
## these read.

## The catalog's own content root. Hard-coded rather than imported so the test
## fails if the module ever moves the tree without the test following.
const ROOT := "res://data/techniques"

## The smallest useful tree. Below this a "spread across grades" claim is
## decorative rather than real.
const MIN_TECHNIQUES := 40

## ADR 0055's per-realm ladder, which shares this directory and is not a def.
const MAGNITUDE_TABLE_FILE := "technique_magnitude_table.tres"

## Realm ordinals on the shared 30-realm ladder. A path floor outside this range
## is unsatisfiable or meaningless.
const MAX_REALM_ORDINAL := 29

## Every id the seeding generator could have produced, rebuilt from the grade
## words it drew from and the five refinement suffixes it used. An authored id is
## never in here; a generated one is.
##
## Built ONCE and cached: the shape set is 26 x 10 x 6 x 5 = 7800 entries, and
## rebuilding it inside the assertion loop would spend the whole run in string
## formatting instead of in assertions.
static var _generated: Dictionary = {}


func _catalog() -> TechniqueCatalog:
	return TechniqueCatalog.instance()


## Every `.tres` in the content tree, directly from disk rather than through the
## catalog, so a file the catalog silently skipped is still asserted on.
func _files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			out.append("%s/%s" % [ROOT, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _defs() -> Array[TechniqueDef]:
	var out: Array[TechniqueDef] = []
	for path in _files():
		# The magnitude table shares this directory and is NOT a TechniqueDef. A
		# `Resource` cast that does not fit yields null, but the magnitude table's
		# script still answers to the Resource interface, so the file name is
		# excluded explicitly rather than relying on the cast to reject it — an
		# empty-id stub in the loop below reported every passive as a duplicate.
		if path.ends_with(MAGNITUDE_TABLE_FILE):
			continue
		var def := load(path) as TechniqueDef
		if def == null or String(def.id).is_empty():
			continue
		out.append(def)
	return out


## The two shapes a DUAL `path` may take, derived from the real constants rather
## than from a literal `+`, so a change to `DUAL_SEPARATOR` cannot desynchronise
## the guard from the content.
static func _dual_pair(path: StringName) -> Array[StringName]:
	if not path.contains(TechniquePolicy.DUAL_SEPARATOR):
		return []
	var out: Array[StringName] = []
	for part in path.split(TechniquePolicy.DUAL_SEPARATOR):
		if not part.is_empty():
			out.append(StringName(part))
	return out


## The signature that makes two passives interchangeable: the same options at the
## same values, in either order. Sorted because the authored order is presentational
## and a reordering is not a new identity.
static func _passive_signature(def: TechniqueDef) -> String:
	var pairs: Array[String] = []
	for entry in def.passive_options:
		(
			pairs
			. append(
				(
					"%s=%s"
					% [
						String(entry.get("option_id", "")),
						str(float(entry.get("value", 0.0))).rstrip("0").rstrip("."),
					]
				)
			)
		)
	pairs.sort()
	return "|".join(pairs)


# --- The tree loads ----------------------------------------------------------


func test_every_authored_file_loads_as_a_named_technique_def() -> void:
	var files := _files()
	assert_eq(files.is_empty(), false, "the content tree is not empty")
	assert_eq(
		files.size() >= MIN_TECHNIQUES,
		true,
		"the tree ships at least %d definitions, found %d" % [MIN_TECHNIQUES, files.size()]
	)
	# The magnitude ladder shares this directory (ADR 0055 puts it beside the content
	# it scales) and is deliberately not a TechniqueDef, so it is named here rather
	# than silently tolerated: a stray that is NOT that file is a real mistake.
	var stray: Array[String] = []
	for path in files:
		if path.ends_with(MAGNITUDE_TABLE_FILE):
			continue
		if load(path) as TechniqueDef == null:
			stray.append(path)
	assert_eq(stray.is_empty(), true, "every authored .tres is a TechniqueDef, stray %s" % [stray])


func test_every_definition_carries_an_id_and_a_name_that_says_what_it_does() -> void:
	for def in _defs():
		assert_ne(String(def.id), "", "%s has an id" % def.resource_path.get_file())
		assert_ne(def.display_name.strip_edges(), "", "'%s' is named" % def.id)
		assert_ne(def.description.strip_edges(), "", "'%s' is described" % def.id)
		assert_ne(def.tags.is_empty(), true, "'%s' is tagged" % def.id)
		assert_ne(def.schools.is_empty(), true, "'%s' names a school" % def.id)


## DEF-0091 named three ways the old corpus was machine-stamped: ids concatenated
## from stat names, and `display_name` produced by title-casing that id. The fix has
## to fail loudly if either shape ever comes back.
func test_no_authored_id_is_a_generated_template() -> void:
	for def in _defs():
		var technique_id := String(def.id)
		assert_eq(
			technique_id.is_valid_identifier(), true, "'%s' is a snake_case id" % technique_id
		)
		assert_eq(
			technique_id == technique_id.to_lower(), true, "'%s' is lower case" % technique_id
		)
		# The `<L><N>_<realm>_<word>_<refinement>` generator shape: a letter, a
		# digit, a grade word, then one of the five refinement suffixes.
		assert_eq(
			_generated_shapes().has(technique_id),
			false,
			"'%s' is not a generated row" % technique_id
		)
		# A display name that is the id with underscores turned into spaces is the
		# corpus's signature tell: it names the option list, not the technique.
		assert_eq(
			def.display_name.to_lower() != technique_id.replace("_", " "),
			true,
			"'%s' is not its id with underscores read as spaces" % technique_id
		)
		# So is a name assembled from the option ids the row grants.
		var granted: Array[String] = []
		for entry in def.passive_options:
			granted.append(String(entry.get("option_id", "")))
		for option_id in granted:
			assert_eq(
				def.display_name.to_lower().contains(option_id),
				false,
				"'%s' does not name itself after the option '%s'" % [def.id, option_id]
			)


func _generated_shapes() -> Dictionary:
	if _generated.is_empty():
		var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		var realms := ["mortal", "spirit", "earth", "heaven", "immortal", "divine"]
		var suffixes := ["base", "refined", "primed", "aged", "perfected"]
		for letter in letters:
			for digit in "0123456789":
				for realm in realms:
					for suffix in suffixes:
						_generated["%s%s_%s_%s" % [letter, digit, realm, suffix]] = true
	return _generated


func test_ids_are_unique_and_the_catalog_resolves_every_one_of_them() -> void:
	var seen := {}
	var catalog := _catalog()
	for def in _defs():
		var technique_id := String(def.id)
		assert_eq(seen.has(technique_id), false, "'%s' is unique" % technique_id)
		seen[technique_id] = true
		# Resolution is by id, not by filename, so the id the save would store is
		# the id that has to resolve.
		var resolved := catalog.definition(def.id)
		assert_ne(resolved, null, "'%s' resolves by id" % technique_id)
		assert_eq(String(resolved.id), technique_id, "'%s' resolves to itself" % technique_id)
		assert_eq(catalog.has(def.id), true, "'%s' is in the catalog" % technique_id)
		assert_eq(
			catalog.technique_ids().has(def.id),
			true,
			"'%s' is listed by the catalog" % technique_id
		)


# --- Passive identity: the DEF-0091 regression guard ------------------------


func test_no_two_techniques_grant_the_same_passive_signature() -> void:
	# THE case. A passive's contribution is its `{option_id, value}` pairs and
	# nothing else (ADR 0054), so two rows with the same pairs are the same
	# technique with a different filename — precisely the interchangeability that
	# made 1363 manuals meaningless.
	var owners := {}
	for def in _defs():
		# Only PASSIVES are compared. An ACTIVE technique carries its payload in its
		# cost block and its resolution, not in `passive_options`, so every active
		# technique would share the empty signature "" and be reported as a
		# duplicate of every other.
		if not def.is_passive() or def.passive_options.is_empty():
			continue
		var signature := _passive_signature(def)
		# `assert_eq` on the absence, NOT `assert_ne(has, false)`. This framework's
		# `assert_ne(actual, unexpected)` passes when the two DIFFER, so
		# `assert_ne(owners.has(sig), false)` passes when the key IS present — the
		# exact inverse of the intent, and it reported a duplicate for every
		# signature that was correctly unique.
		assert_eq(
			owners.has(signature),
			false,
			(
				"'%s' and '%s' grant the same options at the same values (%s)"
				% [String(owners.get(signature, &"")), String(def.id), signature]
			)
		)
		owners[signature] = def.id


func test_every_passive_carries_a_distinct_pair_of_options_within_the_cap() -> void:
	var passives := 0
	for def in _defs():
		if not def.is_passive():
			continue
		passives += 1
		assert_eq(
			def.passive_options.is_empty(), false, "'%s' is a passive and grants something" % def.id
		)
		assert_eq(
			def.passive_options.size() <= TechniquePolicy.PASSIVE_OPTION_CAP,
			true,
			(
				"'%s' holds %d options, at or below the cap of %d"
				% [def.id, def.passive_options.size(), TechniquePolicy.PASSIVE_OPTION_CAP]
			)
		)
		# The cap is what keeps a codex page a comparison rather than a table of
		# numbers, so a one-option passive also fails: there is nothing to choose.
		assert_eq(def.passive_options.size() >= 2, true, "'%s' grants a PAIR" % def.id)
		var ids := {}
		for entry in def.passive_options:
			var option_id := StringName(entry.get("option_id", ""))
			assert_ne(option_id, &"", "'%s' names its option" % def.id)
			assert_eq(ids.has(String(option_id)), false, "'%s' does not repeat an option" % def.id)
			ids[String(option_id)] = true
			assert_ne(
				float(entry.get("value", 0.0)),
				0.0,
				"'%s' grants %s a real value" % [def.id, option_id]
			)
		# It resolves through the master catalog, so a passive never carries an id
		# with no consumer.
		assert_eq(
			def.effects().size(),
			def.passive_options.size(),
			"'%s' resolves every option it authored" % def.id
		)
	assert_eq(passives > 0, true, "the tree ships passives, not just actives")


func test_every_passive_option_exists_and_is_technique_legal() -> void:
	# The load-bearing legality check. `OptionCatalog.allows_activation` derives
	# the activation channels from each record's declared `categories`, so this is
	# exactly the question "may a technique author this option?". The three
	# equipment-only fertility options (DEF-0100) fail it, which is the point.
	var catalog := OptionCatalog.instance()
	var used := {}
	for def in _defs():
		for entry in def.passive_options:
			var option_id := StringName(entry.get("option_id", ""))
			assert_eq(catalog.has_option(option_id), true, "'%s' references a real option" % def.id)
			assert_eq(
				catalog.allows_activation(option_id, ItemActivation.LEARNED),
				true,
				(
					"'%s': %s has a technique consumer (categories %s)"
					% [
						def.id,
						option_id,
						str(catalog.option_record(option_id).get("categories", [])),
					]
				)
			)
			used[String(option_id)] = true
	# ADR 0054 names these two as the reason the `cult_*` pool exists, and they
	# were used by nothing at all. An empty result here means the pool is still dead.
	assert_eq(
		used.has("cult_technique_power"), true, "cult_technique_power is activated by the tree"
	)
	assert_eq(
		used.has("cult_technique_cost_reduction"),
		true,
		"cult_technique_cost_reduction is activated by the tree"
	)


func test_the_authored_pool_stays_inside_the_technique_legal_options() -> void:
	# A whole-tree sweep rather than a per-row one, so a NEW technique carrying an
	# equipment-only option cannot hide behind the per-file assertions.
	var catalog := OptionCatalog.instance()
	for def in _defs():
		for entry in def.passive_options:
			var option_id := StringName(entry.get("option_id", ""))
			var record := catalog.option_record(option_id)
			assert_eq(
				String(record.get("status", "")) == "active",
				true,
				"'%s' does not grant the deprecated '%s'" % [def.id, option_id]
			)
			var categories: Array = record.get("categories", [])
			assert_eq(
				categories.has("technique"),
				true,
				"'%s' grants '%s', which is not technique-legal" % [def.id, option_id]
			)


# --- Paths -------------------------------------------------------------------


func test_every_path_is_a_path_state_a_shared_marker_or_a_valid_dual_join() -> void:
	for def in _defs():
		var path := def.path
		var label := "'%s' at '%s'" % [def.id, path]
		if path == TechniquePolicy.SHARED:
			continue
		if PathState.ALL.has(path):
			continue
		var pair := _dual_pair(path)
		assert_eq(pair.size() == 2, true, "%s is a DUAL join of exactly two" % label)
		for member in pair:
			assert_eq(
				PathState.ALL.has(member), true, "%s names the real path '%s'" % [label, member]
			)
		# `TechniqueDef.path_ids()` is what the slot allocator and the gate read, so
		# the authored string and the parser must agree or a technique claims no slot.
		assert_eq(def.path_ids().size() == 2, true, "%s parses to two path ids" % label)


func test_every_dual_technique_names_two_distinct_paths() -> void:
	var duals := 0
	for def in _defs():
		var pair := _dual_pair(def.path)
		if pair.is_empty():
			continue
		duals += 1
		assert_eq(pair.size() == 2, true, "'%s' names exactly two paths" % def.id)
		assert_eq(pair[0] != pair[1], true, "'%s' names two DISTINCT paths" % def.id)
		# ADR 0059: a DUAL technique commits BOTH paths, so its gate has to name
		# both and the floor is never an either/or.
		for member in pair:
			assert_eq(
				def.min_path_realm.has(member),
				true,
				"'%s' gates '%s' as well as its other path" % [def.id, member]
			)
		# And it is not a shared technique wearing a dual's name, so it must not be
		# gated on the best path instead.
		assert_eq(def.is_shared(), false, "'%s' is not SHARED" % def.id)
	assert_eq(duals >= 2, true, "at least two genuine DUAL techniques, found %d" % duals)


func test_a_shared_technique_gates_on_the_best_path_and_never_on_a_path_key() -> void:
	var shared := 0
	for def in _defs():
		if not def.is_shared():
			continue
		shared += 1
		assert_eq(
			def.min_path_realm.is_empty(),
			true,
			"'%s' is SHARED, so it uses min_realm_index, not a path key" % def.id
		)
		assert_eq(def.path_ids().size(), 1, "'%s' resolves to the single shared marker" % def.id)
	assert_eq(shared > 0, true, "the tree ships SHARED techniques")


func test_path_exclusive_techniques_gate_on_their_own_path() -> void:
	for def in _defs():
		if def.is_shared() or _dual_pair(def.path).size() == 2:
			continue
		assert_eq(PathState.ALL.has(def.path), true, "'%s' names a real path" % def.id)
		# A path floor is the ADR 0059 gate; real content has to exercise it, so a
		# path-exclusive row below the Spirit tier carries none at all.
		if def.required_tier() > 1:
			assert_eq(def.min_path_realm.has(def.path), true, "'%s' gates its own path" % def.id)


func test_every_dual_pair_of_the_ladder_is_authored() -> void:
	var pairs := {}
	for def in _defs():
		var pair := _dual_pair(def.path)
		if pair.size() == 2:
			pairs[_sorted_pair(pair)] = true
	# `first+second` and `second+first` are the SAME technique: the pair is
	# normalised by `_sorted_pair`, so the expected count is the number of UNORDERED
	# pairs, n*(n-1)/2 — three for three paths, not six. Counting the ordered pairs
	# and dividing is just as readable and does not assume the constant.
	var ordered := 0
	for first in PathState.ALL:
		for second in PathState.ALL:
			if first != second:
				ordered += 1
	var expected := ordered / 2
	assert_eq(pairs.size(), expected, "all three dual pairs are authored: %s" % [pairs.keys()])


func _sorted_pair(pair: Array[StringName]) -> String:
	var out: Array[String] = []
	for member in pair:
		out.append(String(member))
	out.sort()
	return "|".join(out)


## `Array.any()` with a bound predicate: the element lookup runs once per authored
## element, so the list is built once and the comparison is a named function.
func _is_element(entry: ElementDef, element_id: StringName) -> bool:
	return entry.id == element_id


# --- Grades, tiers and gates -------------------------------------------------


func test_every_grade_is_a_real_item_grade_constant() -> void:
	var seen := {}
	for def in _defs():
		assert_eq(ItemGrade.ALL.has(def.grade), true, "'%s' grades '%s'" % [def.id, def.grade])
		assert_eq(
			def.required_tier() >= 1 and def.required_tier() <= 4,
			true,
			"'%s' derives a real realm tier" % def.id
		)
		seen[String(def.grade)] = true
	# "Cover the whole realm ladder with a spread" is the authoring brief, and a
	# tree that skipped a grade would be a gap rather than a spread.
	for grade in ItemGrade.ALL:
		assert_eq(
			seen.has(String(grade)), true, "the tree authors at least one '%s' technique" % grade
		)
	# An untiered tree would mean grade is decorative.
	assert_eq(seen.size() == ItemGrade.ALL.size(), true, "every grade band is represented")


func test_every_rarity_is_a_real_item_rarity_constant() -> void:
	for def in _defs():
		assert_eq(
			ItemRarity.is_valid(def.rarity), true, "'%s' carries rarity '%s'" % [def.id, def.rarity]
		)


func test_every_path_floor_is_a_realm_ordinal_on_the_shared_ladder() -> void:
	for def in _defs():
		for path_id in def.min_path_realm.keys():
			assert_eq(
				PathState.ALL.has(StringName(path_id)),
				true,
				"'%s' gates the real path '%s'" % [def.id, path_id]
			)
			var floor := int(def.min_path_realm[path_id])
			assert_eq(
				floor >= 1 and floor <= MAX_REALM_ORDINAL,
				true,
				(
					"'%s' asks for %s realm %d, inside 1..%d"
					% [def.id, path_id, floor, MAX_REALM_ORDINAL]
				)
			)
			# ADR 0059 composes with the grade rather than replacing it, so the
			# ordinal is read off the shared ladder and the floor has to be a real
			# position on it.
			var ladder := RealmDefaults.ladder()
			assert_eq(
				floor <= ladder.size() - 1,
				true,
				(
					"'%s' asks for %s realm %d, inside the %d-realm ladder"
					% [def.id, path_id, floor, ladder.size()]
				)
			)


func test_every_requirement_uses_the_any_path_gate_a_shared_technique_needs() -> void:
	for def in _defs():
		if def.requirement == null:
			continue
		assert_eq(
			def.is_shared(),
			true,
			(
				(
					"'%s' authors an ItemRequirement, which is the best-path gate; only a "
					+ "SHARED technique may use it"
				)
				% def.id
			)
		)
		assert_eq(def.min_path_realm.is_empty(), true, "'%s' uses one gate, not both" % def.id)
		assert_eq(
			(
				int(def.requirement.min_realm_index) >= 1
				and int(def.requirement.min_realm_index) <= MAX_REALM_ORDINAL
			),
			true,
			"'%s' gates on a real ordinal" % def.id
		)
		# `is_empty()` must agree, or a profile carrying only a floor would report
		# as unrestricted and silently admit everyone.
		assert_eq(def.requirement.is_empty(), false, "'%s' is a real gate" % def.id)


# --- Cost block, element vocabulary and shape -------------------------------


func test_a_passive_has_no_cost_block_and_an_active_has_one() -> void:
	for def in _defs():
		if def.is_passive():
			assert_eq(def.qi_cost, 0.0, "passive '%s' costs no qi" % def.id)
			assert_eq(def.stamina_cost, 0.0, "passive '%s' costs no stamina" % def.id)
			assert_eq(def.cooldown, 0.0, "passive '%s' has no cooldown" % def.id)
			assert_eq(def.magnitude, 1.0, "passive '%s' has no magnitude of its own" % def.id)
			continue
		# An active technique pays SOMETHING per use, but not necessarily qi: a
		# recovery technique spends nothing and returns qi, so a qi-cost floor would
		# forbid exactly the techniques that restore. The cooldown is the universal
		# obligation; a resource cost is optional on top of it.
		assert_eq(def.cooldown > 0.0, true, "'%s' has a cooldown" % def.id)
		# Grade is a floor, not a scale, and the ceiling row has to look like one.
		assert_eq(
			def.magnitude > 0.0 and def.magnitude <= 6.0,
			true,
			"'%s' authors a bounded magnitude (%.2f)" % [def.id, def.magnitude]
		)


## Every path that resolves through a MECHANISM authors a share; a path that is only
## ever a pose authors none.
##
## `element_share` is ADR 0069's qi field and ADR 0071's mind `share` — the ONE authored
## field on ONE content type that both of those mechanisms read, `QiDamage` through
## `ELEMENT_SHARE_KEY` and `MindDamage` through `SHARE_KEY`. **Body is the only path that
## reads neither**, and ADR 0070 rules the elemental shape out of it outright: "What body
## must NOT share with qi. Not the element table and not the multiplicative elemental
## shape." `BodyDamage.builder` writes four keys (`aim_meridian`, `aim_mode`,
## `body_wounds`, `tuning`) and no share, so a share on a body technique reached nothing
## at all — while this guard, which predates the gap, made a share MANDATORY on any row
## carrying an element, so the two together were the defect: content the design forbids
## was the only legal content.
##
## So the requirement is scoped to the paths that CONSUME a share, which is what
## `mechanism_for_hit` can route at `QiDamage` or `MindDamage`. A body-exclusive row
## carries an `element` for status (ADR 0105) and search vocabulary only, and is now
## allowed to author its share as absent; the field's default `0.0` means "use the
## module's default" and is not "no element".
##
## An ELEMENTLESS row is either PHYSICAL (share `0.0`) or a PURE-QI blow: a positive
## share reads the omni channel, the bare `element_power_` / `element_defense_` pair
## `ElementProvider` publishes from the summed affinity and summed mastery (ADR 0004,
## "pure qi is a real omni channel"). The tuning default never reaches an elementless
## row -- it prices a technique that NAMED an element and forgot its share.
func test_a_path_that_resolves_a_share_authors_one() -> void:
	var elements := {}
	for def in _defs():
		if def.element == &"":
			# A share outside `[0, 1]` is still an authoring error: the mechanism
			# clamps it, and content must not rely on that.
			assert_eq(
				def.element_share >= 0.0 and def.element_share <= 1.0,
				true,
				(
					(
						"'%s' is unelemental: its share is 0.0 (physical) or a pure-qi "
						+ "share in (0, 1] that reads the omni channel"
					)
					% def.id
				)
			)
			continue
		assert_eq(
			ElementDefaults.all().any(_is_element.bind(def.element)),
			true,
			"'%s' names the real element '%s'" % [def.id, def.element]
		)
		if not _reads_a_share(def):
			# An element with no consuming share is the correct body/mind shape, not a
			# gap: nothing reads it, and a value here would be decoration.
			assert_eq(
				def.element_share,
				0.0,
				"'%s' resolves no share, so it authors none (ADR 0070)" % def.id
			)
			continue
		assert_eq(
			def.element_share > 0.0 and def.element_share <= 1.0,
			true,
			"'%s' routes a share of its magnitude through '%s'" % [def.id, def.element]
		)
		elements[String(def.element)] = true
	assert_eq(
		elements.size() >= 5, true, "the tree uses at least five elements: %s" % [elements.keys()]
	)


## Whether this def's mechanism consumes `element_share`: `QiDamage` through
## `ELEMENT_SHARE_KEY`, `MindDamage` through `SHARE_KEY`, body through NEITHER. A DUAL
## counts when it includes qi or mind, because `mechanism_for_hit` walks `path_ids()` in
## authored order and asks each in turn.
##
## Kept as its own function so the rule is stated once: a guard whose exemption is
## scattered through the loop is a guard whose exemption nobody can find.
static func _reads_a_share(def: TechniqueDef) -> bool:
	for path_id in def.path_ids():
		if path_id == PathState.QI or path_id == PathState.MIND:
			return true
	return false


# --- the two authored hit intents (ADR 0070's aim, ADR 0071's kind) --------------
#
# Read on the SHIPPED `.tres` deliberately. A fixture built inside a test authors the
# very field it is asserting about, so it can only ever prove the mechanism reads a
# value — never that the content ships one. These two guards close the authored-content
# half of that, which is the half that was missing.


## Every `aim_meridian` names a meridian that EXISTS, on both sides.
##
## The name must be one of `MeridianDefaults`' 20 AND one of the `meridian_id`s the
## authored huyệt carry, because those are the two vocabularies `BodyLocation` resolves
## against: `_channel_of` for the channel and `_points_of` -> `meridian_of_point` for
## the point inside it. A meridian with a channel but no huyệt resolves `locked` at a
## neutral `1.0`, and one with neither is a `named` aim at nothing, which
## `site_of` refuses outright — so both are content defects wearing a valid-looking id.
##
## And the ORDER matters: an aim whose channel unlocks DEEPER than the technique's own
## floor is a strike that resolves `random` for every actor below that tier, which is the
## silent form of this same gap. `body_crane_dance`'s first authoring was exactly that —
## `yang_qiao`, tier 12, under a technique that opens at 11.
func test_every_authored_aim_meridian_is_a_meridian_that_exists_and_can_be_unlocked() -> void:
	var authored: Dictionary = {}
	for state in MeridianDefaults.all():
		authored[String(state.id)] = int(state.tier)
	for def in _defs():
		var aim := String(def.aim_meridian)
		if aim.is_empty():
			continue
		assert_eq(
			authored.has(aim),
			true,
			"'%s' aims at '%s', which is not one of the 20 meridians" % [def.id, aim]
		)
		if not authored.has(aim):
			continue
		assert_eq(
			_acupoint_meridians().has(aim),
			true,
			(
				"'%s' aims at '%s', which carries no authored huyệt, so every strike lands "
				+ "on it at the neutral multiplier" % [def.id, aim]
			)
		)
		# A DUAL row's floor is the DEEPEST of its paths, and a named aim below that
		# floor is the same defect; the deepest is the only floor that binds.
		var floor := 0
		for realm in def.min_path_realm.values():
			floor = maxi(floor, int(realm))
		assert_eq(
			int(authored[aim]) <= maxi(floor, 0),
			true,
			(
				(
					"'%s' aims at '%s', which unlocks at tier %d, deeper than its own floor "
					+ "of %d - the aim resolves as random for every actor who can learn it"
				)
				% [def.id, aim, int(authored[aim]), floor]
			)
		)


## Every `mind_kind` is one of the three words `MindDamage._kind_of` branches on.
##
## A fourth spelling is not a new kind and not an error the mechanism raises: `_kind_of`
## answers `DISRUPT` for anything it does not recognise, so a typo silently turns an
## authored `attend` back into the plain strike. The vocabulary is therefore asserted
## HERE, where a typo is a content failure by name, and read once in
## `mind_damage.gd` — two places, and the second cannot grow a fourth without this one
## noticing.
##
## It is NOT asserted that every mind technique authors one. `TechniqueDef.mind_kind`'s
## own contract says `&""` means "no authored intent" and reads as `disrupt`, and 46 of
## the authored `.tres` are not mind techniques at all — so "author a kind or be a
## non-mind row" would be a rule about coverage, not about correctness. `still_water`'s
## own description ("it does no damage to anybody") is the honest `disrupt`, and forcing
## it to a kind would be the author inventing an intent the fiction does not claim.
func test_every_authored_mind_kind_is_one_of_the_three_real_kinds() -> void:
	for def in _defs():
		var kind := String(def.mind_kind)
		if kind.is_empty():
			continue
		assert_eq(
			["disrupt", "obscure", "attend"].has(kind),
			true,
			(
				(
					"'%s' authors the kind '%s', which is not one of disrupt/obscure/attend - "
					+ "MindDamage._kind_of reads anything else as disrupt"
				)
				% [def.id, kind]
			)
		)


## Every `meridian_id` the authored huyệt carry, read off the shipped files rather than
## restated. Read through the same directory `CombatTuning.acupoint_data_dir` names, so
## adding a twenty-first meridian needs no edit here.
static func _acupoint_meridians() -> Dictionary:
	var out: Dictionary = {}
	var directory := CombatTuning.shipped().acupoint_data_dir
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var def: Variant = ResourceLoader.load("%s/%s" % [directory, entry])
			if def is Object:
				out[String((def as Object).get(&"meridian_id"))] = true
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func test_every_defines_five_mastery_rungs_and_no_sixth() -> void:
	# ADR 0056: the per-rung multipliers are constants, not data, so a def may
	# author a lower count and never a sixth.
	for def in _defs():
		assert_eq(
			def.mastery_rungs >= 1 and def.mastery_rungs <= TechniqueScales.MAX_RUNGS,
			true,
			(
				"'%s' authors %d rungs, inside 1..%d"
				% [def.id, def.mastery_rungs, TechniqueScales.MAX_RUNGS]
			)
		)


func test_every_technique_is_learnable_by_a_top_of_the_ladder_actor() -> void:
	# Reachability, the same failure mode `test_bloodline_content` guards: a gate
	# authored above what any actor can reach is dead content, and a gate nobody
	# can pass is worse. A R30 actor on every path must clear every authored row.
	var actor := Actor.new(&"content_auditor", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.set_path(PathState.new(PathState.QI, &"primordial_origin"))
	actor.set_path(PathState.new(PathState.BODY, &"primordial_origin"))
	actor.set_path(PathState.new(PathState.MIND, &"primordial_origin"))
	for def in _defs():
		var unmet := TechniqueGate.unmet(actor, def)
		assert_eq(
			unmet.is_empty(),
			true,
			"'%s' is unreachable by a top-of-ladder actor: %s" % [def.id, str(unmet)]
		)


func test_a_path_floor_actually_refuses_an_actor_who_is_short_on_that_path() -> void:
	# The mirror of the reachability case, and the reason ADR 0059 exists: a qi
	# technique must NOT be learnable by an actor whose qi never moved, however far
	# the body has run. `dual_qi_mind_harmony_cadence` gates at ordinal 19 on both
	# paths, which is Spirit Sovereign on the shared ladder.
	var qi_deep := Actor.new(&"one_path_only", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	qi_deep.set_path(PathState.new(PathState.QI, &"primordial_origin"))
	qi_deep.set_path(PathState.new(PathState.MIND, &"qi_refining"))
	var dual := _catalog().definition(&"dual_qi_mind_harmony_cadence")
	assert_ne(dual, null, "the dual technique resolves")
	var unmet := TechniqueGate.unmet(qi_deep, dual)
	assert_eq(unmet.is_empty(), false, "one deep path does not satisfy a DUAL gate")
	var refused := ""
	for problem in unmet:
		if String(problem["id"]) == PathState.MIND:
			refused = StringName(problem["id"])
	assert_eq(refused, PathState.MIND, "the gate names the short path, so a panel can say which")


# --- Coverage across the three paths -----------------------------------------


func test_every_path_kind_the_slots_distinguish_is_authored() -> void:
	# The slot table spends a loadout across qi, body, mind, universal and DUAL
	# pairs. A tree that missed one kind would leave that pool unspendable.
	var kinds := {"qi": false, "body": false, "mind": false, "shared": false, "dual": false}
	for def in _defs():
		var pair := _dual_pair(def.path)
		if def.is_shared():
			kinds["shared"] = true
		elif pair.size() == 2:
			kinds["dual"] = true
		elif def.path == PathState.QI:
			kinds["qi"] = true
		elif def.path == PathState.BODY:
			kinds["body"] = true
		elif def.path == PathState.MIND:
			kinds["mind"] = true
	for kind in kinds.keys():
		assert_eq(kinds[kind], true, "at least one %s technique is authored" % kind)


func test_both_actives_and_passives_exist_on_every_path_kind() -> void:
	var matrix := {}
	for def in _defs():
		var kind := "dual" if _dual_pair(def.path).size() == 2 else String(def.path)
		var cell: Array = matrix.get(kind, [])
		cell.append(def.active)
		matrix[kind] = cell
	for kind in [String(PathState.QI), String(PathState.BODY), String(PathState.MIND)]:
		var cell: Array = matrix.get(kind, [])
		assert_eq(cell.has(true), true, "%s ships an ACTIVE" % kind)
		assert_eq(cell.has(false), true, "%s ships a PASSIVE" % kind)


func test_the_authored_prose_carries_no_marker_of_the_thing_this_repo_forbids() -> void:
	# AGENTS.md forbids sexual content outright. The shared and DUAL trees sit
	# closest to that territory, so the copy must stay clinical and mechanical.
	var banned := ["seduct", "arous", "orgasm", "climax", "lust", "erotic", "naked", "breast"]
	for def in _defs():
		var prose := ("%s %s" % [def.display_name, def.description]).to_lower()
		for word in banned:
			assert_eq(prose.contains(word), false, "'%s' avoids '%s'" % [def.id, word])


func test_every_id_and_display_name_is_unique_across_the_tree() -> void:
	var names := {}
	for def in _defs():
		var key := def.display_name.to_lower()
		assert_eq(
			names.has(key),
			false,
			(
				"'%s' and '%s' share the display name '%s'"
				% [String(names.get(key, &"")), String(def.id), def.display_name]
			)
		)
		names[key] = def.id
