extends TestCase

## DEF-0212's regression guard: a probe registered into the process-wide `StatusCatalog`
## singleton and never forgotten.
##
## The defect, stated once. `test_status_refusals.gd`'s
## `test_the_baseline_def_is_accepted_so_the_negatives_mean_something` built a well-formed
## `&"probe_accept"` and registered it WITHOUT passing it through `_tracked`, so `setup()`'s
## `_forget` never saw it. A full status-suite run ended with **21 ids instead of the
## shipped twenty**, `fire_immolation` left sitting in `_rejected` beside it with the reason
## *"claimed by fire_immolation, probe_also_claims_fire"*, and **no assertion failed** — the
## suites that would have noticed had all finished. One call site is fixed; the CLASS is what
## this file is for.
##
## ## What this file proves
##
## At the instant each of its own tests runs, the singleton publishes EXACTLY the id set the
## content tree declares, and refuses nothing. That is an invariant of the live process, not
## of an ordering: whichever status suite happens to run after the leaker, this one fails.
## The ids and the reasons are NAMED in the failure, because a bare `21 != 20` sends the next
## reader to the loader when the probe is what leaked.
##
## ## What it does NOT prove, and why the shortfall lives in the runner
##
## It does NOT prove the catalogue is clean at the END of the run, and no `[Fact]` in this
## tree can. `run_tests.gd` offers no ordering or aggregation hook: it walks `_find_tests()`
## in raw `DirAccess` order — UNSORTED, so suite order is a filesystem artifact — and it holds
## no "last suite" concept to hook. `_test_methods()` sorts, so METHOD order within a suite is
## deterministic, but which suite runs when is not, and neither is which suites a filtered
## `--suite` run contains at all. A guard here therefore fires only for a leaker that happened
## to run earlier. It is a PROXY, and claiming otherwise would be exactly the kind of
## order-dependent green this file exists to stop. The failure it converts from silent to
## loud is the one that matters — DEF-0212 shipped clean for a whole run because nothing ever
## looked.
##
## ## Why the expected set is read from the tree and not restated
##
## A pinned twenty-id literal is a second source of truth that drifts, and a guard reading a
## DRIFTED one reports an honest probe as content. So this file derives the expected set
## through the loader's OWN walk (`ContentScan.files_under`, the function
## `StatusCatalog._scan` delegates to) and keys it by the declared `id`, exactly as
## `test_status_catalogue.gd` reads the authored tree.

## This file's probe id. Declared rather than inlined so the "it is not authored content"
## assertion and the two sides of the probe test cannot name different strings.
const PROBE_ID := &"probe_catalogue_pollution_guard"

## The def whose shape the probe copies. `metal_sever` is tier-1 and well-formed, so a
## duplicate of it is a status the loader must admit — the probe has to be a GOOD def, or
## admitting it would prove nothing about cleanup.
const TEMPLATE_ID := "metal_sever"

# --- the invariant, as the running process stands --------------------------------------


func test_the_catalogue_publishes_exactly_the_authored_ids_and_refuses_nothing_right_now() -> void:
	# The three facts are counted and NAMED rather than asserted as bare counts. A size
	# mismatch on a suite of twenty says only "21 != 20", which reads as a content problem
	# and sends the next reader to `res://data/statuses` instead of to the probe that left
	# `probe_also_claims_fire` behind. The surplus list is what turns that into a name.
	var authored := _authored_ids()
	var published := _published_ids()
	var surplus := _surplus(authored)
	var absent := _absent(authored, published)

	# Scope before findings, for the reason the sibling guards give: a scan that reads
	# nothing must not read as a tree that holds nothing. Both sides are non-empty, so an
	# empty surplus below cannot be satisfied by an unwalked directory or a lazy loader.
	assert_eq(authored.is_empty(), false, "the content tree is walked, and holds defs")
	assert_eq(published.is_empty(), false, "and the catalogue is loaded, and publishes ids")
	assert_eq(surplus, [], "no published id is outside the CONTENT TREE: a probe leaked (DEF-0212)")
	assert_eq(absent, [], "and every authored id is published — none lost to a probe's cleanup")
	assert_eq(
		published.size(),
		authored.size(),
		(
			"the catalogue holds EXACTLY the authored ids: %d of %d"
			% [published.size(), authored.size()]
		)
	)
	# The refusals, reported rather than silently dropped: on a well-formed tree every entry
	# here is a test probe, and a probe refusal sitting in the shipped tree's designer-facing
	# report is the half of DEF-0212 a count of ids alone would never have shown.
	assert_eq(
		StatusCatalog.instance().rejected(),
		[],
		"nothing is refused — a probe refusal is never part of the shipped tree"
	)


func test_the_probe_this_file_registers_is_forgotten_before_it_asserts_the_clean_tree() -> void:
	# The guard is worthless if it cannot SEE the thing it guards, so it proves it can. A
	# well-formed probe with an id no `.tres` declares is admitted, shows up in
	# `status_ids()`, and is gone the instant the same unregistering the fixing suites use
	# takes it away. Without this the assertions above could be satisfied by a predicate
	# that never fires, which is the failure mode this repo keeps producing.
	var authored := _authored_ids()
	assert_eq(authored.has(String(PROBE_ID)), false, "the probe's id is not authored content")
	var def := _probe()
	assert_eq(StatusCatalog.instance().register(def), true, "a well-formed probe is admitted")
	assert_eq(_published_ids().has(String(PROBE_ID)), true, "and the catalogue publishes it")
	assert_eq(StatusCatalog.instance().rejected(), [], "and a well-formed def is not a refusal")

	_unregister(PROBE_ID)
	assert_eq(
		_published_ids().has(String(PROBE_ID)), false, "unregistering takes it out of the ids"
	)
	assert_eq(StatusCatalog.instance().rejected(), [], "and leaves no refusal behind")
	# The loop is closed here rather than left to the test above: the tree the other test
	# asserts is exactly the authored one again, so the unregistering is what RESTORED it
	# rather than the probe never having landed. This assertion is the one that fails if
	# someone reaches for `register()` in this file and drops the cleanup.
	assert_eq(_surplus(_authored_ids()), [], "the catalogue is back to exactly the authored ids")


# ── helpers ────────────────────────────────────────────────────────────────────────


## Every id the loader admits in the shipped tree: the defs under
## [constant StatusCatalog.STATUSES_ROOT] carrying the loader's own
## [constant StatusCatalog.STATUS_SCRIPT_CLASS] marker, keyed by the declared `id`.
##
## The loader's own walk, its own text check and its own skip rules, so the expected set
## cannot disagree with what the loader would accept. Renaming a file changes nothing, and no
## id is restated anywhere in this file.
func _authored_ids() -> Dictionary:
	var out: Dictionary = {}
	for path in ContentScan.files_under(StatusCatalog.STATUSES_ROOT):
		var script_class := 'script_class="%s"' % StatusCatalog.STATUS_SCRIPT_CLASS
		if not FileAccess.get_file_as_string(path).contains(script_class):
			continue
		var def := load(path) as StatusDef
		if def == null or def.id == &"":
			continue
		out[String(def.id)] = true
	return out


## What the catalogue publishes right now, as a set of Strings.
func _published_ids() -> Dictionary:
	var out: Dictionary = {}
	for status_id in StatusApi.status_ids():
		out[String(status_id)] = true
	return out


## Published ids the CONTENT TREE does not declare, sorted. Empty is the invariant; a
## non-empty one is the NAME of the probe that outlived its test, which is the whole point
## of reporting it instead of counting it.
func _surplus(authored: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in _published_ids().keys():
		if not authored.has(key):
			out.append(key)
	out.sort()
	return out


## Authored ids the catalogue is not publishing, sorted. The opposite direction of
## [_surplus], and the one that catches a cleanup too eager: an `_forget` that erased a real
## authored id would leave every published-only assertion true.
func _absent(authored: Dictionary, published: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in authored.keys():
		if not published.has(key):
			out.append(key)
	out.sort()
	return out


## A detached copy of an authored def, so the probe is well-formed without restating
## `StatusDef`'s vocabulary — the same move `test_status_catalogue.gd` makes.
## `duplicate()` rather than a field-by-field copy because a copied field list is a second
## vocabulary that rots the first time `StatusDef` grows a field.
##
## `on_landed_blow` is cleared, not inherited: the probe exists to occupy `_ids` and
## `_definitions`, and a probe that also claimed an element's landed blow would leave a
## transient ambiguity in `status_for_element` for any suite running between this `register`
## and the `_unregister` below. The leak under test is a REGISTRATION, not a collision.
func _probe() -> StatusDef:
	var template := load("%s/%s.tres" % [StatusCatalog.STATUSES_ROOT, TEMPLATE_ID]) as StatusDef
	var copy: StatusDef = template.duplicate()
	copy.payload = template.payload.duplicate(true)
	copy.id = PROBE_ID
	copy.on_landed_blow = false
	return copy


## Undo a probe registration. Mirrors `_forget` in `test_status_refusals.gd` and `_cleanup` in
## `test_status_element_mapping.gd` — three copies of five lines rather than one helper in a
## module, because a helper shared across `test_*.gd` files would be a second suite-discovery
## hazard for the saving. The comment travels with each copy because the reason it exists is
## the reason this whole file exists.
func _unregister(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids
