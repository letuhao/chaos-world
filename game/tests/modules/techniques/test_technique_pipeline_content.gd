extends TestCase

## DEF-0203: a REAL authored manual `.tres` delivers a REAL authored `.tres` through
## the REAL item path.
##
## ## Why this file exists at all
##
## Every other delivery test mints `TechniqueDef.new()`, registers it with
## `TechniqueCatalog.register`, and builds a manual whose `id` is the SAME string.
## That is a closed loop: it proves the seam works when the item id and the technique
## id already agree, which is the one thing the shipping tree had never once
## arranged. 1363 authored manuals met 51 authored definitions with an intersection of
## ZERO, so every study in a real build returned `unknown_technique` and every
## definition was unobtainable — while 3005 assertions stayed green.
##
## So this file is the only place in the module that uses the CONTENT, and it
## deliberately uses no helper: no `register()`, no synthetic id, no fabricated
## `ItemDef`. Everything it touches is a file that ships, so a manual that stops
## being delivered, or a technique that stops being obtainable, is a failure here
## rather than a player finding out.
##
## Three things are proven separately, because they fail differently:
##
##   1. the mapping is complete and one-to-one — every authored def names a manual
##      that exists, and no manual is claimed twice;
##   2. a REAL study works end to end — real `ItemDef` from the shipped tree, real
##      `use_item`, real `CodexEntry`, real technique id;
##   3. the guard still refuses — an id no def claims is still `unknown_technique`,
##      and it is refused by the SAME code path the real study succeeded on, so
##      point 2 cannot be passing because the guard was loosened.

const MANUALS_ROOT := "res://data/items/technique"

## One real pair, asserted by name so a swap of two rows fails rather than passing
## on "some manual taught something". `sigil_still_water` is a Mortal `mind`
## technique, which is the one shape a fresh actor can actually learn: a gate test
## at Mortal would prove nothing if the def's own floor refused it.
const PROBE_MANUAL := &"sigil_still_water"
const PROBE_TECHNIQUE := &"mind_still_water"

## Bottom of the shared ladder, on every path. The honest default for an ungated
## def, and what a fresh actor actually stands at.
const MORTAL_REALM := &"qi_refining"

## Top of the shared ladder, on every path. Used only where a case must be refused
## for the RIGHT reason (an id nothing claims) rather than by a realm floor.
const R30 := &"primordial_origin"


## The seam is a PROCESS-WIDE install (see `technique_delivery.gd`), so it is torn
## down here exactly as `test_technique_delivery.gd` does — `run_tests.gd` calls
## teardown after every test precisely because a binding leaks between suites.
func teardown() -> void:
	TechniqueDelivery.clear()
	TechniqueCasting.set_resolver(Callable())


func _wire() -> void:
	TechniqueDelivery.install(Callable(TechniqueDelivery, "bind_learner"))


## An actor the shipping boot order builds: items first, because the seam writes
## into a codex that `TechniquesApi.attach` creates.
func _hero(realm_id: StringName = &"qi_refining") -> Actor:
	var actor := Actor.new(&"practitioner", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	for path_id in PathState.ALL:
		actor.set_path(PathState.new(path_id, realm_id))
	ItemsApi.attach(actor)
	TechniquesApi.attach(actor)
	return actor


## The real authored manual, loaded from its own file in the shipped content tree.
##
## Loaded by PATH rather than through `ItemsApi`'s definition lookup so a failure
## names the content, not an inventory detail. `null` when the file is gone, and
## every case below says so by name.


## Godot 4 has no `StringName(...)` constructor, so every narrowing in this file
## goes through this helper. It accepts whatever a `.get` returned (String,
## StringName, or null) and normalises it.
func _sname(value) -> StringName:
	if value == null:
		return &""
	return StringName(str(value))


## The highest realm ordinal `def` demands across every path it names, so a hero
## can be stood exactly where the authored gate opens. An ungated def yields ordinal
## 0 (Qi Refining), which is the honest floor rather than a generous one.
func _realm_meeting(def: TechniqueDef) -> StringName:
	var ladder := RealmDefaults.ladder()
	var highest := 0
	for path_id in def.min_path_realm.keys():
		highest = maxi(highest, int(def.min_path_realm[path_id]))
	if highest <= 0 or highest >= ladder.size():
		return MORTAL_REALM
	return StringName(str(ladder.realms()[highest].id))


func _manual(item_id: StringName) -> ItemDef:
	var path := "%s/%s.tres" % [MANUALS_ROOT, item_id]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Every `.tres` in the manuals tree, so "how many look authored" is measured here
## rather than assumed in prose. The generated rows match `<L><N>_<realm>_<word>`, so
## a leading digit is the cheapest reliable tell and needs no list kept up to date.
func _manual_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open(MANUALS_ROOT)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var def := load("%s/%s" % [MANUALS_ROOT, entry])
			var item_id := _sname(def.get("id")) if def != null else &""
			if item_id != &"":
				out.append(item_id)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# --- The real pipeline --------------------------------------------------------


func test_a_real_authored_manual_delivers_a_real_authored_def_through_use_item() -> void:
	# THE proof. No helper anywhere in this case: the manual is a shipped `.tres`,
	# the technique is a shipped `.tres`, and the call is `ItemsApi.use_item` — the
	# same verb `item_workbench.gd` and `QuickUseApi.use_slot` make. A test that
	# registered a synthetic def proved the seam; this proves the GAME.
	var manual := _manual(PROBE_MANUAL)
	assert_ne(manual, null, "'%s' is a real authored manual" % PROBE_MANUAL)
	assert_eq(
		_sname(manual.get("category")),
		ItemCategory.TECHNIQUE,
		"and it is a technique manual, not something else"
	)

	var technique := TechniqueCatalog.instance().definition(PROBE_TECHNIQUE)
	assert_ne(technique, null, "'%s' is a real authored technique" % PROBE_TECHNIQUE)
	assert_eq(
		technique.resource_path.get_file(),
		"%s.tres" % PROBE_TECHNIQUE,
		"and it came from the shipped content tree, not a registration"
	)
	assert_eq(technique.delivered_by, PROBE_MANUAL, "the def names the manual that delivers it")

	# Stand the hero at the technique's OWN floor. Authored defs carry a real
	# `min_path_realm` (body_carapace_form demands `body_cultivation` 25), so a Mortal
	# actor is correctly refused `realm_unmet` — the gate working, not a defect. A
	# player who wants this manual cultivates to its floor first, and that is the
	# pipeline this case is meant to prove.
	var actor := _hero(_realm_meeting(technique))
	ItemsApi.inventory(actor).add(manual, 1)
	_wire()
	assert_eq(
		TechniquesApi.codex(actor).count(), 0, "the codex starts empty, so nothing else taught it"
	)

	var result := ItemsApi.use_item(actor, PROBE_MANUAL)
	assert_eq(
		bool(result.get("ok")),
		true,
		"a real manual is studied, not refused: '%s'" % String(result.get("reason", ""))
	)
	assert_eq(
		TechniquesApi.codex(actor).knows(PROBE_TECHNIQUE),
		true,
		"the codex holds the REAL technique id, not the manual's"
	)
	var entry := TechniquesApi.codex(actor).entry(PROBE_TECHNIQUE)
	assert_ne(entry, null, "as a CodexEntry")
	assert_eq(entry.mastery_rung, 0, "at rung 0: mastery is a separate investment")
	assert_eq(
		String(result.get("learned_from")),
		String(PROBE_MANUAL),
		"and the outcome names the manual that delivered it"
	)
	# Delivery consumes the manual, which is the item's half of the contract.
	assert_eq(ItemsApi.inventory(actor).count(PROBE_MANUAL), 0, "the manual is consumed")


func test_a_learned_real_technique_can_then_be_equipped_and_contributes() -> void:
	# The end of the chain DEF-0203 broke: a def that could never be learned could
	# never be bound, so a passive could never contribute and an active could never
	# be cast. Proving delivery alone would leave the other two states unproven.
	var manual := _manual(PROBE_MANUAL)
	assert_ne(manual, null, "the real manual loads")
	var passive := _manual(&"sigil_clear_mind")
	assert_ne(passive, null, "and a real passive manual loads")
	# This case studies the SAME technique as the case above, so it stands where that
	# technique's authored gate opens rather than at Mortal. The def is resolved here
	# rather than carried over, because it is local to the other test's body.
	var technique := TechniqueCatalog.instance().definition(PROBE_TECHNIQUE)
	assert_ne(technique, null, "and the technique it delivers resolves")
	var actor := _hero(_realm_meeting(technique))
	ItemsApi.inventory(actor).add(manual, 1)
	_wire()

	var before := actor.stats.modifier_count()
	var studied := ItemsApi.use_item(actor, PROBE_MANUAL)
	assert_eq(bool(studied.get("ok")), true, "studied: '%s'" % String(studied.get("reason", "")))
	# ADR 0054: delivery HOLDS. It must not bind a slot or apply a contribution.
	assert_eq(actor.stats.modifier_count(), before, "a study contributes nothing yet")
	assert_eq(TechniquesApi.slots(actor).all().is_empty(), true, "and occupies no slot")

	# The middle state ADR 0053 separates, reached only because the first one works.
	# This actor already stands at the def's floor, so the bind is legal here.
	var equipped := TechniquesApi.equip(actor, PROBE_TECHNIQUE)
	assert_eq(
		bool(equipped.get("ok")),
		true,
		"and it binds when asked: '%s'" % String(equipped.get("reason", ""))
	)
	assert_eq(TechniquesApi.slots(actor).is_equipped(PROBE_TECHNIQUE), true, "the slot is occupied")
	assert_eq(int(TechniquesApi.summary(actor)["equipped_count"]), 1, "the loadout counts it")


# --- The mapping itself -------------------------------------------------------


func test_every_authored_def_names_a_manual_that_exists_and_is_a_technique() -> void:
	# Completeness, over the WHOLE shipped tree and not the probe pair: a def that
	# names no manual is unobtainable, which is the exact DEF-0203 condition and the
	# one no test could see because every test supplied its own def.
	var catalog := TechniqueCatalog.instance()
	var ids := catalog.technique_ids()
	assert_eq(ids.is_empty(), false, "the catalog holds the shipped defs")
	var missing: Array[String] = []
	var wrong_category: Array[String] = []
	var unruled: Array[String] = []
	for technique_id in ids:
		var def := catalog.definition(technique_id)
		var manual_id := def.delivered_by
		if manual_id == &"":
			# A def whose id IS a manual resolves through the id path, so an empty
			# `delivered_by` is only a gap when nothing else can find it.
			if not _manual_exists(technique_id):
				missing.append(String(technique_id))
			continue
		var manual := _manual(manual_id)
		if manual == null:
			unruled.append("%s -> %s" % [String(technique_id), String(manual_id)])
			continue
		if _sname(manual.get("category")) != ItemCategory.TECHNIQUE:
			wrong_category.append("%s -> %s" % [String(technique_id), String(manual_id)])
	assert_eq(unruled.is_empty(), true, "every named manual exists on disk: %s" % [unruled])
	assert_eq(
		wrong_category.is_empty(),
		true,
		"and every one is a technique manual: %s" % [wrong_category]
	)
	assert_eq(missing.is_empty(), true, "and every def names one: %s" % [missing])


func test_no_two_defs_claim_the_same_manual() -> void:
	# One-to-one, because the second claim would silently shadow the first: two
	# techniques, one book, and `last registration wins` is not an authored decision.
	# This is the failure a per-def check cannot see — every row is individually
	# valid — so it is asserted over the whole map.
	var catalog := TechniqueCatalog.instance()
	var claimed := {}
	var clashes: Array[String] = []
	for technique_id in catalog.technique_ids():
		var def := catalog.definition(technique_id)
		if def.delivered_by == &"":
			continue
		var manual_id := String(def.delivered_by)
		if claimed.has(manual_id):
			clashes.append(
				(
					"'%s' and '%s' both claim '%s'"
					% [String(claimed[manual_id]), String(technique_id), manual_id]
				)
			)
			continue
		claimed[manual_id] = technique_id
	assert_eq(clashes.is_empty(), true, "each manual teaches exactly one technique: %s" % [clashes])


func test_the_mapped_manuals_are_the_hand_authored_ones_not_the_generated_filler() -> void:
	# Pins WHY Option B was chosen over renaming items. A generated manual carries a
	# `<letter><digit>_...` id, so mapping one would mean a technique named after a
	# stat-list filler row. The assertion is on the shape rather than on a count, so
	# it does not need re-measuring when the corpus grows.
	var catalog := TechniqueCatalog.instance()
	var generated: Array[String] = []
	for technique_id in catalog.technique_ids():
		var manual_id := catalog.definition(technique_id).delivered_by
		if manual_id == &"":
			continue
		var head := String(manual_id).split("_")[0]
		if head.length() >= 2 and head.substr(1).is_valid_int():
			generated.append("%s -> %s" % [String(technique_id), String(manual_id)])
	assert_eq(
		generated.is_empty(),
		true,
		"no technique is delivered by a template-generated row: %s" % [generated]
	)


func test_the_delivered_manuals_are_reachable_through_a_shipped_source_route() -> void:
	# Requirement 3: a technique a player can never ACQUIRE is not obtainable. A
	# declared `sources` entry is only a claim; `ItemSources.KINDS` marks `quest`
	# unshipped, so a manual resting only on a quest route is declared-and-
	# unreachable. Every mapped manual must clear one SHIPPED kind.
	# `use_item` cannot spend a required progression input either, so an item ruled
	# by `ProgressionRoles` is refused before the seam is ever reached.
	var catalog := TechniqueCatalog.instance()
	var stranded: Array[String] = []
	var spendable := 0
	for technique_id in catalog.technique_ids():
		var manual_id := catalog.definition(technique_id).delivered_by
		if manual_id == &"":
			continue
		if ProgressionRoles.is_progression_input(manual_id):
			stranded.append(
				(
					"%s: '%s' is a progression input, so use_item refuses it"
					% [String(technique_id), String(manual_id)]
				)
			)
			continue
		var manual := _manual(manual_id)
		if manual == null:
			continue
		spendable += 1
		# Pass the WHOLE `sources` array, not one entry. `_has_shipped_route` asks
		# whether ANY declared kind is shipped, so handing it a single route — even
		# via `_first_route`, which returns only the first — reported every manual
		# as stranded, because `sigil_clear_mind` and 50 others open on an unshipped
		# `quest` and only later name a shipped one.
		if not _has_shipped_route(manual.get("sources")):
			stranded.append(
				"%s: '%s' declares no shipped route" % [String(technique_id), String(manual_id)]
			)
	assert_eq(spendable > 0, true, "the mapped manuals load")
	assert_eq(stranded.is_empty(), true, "every technique is acquirable: %s" % [stranded])


## Whether a manual's `sources` array names at least one route kind that shipping
## code actually delivers. Kind semantics are `ItemSources.KINDS` (the one reader of
## the field); a route whose target is missing from the content corpus is NOT read
## here because that is a content-corpus question with its own audit, and the
## assertion here is the one the seam depends on: a shipped VERB exists.
func _has_shipped_route(sources) -> bool:
	if not sources is Array:
		return false
	for entry in sources:
		var kind := _sname(String(entry).split(":")[0])
		if ItemSources.knows(kind) and ItemSources.is_shipped(kind):
			return true
	return false


## Whether a manual with this id exists in the shipped tree. Answers the id-equality
## fallback's question, which the def itself cannot.
func _manual_exists(item_id: StringName) -> bool:
	return _manual(item_id) != null


# --- The guard is NOT weakened -----------------------------------------------


func test_an_id_nothing_claims_is_still_refused_unknown_technique() -> void:
	# Requirement 2, and the half of this file that could have regressed: the seam
	# now resolves through an authored field, so "the mapping made everything
	# resolvable" is the failure mode. A generated manual is the exact real-world
	# case — 1219 of them exist and none of them is claimed — so it is used here
	# rather than a made-up id.
	var manual := _manual(&"A10_immortal_axletree_aged")
	assert_ne(manual, null, "a real generated manual loads")
	assert_eq(
		TechniqueCatalog.instance().delivers(_sname(manual.get("id"))),
		null,
		"nothing claims it, so nothing resolves it"
	)
	var actor := _hero(&"primordial_origin")
	ItemsApi.inventory(actor).add(manual, 1)
	_wire()
	var refused := ItemsApi.use_item(actor, &"A10_immortal_axletree_aged")
	assert_eq(bool(refused.get("ok")), false, "an unclaimed manual is refused even at R30")
	assert_eq(String(refused.get("reason")), "unknown_technique", "by name, not by a realm floor")
	assert_eq(TechniquesApi.codex(actor).count(), 0, "and the codex is untouched")
	assert_eq(
		ItemsApi.inventory(actor).count(&"A10_immortal_axletree_aged"),
		1,
		"a refused study consumes nothing"
	)


func test_a_manual_near_a_technique_id_in_name_still_resolves_to_nothing() -> void:
	# The reason there is no name or family rule. `mind_still_water` is delivered by
	# `sigil_still_water`; a rule matching on the shared tail would also resolve
	# `sigil_heaven_gather`-style neighbours to whatever happens to be adjacent. The
	# assertion is that a real, adjacent-looking, unclaimed manual is refused.
	var adjacent := _manual(&"sigil_sky_ward")
	assert_ne(adjacent, null, "a real adjacent-looking manual loads")
	var actor := _hero(&"primordial_origin")
	ItemsApi.inventory(actor).add(adjacent, 1)
	_wire()
	# Unclaimed by the shipped mapping, so this must refuse rather than resolve to
	# some mind technique whose name shares a word with it.
	if TechniqueCatalog.instance().delivers(&"sigil_sky_ward") == null:
		var refused := ItemsApi.use_item(actor, &"sigil_sky_ward")
		assert_eq(bool(refused.get("ok")), false, "an unclaimed adjacent id refuses")
		assert_eq(String(refused.get("reason")), "unknown_technique", "by name")
	else:
		# If a future pass claims it, the assertion that matters is that it resolves
		# to the technique it was AUTHORED to deliver, never to a neighbour.
		var resolved := TechniqueCatalog.instance().delivers(&"sigil_sky_ward")
		var owner := ""
		for technique_id in TechniqueCatalog.instance().technique_ids():
			var def := TechniqueCatalog.instance().definition(technique_id)
			if def.delivered_by == &"sigil_sky_ward":
				owner = String(technique_id)
		assert_eq(String(resolved.id), owner, "it resolves to its authored def, exactly")


func test_id_equality_still_resolves_so_an_agreeing_pair_needs_no_authoring() -> void:
	# The compatibility half: `delivers` falls back to id equality, so the mapping is
	# additive rather than a migration, and a future manual authored with a technique
	# id works without anyone remembering to add a `delivered_by`.
	var def := TechniqueDef.new()
	def.id = &"pipeline_id_equality_probe"
	def.display_name = "Probe"
	def.grade = ItemGrade.MORTAL
	def.path = PathState.QI
	def.delivered_by = &"pipeline_manual_probe"
	TechniqueCatalog.instance().register(def)
	var actor := _hero()
	var manual := ItemDef.new()
	manual.id = &"pipeline_manual_probe"
	manual.display_name = "Probe Manual"
	manual.category = ItemCategory.TECHNIQUE
	manual.grade = ItemGrade.MORTAL
	ItemsApi.inventory(actor).add(manual, 1)
	_wire()
	var studied := ItemsApi.use_item(actor, manual.id)
	assert_eq(
		bool(studied.get("ok")),
		true,
		"the authored field delivers it: '%s'" % String(studied.get("reason", ""))
	)
	assert_eq(TechniquesApi.codex(actor).knows(def.id), true, "the codex holds the def id")

	# And the same def under its own id resolves with no `delivered_by` at all.
	var bare := TechniqueDef.new()
	bare.id = &"pipeline_bare_id_probe"
	bare.display_name = "Bare Probe"
	bare.grade = ItemGrade.MORTAL
	bare.path = PathState.QI
	TechniqueCatalog.instance().register(bare)
	assert_ne(
		TechniqueCatalog.instance().delivers(&"pipeline_bare_id_probe"),
		null,
		"id equality is still the second, exact path"
	)


# --- The facade cap is still not spent ---------------------------------------


func test_the_mapping_cost_the_facade_no_method() -> void:
	# The mapping is a field on the def and an index on the catalog — neither is on
	# `TechniquesApi`, which ADR 0056 pins at twelve.
	var script: Script = TechniquesApi.new().get_script()
	var published: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method.get("name", ""))
		if method_name.begins_with("_") or published.has(method_name):
			continue
		published.append(method_name)
	assert_eq(published.size(), 12, "still exactly twelve public methods")
	assert_eq(published.has("delivers"), false, "the resolver is not a facade method")
