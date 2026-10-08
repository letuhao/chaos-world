extends TestCase

## ## DEF-0343: the shipped guilds' recognition is AUTHORED, and this is the guard that keeps it so
##
## The FIELD and its ONE consumer shipped first (`InstitutionPositionDef.standing_percent_stats`
## and `InstitutionProjection.grant`, ADR 0084) and the CONTENT did not: all three `.tres` files
## under `res://data/packs/guilds/organizations` authored an EMPTY allowlist on every office, so the recognition
## a guild confers was authored-but-unreachable — a player who founded The Lantern Exchange
## received a seat, a duty and a treasury and NOT one point of recognition.
##
## ## What this suite measures, and against what
##
## The sweep runs over the REAL `.tres` corpus rather than a fixture, because a fixture and the
## production shape have quietly diverged before (ADR 0248): one typo in a shipped id makes
## `InstitutionProjection.unknown_stat` refuse the WHOLE allowlist by name, so an id no holder can
## name is a gate no holder can satisfy.
##
## 1. Every authored id is NAMEABLE on a live sheet and has a non-zero baseline on a fully
##    invested one — otherwise a PERCENT on it is the silent `(0.0 + 0.0) * (1 + p) = 0.0`
##    no-op ADR 0068 measured on 44 items.
## 2. An office that grants recognition ASKS for work (`duty_per_period > 0`), the office half
##    of AGENTS.md's yin-yang pair.
## 3. The two guilds recognise DIFFERENT things, and so do their offices: a per-office authored
##    choice, never one uniform grant.
## 4. End to end: a founder of the Exchange is recognised by the bounded percent through the
##    PRODUCTION path, and the grant FALLS when standing falls — a demotion is the only exit
##    recognition has.
##
## ## `torrent_field_circle` authors NO offices and NO ids, ON PURPOSE
##
## The farmers' circle is the no-offices organization: recognition begins where office begins,
## and it begins nowhere here — ADR 0083's FIRST state, a design rather than a gap. Do not
## "complete" it by adding ids; there is no office for them to project through.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over `ContentScan.files_under`'s materialized
## snapshot, over a def's own authored `positions`, over an allowlist's own keys and over a
## literal `range`; none appends to anything it walks, so no bound can grow in lockstep with
## its own body and `test_no_unbounded_wait.gd` has nothing to reject.

## The ONE directory every authored organization lives in, swept as the corpus it is rather
## than written down as a file list: a fourth guild dropped in is measured here with no edit
## to this file.
const INSTITUTIONS_DIR := "res://data/packs/guilds/organizations"
## The two guilds DEF-0343 is about, read for the per-office and per-guild shape assertions.
## The farmers' circle is deliberately absent: it authors no office at all — see the class note.
const LANTERN := "res://data/packs/guilds/organizations/lantern_exchange.tres"
const HUNT := "res://data/packs/guilds/organizations/grey_horizon_hunt.tres"
## The office ids the DEF names as the pair that must differ: the ordinary member and the one
## seat of the counting house.
const CLERK := &"clerk"
const SEAT := &"first_ledger"
const LANTERN_ID := &"lantern_exchange"
## The scratch tree the RED case writes its broken COPIES of the real `.tres` into. Under the OS
## temp directory, never the repository: the shipped file is READ and never mutated, because
## `load()` caches process-wide and a write to it would leak into every suite after this one.
const SCRATCH_DIR := "cw_institution_guild_recognition_test"
## The scenario subdirectories, one per break, so a fault is attributable to the copy that caused
## it. Also what teardown removes.
const SCRATCH_CASES := ["clean", "typo", "zero_baseline"]

## Everything this suite mints. **`free()` is never called on an entry**: `Actor` and
## `Resource` both extend `RefCounted`, and `Object.free()` on one is a SCRIPT ERROR that
## aborts the rest of teardown. Dropping the array IS the release.
var _born: Array = []
var _registry: InstitutionRegistry = null
## An actor carrying no grant at all, so "nothing outside the allowlist moved" is measured
## against the same fully invested sheet rather than against a hand-written number.
var _reference: Actor = null
## The scratch root once the RED case has built it, so teardown can remove what it left.
var _scratch: String = ""


func setup() -> void:
	# BOTH process singletons are cleared in `setup` AND in `teardown`: the runner drives
	# every suite in ONE process, so `setup` clears what a PREVIOUS suite left and `teardown`
	# clears what this one does.
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	_registry = InstitutionRegistry.new()
	InstitutionBoot.install(_registry)
	_reference = _actor(&"reference")


func teardown() -> void:
	InstitutionMembership.clear()
	InstitutionDefCatalog.clear()
	if InstitutionRegistry.shared != null:
		InstitutionRegistry.shared.clear()
	_born.clear()
	if _registry != null:
		_registry.clear()
		_registry = null
	if _scratch != "":
		for file in ContentScan.files_under(_scratch):
			DirAccess.remove_absolute(file)
		for case_name in SCRATCH_CASES:
			DirAccess.remove_absolute(_scratch.path_join(case_name))
		DirAccess.remove_absolute(_scratch)
		_scratch = ""


# --- The sweep: the real corpus, not a fixture -----------------------------------


## ## Every id the shipped corpus names must be nameable AND carry a baseline
##
## The two halves are separately decidable and neither is inferred from the other, so the sweep
## reports both: `unknown_stat` answers "has this sheet a derivation at all", and the derived
## read answers "is that derivation non-zero for a body that has invested in everything". An id
## failing the first is the refusal that grades the whole allowlist by name; one failing the
## second is a grant that lands, sits in the ledger and moves nothing.
func test_every_shipped_office_allowlist_resolves_and_can_carry_a_percent() -> void:
	var swept := _sweep(INSTITUTIONS_DIR)
	# Both populations must be non-zero, or the sweep found nothing and would pass forever.
	assert_eq(
		int(swept["offices"]) > 0, true, "at least one shipped office really authors recognition"
	)
	assert_eq(int(swept["named"]) > 0, true, "and the corpus really does name stat ids")
	assert_eq(
		(swept["faults"] as Array).is_empty(),
		true,
		"no shipped office allowlist has a fault: %s" % _faults_text(swept)
	)


# --- The per-office and per-guild shape -------------------------------------------


## ## The two guilds author DIFFERENT recognitions, and so do their offices
##
## DEF-0343's own prescription: `clerk` and `first_ledger` are a pair that must differ, "so one
## office being recognised for credit is visibly a choice" — and a hunter being recognised for
## endurance where a merchant is recognised for the ledger is the point of two guilds rather
## than one. Every office of both guilds authors recognition, because an emptied office would
## read as the pre-fix state returning.
func test_the_two_guilds_recognise_different_things_and_so_do_their_offices() -> void:
	var lantern := _def(LANTERN)
	var hunt := _def(HUNT)
	# Every authored office of both guilds carries a non-empty allowlist. The shipped sect and
	# nation families do author empty ordinary offices and that is legal content; the GUILDS
	# are the family this DEF is about, where recognition becoming reachable is the fix, so an
	# emptied office here is the defect returning.
	for guild in [lantern, hunt]:
		for office in guild.positions:
			assert_ne(office, null, "no null office row")
			assert_eq(
				office.standing_percent_stats.is_empty(),
				false,
				(
					"'%s' authors no recognition, so the guild is recognised for nothing again"
					% office.id
				)
			)
	# The DEF's own pair: the ordinary member is recognised for something the seat is not.
	assert_ne(
		_ids_of(lantern.position(CLERK)),
		_ids_of(lantern.position(SEAT)),
		"the clerk and the seat share one allowlist, so recognition is uniform rather than a choice"
	)
	# The general form: every office of one guild authors a distinct set, so office itself is
	# the authored choice.
	for guild in [lantern, hunt]:
		var distinct := _distinct_sets(guild)
		assert_eq(
			distinct,
			guild.positions.size(),
			(
				"%s authors %d office(s) but only %d distinct allowlist(s)"
				% [guild.id, guild.positions.size(), distinct]
			)
		)
	# And the two guilds differ from each other: a hunter is recognised for other things.
	assert_ne(
		_guild_ids(lantern),
		_guild_ids(hunt),
		"a hunter is recognised for the same things as a merchant, so the two guilds are one"
	)


# --- The end-to-end measurement ---------------------------------------------------


## ## The measurement: a founder is recognised, and loses it when standing falls
##
## Driven through the PRODUCTION path — `InstitutionMembership.found` projects the office's own
## allowlist — so this is not a re-measurement of the projector. The founder is seated in
## `first_ledger`, whose authored ids are `poise` and `dao_heart`; at the authored
## `founder_standing` of 40 the percent is 0.04, at 100 it is the cap 0.10, at 50 it is 0.05,
## and at 0 the grant is a zero percent — a falling number is the only exit recognition has.
func test_a_founder_is_recognised_and_the_grant_falls_when_the_standing_falls() -> void:
	var actor := _actor(&"founder")
	var poise_before := actor.stats.derived(Stat.POISE)
	var dao_before := actor.stats.derived(Stat.DAO_HEART)
	var found := InstitutionMembership.found(_registry, actor, _def(LANTERN), "me")
	assert_eq(
		bool(found["ok"]),
		true,
		"the Exchange is founded off its shipped content: %s" % str(found.get("reason", ""))
	)
	var granted: Dictionary = found["granted"]
	assert_eq(granted.size(), 2, "both authored seat ids were granted, not one")
	assert_almost_eq(
		float(granted[String(Stat.POISE)]),
		0.04,
		"the percent is the founder standing's own rate, well under the cap"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.POISE), poise_before * 1.04, "so the seat's first id moved by it"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.DAO_HEART), dao_before * 1.04, "and so did the second"
	)
	# An allowlist is a partition, not "something changed": nothing outside it moved.
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH),
		_reference.stats.derived(Stat.MAX_HEALTH),
		"and nothing outside the allowlist moved"
	)
	# The rise: to 100, where the percent is at its ceiling.
	var raised := InstitutionMembership.move_standing(_registry, actor, LANTERN_ID, 60)
	assert_eq(int(raised["applied"]), 60, "standing is earned")
	assert_almost_eq(
		actor.stats.derived(Stat.POISE),
		poise_before * 1.10,
		"recognition rises with it, to the bounded ceiling"
	)
	# The demotion, first to 50: a real, non-zero percent that FELL rather than vanished.
	var fell := InstitutionMembership.move_standing(_registry, actor, LANTERN_ID, -50)
	assert_eq(int(fell["applied"]), -50, "standing falls")
	assert_almost_eq(
		actor.stats.derived(Stat.POISE), poise_before * 1.05, "so the granted percent falls with it"
	)
	# And to nothing at all, exactly: a strip that only nearly works strands the grant.
	InstitutionMembership.move_standing(_registry, actor, LANTERN_ID, -50)
	assert_almost_eq(
		actor.stats.derived(Stat.POISE),
		poise_before,
		"and at zero standing the sheet is restored exactly"
	)


# --- The red path, so the sweep is a tested guard (INC-0016) ----------------------


## ## The sweep can go RED, measured on scratch COPIES of the real file
##
## A green guard is not a tested guard: `test_every_shipped_office_allowlist_...` passes the
## moment the content is right, so this case drives the SAME `_sweep` with the real
## `lantern_exchange.tres` copied into a scratch tree and ONE id broken, twice — a typo no sheet
## can name, and `damage_reduction`, which is nameable and derives a literal `0.0` (ADR 0068).
## **The shipped file is never written**; the scratch copy is what is broken, and teardown
## removes it. The unbroken copy is swept first as the control, so the faults below are the break
## and not the copy.
func test_the_sweep_reports_a_broken_id_in_a_scratch_copy_of_the_real_file() -> void:
	var source := FileAccess.get_file_as_string(LANTERN)
	assert_ne(source, "", "the shipped file is readable")
	# The control: an unbroken COPY of the shipped file, swept by the same function.
	var clean_dir := _scratch_case("clean", source)
	var clean := _sweep(clean_dir)
	assert_eq(int(clean["named"]) > 0, true, "the scratch copy is measured rather than skipped")
	assert_eq(
		(clean["faults"] as Array).is_empty(),
		true,
		"an unbroken copy is clean: %s" % _faults_text(clean)
	)
	# Break one id with a one-letter transposition, which is exactly the authoring slip
	# `unknown_stat` refuses BY NAME — over the whole allowlist.
	var typo := source.replace('"fortune"', '"fotune"')
	assert_ne(typo, source, "the break really changed the text")
	var typo_dir := _scratch_case("typo", typo)
	var typo_swept := _sweep(typo_dir)
	assert_eq(
		_faults_text(typo_swept).contains("fotune"),
		true,
		"the sweep names the broken id: %s" % _faults_text(typo_swept)
	)
	# The OTHER read on its own, because nameability does not imply a baseline: this id IS
	# nameable and derives zero on every actor, so only the baseline half can catch it.
	var zero := source.replace('"fortune"', '"damage_reduction"')
	assert_ne(zero, source, "the substitution really changed the text")
	var zero_dir := _scratch_case("zero_baseline", zero)
	var zero_swept := _sweep(zero_dir)
	assert_eq(
		InstitutionProjection.unknown_stat(_reference, {String(Stat.DAMAGE_REDUCTION): 0.0}),
		null,
		"damage_reduction IS nameable, so the refusal would never catch it"
	)
	assert_eq(
		_faults_text(zero_swept).contains("damage_reduction"),
		true,
		"while the baseline read does: %s" % _faults_text(zero_swept)
	)


# --- Helpers ----------------------------------------------------------------------


## ## Every fault in the corpus at `root`, as data rather than as an assertion
##
## PURE: no `assert_*`, so the RED case can read WHICH fault fired rather than only that one
## did. `faults` is a list of printable strings; `offices` and `named` are the populations the
## caller proves non-zero, so a sweep that found nothing cannot pass as a clean one.
##
## A `for` over `ContentScan.files_under`'s materialized, sorted snapshot, over each def's own
## authored `positions` and over each allowlist's own keys: none of the three is appended to by
## the body, so no bound here can grow in lockstep with its own loop.
func _sweep(root: String) -> Dictionary:
	var faults: Array[String] = []
	var offices := 0
	var named := 0
	for path in ContentScan.files_under(root):
		var loaded = load(path)
		if loaded == null or not (loaded is InstitutionDef):
			faults.append("%s does not load as an institution" % path)
			continue
		var def := loaded as InstitutionDef
		for office in def.positions:
			if office == null:
				faults.append("%s authors a null office" % path.get_file())
				continue
			if office.standing_percent_stats.is_empty():
				continue
			offices += 1
			if office.duty_per_period <= 0:
				faults.append(
					"%s/%s grants recognition with no duty on it" % [path.get_file(), office.id]
				)
			for key in office.standing_percent_stats.keys():
				named += 1
				var stat_id := String(key)
				if InstitutionProjection.unknown_stat(_reference, {stat_id: 0.0}) != null:
					faults.append(
						(
							"%s/%s names '%s', which no live sheet can name"
							% [path.get_file(), office.id, stat_id]
						)
					)
				elif _reference.stats.derived(StringName(stat_id)) == 0.0:
					faults.append(
						(
							"%s/%s names '%s', whose baseline is zero"
							% [path.get_file(), office.id, stat_id]
						)
					)
	return {"faults": faults, "offices": offices, "named": named}


## A sweep's faults as one line. Built by hand rather than `String.join`, which takes a
## `PackedStringArray` and would be a second conversion at every call site.
func _faults_text(swept: Dictionary) -> String:
	var out := ""
	for fault in swept["faults"] as Array:
		out += String(fault) + "; "
	return out


## The scratch root, created on first use. Under the OS temp directory, never the repository.
func _scratch_root() -> String:
	if _scratch == "":
		_scratch = OS.get_environment("TEMP").path_join(SCRATCH_DIR)
		DirAccess.make_dir_recursive_absolute(_scratch)
	return _scratch


## One scenario directory holding one broken copy of the shipped file. `for` over nothing —
## a single write — so there is no loop here to bound.
func _scratch_case(case_name: String, text: String) -> String:
	var dir := _scratch_root().path_join(case_name)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("lantern_exchange.tres"), FileAccess.WRITE)
	assert_ne(file, null, "the scratch '%s' copy is writable" % case_name)
	file.store_string(text)
	file.close()
	return dir


## The def at `path`, loaded and never written.
func _def(path: String) -> InstitutionDef:
	var loaded := load(path)
	assert_ne(loaded, null, "%s loads" % path)
	return loaded as InstitutionDef


## One office's allowlist as sorted strings. Sorted on `Array[String]` for the reason
## `InstitutionDef.position_ids` states: interned ids do not order by their string value, so a
## positional expectation would be testing the engine rather than the content.
func _ids_of(office: InstitutionPositionDef) -> Array[String]:
	var out: Array[String] = []
	for key in office.standing_percent_stats.keys():
		out.append(String(key))
	out.sort()
	return out


## How many DISTINCT allowlists `def`'s offices author. `1` is a guild whose offices are all
## recognised for the same things, which is the uniform grant DEF-0343 measured.
func _distinct_sets(def: InstitutionDef) -> int:
	var seen: Array[String] = []
	for office in def.positions:
		if office == null:
			continue
		var joined := ""
		for stat_id in _ids_of(office):
			joined += stat_id + ","
		if not seen.has(joined):
			seen.append(joined)
	return seen.size()


## Every stat id `def`'s offices recognise between them, as sorted strings.
func _guild_ids(def: InstitutionDef) -> Array[String]:
	var out: Array[String] = []
	for office in def.positions:
		if office == null:
			continue
		for key in office.standing_percent_stats.keys():
			var stat_id := String(key)
			if not out.has(stat_id):
				out.append(stat_id)
	out.sort()
	return out


## An actor with EVERY base attribute at a positive value and a funded founding pool, so a
## derived stat reads non-zero for want of an investment no author intended, and a founding
## can never be refused for want of money.
func _actor(actor_id: StringName) -> Actor:
	var actor := Actor.new(actor_id, {})
	actor.add_resource(ResourcePool.new(InstitutionFounding.DEFAULT_FUNDING_POOL, 9000.0))
	_born.append(actor)
	for attribute in Stat.BASE_ATTRIBUTES:
		actor.stats.set_base(attribute, 10.0)
	return actor
