extends TestCase

## **A nation grants recognition and access, never power** (ADR 0084). The same
## invariant the sibling tiers pin: the facade publishes no power-granting verb,
## no file in the module writes a base attribute, every modifier on the stack is a
## source-tagged PERCENT, and a seating never moves standing while a standing
## change never moves a seating — the offices/standing split that is this tier's
## form of ADR 0064's position/standing independence, asserted in both directions
## because a design that collapsed the pair into one number would pass a combined
## check by having no second number to contradict.

## Every verb a facade must never grow. If one of these appears on `NationApi`,
## the "grants no power" invariant is broken and a nation can hand out a stat.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
]

## The verbs that ARE the facade. Asserted as a whole, so a verb added later fails
## here rather than slipping past the word list.
const PUBLISHED := [
	"accrue_territory",
	"act",
	"attach",
	"claim_territory",
	"declare_war",
	"found",
	"release_territory",
	"resolve_conflict",
	"set_stance",
	"state",
	"summary",
]

## Every script this module owns, so the "never writes a base" case reads the
## whole module rather than one file.
const MODULE_FILES := [
	"res://src/modules/nation/api.gd",
	"res://src/modules/nation/nation_act.gd",
	"res://src/modules/nation/nation_catalog.gd",
	"res://src/modules/nation/nation_def.gd",
	"res://src/modules/nation/nation_office_def.gd",
	"res://src/modules/nation/nation_projection.gd",
	"res://src/modules/nation/nation_resolve.gd",
	"res://src/modules/nation/nation_state.gd",
	"res://src/modules/nation/nation_state_component.gd",
	"res://src/modules/nation/nation_territory_def.gd",
	"res://src/modules/nation/nation_tuning.gd",
]

const MARCH := &"march_of_the_nine_provinces"
const RIVER := &"river_march"
## The authored claim of the march: standing 80 at the shipped rate of 0.001.
const MARCH_STANDING := 80
const MARCH_PERCENT := 0.08


func _hero(actor_id: StringName = &"polity_a") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	return actor


func _founded() -> Actor:
	var actor := _hero()
	NationApi.found(actor, MARCH, "polity_a")
	return actor


func test_the_facade_exposes_no_power_granting_verb_at_all() -> void:
	var published := _published_verbs()
	assert_eq(published.is_empty(), false, "the facade's method list is readable")
	for verb in FORBIDDEN_VERBS:
		assert_eq(published.has(verb), false, "NationApi publishes no '%s'" % verb)
	# And the surface is exactly the found-and-read one, so an unlisted verb added
	# later still fails rather than slipping past the word list.
	assert_eq(published, PUBLISHED, "the facade is the found-and-read surface ADR 0084 describes")


func test_the_module_writes_no_base_attribute_anywhere() -> void:
	for rel in MODULE_FILES:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for forbidden in FORBIDDEN_VERBS:
			assert_eq(_calls(body, forbidden), 0, "%s never calls %s" % [rel.get_file(), forbidden])


## How many times `needle` appears in CODE, ignoring the `##` prose that documents
## it. This module names the writes it refuses inside its own class docs — ADR 0084's
## whole argument is *which* writes are forbidden, so the forbidden names are written
## down in sentences — and a raw `body.contains(forbidden)` scan fails on those
## sentences while reading the code beside them as clean. The invariant is about what
## the module EXECUTES, so the comment lines are dropped first and the scan that
## follows is over executable text only.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


## Every method name `NationApi` publishes, read from the facade script itself. The
## facade is all static functions and GDScript refuses a non-static call on a class
## reference, so `load()` is the one way in. An unreadable facade hands back an
## empty list, which every caller above fails on rather than quietly accepts.
##
## Underscore-prefixed names are dropped here exactly as the arch gate drops them,
## so this helper and the gate count the same verbs.
func _published_verbs() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load("res://src/modules/nation/api.gd")
	if script == null:
		return out
	for method in script.get_script_method_list():
		var verb: String = method["name"]
		if verb.begins_with("_"):
			continue
		if not out.has(verb):
			out.append(verb)
	out.sort()
	return out


## Every modifier this module ever writes is a PERCENT under a per-office tag. A
## FLAT is realm-blind and a `set_base` bypasses the modifier stack entirely, so
## either would be how a member smuggles themselves through the gates meant to
## test them (ADR 0084, citing ADR 0052/0054). Read off the live stack, not the
## source.
func test_every_modifier_this_module_writes_is_a_source_tagged_percent() -> void:
	var actor := _founded()
	var seated := NationApi._hold_office(actor, &"reeve", "polity_a")
	assert_eq(bool(seated["ok"]), true, "the seating landed")
	var count := 0
	var tags := {}
	for modifier in actor.stats._modifiers:
		if not NationState.is_own_source(modifier.source):
			continue
		count += 1
		assert_eq(modifier.op, Stat.Op.PERCENT, "a nation modifier is PERCENT, never FLAT or MULT")
		assert_almost_eq(
			modifier.value, MARCH_PERCENT, "and it is the bounded percent the standing earned"
		)
		tags[String(modifier.source)] = true
	assert_ne(count, 0, "the seated member does carry a grant")
	assert_eq(tags.size(), 3, "one tag per held office: marshal, auditor and reeve")


## A seating writes the offices and leaves standing alone; a standing change moves
## standing and leaves the offices alone. Each direction is asserted separately.
func test_a_seating_does_not_move_standing_and_accruing_does_not_move_a_seating() -> void:
	var actor := _founded()
	assert_eq(
		int(NationApi.state(actor)["standing"]), MARCH_STANDING, "founded at the authored claim"
	)
	# Direction one: seating writes the offices and leaves standing alone.
	var seated := NationApi._hold_office(actor, &"reeve", "polity_a")
	assert_eq(bool(seated["ok"]), true, "the seating landed")
	assert_eq(
		String((NationApi.state(actor)["offices"] as Dictionary)["reeve"]),
		"polity_a",
		"the seat is held"
	)
	assert_eq(int(NationApi.state(actor)["standing"]), MARCH_STANDING, "standing did not move")
	# Direction two: accruing moves standing and leaves the offices alone.
	var offices_before: Dictionary = (NationApi.state(actor)["offices"] as Dictionary).duplicate(
		true
	)
	var claimed := NationApi.claim_territory(actor, RIVER)
	assert_eq(bool(claimed["ok"]), true, "the take landed")
	var accrued := NationApi.accrue_territory(actor, 4)
	assert_eq(int(accrued["settled"]), 1, "one claim settled")
	assert_eq(
		int(NationApi.state(actor)["standing"]),
		MARCH_STANDING + 3,
		"standing moved by the tier-0 net over 4 periods"
	)
	assert_eq(NationApi.state(actor)["offices"] as Dictionary, offices_before, "the board did not")
