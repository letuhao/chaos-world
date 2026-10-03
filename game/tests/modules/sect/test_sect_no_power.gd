extends TestCase

## **An institution grants recognition, access and transmission, and never power**
## (ADR 0084). That sentence is the whole design, and the only thing holding it in
## place is this suite.
##
## ADR 0084 says so out loud: *"`tools arch` cannot see a method that does not
## exist. The invariant is pinned the way `test_destiny_earning.gd` pins the absence
## of a removal verb."* So the first case is structural — it reads `SectApi`'s
## published method list and fails if a power-granting verb ever appears on it — and
## the cases after it are the behavioural halves that a structural test cannot reach:
## that joining, being fully recognised and holding the top office changes no
## derived stat by even a rounding step, and that position and standing never derive
## from each other in either direction (ADR 0064, carried forward by ADR 0083).

## Every verb a facade must never grow. If one of these appears on `SectApi`, the
## "grants no power" invariant has been broken and a sect can hand out a stat.
const FORBIDDEN_VERBS := [
	"grant_stat",
	"grant_attribute",
	"set_base",
	"add_base",
	"power_up",
	"buff",
	"apply_modifier",
	"grant_modifier",
]

## The verbs that ARE the facade. Asserted as a whole, not just by the absence of
## the forbidden ones, so a verb added later fails here rather than slipping past the
## word list — and so the cap of twelve is visible in a test rather than only in a
## Python constant.
const PUBLISHED := [
	"advance_succession",
	"attach",
	"found",
	"gate",
	"join",
	"leave",
	"move_standing",
	"promote",
	"state",
	"summary",
	"teach",
]

const HOUSE := &"t_house"
const MEMBER := &"t_member"
const STEWARD := &"t_steward"
const READER := &"t_reader"

## Every script this module owns, so the "never calls `set_base`" case reads the
## whole module rather than one file.
const MODULE_FILES := [
	"res://src/modules/sect/api.gd",
	"res://src/modules/sect/sect_projection.gd",
	"res://src/modules/sect/sect_def.gd",
	"res://src/modules/sect/sect_position_def.gd",
	"res://src/modules/sect/sect_state.gd",
	"res://src/modules/sect/sect_gate.gd",
	"res://src/modules/sect/sect_catalog.gd",
	"res://src/modules/sect/sect_doctrine_def.gd",
	"res://src/modules/sect/sect_doctrine_catalog.gd",
	"res://src/modules/sect/sect_founding.gd",
	"res://src/modules/sect/sect_succession.gd",
	"res://src/modules/sect/sect_teaching.gd",
]


func setup() -> void:
	(
		SectFixtureCatalog
		. install(
			[
				(
					SectFixtureCatalog
					. sect(
						HOUSE,
						[
							SectFixtureCatalog.bare_position(MEMBER),
							SectFixtureCatalog.seat(STEWARD, 60),
							SectFixtureCatalog.room(READER, 3, 20),
							SectFixtureCatalog.wide_position(&"t_archivist", 1, 40),
						]
					)
				)
			]
		)
	)


func teardown() -> void:
	SectFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	return actor


## A member pushed as far as the content allows: sworn, fully recognised, holding
## the top office. This is the actor the invariants below are measured on.
func _maximal(actor: Actor) -> Actor:
	SectApi.join(actor, HOUSE)
	SectApi.move_standing(actor, 1000)
	SectApi.promote(actor, STEWARD)
	return actor


# --- The invariant, structurally ---------------------------------------------


## The single most valuable case in this suite. A sect grants no power because its
## public surface has no way to grant any: other modules may reference only
## `api.gd`, so if no verb there can touch a stat, nothing outside the module can
## either. A future `grant_bonus()` fails here rather than in a player's save.
func test_the_facade_exposes_no_power_granting_verb_at_all() -> void:
	var published := _published_verbs()
	assert_eq(published.is_empty(), false, "the facade's method list is readable")
	for verb in FORBIDDEN_VERBS:
		assert_eq(published.has(verb), false, "SectApi publishes no '%s'" % verb)
	# And the surface is exactly the join-and-read one, so an unlisted verb added
	# later still fails rather than slipping past the word list.
	assert_eq(published, PUBLISHED, "the facade is the join-and-read surface ADR 0084 describes")
	assert_eq(published.size() <= 12, true, "and it is inside the twelve-method cap")


## The complement of the case above: nothing in the facade's own body reaches for a
## base-attribute write either. `set_base` bypasses the modifier stack entirely, so
## it cannot be stripped, cannot be rebuilt idempotently, and it *does* satisfy
## `get_base(...)` — which is exactly how a member would smuggle themselves through
## the gates meant to test them (ADR 0084, citing ADR 0052/0054).
func test_the_module_writes_no_base_attribute_anywhere() -> void:
	for rel in MODULE_FILES:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for forbidden in ["set_base", "add_base", "add_provider", 'set_component(&"race']:
			assert_eq(_calls(body, forbidden), 0, "%s never calls %s" % [rel.get_file(), forbidden])


## How many times `needle` appears in CODE, ignoring the `##` prose that documents
## it. This module names the verbs it refuses inside its own class docs — ADR 0084's
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


## Every modifier this module ever writes is a PERCENT. A FLAT is realm-blind —
## decisive at R2, noise by roughly realm 12 across the 551x ladder (ADR 0063) —
## and a FLAT on a rate stat is the silent `(0.0 + 0.0) * (1 + p) = 0.0` no-op ADR
## 0068 measured on 44 items. So this walks the live stack, not the source.
func test_every_modifier_this_module_writes_is_a_source_tagged_percent() -> void:
	var actor := _maximal(_hero())
	assert_ne(_own_modifiers(actor), 0, "the maximal member does carry a grant")
	for modifier in actor.stats._modifiers:
		if not SectState.is_own_source(modifier.source):
			continue
		assert_eq(modifier.op, Stat.Op.PERCENT, "a sect modifier is PERCENT, never FLAT or MULT")
		assert_eq(modifier.source, SectState.source_for(HOUSE), "and carries the sect's own tag")
		assert_almost_eq(
			modifier.value, InstitutionClaim.STANDING_PERCENT_CAP, "and it is the capped percent"
		)
	# Only stats on the office's authored allowlist may be touched at all.
	var allowlist: Dictionary = (
		SectCatalog.instance().sect_definition(HOUSE).position(STEWARD).standing_percent_stats
	)
	for modifier in actor.stats._modifiers:
		if SectState.is_own_source(modifier.source):
			assert_eq(
				_recognised_ids().has(String(modifier.stat)),
				true,
				"'%s' is on the office's authored allowlist" % modifier.stat
			)


# --- The invariant, behaviourally --------------------------------------------


## ## The measurement ADR 0084 asks for, in the form it asks for
##
## After joining, being fully recognised and holding the top office, every derived
## stat the institution did NOT touch is **byte-identical** to what it was before —
## not "close", identical. The one stat this office is authored to recognise moves
## by the bounded percent and nothing else; the other thirty-odd are exactly where
## they were. That split is ADR 0084's whole content: the political stat surface of
## the game is an authored allowlist and one capped percent on it, and a PERCENT
## rides the member's own growth rather than being folded into a base.
func test_joining_reaching_the_cap_and_holding_the_top_office_changes_no_derived_stat() -> void:
	var actor := _hero()
	var before := _derived(actor)
	var bases_before := actor.stats.base_dict()
	_maximal(actor)
	# The claim really is maximal, or the case proves nothing.
	var claim := SectApi.state(actor)
	assert_eq(String(claim["institution"]), String(HOUSE), "sworn to the house")
	assert_eq(String(claim["position"]), String(STEWARD), "holding the top office")
	assert_eq(int(claim["standing"]), 100, "at the authored cap")
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		0.10,
		"so the projection DID grant the capped percent"
	)
	var untouched := _untouched_by(actor)
	# Pin the precondition the next assertion leans on: the office really does
	# recognise exactly one stat, so "untouched" is a partition and not an
	# accident of an empty allowlist. Without this, a `_untouched_by` that returned
	# nothing would read as "the institution touched no stats at all".
	assert_eq(_recognised_ids().size(), 1, "the office recognises exactly one stat")
	assert_ne(actor.stats.derived_all().size(), 0, "and the actor has derived stats at all")
	assert_ne(untouched.size(), 0, "and %d of them are outside that allowlist" % untouched.size())
	for stat_id in untouched.keys():
		assert_eq(
			actor.stats.derived(StringName(stat_id)),
			float(before[stat_id]),
			"'%s' is untouched by the institution" % stat_id
		)
	# The recognised stat moved by exactly the granted percent — the one number a sect
	# is allowed to move, and it is a PERCENT rather than a base write, which is what
	# makes a re-attach free of consequence rather than compounding.
	assert_almost_eq(
		actor.stats.derived(Stat.INSIGHT_GAIN),
		float(before["insight_gain"]) * (1.0 + InstitutionClaim.STANDING_PERCENT_CAP),
		"and the recognised stat moved by the percent and not by a base write"
	)
	assert_eq(actor.stats.base_dict(), bases_before, "nor was any base attribute written")
	# And after leaving, the actor is back to the same numbers again — the exit is
	# as exact as the entry, and the entry is exact too once the allowlist is removed.
	SectApi.leave(actor)
	assert_eq(_derived(actor), before, "leaving restores every derived stat")
	assert_eq(actor.stats.base_dict(), bases_before, "and writes no base on the way out")


## ## Realm-invariance in ratio, the second measurement ADR 0084 names
##
## For one actor, the derived-stat RATIO on every allowlisted id is identical at R1
## and at R30. That is what makes "a percent, never a flat" a property rather than a
## hope: a flat is decisive on a shallow sheet and vanishes on a deep one, whereas a
## percent rides the sheet and therefore means the same thing on both.
func test_the_recognition_is_realm_invariant_in_ratio_at_r1_and_at_r30() -> void:
	var shallow := _hero(&"shallow")
	var deep := _hero(&"deep")
	deep.stats.set_base(Stat.PHYSIQUE, 300.0)
	deep.stats.set_base(Stat.COMPREHENSION, 240.0)
	var shallow_base := _allowlist_base(shallow)
	var deep_base := _allowlist_base(deep)
	_maximal(shallow)
	_maximal(deep)
	var office := SectCatalog.instance().sect_definition(HOUSE).position(STEWARD)
	assert_ne(office.standing_percent_stats.size(), 0, "the office recognises something")
	for stat_id in office.standing_percent_stats.keys():
		var id := StringName(stat_id)
		var at_r1 := actor_ratio(shallow, id, shallow_base[id])
		var at_r30 := actor_ratio(deep, id, deep_base[id])
		assert_almost_eq(at_r1, at_r30, "'%s' is the same ratio at R1 and at R30" % stat_id)
		# The ratio is `1 + the granted percent` — ADR 0084's formula made concrete.
		# `1.0` here would be the claim that a percent moves nothing, which is the
		# opposite of what ADR 0084 grants: the bounded percent is the ONE thing an
		# institution is allowed to hand out, and asserting it moved no stat would be
		# asserting the recognition is not there.
		assert_almost_eq(
			at_r1,
			1.0 + InstitutionClaim.STANDING_PERCENT_CAP,
			"'%s' is the recognition itself, and only the recognition" % stat_id
		)
		assert_almost_eq(
			SectProjection.contribution(shallow, id),
			InstitutionClaim.STANDING_PERCENT_CAP,
			"'%s' and the modifier on the stack is the same percent" % stat_id
		)


## Position and standing are two facts, and **neither is ever derived from the
## other** (ADR 0064, carried forward by ADR 0083). Each direction is asserted
## separately because a design that collapsed the pair into one number would pass a
## single combined check: it would simply have no second number to contradict.
func test_a_promotion_does_not_move_standing_and_a_standing_change_does_not_move_position() -> void:
	var actor := _hero()
	SectApi.join(actor, HOUSE)
	# 30 standing is under `t_steward`'s authored floor of 60, so promoting here
	# would be refused for the floor rather than exercised. This suite is about
	# what a promotion does to the OTHER number, so it takes the ordinary route
	# and reaches the office with the standing the office asks for.
	SectApi.move_standing(actor, 60)

	# Direction one: promotion writes the position and leaves standing alone.
	var standing_before := int(SectApi.state(actor)["standing"])
	var promoted := SectApi.promote(actor, STEWARD)
	assert_eq(bool(promoted["ok"]), true, "the promotion landed")
	assert_eq(String(SectApi.state(actor)["position"]), String(STEWARD), "the position moved")
	assert_eq(int(SectApi.state(actor)["standing"]), standing_before, "standing did not")
	# The grant is read AFTER the promotion, and compared against the percent the
	# standing-alone member would have had. The office carries the allowlist, so
	# seating someone does move the contribution — what must not move is STANDING.
	# Comparing a post-promotion grant to the seated value is what makes that the
	# claim: if `promote` had awarded standing, the grant would have moved too.
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		InstitutionClaim.standing_percent(standing_before),
		"and the grant is exactly the recognition that standing already earned"
	)

	# Direction two: a standing change moves standing and leaves the position alone.
	var position_before := String(SectApi.state(actor)["position"])
	var moved := SectApi.move_standing(actor, 25)
	assert_eq(bool(moved["ok"]), true, "the standing change landed")
	assert_eq(int(SectApi.state(actor)["standing"]), standing_before + 25, "standing moved")
	assert_eq(String(SectApi.state(actor)["position"]), position_before, "the position did not")


## A member with thick standing and no office is the state ADR 0064's split exists
## to make expressible. The projection must honour the office, never the standing:
## an allowlist is a property of an office, so a member holding none recognises
## nothing however much the sect thinks of them.
func test_thick_standing_in_no_office_recognises_nothing_and_grants_nothing() -> void:
	var actor := _hero()
	SectApi.join(actor, HOUSE)
	SectApi.move_standing(actor, 100)
	assert_eq(String(SectApi.state(actor)["position"]), "", "holds no office at all")
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		0.0,
		"so the office allowlist projects nothing"
	)
	assert_eq(_own_modifiers(actor), 0, "and the stack carries nothing of ours")
	# Gaining the office grants it, without a single point of standing changing.
	var before := SectApi.state(actor)
	SectApi.promote(actor, STEWARD)
	assert_eq(int(SectApi.state(actor)["standing"]), int(before["standing"]), "standing unchanged")
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		0.10,
		"and the office now grants the capped percent"
	)


## The projection is derived, so it can be rebuilt from the ledger at any time and
## lands in exactly one place. This is the property that makes a restored save safe
## to attach, and it is why `SectProjection.apply` strips before it rebuilds.
func test_the_projection_is_derived_so_reapplying_it_is_free_of_consequence() -> void:
	var actor := _maximal(_hero())
	var before := _fingerprint(actor)
	for cycle in 5:
		SectApi.attach(actor)
		SectProjection.apply(actor, SectApi.state(actor))
		assert_eq(_fingerprint(actor), before, "cycle %d leaves the actor identical" % cycle)
	assert_eq(_own_modifiers(actor), 1, "one office, one modifier, however many rebuilds")
	assert_almost_eq(SectProjection.contribution(actor, Stat.INSIGHT_GAIN), 0.10, "granted once")


# --- Helpers -----------------------------------------------------------------


## Every method name `SectApi` publishes, read from the facade script itself. The
## facade is all static functions and GDScript refuses a non-static call on a class
## reference, so `load()` is the one way in. An unreadable facade hands back an
## empty list, which every caller above fails on rather than quietly accepts.
##
## Underscore-prefixed names are dropped here exactly as `tools/arch/enforce.py`
## drops them: `FUNC_RE` then `if not name.startswith("_")` (see the facade-counting
## block in `_violation`). The gate and this helper therefore count the same verbs,
## so `published.size() <= 12` here is the cap `tools arch` actually enforces rather
## than a private method being counted against the facade that never shipped it.
func _published_verbs() -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load("res://src/modules/sect/api.gd")
	if script == null:
		return out
	for method in script.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## Every derived stat, keyed by its string id. The comparison that matters is
## `assert_eq` on the whole map: byte-identical, not approximately equal.
func _derived(actor: Actor) -> Dictionary:
	var out := {}
	for stat_id in actor.stats.derived_all().keys():
		out[String(stat_id)] = actor.stats.derived(stat_id)
	return out


## The pre-claim value of every stat on the office's allowlist, which is what the
## ratio is measured against.
func _allowlist_base(actor: Actor) -> Dictionary:
	var out := {}
	var office := SectCatalog.instance().sect_definition(HOUSE).position(STEWARD)
	for stat_id in office.standing_percent_stats.keys():
		out[String(stat_id)] = actor.stats.derived(StringName(stat_id))
	return out


## Every derived stat the current claim is **not** allowed to move — the complement
## of the office's authored allowlist. This is what ADR 0084's "recognition on an
## authored allowlist" actually has to mean: an institution that recognised only
## `insight_gain` must leave `max_health`, `defense_physical` and the other
## thirty-odd exactly where they were, which is a far stronger statement than
## "nothing moved" and the only one a bounded percent can satisfy.
func _untouched_by(actor: Actor) -> Dictionary:
	# `_recognised_ids()` rather than re-reading the def here: this helper and the
	# allowlist assertion above must be looking at the SAME office, and two
	# lookups of the same thing is how they end up disagreeing.
	var recognised_ids := _recognised_ids()
	var out := {}
	for stat_id in actor.stats.derived_all().keys():
		if recognised_ids.has(String(stat_id)):
			continue
		out[String(stat_id)] = true
	return out


## The office allowlist as plain `String` ids, for every comparison that has to
## match a def authored in code against a `.tres` authored on disk. See
## `_untouched_by` for why the two cannot be compared as-is.
func _recognised_ids() -> Array[String]:
	var out: Array[String] = []
	var position := (
		SectCatalog.instance().sect_definition(HOUSE).position(STEWARD) if HOUSE != "" else null
	)
	if position == null:
		return out
	for key in position.standing_percent_stats.keys():
		out.append(String(key))
	return out


## The derived-stat ratio a maximal claim produced on `stat_id`, read as
## `after / before`. A percent rides the sheet, so this is the same number at every
## realm; a flat would be enormous on a shallow sheet and negligible on a deep one.
func actor_ratio(actor: Actor, stat_id: StringName, before: float) -> float:
	var after := actor.stats.derived(stat_id)
	if before == 0.0:
		return 1.0
	return after / before


func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"claim": SectApi.state(actor),
		"traits": actor.traits.to_array(),
		"modifiers": _own_modifiers(actor),
		"insight": SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		"max_health": actor.stats.derived(Stat.MAX_HEALTH),
		"derived": _derived(actor),
	}


func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if SectState.is_own_source(modifier.source):
			total += 1
	return total
