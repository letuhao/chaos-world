extends TestCase

## ADR 0131: the generated character index is a bridge, not a source of truth.
##
## ## Why this file exists at all
##
## `core/portrait_resolver.gd` is asserted never to READ an index, so the one file that does read
## one had no test of its own. That left a defect no value assertion could see: `portrait_path` and
## `validate` filtered on `status == "generated"` while `tools character_assets install` writes
## `approved` (`character_assets.py:1396`), so every portrait the shipped `approve` command
## produced resolved to the placeholder while the catalog reported it as art. A green suite,
## correct data, no face.
##
## ## The invariant
##
## **A slot is installed at either status and at no other.** One constant, read by the reader AND
## the audit, so the two cannot drift apart a second time.
##
## ## Why every test re-asserts the fixture root
##
## The runner calls `setup` ONCE per suite (`run_tests.gd:61`) and `teardown` after EVERY test
## (`:92`). A teardown that deleted the fixture therefore emptied it after the first test, and
## every later assertion read a catalog that no longer existed — which is how a suite of negative
## assertions passes on nothing. So: write once, re-point per test, and never delete.

const FIXTURE := "user://test_portrait_index_fixture.jsonl"

## The five race ids the game actually defines, read from `res://data/races`. Written out rather
## than scanned so a test failure names WHICH race started matching, and so adding a sixth race is
## a deliberate edit here rather than a silent behaviour change.
const AUTHORED_RACE_IDS: Array[StringName] = [
	&"commonborn",
	&"emberblood",
	&"emberblood_touched",
	&"stoneborn",
	&"tidecaller",
]
const MISSING := "res://assets/characters/portraits/no_such_file.png"
## A path that EXISTS, so "installed art on disk is not a gap" means something. It is not a PNG
## because `validate` only asks `FileAccess.file_exists`; the shipped portraits directory does not
## exist, so there is no portrait file to name. The file under test is the one guaranteed present.
const PRESENT := "res://src/core/portrait_index.gd"


func setup() -> void:
	_write_fixture()


func teardown() -> void:
	# Hand the real catalog back to whatever runs next, and drop the cache so no test reuses the
	# previous test's rows.
	PortraitIndex.set_index_root("")
	PortraitIndex.instance().invalidate()


# --- The status filter ------------------------------------------------------


func test_the_fixture_is_actually_read() -> void:
	# Without this the whole suite can pass on an EMPTY catalog: every negative assertion
	# ("a planned portrait does not resolve") is satisfied by a catalog that loaded nothing.
	# A green guard that discriminates nothing is worse than a red one (INC-0016).
	_use_fixture()
	assert_eq(FileAccess.file_exists(FIXTURE), true, "the fixture was written")
	assert_eq(_read_ids(), 5, "every fixture row was parsed")


func _read_ids() -> int:
	return PortraitIndex.instance().ids().size()


func test_an_installed_generated_portrait_resolves() -> void:
	_use_fixture()
	assert_eq(
		PortraitIndex.instance().portrait_path(&"character-0002"), PRESENT, "generated is installed"
	)


func test_an_approved_portrait_resolves_too() -> void:
	# THE REGRESSION. `install` writes `approved`, so a `generated`-only filter silently drops
	# every portrait the shipped command produces.
	_use_fixture()
	assert_eq(
		PortraitIndex.instance().portrait_path(&"character-0001"), PRESENT, "approved is installed"
	)


func test_a_planned_portrait_does_not_resolve() -> void:
	# The other half of the invariant: widening the filter must not admit unrendered art.
	_use_fixture()
	assert_eq(
		PortraitIndex.instance().portrait_path(&"character-0003"), "", "planned is not installed"
	)


# --- The audit --------------------------------------------------------------


func test_validate_reports_a_planned_portrait() -> void:
	_use_fixture()
	var found := _problems()
	assert_eq(
		found.has("character character-0003 portrait is planned"),
		true,
		"a gap is reported: " + str(found)
	)


func test_validate_reports_an_installed_portrait_whose_file_is_missing() -> void:
	# Existence, not just a non-empty array: the shipped portraits directory does not exist and
	# `PortraitResolver.validate` only checked emptiness, so the gate was green on four portraits
	# that cannot load.
	_use_fixture()
	assert_eq(
		_problems().has("character character-0004 portrait file is missing: " + MISSING),
		true,
		"a missing file is a content gap"
	)


func test_validate_accepts_an_installed_portrait_whose_file_exists() -> void:
	_use_fixture()
	# Spelled with the full prefix the format string emits, so this asserts the ABSENCE of a
	# message that would otherwise appear — not the absence of a string that never existed.
	assert_eq(
		_problems().has("character character-0001 portrait file is missing: " + PRESENT),
		false,
		"installed art on disk is not a gap: " + str(_problems())
	)


# --- Identity ---------------------------------------------------------------


func test_a_race_resolves_to_the_lowest_id_in_sorted_order() -> void:
	# Never in file order: a `DirAccess`-shaped read is not stable, and two runs must not
	# disagree about which face a race has. `character-0000` is written LAST and is the LOWEST
	# id, so a file-order reader would answer `character-0001` and this row is what tells the
	# two behaviours apart.
	_use_fixture()
	assert_eq(
		PortraitIndex.instance().character_for_race(&"tidecaller"),
		&"character-0000",
		"lowest id, not first line"
	)


func test_no_generated_row_carries_an_authored_race_so_step_2b_is_unreachable() -> void:
	# Step 2b of `PortraitResolver.resolve` asks this index for a generated face when no authored
	# PortraitDef answers. It can never match: `character-index.jsonl` has 2000 rows and NOT ONE
	# carries an authored race id — its `race:` tags are free text (race:human, race:plantkin,
	# race:beastkin) while the game defines five (commonborn, emberblood, emberblood_touched,
	# stoneborn, tidecaller). Measured, not inferred.
	#
	# Asserted so the branch cannot rot unnoticed. A step that can never fire is dead code that reads
	# as a live fallback, and a reader of `resolve()` would reasonably believe a race with no
	# authored `.tres` gets a generated face. It does not: it gets the placeholder. If the crowd
	# generator is ever taught the authored race vocabulary this test FAILS, which is the point —
	# it turns a silent no-op into a decision somebody has to make about step 2b.
	var index := PortraitIndex.instance()
	# The REAL index, not the fixture: this is a claim about the shipped corpus, and a fixture
	# written by this suite would agree with anything. `set_index_root("")` restores the authored
	# content root, then `invalidate` drops the latched read.
	PortraitIndex.set_index_root("")
	var authored := 0
	for race_id in AUTHORED_RACE_IDS:
		if index.character_for_race(race_id) != &"":
			authored += 1
	assert_eq(
		authored,
		0,
		(
			"a generated row now carries an authored race id, so step 2b can fire; decide whether to "
			+ "keep the branch, and update DEF-0298"
		)
	)


# --- Internals --------------------------------------------------------------


## Point the singleton at the fixture and drop the cache, in that order. The index latches
## `_loaded` on its first read, so a cache left over from another test is indistinguishable from
## a correct one until an assertion disagrees — which is why this is per test, not per suite.
func _use_fixture() -> void:
	PortraitIndex.set_index_root(FIXTURE)
	PortraitIndex.instance().invalidate()


func _problems() -> Array[String]:
	return PortraitIndex.instance().validate()


## Five rows built from a FIXED literal list. The bound is the list's length, read before the
## loop, and the body appends to a different array than the one it iterates — the INC-0002
## discipline, stated here because the alternative is invisible to `test_no_unbounded_wait`.
func _write_fixture() -> void:
	var rows: Array[Dictionary] = [
		_row("character-0001", "tidecaller", "approved", PRESENT),
		_row("character-0002", "emberblood", "generated", PRESENT),
		_row("character-0003", "stoneborn", "planned", ""),
		_row("character-0004", "commonborn", "approved", MISSING),
		# Written LAST and with the LOWEST id: see the sorted-order test.
		_row("character-0000", "tidecaller", "approved", PRESENT),
	]
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	if file == null:
		return
	for row in rows:
		file.store_line(JSON.stringify(row))
	file.close()


func _row(character_id: String, race: String, status: String, path: String) -> Dictionary:
	return {
		"id": character_id,
		"tags": ["race:" + race, "palette:neutral", "build:slender"],
		"assets":
		{
			"dialogue_portrait": {"status": status, "path": path},
		},
	}
