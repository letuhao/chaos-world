extends TestCase

## BL-0146 / BL-0155: three fields that every `MindRealmSeed` used to author were
## read by nothing anywhere — not in `res://src`, not in `tools/`, not in any ADR.
## They were deleted. This suite is the guard against their return, and it has
## three legs because a one-leg "the field is absent" check is satisfied just as
## well by the seed class having lost something else, or by the search set being
## empty. Leg 3 is what stops that, and it is not hypothetical: the first version
## of this file read `get_property_list()`, got an empty list, and passed legs 1
## and 2 vacuously. Only leg 3 went red.
##
## Why each was deleted rather than wired (measured, not assumed):
##
##   `sea_milestone_work`, `meridian_milestone_work` — the Thức Hải milestone
##     (`MindTraining.strengthen_sea`) already costs a mandatory per-realm
##     `sea_catalyst`, and `train_channel` already costs the realm's
##     `training_item`. ADR 0096 rejected a fourth mandatory consumable on exactly
##     this reasoning: it doubles the cost of a boundary and adds no choice to it.
##     Charging work as well is the same decision taken twice. `train_channel` is
##     worse than redundant — it is the verb that raises a channel to
##     `required_channel_state` (STRENGTHENED), which IS the next realm's entry
##     gate, so a work threshold there taxes the gate-raising verb itself.
##
##   `resonance_required` — byte-identical to `BodyRealmSeed.resonance_rank` at all
##     30 realms, and `MeridianNetwork.resonance_rank` is ONE shared field written
##     only by `body_cultivation/training.gd`. The mind path raises it nowhere, so
##     gating the R19+ anchor milestone (`strengthen_anchor`) on it would lock an
##     actor who never trains body out of that milestone permanently. That is the
##     trap BL-0143 recorded; re-adding the field invites re-walking it.
##
## `insight_required` is the fourth field and is STILL HERE. It is exactly
## `comprehension_required * 0.5` at all 30 realms, so it is a strictly weaker copy
## of the gate `MindBreakthroughCondition` already enforces and can never bind —
## but `game/tests/modules/test_seed_generator_parity.gd` reads it, and deleting it
## is that suite's edit, not this one's. BL-0146 carries the change.
##
## On AGENTS.md's RATE_STEP ceiling: it does NOT depend on these fields. The rule
## names `progress_required` — "the smallest per-realm step in the three authored
## `progress_required` ladders" — and `test_realm_rate.gd` computes the bound from
## `BUDGET_FIELD := "progress_required"`. Deleting the two work-budget fields
## leaves the RATE_STEP bound untouched. BL-0155 asserted the opposite; it was
## wrong, and this note is here so it is not re-litigated.

## The three deleted names. A field is deleted, not renamed: a rename is the same
## dead data under another spelling, so the guard matches the name a reader would
## have to reach for.
const DELETED := [
	"sea_milestone_work",
	"meridian_milestone_work",
	"resonance_required",
]

## Properties the seed class is known to carry and that production code reads. The
## liveness term asserts these are still declared, so "the declaration scan read
## nothing" cannot pass as "the deleted fields are gone".
const LIVE_PROPERTIES := [
	"id",
	"progress_required",
	"comprehension_required",
	"required_channel_state",
	"sea_capacity",
	"sea_catalyst",
]

const SEED_SCRIPT := "res://src/modules/mind_cultivation/realm_seed.gd"
const SEED_DIR := "res://data/mind_cultivation/realms"

## Cached because the runner calls `setup()` before every case. Cleared in
## `teardown()`, which is idempotent and runs whatever the case did.
var _exports: Dictionary = {}
var _seed_file_names_cache: PackedStringArray = PackedStringArray()


func teardown() -> void:
	_exports.clear()
	_seed_file_names_cache = PackedStringArray()


# ── Leg 1: the class does not declare them ──────────────────────────────────


## The seed class declares no property a reader could reach. Read from the class's
## SOURCE, the way `test_realm_rate.gd` reads a module for an authored constant,
## because a field re-added to `realm_seed.gd` with no seed re-authoring it is still
## a field that invites the next reader — and because reflection proved unreliable
## here (see the header).
func test_the_seed_class_no_longer_declares_the_deleted_fields() -> void:
	var declared := _exported_names()
	for name in DELETED:
		assert_eq(
			declared.has(name),
			false,
			"MindRealmSeed.%s is back and nothing reads it. See this suite's header." % name
		)


# ── Leg 2: no shipped seed authors them ─────────────────────────────────────


## No `.tres` under the seed directory carries the line. Separate from leg 1
## because a line for a property the class has dropped is SILENTLY IGNORED by Godot
## — measured, not assumed — so the data can be wrong while the class is right, and
## only this leg sees it.
func test_no_shipped_seed_authors_a_deleted_field() -> void:
	var files := _seed_file_names()
	for file_name in files:
		var body := FileAccess.get_file_as_string("%s/%s" % [SEED_DIR, file_name])
		for name in DELETED:
			assert_eq(
				body.contains("%s =" % name),
				false,
				"%s authors %s again; the generator still emits it." % [file_name, name]
			)


# ── Leg 3: the liveness term, unconditional ─────────────────────────────────


## The term that gives legs 1 and 2 something to bite on.
##
## Legs 1 and 2 are both absence checks, and an absence check has a failure mode
## indistinguishable from success: if the search set is empty, both pass without
## having looked at anything. Three ways that happens here, all asserted.
##
##   1. The seed directory listing is empty or short — the seeds were moved,
##      renamed or deleted, and leg 2 is scanning a subset (or nothing).
##   2. The declaration scan matched nothing — the class source was unreadable, the
##      pattern stopped matching, or the file was replaced, and leg 1 is comparing
##      against `{}`. This one already happened once: a reflection-based first
##      version produced an empty property list and two vacuous passes.
##   3. The seeds stopped loading as `MindRealmSeed` — every value check anywhere
##      that reads a seed is now reading a null, and this guard would agree.
##
## Each term is checked against the ladder itself rather than against a literal, so
## it cannot be satisfied by a constant a later edit invalidates in silence. This is
## the shape of the third leg of `test_arch_rules.gd`'s app-state case: while the tree
## is clean the correspondence holds trivially, and the term is what says so out loud.
## Without it this suite is a checker and a tree agreeing with each other, whatever
## that agreement said.
func test_the_seed_set_this_guard_scans_is_the_whole_ladder_and_still_reads() -> void:
	var ladder := RealmDefaults.ladder()
	var files := _seed_file_names()
	assert_eq(
		files.size(),
		ladder.size(),
		"%s holds one seed per realm; a short listing means the cases above never look." % SEED_DIR
	)
	var declared := _exported_names()
	assert_ne(declared.size(), 0, "%s was read and its @export vars matched" % SEED_SCRIPT)
	for name in LIVE_PROPERTIES:
		assert_eq(
			declared.has(name),
			true,
			"MindRealmSeed still declares %s, so the scan above is the real one" % name
		)
	for realm in ladder.realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		assert_ne(
			seed,
			null,
			"%s loads as a MindRealmSeed, so the checks above describe shipped data" % realm.id
		)


# ── Helpers ─────────────────────────────────────────────────────────────────


## The `.tres` files in the seed directory.
##
## `DirAccess.get_files_at` returns every file, so a stray editor artefact or a
## `.uid` would be counted and read as though it were a seed. Filtered, and the
## filter is asserted from the outside by the ladder-size term above: if `.tres`
## ever stopped matching, that listing collapses and the term fires.
func _seed_file_names() -> PackedStringArray:
	if not _seed_file_names_cache.is_empty():
		return _seed_file_names_cache
	var out := PackedStringArray()
	for file_name in DirAccess.get_files_at(SEED_DIR):
		if file_name.ends_with(".tres"):
			out.append(file_name)
	out.sort()
	_seed_file_names_cache = out
	return out


## Every `@export var` name the seed class declares.
##
## Read from SOURCE, one line at a time, rather than through reflection:
## `get_property_list()` on this Resource returned an empty list and would have made
## every check above vacuous. `strip_edges` also drops the `\r`, so a CRLF checkout
## scans the same as an LF one.
##
## Deliberately not a RegEx: an earlier version used one, and Godot's `^` is not
## multiline without a flag, so it matched nothing and looked like an empty class.
## A line scan has no flag to get wrong. The cost is that an `@export var` inside a
## comment or a string would count as a declaration — that errs toward red, never
## toward a vacuous pass, which is the safe direction for this guard.
##
## The file's non-emptiness is asserted here rather than left to the liveness term, so
## a caller asking this question alone cannot be handed a silent empty answer. No node
## and no resource is minted, so there is nothing to free.
func _exported_names() -> Dictionary:
	if not _exports.is_empty():
		return _exports
	var body := FileAccess.get_file_as_string(SEED_SCRIPT)
	assert_ne(body, "", "%s is readable" % SEED_SCRIPT)
	if body.is_empty():
		return _exports
	for line in body.split("\n"):
		var text := String(line).strip_edges()
		if not text.begins_with("@export"):
			continue
		var at := text.find("var ")
		if at < 0:
			continue
		var rest := String(text.substr(at + 4)).strip_edges()
		var name := String(rest.split(" ")[0]).split(":")[0]
		if not name.is_empty():
			_exports[name] = true
	return _exports
