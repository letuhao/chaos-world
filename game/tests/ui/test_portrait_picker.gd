extends TestCase

## The face picker at creation (ADR 0257, BL-0882).
##
## ## What this suite proves, and what it must NOT
##
## It proves the picker OFFERS only faces the resolver would honour, that it
## RECORDS through `PortraitResolver.choose` and no other verb, and that a hero
## who takes no face resolves exactly as they did before the control existed.
##
## Those three are different claims and a single happy-path test proves none of
## them alone: a picker offering everything passes "the list is non-empty", and a
## picker that never writes passes "creation still succeeds". So the negative
## cases carry their own tests, named for the defect they catch.
##
## ## What it deliberately does not prove
##
## It does not prove the catalogue is free of shadowed variants. That is
## `PortraitResolver.validate()`'s job (BL-0883), and this suite READS that
## verdict rather than restating the rule: the shadowing filter is only
## interesting when there IS a shadow, so a synthetic pair proves the filter fires
## and shipped content is left to the audit that owns it.

const SCREEN := "res://src/ui/screens/character_creation.tscn"
const PICKER_SCENE := "res://src/ui/panels/portrait_picker.tscn"
const PICKER_SOURCE := "res://src/ui/panels/portrait_picker.gd"
const SCREEN_SOURCE := "res://src/ui/screens/character_creation.gd"

## Every node this suite instantiates, tracked and released in `teardown()`.
##
## `free()`, never `queue_free()`: the runner drives every suite inside
## `SceneTree._initialize()`, where the deferred path never drains, so a queued
## free is a node that outlives the run (the 67 GB incident, AGENTS.md). Released
## from ONE place on purpose — call sites are interleaved with early returns, so
## freeing at each mint is skipped by any test that returns before the end.
var _born: Array = []


func setup() -> void:
	_born = []


func teardown() -> void:
	for node in _born:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.free()
	_born = []


# --- Fixtures ----------------------------------------------------------------


## A picker, minted through the scene so its own `_bind_nodes` runs against real
## nodes — a picker whose children never mounted would publish an empty list and
## pass every "is it empty" assertion for the wrong reason.
func _picker() -> PortraitPicker:
	var picker := (load(PICKER_SCENE) as PackedScene).instantiate() as PortraitPicker
	_born.append(picker)
	return picker


## The creation screen, committed through the real flow so the hero, the race and
## the face all come from the same path a player walks.
func _screen() -> CharacterCreation:
	var screen := (load(SCREEN) as PackedScene).instantiate() as CharacterCreation
	_born.append(screen)
	screen.bind_creation(CharacterCreationFlow.new().candidates(), _commit)
	return screen


func _commit(origin_id: StringName) -> Dictionary:
	return CharacterCreationFlow.new().build(origin_id)


# --- Offering ----------------------------------------------------------------


## The published list is sorted by id and deterministic, which is what makes the
## offer the same on two reads rather than a `DirAccess` order.
func test_options_are_sorted_by_id_and_do_not_reorder_between_reads() -> void:
	var picker := _picker()
	picker.show_race(&"emberblood")
	var first: Array = picker.summary().get("option_ids", [])
	assert_eq(first.size() > 0, true, "the emberblood body has faces to offer")
	var sorted := first.duplicate()
	sorted.sort()
	assert_eq(first, sorted, "offered in SORTED id order")
	picker.show_race(&"emberblood")
	assert_eq(picker.summary().get("option_ids", []), first, "and a second read is identical")


## A tidecaller may not wear a stoneborn's face, and the placeholder is not a
## face anyone chooses — it is the answer to having no art (ADR 0131).
func test_only_this_bodies_own_faces_are_offered() -> void:
	var picker := _picker()
	picker.show_race(&"stoneborn")
	var offered: Array = picker.summary().get("option_ids", [])
	assert_eq(offered.size() > 0, true, "the stoneborn body has faces")
	var catalog := PortraitCatalog.instance()
	for raw in offered:
		var id := StringName(raw)
		var def := catalog.portrait_definition(id)
		assert_ne(def, null, "%s is a real authored portrait" % id)
		assert_eq(def.race_id, &"stoneborn", "%s belongs to the body that offered it" % id)
		assert_eq(def.is_placeholder(), false, "%s is not the fallback face" % id)


## The shadowing filter, exercised where it can actually fire.
##
## ## Why a SYNTHETIC shadow, and why that is the honest form
##
## Shipped content is what BL-0883 is about, and cutting it is a separate change.
## Asserting against today's tree would make this test permanently green while the
## shadowing still exists, and permanently red the day the duplicates are cut —
## a test measuring the content rather than the rule. So a synthetic pair is
## registered through the catalog's own probe seam, the LOSER is shown to be
## filtered out, and the probe is cleared in the same test: the headless runner
## shares one process, so a probe left registered would be visible to every suite
## after this one.
func test_a_shadowed_variant_is_never_offered() -> void:
	var catalog := PortraitCatalog.instance()
	# ## The names carry the ORDER, and the order is the whole test
	# ##
	# `for_variant` takes the FIRST in sorted id order (ADR 0177), so the two
	# probe names are chosen so the REACHABLE one sorts first and the SHADOWED one
	# sorts second. Naming them the other way round would make the loser the
	# winner, and the test would assert the opposite of the rule it is guarding.
	var holder_id := &"aaa_probe_variant_holder"
	var shadow_id := &"zzz_probe_shadowed_face"
	var race := &"proberace"
	# Both declare the SAME variant, which is what makes them a collision rather
	# than two unrelated faces.
	var holder := _probe_face(holder_id, race, "probe-collision")
	var shadow := _probe_face(shadow_id, race, "probe-collision")
	catalog.with_probe(holder)
	catalog.with_probe(shadow)
	var picker := _picker()
	picker.show_race(race)
	var offered: Array = picker.summary().get("option_ids", [])
	# Cleared BEFORE the assertions so a failed assert cannot leave a probe in a
	# process-wide singleton the next suite would read (INC-0016).
	catalog.clear_probe(holder_id)
	catalog.clear_probe(shadow_id)
	assert_eq(offered.has(String(shadow_id)), false, "the SHADOWED face is never offered")
	assert_eq(offered.has(String(holder_id)), true, "but the reachable one is offered")
	assert_eq(
		offered.size(),
		1,
		"exactly one of a colliding pair is offered — two would render identically"
	)


## A synthetic `PortraitDef` for the probe seam. Registered through
## `PortraitCatalog.with_probe` and cleared in the same test.
func _probe_face(id: StringName, race: StringName, variant: String) -> PortraitDef:
	var def := PortraitDef.new()
	def.id = id
	def.display_name = "Probe %s" % String(id)
	def.race_id = race
	# `role:` is an axis ADR 0177 named, and it is what makes this a SELECTABLE
	# variant rather than a palette the picker would ignore.
	def.visual_traits = [&"role:%s" % variant]
	return def


# --- Recording ---------------------------------------------------------------


## The whole point of the feature: the chosen face SURVIVES, and it is recorded
## through the one verb that owns it.
##
## The save round trip is asserted through `Actor.to_dict` and `from_dict` rather
## than by reading the field back off the live actor, because a field written on
## an object and read from the same object proves persistence was never involved.
func test_a_chosen_face_is_recorded_and_survives_a_save_round_trip() -> void:
	var screen := _screen()
	var option := _first_offered_face(screen)
	assert_eq(option.is_empty(), false, "this body has a face to choose")
	assert_eq(screen.act_choose_face(StringName(option)), true, "the face is accepted")
	var outcome := screen.act_commit(&"the_one_who_stayed")
	assert_eq(bool(outcome.get("ok", false)), true, "creation commits")
	var hero := outcome.get("actor", null) as Actor
	assert_ne(hero, null, "and mints a hero")
	assert_eq(
		String(PortraitResolver.chosen_portrait_id(hero)),
		option,
		"the hero carries the face through PortraitResolver.choose"
	)
	var restored := Actor.from_dict(hero.to_dict())
	assert_eq(
		String(PortraitResolver.chosen_portrait_id(restored)),
		option,
		"and the face survives a save round trip"
	)
	var view := PortraitResolver.resolve(restored, &"stoneborn")
	assert_eq(String(view.get("portrait_id", "")), option, "resolve honours the choice")
	assert_eq(String(view.get("source", "")), "chosen", "and names WHICH step answered")


## `choose` is the ONLY write. A second persistence path or a second field would
## pass every behavioural test above and still be a second answer to "what is
## this hero's face", which is the drift ADR 0257 §1 forbids.
func test_the_choice_is_recorded_through_choose_and_nothing_else() -> void:
	var screen := _screen()
	var option := _first_offered_face(screen)
	screen.act_choose_face(StringName(option))
	var outcome := screen.act_commit(&"the_one_who_stayed")
	var hero := outcome.get("actor", null) as Actor
	var appearance: Dictionary = hero.get_module_data(PortraitResolver.APPEARANCE_KEY)
	assert_eq(
		appearance.size(),
		1,
		"exactly one field was written: a second key would be a second copy of the face"
	)
	assert_eq(
		String(appearance.get(PortraitResolver.PORTRAIT_FIELD, "")),
		option,
		"and it is the resolver's own field name, not a private one"
	)


# --- Optionality -------------------------------------------------------------


## THE test for "choosing is optional and never blocks creation". A hero who takes
## no face resolves race-then-placeholder, byte for byte as they did before this
## control existed.
func test_a_hero_with_no_chosen_face_resolves_exactly_as_before() -> void:
	var screen := _screen()
	var outcome := screen.act_commit(&"the_one_who_stayed")
	assert_eq(bool(outcome.get("ok", false)), true, "creation commits with no face chosen")
	var hero := outcome.get("actor", null) as Actor
	assert_eq(
		String(PortraitResolver.chosen_portrait_id(hero)),
		"",
		"nothing was recorded, so there is no second path to have written one"
	)
	var view := PortraitResolver.resolve(hero, &"stoneborn")
	assert_eq(String(view.get("source", "")), "race", "the hero resolves by their body")
	assert_eq(bool(view.get("is_placeholder", true)), false, "and has an authored face")


## An EMPTY catalogue cannot fail a creation. The picker is fed a body nobody
## authored a face for, and the hero still arrives.
func test_an_empty_offer_never_fails_creation() -> void:
	var picker := _picker()
	picker.show_race(&"no_such_body_at_all")
	var view: Dictionary = picker.summary()
	assert_eq(bool(view.get("has_options", true)), false, "there is nothing to offer")
	assert_eq((view.get("option_ids", []) as Array).size(), 0, "and the list says so")
	var screen := _screen()
	assert_eq(screen.act_choose_face(&""), true, "taking no face is a legal answer")
	var outcome := screen.act_commit(&"the_one_who_stayed")
	assert_eq(bool(outcome.get("ok", false)), true, "and creation commits regardless")


## An id the picker never offered is refused, so the control cannot become a way
## to write a face the catalogue cannot explain.
func test_a_face_the_picker_never_offered_is_refused() -> void:
	var screen := _screen()
	assert_eq(screen.act_choose_face(&"no_such_face"), false, "an unoffered face is refused")
	assert_eq(String(screen.chosen_portrait()), "", "and nothing was held")


# --- The bound ---------------------------------------------------------------


## The bound is the ONE shared number. A list built by walking the catalogue is a
## `for` over a data-derived row count with one live Control per row — the shape
## behind the recorded 67 GB / 105 GB commit incident (INC-0002).
func test_the_offer_is_clamped_through_the_shared_row_budget() -> void:
	var source := _code_only(PICKER_SOURCE)
	assert_eq(
		source.contains("RowBudget.cap("),
		true,
		"the picker clamps its catalogue walk through the shared helper"
	)
	# One cap, in the picker's own walk. A SECOND `RowBudget.cap` in this file
	# would be a second independently-chosen ceiling, which is the drift
	# `row_budget.gd:17-20` names as the reason the helper is shared.
	assert_eq(
		source.count("RowBudget.cap("),
		1,
		"exactly one call site, so there is one number and not six that drift"
	)
	assert_eq(source.count("MAX_ROWS"), 0, "and no private ceiling of its own")


## The published counts are what let a truncated list SAY it is truncated instead
## of appearing to end (AGENTS.md: a screen that reports N of M).
func test_the_summary_reports_shown_of_total_and_truncation() -> void:
	var picker := _picker()
	picker.show_race(&"emberblood")
	var view: Dictionary = picker.summary()
	assert_eq(view.has("option_count"), true, "the shown count is published")
	assert_eq(view.has("total_count"), true, "and the total it came from")
	assert_eq(
		int(view.get("option_count", 0)),
		int(view.get("total_count", -1)),
		"an untruncated list shows all of it"
	)
	assert_eq(bool(view.get("truncated", true)), false, "and does not claim truncation")
	for entry in picker.options():
		assert_eq(bool(entry.get("honoured", false)), true, "every option is honoured")


## A screen summary is primitives only, and the picker's own is nested under its
## key rather than flattened into a second copy (AGENTS.md).
func test_the_picker_summary_is_primitives_only() -> void:
	var picker := _picker()
	picker.show_race(&"emberblood")
	_assert_primitive_tree(picker.summary(), "the picker summary", 0)


func _assert_primitive_tree(value: Variant, label: String, depth: int) -> void:
	if depth > 4:
		return
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				_assert_primitive_tree((value as Dictionary)[key], label, depth + 1)
		TYPE_ARRAY:
			for entry in value as Array:
				_assert_primitive_tree(entry, label, depth + 1)
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			assert_eq(true, true, "%s carries a primitive" % label)
		_:
			assert_eq(
				true,
				false,
				"%s carries a %s, which is not a primitive" % [label, type_string(typeof(value))]
			)


## The first face the screen's own picker offers, or `""` when it offers none.
##
## Asked DIRECTLY, not through `screen.summary()`: that summary is `{}` before a
## hero exists, and the offer must be readable before then — the face is part of
## the answer the player is giving, not a thing that appears with the hero.
func _first_offered_face(screen: CharacterCreation) -> String:
	screen.refresh_candidates()
	var picker := screen.get_node_or_null("%PortraitPicker") as PortraitPicker
	if picker == null:
		return ""
	for entry in picker.options():
		var id := String(entry.get("portrait_id", ""))
		if not id.is_empty():
			return id
	return ""


## The CODE of a GDScript file, with every comment line removed. The structural
## guard searches source for a helper name and these files DOCSTRING it, so the
## search must be about code rather than about the prose documenting the rule.
func _code_only(path: String) -> String:
	var code := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		code += line + "\n"
	return code
