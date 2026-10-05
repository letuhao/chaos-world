extends TestCase

## `ItemDef.sources` resolution: the reader that turns an authoring claim into an
## answer about shipping code.
##
## The content-facing tests read the **shipped** content tree on purpose. A
## fixture would pass forever after the content it mirrors is deleted, which is
## the failure this suite exists to prevent: `body_tribulation_breakthrough_pill`
## declaring `boss:body_tribulation_guardian` was only ever a string until an
## authored encounter made it true. The probes here are built from the real
## `res://data/recipes` and `res://data/loot/encounters` trees, so deleting either
## makes these tests red.

const REAL_ITEM := &"body_tribulation_breakthrough_pill"
const REAL_BOSS := "body_tribulation_guardian"
const REAL_RECIPE := "body_tribulation_pill_recipe"
const RECIPE_DIR := "res://data/recipes"
const ENCOUNTER_DIR := "res://data/loot/encounters"
const ITEMS_DIR := "res://data/items"
## Depth ceiling for the content walk below. The item tree is three levels deep;
## a ceiling is required because a symlinked directory would otherwise recurse
## until the stack gives out.
const WALK_DEPTH := 6

# --- The claim a player can actually walk ------------------------------------


func test_a_shipped_item_resolves_through_a_route_the_content_backs() -> void:
	var def := _shipped_def(REAL_ITEM)
	assert_ne(def, null, "the shipped breakthrough pill is in the content tree")
	if def == null:
		return
	var result := ItemSources.resolve(def, _content_probe())
	assert_eq(result["obtainable"], true, "a route shipping code can close exists")
	assert_eq(result["reason"], "", "nothing is reported against a satisfied item")
	assert_eq(int(result["satisfied"]) > 0, true, "at least one route is satisfied")
	assert_eq(int(result["total"]), 2, "the pill declares craft and boss routes")


func test_the_craft_route_resolves_to_a_recipe_that_exists() -> void:
	var def := _shipped_def(REAL_ITEM)
	assert_ne(def, null, "the shipped pill resolves")
	if def == null:
		return
	var craft := _route_of(ItemSources.resolve(def, _content_probe()), "craft")
	assert_eq(craft["satisfied"], true, "the recipe it names is authored")
	assert_eq(String(craft["ref"]), REAL_RECIPE, "the authored recipe id")


func test_the_boss_route_resolves_to_an_encounter_that_can_spawn_it() -> void:
	var def := _shipped_def(REAL_ITEM)
	assert_ne(def, null, "the shipped pill resolves")
	if def == null:
		return
	var boss := _route_of(ItemSources.resolve(def, _content_probe()), "boss")
	assert_eq(boss["satisfied"], true, "an authored encounter hosts the boss")
	assert_eq(String(boss["ref"]), REAL_BOSS, "the authored boss id")


func test_the_answer_is_primitives_only() -> void:
	# A panel renders this without reaching into a Resource, so no entry may hold
	# one. Asserting the shape is what keeps `ui/` from needing a new module edge.
	var def := _shipped_def(REAL_ITEM)
	if def == null:
		assert_ne(def, null, "the shipped pill resolves")
		return
	var result := ItemSources.resolve(def, _content_probe())
	_primitives_only(result, "resolve result")
	for route in result["routes"]:
		_primitives_only(route, "route")


# --- A refusal is inert ------------------------------------------------------


func test_a_boss_no_encounter_hosts_resolves_to_nothing_actionable() -> void:
	# The whole point of the reader: a claim nothing can satisfy reports itself
	# instead of passing for an obtainable item.
	var def := _shipped_def(REAL_ITEM)
	if def == null:
		assert_ne(def, null, "the shipped pill resolves")
		return
	def.sources = [&"boss:body_great_luo_guardian"]
	var result := ItemSources.resolve(def, {})
	assert_eq(result["obtainable"], false, "no probe means no established route")
	assert_eq(result["satisfied"], 0, "nothing is satisfied")
	assert_eq(String(result["reason"]), ItemSources.UNPROBED, "the reason names the gap")


func test_a_refused_route_leaves_the_caller_nothing_to_hand_on() -> void:
	var def := _shipped_def(REAL_ITEM)
	if def == null:
		assert_ne(def, null, "the shipped pill resolves")
		return
	def.sources = [&"boss:a_boss_no_encounter_hosts"]
	var probe := _content_probe()
	var result := ItemSources.resolve(def, probe)
	assert_eq(result["obtainable"], false, "the refused boss route is not satisfied")
	assert_eq(ItemSources.first_satisfied(def, probe), {}, "no route is offered")
	assert_eq(ItemSources.obtainable(def, probe), false, "the boolean agrees")
	assert_eq(_route_of(result, "boss")["satisfied"], false, "the route itself is inert")


func test_a_definition_with_no_source_is_not_obtainable() -> void:
	var def := ItemDef.new()
	def.id = &"a_numeraire_like_unit_of_account"
	assert_eq(ItemSources.obtainable(def, _content_probe()), false, "nothing is claimed")
	assert_eq(
		String(ItemSources.resolve(def, _content_probe())["reason"]),
		ItemSources.NO_SOURCE,
		"reason"
	)


func test_a_refused_route_never_counts_as_satisfied_next_to_a_working_one() -> void:
	# One refused route among several must not hide the route that does work, and
	# must not poison it either: `obtainable` is true, `reason` is empty.
	var def := _shipped_def(REAL_ITEM)
	if def == null:
		assert_ne(def, null, "the shipped pill resolves")
		return
	def.sources = [&"gather", &"boss:%s" % REAL_BOSS]
	var result := ItemSources.resolve(def, _content_probe())
	assert_eq(result["obtainable"], true, "the boss route carries the item")
	assert_eq(String(result["reason"]), "", "a working route clears the reason")
	assert_eq(int(result["satisfied"]), 1, "exactly one route works")
	assert_eq(
		String(_route_of(result, "gather")["reason"]),
		ItemSources.UNPROBED,
		(
			"the gather route is shipped but unprobed here, so it says `no_probe` rather than "
			+ "`no_shipped_route` — the two need different fixes, and now that a forager exists "
			+ "the honest remaining gap is the missing probe"
		)
	)


# --- The vocabulary ----------------------------------------------------------


func test_an_unknown_kind_is_refused_rather_than_guessed() -> void:
	var def := ItemDef.new()
	def.id = &"thing"
	def.sources = [&"dragon:an_unowned_route"]
	var result := ItemSources.resolve(def, _content_probe())
	assert_eq(result["obtainable"], false, "an unknown prefix delivers nothing")
	assert_eq(String(result["reason"]), ItemSources.UNKNOWN_KIND, "named as unknown")
	assert_eq(bool(ItemSources.routes(def)[0]["ok"]), false, "the route does not parse")


func test_a_kind_that_must_name_a_target_and_does_not_is_refused() -> void:
	var def := ItemDef.new()
	def.id = &"thing"
	def.sources = [&"boss:"]
	var route := ItemSources.routes(def)[0]
	assert_eq(bool(route["ok"]), false, "an empty reference is not a route")
	assert_eq(String(route["reason"]), ItemSources.MISSING_REF, "named as a missing ref")
	assert_eq(ItemSources.obtainable(def, _content_probe()), false, "delivers nothing")


func test_a_kind_that_must_not_name_a_target_and_does_is_refused() -> void:
	var def := ItemDef.new()
	def.id = &"thing"
	def.sources = [&"gather:somewhere"]
	var route := ItemSources.routes(def)[0]
	assert_eq(bool(route["ok"]), false, "a stray reference is not a route")
	assert_eq(String(route["reason"]), ItemSources.UNEXPECTED_REF, "named as unexpected")


func test_a_gather_route_reports_that_shipping_code_now_delivers_it() -> void:
	# ## This test INVERTED, and the reason it existed is the reason it flipped
	#
	# It used to assert `gather` was UNSHIPPED — "`gather` has no forager ... because the
	# two need different fixes". That was true, and it was the reason the route stayed
	# unflipped: a route cannot honestly be marked shipped while the reader says nothing
	# delivers it. The `forage` module now provides the verb (DEF-0201), `economy_boot`
	# installs `ForageGranary.deliver` as its granter, and `ItemSources.KIND_GATHER` is
	# `shipped: true` — so the reader must now AGREE, and this test is what makes that
	# agreement load-bearing rather than a flag someone flipped.
	#
	# The critical half is the one a flag alone cannot satisfy: **a probe that cannot
	# actually reach a node still reports the route as unsatisfied.** `shipped: true` is a
	# claim about the program's shape; the probe is the evidence. Both are asserted, so
	# neither can pass alone.
	var def := ItemDef.new()
	def.id = &"thing"
	def.sources = [&"gather"]
	# Two DIFFERENT negative probes, because the reader distinguishes them and conflating
	# them would hide that: one that answers false is PROBED and unsatisfied
	# (`route_unsatisfied`); one with no gather entry at all is UNPROBED (`no_probe`). Neither
	# may report obtainable, and the distinction is the point — the first needs a deliverable,
	# the second needs an injection.
	assert_eq(
		String(ItemSources.resolve(def, _unsatisfying_probe())["reason"]),
		ItemSources.UNSATISFIED,
		"a probe that reaches nothing reports the route unsatisfied"
	)
	var result := ItemSources.resolve(def, _content_probe())
	assert_eq(result["obtainable"], false, "and a def with no working route is not deliverable")
	assert_eq(
		String(result["reason"]),
		ItemSources.UNPROBED,
		"named as no probe, which is the honest reason and not 'no route'"
	)
	# With a probe that CAN reach a node, the same def is obtainable — which is only true
	# because the route is genuinely shipped. `_content_probe` deliberately has NO gather entry
	# (it mirrors the composition root's own injections, which predate foraging), so the
	# satisfying probe supplies one: that a route only needs a probe asking the right question.
	var delivered := ItemSources.resolve(def, _satisfying_probe())
	assert_eq(delivered["obtainable"], true, "a satisfied probe makes the shipped route deliver")
	assert_eq(ItemSources.is_shipped(ItemSources.KIND_GATHER), true, "gather is shipped")
	assert_eq(ItemSources.is_shipped(ItemSources.KIND_BOSS), true, "boss is shipped")
	assert_eq(
		String(ItemSources.KIND_GATHER) in ItemSources.unshipped_kind_ids(),
		false,
		"and gather is no longer listed among the unshipped kinds"
	)
	assert_ne(
		String(ItemSources.KIND_BOSS) in ItemSources.unshipped_kind_ids(), true, "boss is not"
	)


func test_a_duplicate_source_is_one_route() -> void:
	var def := ItemDef.new()
	def.id = &"thing"
	def.sources = [&"boss:x", &"boss:x", &"boss:y"]
	assert_eq(ItemSources.routes(def).size(), 2, "the repeated claim is one route")


func test_the_vocabulary_carries_every_kind_the_corpus_declares() -> void:
	# The drift gate. An item declaring a prefix this reader has never heard of is
	# a claim nothing can resolve, which is exactly the state the corpus was in
	# before this class existed. Read the whole item tree, so it fails the day a
	# new kind is authored without a decision about who delivers it.
	var declared := _declared_kinds()
	assert_eq(declared.size() > 0, true, "the corpus declares acquisition sources")
	var unknown: Array[String] = []
	for kind in declared:
		if not ItemSources.knows(StringName(kind)):
			unknown.append(kind)
	assert_eq(unknown, [], "every authored source kind is in the reader's vocabulary")


func test_the_corpus_declares_a_boss_route_for_a_pill_the_pill_names() -> void:
	# The reverse direction: the reader and the content must agree that this boss
	# is enterable, from the content alone. A reader whose probes disagree with
	# the audit's is worse than no reader.
	var def := _shipped_def(REAL_ITEM)
	if def == null:
		assert_ne(def, null, "the shipped pill resolves")
		return
	var probe := _content_probe()
	assert_eq(bool(probe[ItemSources.KIND_BOSS].call(REAL_BOSS)), true, "the boss is hosted")
	assert_eq(bool(probe[ItemSources.KIND_CRAFT].call(REAL_RECIPE)), true, "the recipe is authored")


# --- Content-derived probes --------------------------------------------------


## Probes built from the shipped content tree, standing in for the composition
## root's injection. Deliberately the same three questions the content audit
## asks, so a test and the audit cannot read the tree differently.
func _content_probe() -> Dictionary:
	var craft := func(recipe_id: String) -> bool:
		return ResourceLoader.exists("%s/%s.tres" % [RECIPE_DIR, recipe_id])
	var boss := func(boss_id: String) -> bool: return _hosted_bosses().has(boss_id)
	var domain := func(_domain_id: String) -> bool:
		return ResourceLoader.exists("res://data/domains/%s.tres" % _domain_id)
	return {
		ItemSources.KIND_CRAFT: craft,
		ItemSources.KIND_BOSS: boss,
		ItemSources.KIND_DOMAIN: domain,
		ItemSources.KIND_STARTER: func(_ref: String) -> bool: return false,
	}


## A probe that answers `false` for everything it is asked.
##
## This is the half that proves `gather` being `shipped: true` is not just a flipped flag.
## `is_shipped` is a CLAIM about `game/src`; the probe is the EVIDENCE that shipping code can
## actually deliver. With a probe that reaches nothing, the same `def` must still report
## `obtainable: false` — otherwise `shipped: true` would be indistinguishable from a route
## nothing implements, which is the failure `item_sources.gd`'s own `NO_SHIPPED_ROUTE` note
## warns about ("a `shipped` flag with no callable verb is a claim the audit cannot detect").
func _unsatisfying_probe() -> Dictionary:
	return {
		ItemSources.KIND_CRAFT: func(_ref: String) -> bool: return false,
		ItemSources.KIND_BOSS: func(_ref: String) -> bool: return false,
		ItemSources.KIND_DOMAIN: func(_ref: String) -> bool: return false,
		ItemSources.KIND_STARTER: func(_ref: String) -> bool: return false,
		ItemSources.KIND_GATHER: func(_ref: String) -> bool: return false,
	}


## A probe that answers `true` for everything — the delivery-side counterpart, so the
## inverted gather test can show the SAME def becoming obtainable purely because the route is
## genuinely shipped.
func _satisfying_probe() -> Dictionary:
	return {
		ItemSources.KIND_CRAFT: func(_ref: String) -> bool: return true,
		ItemSources.KIND_BOSS: func(_ref: String) -> bool: return true,
		ItemSources.KIND_DOMAIN: func(_ref: String) -> bool: return true,
		ItemSources.KIND_STARTER: func(_ref: String) -> bool: return true,
		ItemSources.KIND_GATHER: func(_ref: String) -> bool: return true,
	}


## Every boss id an authored `LootEncounterDef` lists, which is the whole of what
## `LootApi.enter_domain` can spawn. Read as text rather than loaded as resources
## so the assertion stays a statement about the shipped files.
func _hosted_bosses() -> Dictionary:
	var out: Dictionary = {}
	for path in _tres_files(ENCOUNTER_DIR):
		for boss_id in _field_array(path, "boss_ids"):
			out[boss_id] = true
	return out


func _field_array(path: String, field: String) -> Array[String]:
	return _string_name_array(FileAccess.get_file_as_string(path), "%s = " % field)


## Every `sources` prefix the authored item tree declares.
func _declared_kinds() -> Dictionary:
	var out: Dictionary = {}
	for path in _tres_files(ITEMS_DIR):
		for entry in _string_name_array(FileAccess.get_file_as_string(path), "sources = "):
			var separator := entry.find(":")
			var kind := entry if separator < 0 else entry.substr(0, separator)
			if not kind.is_empty():
				out[kind] = true
	return out


## The entries of the first `Array[StringName]([...])` literal that follows
## `marker`.
##
## The opening bracket is searched for **after** the `(`, not after the marker:
## the type name contains its own `[`, and a search from the marker lands on that
## one, which reads back as the single entry `StringName` and silently empties
## every answer built from it.
func _string_name_array(text: String, marker: String) -> Array[String]:
	var out: Array[String] = []
	var start := text.find(marker)
	if start < 0:
		return out
	var open := text.find("([", start)
	if open < 0:
		return out
	open += 1
	var close := text.find("]", open)
	if close < 0:
		return out
	for quoted in text.substr(open + 1, close - open - 1).split(","):
		var cleaned := quoted.strip_edges().trim_prefix('&"').trim_suffix('"')
		if not cleaned.is_empty():
			out.append(cleaned)
	return out


## Every `sources` prefix the authored item tree declares.
func _shipped_def(item_id: StringName) -> ItemDef:
	return Crafting.resolve(item_id)


## Every `.tres` under `root`, bounded by [constant WALK_DEPTH].
func _tres_files(root: String, depth: int = 0) -> Array[String]:
	var out: Array[String] = []
	if depth > WALK_DEPTH:
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				out.append_array(_tres_files(path, depth + 1))
			elif entry.ends_with(".tres"):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _route_of(result: Dictionary, kind: String) -> Dictionary:
	for route in result["routes"]:
		if String(route["kind"]) == kind:
			return route
	return {}


func _primitives_only(value, label: String) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in value:
				_primitives_only(value[key], "%s.%s" % [label, key])
			return
		TYPE_ARRAY:
			var index := 0
			for entry in value:
				_primitives_only(entry, "%s[%d]" % [label, index])
				index += 1
			return
		_:
			var kind := type_string(typeof(value))
			assert_eq(
				kind in ["Nil", "bool", "int", "float", "String", "StringName"],
				true,
				"%s holds a %s" % [label, kind],
			)
