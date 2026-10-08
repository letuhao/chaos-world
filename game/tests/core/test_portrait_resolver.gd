extends TestCase

## ADR 0131: a portrait is derived from authored ids and the generator stays optional.
##
## ## The invariant that matters most
##
## **Resolution is total.** Every actor gets a face, including an NPC that never went through
## creation and an actor whose authored portrait was deleted from the content tree. That is what
## makes a panel able to render without defending against a null.
##
## ## The other invariant
##
## **The resolver never reads the asset index.** That is what keeps the deferred generator
## optional rather than load-bearing, and it is asserted structurally below — a value assertion
## cannot see it, because deleting the index and deleting the authored `.tres` both produce a
## missing portrait and only one of them is the defect.

## The expression text `unique-0001__expression-02` declares. Held in one place because four
## tests ask for a variant and three of them must ask for the SAME one — a test that retyped it
## would drift from the resource and pass for the wrong reason. Concatenated rather than one long
## literal because gdformat re-joins a parenthesised single string and lands over the 100 limit.
const EXPRESSION_VARIANT := (
	"expression:flat professional focus, eyes on the reading " + "and not on whoever is holding it"
)

var _actor: Actor


func setup() -> void:
	_actor = Actor.new()
	_actor.id = &"portrait_bearer"
	# Declared HERE, not in a test body: `run_tests.gd:95` reads `_test_expected` straight after
	# `setup()` and `_test_begin()` resets it to 0 before every body, so a per-test call is a no-op
	# that reads like protection. Floor 1 is the floor that catches the shape that actually happens -
	# a body that dies before its first assert records neither a pass nor a failure, so the suite
	# reports 0 failed having skipped its own proof. That is worse than a red, because a red is at
	# least honest. Three tests here were silently aborting on a type-cast in
	# `PortraitIndex.character_for_race` and the suite still printed "146 passed".
	expect_assertions(1)


# --- Resolution -------------------------------------------------------------


func test_an_actor_with_no_race_resolves_to_the_placeholder_rather_than_to_nothing() -> void:
	var view := PortraitResolver.resolve(_actor, &"")
	assert_eq(String(view["portrait_id"]), "placeholder", "every actor has a face")
	assert_eq(bool(view["is_placeholder"]), true, "and this one is the fallback")
	assert_eq(String(view["source"]), "placeholder", "named so a panel can tell it from a choice")


func test_an_actor_with_a_race_resolves_to_that_race_portrait() -> void:
	# The NPC case, and the reason no NPC needs a special path.
	var view := PortraitResolver.resolve(_actor, &"tidecaller")
	assert_eq(String(view["portrait_id"]), "tidecaller", "the body plan's own face")
	assert_eq(String(view["source"]), "race", "step two answered")
	assert_eq(bool(view["is_placeholder"]), false, "not the fallback")


func test_every_authored_race_has_a_face_so_the_fallback_never_silently_becomes_one() -> void:
	# A whole body plan reading as `is_placeholder` is a content gap that looks like working
	# art, so it is asserted per race rather than left to a human to notice.
	for race_id in [&"stoneborn", &"tidecaller", &"emberblood", &"commonborn"]:
		var view := PortraitResolver.resolve(_actor, race_id)
		assert_eq(bool(view["is_placeholder"]), false, "%s has a face of its own" % race_id)


func test_a_chosen_face_wins_over_the_race_default() -> void:
	PortraitResolver.choose(_actor, &"stoneborn")
	var view := PortraitResolver.resolve(_actor, &"tidecaller")
	assert_eq(String(view["portrait_id"]), "stoneborn", "the choice wins")
	assert_eq(String(view["source"]), "chosen", "and step one is named")


func test_a_chosen_face_survives_a_save_round_trip() -> void:
	# It rides in `module_data`, which `Actor.to_dict` copies verbatim, so a save reloads with
	# the face it was created with rather than re-rolling one.
	PortraitResolver.choose(_actor, &"emberblood")
	var restored := Actor.from_dict(_actor.to_dict())
	var view := PortraitResolver.resolve(restored, &"stoneborn")
	assert_eq(String(view["portrait_id"]), "emberblood", "the chosen face survives the save")


func test_a_chosen_face_that_no_longer_exists_falls_through_to_the_race() -> void:
	# A `.tres` deleted between two runs must not leave an actor with no face. Dropped rather
	# than honoured, because honouring it would need the content to still exist.
	var actor := Actor.new()
	actor.set_module_data(PortraitResolver.APPEARANCE_KEY, {"portrait_id": "deleted_long_ago"})
	var view := PortraitResolver.resolve(actor, &"stoneborn")
	assert_eq(String(view["portrait_id"]), "stoneborn", "the fallback chain continued")
	assert_eq(String(view["source"]), "race", "and named the step that answered")


func test_resolution_is_a_pure_function_of_actor_state() -> void:
	# The same actor resolves the same way twice, which is what makes a save reproducible: no
	# randomness, and nothing keyed by scan position.
	var first := PortraitResolver.resolve(_actor, &"stoneborn")
	var second := PortraitResolver.resolve(_actor, &"stoneborn")
	assert_eq(String(first["portrait_id"]), String(second["portrait_id"]), "stable across reads")


func test_no_actor_resolves_rather_than_crashing() -> void:
	# `ui/` drives panels headlessly with no scene tree, so a null actor is a real input.
	var view := PortraitResolver.resolve(null, &"stoneborn")
	assert_eq(String(view["source"]), "none", "no actor has no portrait, and says so")


# --- Choosing ---------------------------------------------------------------


func test_choose_refuses_an_id_no_content_defines() -> void:
	var out := PortraitResolver.choose(_actor, &"a_face_that_does_not_exist")
	assert_eq(bool(out["ok"]), false, "a typo cannot paint an actor into nothing")
	assert_eq(String(out["reason"]), "unknown_portrait", "and the refusal is named")
	assert_eq(String(PortraitResolver.chosen_portrait_id(_actor)), "", "nothing was stored")


# --- The generator stays optional ---------------------------------------------


func test_the_resolver_never_reads_the_asset_index() -> void:
	# The load-bearing decision. The generator writes a PNG and an index row; a sync step turns
	# index rows into authored resources. Delete the index and every actor still resolves — so a
	# rendering tool can land later without a refactor.
	#
	# Read from the RESOLVER's source, not the index file: the file may legitimately not exist
	# yet, and what must never happen is the resolver depending on it.
	for path in [
		"res://src/core/portrait_resolver.gd",
		"res://src/core/portrait_catalog.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_eq(source.contains("asset-index"), false, "%s names no asset index" % path)
		assert_eq(source.contains("character-index"), false, "%s names no character index" % path)
	# The catalog's ONLY file access is the authored content scan, which is the whole point.
	assert_eq(
		PortraitCatalog.ROOT,
		"res://data/portraits",
		"the catalog reads authored resources, never art"
	)


func test_the_resolver_is_answered_from_authored_resources_only() -> void:
	# The positive half of the same rule: every portrait it can return is a `PortraitDef` it
	# loaded from `res://data/portraits`, and the placeholder is one of them.
	var catalog := PortraitCatalog.instance()
	for portrait_id in catalog.ids():
		assert_eq(
			catalog.portrait_definition(portrait_id) != null,
			true,
			"%s resolves to a definition" % portrait_id
		)
	assert_eq(
		catalog.placeholder() != null,
		true,
		"the placeholder is authored content, not a synthesized stub"
	)


# --- Variants (ADR 0177) ------------------------------------------------------


func test_an_unrequested_variant_leaves_the_face_exactly_as_it_was() -> void:
	# The default must be untouched. A variant is an enhancement and never a requirement, because
	# resolution is total (ADR 0131) and a missing variant must not leave an actor faceless.
	var plain := PortraitResolver.resolve(_actor, &"tidecaller")
	var asked := PortraitResolver.resolve(_actor, &"tidecaller", "")
	assert_eq(String(asked["portrait_id"]), String(plain["portrait_id"]), "same portrait")
	assert_eq(
		(asked["layer_paths"] as Array).size(),
		(plain["layer_paths"] as Array).size(),
		"same layers"
	)
	assert_eq(bool(asked["variant_found"]), false, "nothing was asked for, so nothing was found")
	assert_eq(String(asked["variant"]), "", "and the request is published as empty")


func test_a_declared_variant_is_selected_over_the_base_face() -> void:
	var view := PortraitResolver.resolve(_actor, &"echoless", EXPRESSION_VARIANT)
	assert_eq(String(view["portrait_id"]), "unique-0001__expression-02", "the variant answered")
	assert_eq(bool(view["variant_found"]), true, "and it says so")
	assert_eq(String(view["source"]), "race", "without inventing a fourth source word")


func test_an_undeclared_variant_falls_back_and_says_it_did() -> void:
	# The important half. A variant nobody authored must NOT resolve to a null or to a silent
	# substitution: the actor keeps a face, and the view names the gap.
	var view := PortraitResolver.resolve(_actor, &"echoless", "expression:flat professional focus")
	assert_eq(String(view["portrait_id"]), "unique-0001", "the base face still answers")
	assert_eq(bool(view["is_placeholder"]), false, "and it is not the fallback")
	assert_eq(bool(view["variant_found"]), false, "but the missing variant is reported")
	assert_eq(
		String(view["variant"]), "expression:flat professional focus", "naming what was asked"
	)


func test_a_variant_is_never_taken_from_another_body_plan() -> void:
	# The expression variant is authored against `echoless`. Asking the emberblood for it must not
	# hand over another body plan's face, which is the cross-race leak this lookup exists to prevent.
	var view := PortraitResolver.resolve(_actor, &"emberblood", EXPRESSION_VARIANT)
	assert_ne(String(view["portrait_id"]), "unique-0001__expression-02", "no cross-race variant")
	assert_eq(String(view["portrait_id"]), "emberblood", "the emberblood keeps its own face")


func test_two_portraits_declaring_one_variant_is_reported() -> void:
	# `for_variant` takes the first in sorted id order, so a duplicate is shadowed with no error
	# anywhere unless something says so.
	assert_eq(
		PortraitResolver.validate().has(
			"portrait: unique-0001__expression-02 and X both declare variant"
		),
		false,
		"no duplicate variant is authored today"
	)
	# And the rule is live: asking for the variant is what makes it reachable at all.
	assert_ne(
		PortraitCatalog.instance().for_variant(&"echoless", EXPRESSION_VARIANT),
		null,
		"the authored variant is reachable"
	)
	assert_eq(
		PortraitCatalog.instance().for_variant(&"echoless", "expression:flat professional focus"),
		null,
		"an unauthored variant is null rather than a guess"
	)


func test_the_placeholder_is_never_answered_as_a_variant() -> void:
	var view := PortraitResolver.resolve(_actor, &"no_such_race", EXPRESSION_VARIANT)
	assert_eq(bool(view["is_placeholder"]), true, "an unknown race still falls back")
	assert_eq(bool(view["variant_found"]), false, "the fallback is not a variant")


# --- A published named-cast portrait reaches the game --------------------------


func test_a_published_character_portrait_resolves_with_every_layer() -> void:
	# The end of the whole program: a rendered PNG declared with a correct per-shot canvas, synced
	# into an authored resource, read back by the catalog the game loads. If this fails, the art is
	# files nothing can map to.
	#
	# Asserted on the RESOURCE and its layer LIST, never on the PNG files being present: the art
	# lives in a gitignored folder, so an existence check would fail on a clean clone for a reason
	# that has nothing to do with the wiring under test. The panel reports a missing file itself.
	var def := PortraitCatalog.instance().portrait_definition(&"unique-0001")
	assert_ne(def, null, "the published portrait is not in the catalog")
	# The def holds the KEY like every authored display field, so the sentence is what it reads as.
	assert_eq(L.t(String(def.display_name)), "Ilsa Renn", "authored display name survived the sync")
	var layers := def.layer_paths
	assert_eq(layers.size(), 2, "both installable shots are declared as layers")
	assert_eq(
		String(layers[0]),
		"res://assets/characters/unique/unique-0001/ilsa_dialogue_portrait.png",
		"the dialogue portrait is the BASE layer, so the face is underneath"
	)
	assert_eq(
		String(layers[1]),
		"res://assets/characters/unique/unique-0001/ilsa_map_sprite.png",
		"the map token composites over the face, not under it"
	)


func test_a_published_portrait_resolves_for_an_actor_that_chooses_it() -> void:
	# `for_race` is not the only way in: `unique-0001`'s race (`echoless`) is not an authored
	# RaceDef, so `RaceApi.race_of` can never produce it and the chosen-id step is what makes this
	# portrait reachable at all. A resource nothing can select is a resource nothing draws.
	PortraitResolver.choose(_actor, &"unique-0001")
	var view := PortraitResolver.resolve(_actor, &"tidecaller")
	assert_eq(String(view["portrait_id"]), "unique-0001", "the chosen portrait answered")
	assert_eq(String(view["source"]), "chosen", "and it says which step answered")
	assert_eq((view["layer_paths"] as Array).size(), 2, "with both layers to composite")


func test_a_published_portrait_declares_one_value_per_variant_axis() -> void:
	# Two values on one axis is not a richer trait set. `trait_value` returns the first match and
	# ADR 0177 matches a variant WHOLE, so a second value on the same axis lets one portrait answer
	# for two variants it was never drawn as.
	var def := PortraitCatalog.instance().portrait_definition(&"unique-0001")
	assert_ne(def, null, "the published portrait is in the catalog")
	var axes: Dictionary = {}
	var repeated: Array[String] = []
	for trait_id in def.visual_traits:
		var axis := String(trait_id).split(":")[0]
		if axes.has(axis):
			repeated.append(axis)
		axes[axis] = true
	assert_eq(
		repeated, [] as Array[String], "an axis repeated on one portrait makes a variant ambiguous"
	)


func test_a_rendered_expression_is_reachable_as_a_variant() -> void:
	# The variant mechanism was previously proven only by a hand-written `stage:retired` fixture,
	# which left the real question open: can a character's ACTUAL rendered art be selected? This is
	# that question, asked with the exact text `tools/character_bundle_sync` publishes as the trait,
	# because `declares_variant` matches the whole `axis:value` string.
	expect_assertions(3)
	var expression := "flat professional focus, eyes on the reading and not on whoever is holding it"
	var view := PortraitResolver.resolve(_actor, &"echoless", "expression:%s" % expression)
	assert_eq(
		String(view["portrait_id"]),
		"unique-0001__expression-02",
		"the rendered expression answered, not the base portrait"
	)
	assert_eq(bool(view["variant_found"]), true, "and it says so")
	assert_eq(
		String(view["layer_paths"][0]),
		"res://assets/characters/unique/unique-0001/ilsa_expression_02.png",
		"drawing the expression render itself, not the base composited under it"
	)


func test_an_unrendered_expression_falls_back_rather_than_guessing() -> void:
	# The negative half, and the one that matters most: a request for art that does not exist must
	# return the base face with `variant_found: false`, never a near-miss member.
	expect_assertions(2)
	var view := PortraitResolver.resolve(
		_actor, &"echoless", "expression:flat professional focus, eyes elsewhere"
	)
	assert_eq(String(view["portrait_id"]), "unique-0001", "the base portrait still answers")
	assert_eq(bool(view["variant_found"]), false, "and the missing variant is reported")


func test_every_player_creation_origin_has_a_face() -> void:
	# `RACE_BY_ORIGIN` in app/character_creation_flow.gd maps three origins to three races, and
	# `emberblood_touched` had a committed fallback PNG with NO PortraitDef pointing at it - so a
	# player who chose "the chosen instrument" fell through to the placeholder and saw an empty box.
	# A resource nothing selects is a resource nothing draws, and the gap was invisible because
	# nothing asserted that every origin is reachable.
	expect_assertions(1)
	var origins := {
		"the_one_who_stayed": &"stoneborn",
		"the_one_who_returned": &"tidecaller",
		"the_chosen_instrument": &"emberblood_touched",
	}
	var missing: Array[String] = []
	for race_id in origins.values():
		if PortraitCatalog.instance().for_race(race_id) == null:
			missing.append(String(race_id))
	assert_eq(missing, [] as Array[String], "a player origin has no portrait")


# --- Portraits grant nothing ---------------------------------------------------


func test_a_portrait_declares_no_stat_field() -> void:
	# ADR 0062: a race without a liability is a content bug, and appearance that changes numbers
	# is a balance surface. Structural, because a value assertion cannot see an absent field.
	#
	# Read from CODE, not raw text: this very docstring explains the rule using the words the
	# guard forbids, so scanning the file unstripped matches the PROSE and fails on correct code.
	var source := _code_only(FileAccess.get_file_as_string("res://src/core/portrait_def.gd"))
	for forbidden in ["stat_modifier", "set_base", "add_modifier", "power", "realm", "rate"]:
		assert_eq(source.contains(forbidden), false, "PortraitDef declares no %s" % forbidden)


func test_two_actors_differing_only_in_portrait_have_identical_stats() -> void:
	# The end-to-end half of the same rule: choosing a face changes nothing about a body.
	var other := Actor.new()
	other.id = &"other_bearer"
	var before := _base_stats(_actor)
	PortraitResolver.choose(_actor, &"stoneborn")
	assert_eq(_base_stats(_actor), before, "choosing a face changes no stat")
	assert_eq(_base_stats(other), before, "and two actors still match")


# --- Content -------------------------------------------------------------------


func test_the_authored_portraits_are_well_formed_and_a_placeholder_exists() -> void:
	# The race portraits' art now EXISTS (DEF-0297 closed: `res://assets/characters/portraits/`
	# is authored with commonborn/emberblood/stoneborn/tidecaller), so the missing-art class is
	# no longer open and this is the stronger claim: NO portrait is missing, unnamed or
	# layerless.
	#
	# **Scoped to the classes this test owns, deliberately.** It asserted `validate()` returns
	# nothing, which was true when the only known gap was missing art. A peer then authored ~300
	# more portraits, and `validate()` legitimately reports a DIFFERENT class — shadowed
	# variants, two portraits claiming the same trait for one race, which that generator
	# produced. Asserting the whole list empty therefore made this test a permanent red over a
	# content defect that is not its subject and that has its own owner.
	#
	# So it asserts both halves: the classes this suite ever covered are closed, AND every
	# remaining problem is a shadowed-variant report. A genuinely NEW defect class still cannot
	# hide here — it would be neither `has no file at` nor `both declare variant`.
	var problems := PortraitResolver.validate()
	for problem in problems:
		assert_eq(
			problem.contains(" both declare variant "),
			true,
			(
				"the only open class is shadowed variants, so a new defect cannot hide: "
				+ str(problems)
			)
		)
	assert_eq(
		_missing_art(problems).is_empty(),
		true,
		"and no portrait is missing art, unnamed or layerless any more"
	)
	assert_ne(
		PortraitCatalog.instance().placeholder(),
		null,
		"and the fallback that makes it total exists"
	)


func test_a_missing_layer_file_is_reported_naming_the_portrait_and_the_path() -> void:
	# The guard is live, not merely written (INC-0016). Now that the real art resolves, asserting
	# emptiness would prove nothing - a guard that reported nothing would pass it. So the gap is
	# built ON A THROWAWAY PORTRAIT and the guard must catch THAT one, proving the check fires
	# on a missing file while the shipped content is clean.
	#
	# This is the shape the whole suite needed: before, "the art is missing" was a permanent
	# fact, so the guard's firing was indistinguishable from the content being broken.
	var catalog := PortraitCatalog.instance()
	var probe_id := &"__missing_art_probe__"
	var probe := PortraitDef.new()
	probe.id = probe_id
	probe.display_name = "Probe"
	probe.race_id = &"stoneborn"
	probe.layer_paths = ["res://assets/characters/portraits/__no_such_file__.png"] as Array[String]
	catalog.with_probe(probe)
	var problems := PortraitResolver.validate()
	catalog.clear_probe(probe_id)
	var expected := (
		"portrait: __missing_art_probe__ has no file at"
		+ " res://assets/characters/portraits/__no_such_file__.png"
	)
	assert_eq(
		problems.has(expected),
		true,
		"the guard fires and names portrait and path: " + str(problems)
	)
	var after := PortraitResolver.validate()
	assert_eq(
		after.has(expected),
		false,
		"and stops reporting it once the probe is withdrawn, so no suite inherits it"
	)
	assert_eq(
		_missing_art(after).is_empty(),
		true,
		"and the shipped content is clean of every class this suite guards"
	)


func test_the_placeholder_is_exempt_from_the_missing_file_check() -> void:
	# The exemption the empty-layer check already makes, extended to the file check. The
	# placeholder declares an EMPTY `layer_paths` on purpose: it is the face every actor gets
	# BEFORE any art exists, so demanding a file of it would make the fallback un-authorable and
	# resolution total only in theory (ADR 0131).
	var placeholder := PortraitCatalog.instance().placeholder() as PortraitDef
	assert_eq(placeholder.layer_paths.is_empty(), true, "it declares no layer at all")
	for problem in PortraitResolver.validate():
		assert_eq(
			problem.contains("portrait: placeholder has no file at"),
			false,
			"the fallback is never asked for art"
		)


func test_a_layer_file_that_exists_is_not_reported() -> void:
	# The negative half, and what stops the guard becoming noise: real art on disk is not a gap.
	#
	# **This suite asserted nothing once the race art landed.** It was a `for` over
	# `validate()`'s problems, and the list is now EMPTY, so every iteration was skipped and the
	# case passed having checked no file at all — the loop version of the same vacuity the skill
	# warns about, and it hid for exactly as long as the content gap it was written beside.
	#
	# A negative claim needs a positive population. The probe below is the SAME missing file the
	# sibling test registers, so the guard is observed reporting it, and each reported path is
	# then checked against the filesystem: a message naming a file that exists is a lie, and a
	# lie in a validation report is worse than no report.
	var catalog := PortraitCatalog.instance()
	var probe_id := &"__present_art_probe__"
	var probe := PortraitDef.new()
	probe.id = probe_id
	probe.display_name = "Probe"
	probe.race_id = &"stoneborn"
	probe.layer_paths = ["res://assets/characters/portraits/stoneborn.png"] as Array[String]
	catalog.with_probe(probe)
	var problems := PortraitResolver.validate()
	catalog.clear_probe(probe_id)
	assert_eq(
		_missing_art(problems).is_empty(),
		true,
		"art that EXISTS is not a gap, so the guard says nothing about it: " + str(problems)
	)
	for problem in _missing_art(problems):
		var path := problem.trim_prefix("portrait: ").get_slice(" has no file at ", 1)
		if path == "":
			continue
		assert_eq(
			FileAccess.file_exists(path),
			false,
			"a reported path really is absent, or the message is a lie: " + path
		)


## Just the problems this suite's rules own, so a defect class belonging to another owner cannot
## make it red and a genuinely new class still can.
func _missing_art(problems: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for problem in problems:
		if (
			problem.contains(" has no file at ")
			or problem.contains(" has no layer to draw")
			or problem.contains(" has no display name")
			or problem.contains(" has no definition")
			or problem.contains("no authored portraits loaded")
			or problem.contains("the placeholder is missing")
			or problem.contains("the placeholder names a race")
		):
			out.append(problem)
	return out


func test_the_placeholder_does_not_claim_a_race() -> void:
	# A placeholder tied to a race is a face that fails for exactly the actors who most need it.
	# Typed through `as`, because `placeholder()` returns a nullable Resource and inferring from
	# it yields a Variant, which this project treats as an error.
	var placeholder := PortraitCatalog.instance().placeholder() as PortraitDef
	assert_eq(placeholder.race_id, &"", "the fallback belongs to nobody in particular")


# --- Internals ---------------------------------------------------------------


## The actor's own base allocation as a sorted string, so two actors compare by value and the
## dictionary's key order cannot make them look different.
func _base_stats(actor: Actor) -> String:
	var pairs: Array[String] = []
	for key in actor.stats.base_dict().keys():
		pairs.append("%s=%s" % [key, actor.stats.base_dict()[key]])
	pairs.sort()
	return ",".join(pairs)


## `source` with every GDScript comment line removed, so a structural guard reads CODE and never
## the prose describing what the code must not do.
##
## Removed by LINE because a docstring explaining a rule naturally uses the rule's own words: a
## guard that scans raw text matches the explanation and fails on correct code, which is how a
## guard ends up disabled instead of enforced.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
