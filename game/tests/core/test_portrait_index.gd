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

const FIXTURE := "user://test_portrait_index_fixture.jsonl"
const MISSING := "res://assets/characters/portraits/no_such_file.png"
const PRESENT := "res://assets/characters/portraits/tidecaller.png"


func setup() -> void:
	_write_fixture()
	PortraitIndex.set_index_root(FIXTURE)


func teardown() -> void:
	# The singleton outlives the suite, and the resolver reads it. Leaving the fixture root
	# installed would hand the next suite this suite's rows.
	PortraitIndex.set_index_root("")
	if FileAccess.file_exists(FIXTURE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	PortraitIndex.instance().invalidate()


# --- The status filter ------------------------------------------------------


func test_the_fixture_is_actually_read() -> void:
	# Without this the whole suite can pass on an EMPTY catalog: every negative assertion
	# ("a planned portrait does not resolve") is satisfied by a catalog that loaded nothing.
	# A green guard that discriminates nothing is worse than a red one (INC-0016).
	assert_eq(FileAccess.file_exists(FIXTURE), true, "the fixture was written")
	assert_eq(
		FileAccess.get_file_as_string(FIXTURE).split("\n", false).size(),
		5,
		"the fixture is five lines, one row each"
	)
	var read := PortraitIndex.instance().ids()
	assert_eq(read.size(), 5, "every fixture row was parsed; read " + str(read))


func test_an_installed_generated_portrait_resolves() -> void:
	assert_eq(
		PortraitIndex.instance().portrait_path(&"character-0002"), PRESENT, "generated is installed"
	)


func test_an_approved_portrait_resolves_too() -> void:
	# THE REGRESSION. `install` writes `approved`, so a `generated`-only filter silently drops
	# every portrait the shipped command produces.
	assert_eq(
		PortraitIndex.instance().portrait_path(&"character-0001"), PRESENT, "approved is installed"
	)


func test_a_planned_portrait_does_not_resolve() -> void:
	# The other half of the invariant: widening the filter must not admit unrendered art.
	assert_eq(PortraitIndex.instance().portrait_path(&"character-0003"), "", "planned is not installed")


# --- The audit --------------------------------------------------------------


func test_validate_reports_a_planned_portrait() -> void:
	assert_eq(
		_problems().has("character-0003 portrait is planned"), true, "a gap is reported, not hidden"
	)


func test_validate_reports_an_installed_portrait_whose_file_is_missing() -> void:
	# Existence, not just a non-empty array: the shipped portraits directory does not exist and
	# `PortraitResolver.validate` only checked emptiness, so the gate was green on four portraits
	# that cannot load.
	assert_eq(
		_problems().has("character-0004 portrait file is missing: " + MISSING),
		true,
		"a missing file is a content gap"
	)


func test_validate_accepts_an_installed_portrait_whose_file_exists() -> void:
	assert_eq(
		_problems().has("character-0001 portrait file is missing: " + PRESENT),
		false,
		"installed art on disk is not a gap"
	)


# --- Identity ---------------------------------------------------------------


func test_a_race_resolves_to_the_lowest_id_in_sorted_order() -> void:
	# Never in file order: a `DirAccess`-shaped read is not stable, and two runs must not
	# disagree about which face a race has.
	assert_eq(
		PortraitIndex.instance().character_for_race(&"tidecaller"),
		&"character-0000",
		"lowest id, not first line"
	)


# --- Internals --------------------------------------------------------------


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
		# Written LAST and with the LOWEST id, so a reader that took file order would answer
		# `character-0001` and this row is what tells the two behaviours apart.
		_row("character-0000", "tidecaller", "approved", PRESENT),
	]
	var lines: Array[String] = []
	for row in rows:
		lines.append(JSON.stringify(row))
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	if file == null:
		return
	for line in lines:
		file.store_line(line)
	file.close()


func _row(character_id: String, race: String, status: String, path: String) -> Dictionary:
	return {
		"id": character_id,
		"tags": ["race:" + race, "palette:neutral", "build:slender"],
		"assets": {
			"dialogue_portrait": {"status": status, "path": path},
		},
	}
