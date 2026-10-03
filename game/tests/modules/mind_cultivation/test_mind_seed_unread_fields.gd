extends TestCase

## BL-0146 / BL-0155: three fields that every `MindRealmSeed` used to author were
## read by nothing anywhere — not in `res://src`, not in `tools/`, not in any ADR.
## They were deleted. This suite is the guard against their return, and it has
## three legs because a one-leg "the field is absent" check is satisfied just as
## well by the seed class having lost something else, or by the search set being
## empty. Leg 3 is what stops that.
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
## liveness term asserts these are still present, so "the property list came back
## empty" cannot pass as "the deleted fields are gone".
const LIVE_PROPERTIES := [
	"id",
	"progress_required",
	"comprehension_required",
	"required_channel_state",
	"sea_capacity",
	"sea_catalyst",
]

const SEED_DIR := "res://data/mind_cultivation/realms"

## Cached because the runner calls `setup()` before every case and this reads a
## class and a directory. Both are refcounted and released here, not left to the
## frame: `teardown()` is idempotent and runs whatever the case did.
var _declared: Dictionary = {}
var _seed_files_cache: PackedStringArray = PackedStringArray()


func teardown() -> void:
	_declared.clear()
	_seed_files_cache = PackedStringArray()


# ── Leg 1: the class does not declare them ──────────────────────────────────


## The seed class carries no property a reader could reach. Checked against the
## class's OWN property list rather than only against the shipped `.tres`, because
## the two fail differently: a field re-added to `realm_seed.gd` with no seed
## re-authoring it is still a field that invites the next reader.
func test_the_seed_class_no_longer_declares_the_deleted_fields() -> void:
	var declared := _declared_properties()
	assert_ne(
		declared.size(),
		0,
		"MindRealmSeed declares properties; an empty list means the class was never read"
	)
	for name in DELETED:
		assert_eq(
			declared.has(name),
			false,
			(
				"MindRealmSeed.%s is back, and it is read by nothing. The reason it was"
				" deleted is in this suite's header."
				% name
			)
		)


# ── Leg 2: no shipped seed authors them ─────────────────────────────────────


## No `.tres` under the seed directory carries the line. Separate from leg 1
## because a line for a property the class has dropped is SILENTLY IGNORED by
## Godot — measured, not assumed — so the data can be wrong while the class is
## right, and only this leg sees it.
func test_no_shipped_seed_authors_a_deleted_field() -> void:
	var files := _seed_file_names()
	assert_ne(
		files.size(),
		0,
		"%s lists .tres files; an empty listing would satisfy this case vacuously" % SEED_DIR
	)
	for file_name in files:
		var body := FileAccess.get_file_as_string("%s/%s" % [SEED_DIR, file_name])
		assert_ne(body, "", "%s is readable" % file_name)
		for name in DELETED:
			assert_eq(
				body.contains("%s =" % name),
				false,
				(
					"%s authors %s again. The generator still emits it, so a regeneration"
					" re-seeds it and the class drops it silently."
					% [file_name, name]
				)
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
##   2. The property list came back empty — the class was not read at all, and
##      leg 1 is comparing against `{}`.
##   3. The seeds stopped loading as `MindRealmSeed` — every value check anywhere
##      that reads a seed is now reading a null, and this guard would agree.
##
## Each term is checked against the ladder itself rather than against a literal, so
## it cannot be satisfied by a constant a later edit invalidates in silence. This
## is the shape of the third leg of `test_arch_rules.gd`'s app-state case: while
## the tree is clean the correspondence holds trivially, and the term is what says
## so out loud. Without it this suite is a checker and a tree agreeing with each
## other, whatever that agreement said.
func test_the_seed_set_this_guard_scans_is_the_whole_ladder_and_still_reads() -> void:
	var ladder := RealmDefaults.ladder()
	var files := _seed_file_names()
	assert_eq(
		files.size(),
		ladder.size(),
		(
			"%s holds exactly one seed per realm. A short listing means the cases above scan"
			" a subset, and would report a deleted field as absent because they never looked"
			" for it." % SEED_DIR
		)
	)
	var declared := _declared_properties()
	for name in LIVE_PROPERTIES:
		assert_eq(
			declared.has(name),
			true,
			"MindRealmSeed still declares %s, so the property list above is the real one" % name
		)
	for realm in ladder.realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		assert_ne(
			seed,
			null,
			(
				"%s loads as a MindRealmSeed, so the field checks above describe shipped data"
				% realm.id
			)
		)


# ── Helpers ─────────────────────────────────────────────────────────────────


## The `.tres` files in the seed directory.
##
## `DirAccess.get_files_at` returns every file, so a stray editor artefact or a
## `.uid` would be counted and read as though it were a seed. Filtered, and the
## filter is asserted from the outside by the ladder-size term above: if `.tres`
## ever stopped matching, that listing collapses and the term fires.
func _seed_file_names() -> PackedStringArray:
	if not _seed_files_cache.is_empty():
		return _seed_files_cache
	var out := PackedStringArray()
	for file_name in DirAccess.get_files_at(SEED_DIR):
		if file_name.ends_with(".tres"):
			out.append(file_name)
	out.sort()
	_seed_files_cache = out
	return out


## The names `MindRealmSeed` actually declares, read from the class itself.
##
## `get_property_list()` on a `Resource` includes the engine's own properties
## alongside the script's, which is fine: this is an existence question about
## specific names, not a shape assertion about the list. The probe instance is a
## RefCounted and is released explicitly rather than left to the frame.
func _declared_properties() -> Dictionary:
	if not _declared.is_empty():
		return _declared
	var probe := MindRealmSeed.new()
	for entry in probe.get_property_list():
		_declared[String(entry["name"])] = true
	probe.free()
	return _declared