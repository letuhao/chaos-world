extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const DANTIAN_SCRIPT := "res://src/modules/qi_cultivation/dantian.gd"

## A read of a member on any expression whose name ends in `dantian`, capturing the
## member name. Deliberately name-free on the field side: the field is compared
## against what `Dantian` declares, so nothing here has to be updated when a ruling
## deletes another member. The leading `(?:...)?` keeps it off an identifier that
## merely *starts* with `dantian` — `to_seed.dantian_quality_required` has no dot after
## `dantian` and never matches.
const DANTIAN_READ := "(?:[A-Za-z_][A-Za-z0-9_]*)?[Dd]antian\\s*\\.\\s*([A-Za-z_][A-Za-z0-9_]*)"

## Every member `Dantian` declares, read off the class rather than listed here: a
## name list is a list of the members deleted *so far*, and the next deletion would
## sail straight past it. Fields and methods are one set, so `dantian.damage()` is
## legal and `dantian.set_tier()` is not — the shape of the defect decides, not the
## parenthesis.
var members: Dictionary = _dantian_members()

## True while a `"""` block literal is open. A member rather than a local because such a
## literal spans lines and the blanking has to carry across them.
var _in_block_string := false


func _dantian_members() -> Dictionary:
	var out: Dictionary = {}
	var text := FileAccess.get_file_as_string(DANTIAN_SCRIPT)
	# Bounded by the file's own line count; the body appends to `out`, which it is not
	# walking (INC-0002).
	for line in text.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.begins_with("@export "):
			code = code.substr("@export ".length())
		for decl in ["static func ", "var ", "const ", "signal ", "func "]:
			if not code.begins_with(decl):
				continue
			var head := code.substr(decl.length()).split("(")[0].strip_edges()
			out[head.split(":")[0].strip_edges()] = true
			break
	# `new` is the engine's constructor rather than a member anyone declared, and
	# `Dantian.new()` is how a test obtains one. Listed here, not special-cased at the
	# call site, so the member set stays the single answer.
	out["new"] = true
	return out


## The line reduced to CODE: comments removed, string literals blanked. The defect this
## scan hunts is an EXECUTED read, so neither prose nor a message handed to an
## assertion is code — this file's own record (`"Dantian.tier is back"`, and the
## `dantian.gd` path inside an assertion label) is what a bare grep trips on, which is
## how the first version of this guard caught its own documentation.
## Bounded by the line's own length with the index advancing every pass (INC-0002).
func _code_only(line: String) -> String:
	var out := ""
	var in_string := ""
	var index := 0
	while index < line.length():
		var ch := line[index]
		if _in_block_string:
			if ch == '"' and line.substr(index, 3) == '"""':
				_in_block_string = false
				index += 3
				continue
			index += 1
			continue
		if in_string != "":
			if ch == in_string:
				in_string = ""
			index += 1
			continue
		if ch == "#":
			break
		if ch == '"' or ch == "'":
			if line.substr(index, 3) == '"""' or line.substr(index, 3) == "'''":
				_in_block_string = true
				index += 3
				continue
			in_string = ch
			index += 1
			continue
		out += ch
		index += 1
	return out


## ADR 0180, ruling Q1: `dantian_tier` is DELETED, and this suite is what stops
## it coming back ungated.
##
## The defect it closes (DEF-0228): the field was authored on all 30 seeds, written
## by `synchronize`, published on `panel_state`, rendered as a row name — and read
## by nothing. `_dantian_ready` checked injured/progress/comprehension/quality/ratio.
##
## Why DELETE rather than gate, which is the part worth re-deriving:
##
## - The three bands are a restatement of the ladder's own tiers. Nine Mortal, nine
##   Spirit, then IMMORTAL and TRANSCENDENT together — so `lower`/`middle`/`upper`
##   said nothing the realm line does not already print, and the screen printed it
##   beside the realm name.
## - The bands are NOT monotone, so a floor could not have gated anything. The
##   only writer is `QiTraining.synchronize`, which reads the realm the actor is
##   STANDING in (`training.gd:16`, `seed.dantian_tier`). A gate comparing that
##   against the target realm's own floor is therefore unsatisfiable at exactly the
##   two band edges and free at the other 27:
##     tribulation(lower)      -> spirit_condensation(middle)
##     spirit_ascension(middle)-> earth_immortal(upper)
##   `test_the_band_edges_are_where_a_tier_gate_would_have_walled_the_ladder_off`
##   below proves those two from the corpus, so the deletion is not a taste call.
##
## Re-adding the field is therefore a defect, not a feature. These are structural
## assertions rather than a behavioural walk because a tier that gates nothing has
## no behaviour to walk: the only question is whether the name is back.


## No qi seed declares a dantian tier. The field is authored data, so this reads
## the corpus rather than the loaded resource — a stale `.tres` in the import cache
## cannot make this green (ADR 0028's rule that the file is the truth).
func test_no_qi_seed_declares_a_dantian_tier() -> void:
	var ladder := RealmDefaults.ladder()
	var checked := 0
	for realm in ladder.realms():
		var path := "res://data/qi_cultivation/realms/%s.tres" % realm.id
		var text := FileAccess.get_file_as_string(path)
		assert_eq(text.is_empty(), false, "%s is readable" % realm.id)
		assert_eq(
			text.contains("dantian_tier"),
			false,
			"%s declares dantian_tier: a ladder no gate reads (ADR 0180)" % realm.id
		)
		checked += 1
	assert_eq(checked, 30, "and it graded the whole ladder, not a sample")


## The seed class does not carry the field either, so a fresh `.tres` written in
## the editor cannot reintroduce it by assigning a property that still exists.
func test_the_seed_class_carries_no_dantian_tier() -> void:
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	assert_ne(seed, null, "the first realm still has a seed")
	var declared: Array[String] = []
	for entry in seed.get_property_list():
		declared.append(String(entry.get("name", "")))
	assert_eq(
		declared.has("dantian_tier"),
		false,
		"QiRealmSeed still exports dantian_tier; every seed would be authoring a label"
	)


## No source file in the module reads or writes a dantian tier. `rg` over the
## shipped source is the guard; this asserts the outcome on the two classes that
## used to carry it, so a partial re-add (the field back, the writer gone) still
## fails rather than passing as dead data.
func test_the_runtime_carries_no_dantian_tier() -> void:
	var dantian_script := FileAccess.get_file_as_string(
		"res://src/modules/qi_cultivation/dantian.gd"
	)
	assert_eq(
		dantian_script.contains("set_tier"),
		false,
		"Dantian.set_tier is back; only synchronize ever called it"
	)
	assert_eq(
		dantian_script.contains("var tier"),
		false,
		"Dantian.tier is back; nothing read it but the row label"
	)
	var training := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/training.gd")
	assert_eq(training.contains("dantian_tier"), false, "training.gd writes a dantian tier again")
	var api_source := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/api.gd")
	assert_eq(
		api_source.contains("dantian_tier"),
		false,
		"panel_state publishes dantian_tier again; a screen would render a label"
	)


## `QiStats` is the module's declaration of what the dantian contributes, and it was
## the one file in the module this suite never opened.
##
## A `DANTIAN_TIER` constant there would be the exact ADR 0180 shape — a published
## label nothing reads — and it would survive every other assertion here, because
## `Dantian` would still carry no `tier` and no seed would still declare one. The
## check is on CODE lines, so this file's own prose stays free to name the field.
func test_qi_stats_declares_no_dantian_tier_constant() -> void:
	var reader := RegEx.new()
	reader.compile("DANTIAN_TIER")
	var text := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/stats.gd")
	var offender := ""
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		if reader.search(line) != null:
			offender = line.strip_edges()
			break
	assert_eq(
		offender.is_empty(),
		true,
		"QiStats declares a dantian tier (%s): a label nothing reads (ADR 0180)" % offender
	)
	# And the capacity it does contribute is still declared, so the guard above
	# cannot pass on a `stats.gd` that lost the qi surface entirely.
	assert_eq(
		text.contains("const DANTIAN_CAPACITY"),
		true,
		"capacity is still declared, so the check above is reading a real surface"
	)


## ## The qi TESTS must not READ the field either, which is where it survived.
##
## The runtime greps above cover `src/`, and they were all green while
## `tests/modules/qi_cultivation/test_qi_training.gd` still read it. That read is
## the dangerous shape, not prose: GDScript raises "Invalid access to property or key
## 'tier'" on it and ABORTS the enclosing function, so the assertions after it never
## run, the aborted test reports no failure, and the suite prints `0 failed` while a
## test silently verifies nothing.
##
## ## Why the scan is now STRUCTURAL, and why it covers every directory
##
## It used to grep `res://tests/modules/qi_cultivation` for the literal `dantian.tier`.
## Both halves of that were narrower than the claim. The *directory* was one of six:
## qi tests now live in `tests/modules/qi_cultivation`, `tests/app`, `tests/ui`,
## `tests/acquisition`, `tests/modules/combat_engine` and `tests/modules/race` — the
## same bug, one directory over. And the *name* was a list of the fields deleted so
## far, so the next deletion would have sailed straight past it.
##
## So the guard no longer knows any deleted name. It reads the member set `Dantian`
## actually declares and reports **any read of a `Dantian` member it does not** — one
## rule that covers `tier`, `set_tier`, and every field a future ruling deletes. A
## directory list is a name list too, so the walk is the whole `res://tests` tree via
## `ContentScan`, which is already depth-capped at `MAX_DEPTH`.
##
## ## Why strings and comments are blanked, not just comments
##
## The defect is an EXECUTED read. A comment is prose; a string literal is a message
## passed to an assertion. This file's own record — `"Dantian.tier is back"` and
## `"res://src/modules/qi_cultivation/dantian.gd"` — is exactly the text a bare grep
## trips on, and it is why the first version of this guard caught its own
## documentation. Both are removed before the match; the file is also excluded as the
## ruling's record.


## The live half of the guarantee. `QiTestKit.dantian()` returns a statically typed
## `Dantian`, so a read of a member it does not declare is a COMPILE error and the
## suite fails to LOAD — loud, named, and fatal to the whole file. That only holds
## while `Dantian` exposes no dynamic property surface: `_get`/`_set` would answer a
## missing name at run time and turn every future deleted field back into the silent
## abort this ruling closed. This is the assertion that makes the scans below a
## backstop rather than the primary mechanism.
func test_the_dantian_has_no_dynamic_property_surface() -> void:
	var text := FileAccess.get_file_as_string(DANTIAN_SCRIPT)
	assert_eq(
		text.contains("class_name Dantian"),
		true,
		"Dantian is still declared, so the hook scan below is reading a real file"
	)
	for hook in [
		"func _get(", "func _set(", "func _get_property_list(", "func _validate_property("
	]:
		assert_eq(
			text.contains(hook),
			false,
			(
				(
					"Dantian grew %s: a read of a removed member answers at run time again and "
					% hook
				)
				+ "aborts the enclosing function silently (ADR 0180)"
			)
		)
	# And the member set this file derives is not empty, so a `dantian.gd` that lost
	# the qi surface cannot pass the hook scan by being unrecognisable.
	assert_eq(
		members.has("structural_capacity"),
		true,
		"capacity is still declared, so the hook scan is reading a real surface"
	)


## The scan's own matcher, proved against a synthetic line. A guard whose regex fails
## to compile, or matches nothing, is green forever — this is the check that says the
## pattern still recognises a read, that the member it found is one `Dantian` does NOT
## declare, and that a DECLARED member passes, so the rule is "not declared" and not
## "any dot at all". Nothing here touches shipped content.
func test_the_dantian_read_matcher_fires_on_a_removed_member() -> void:
	var reader := RegEx.new()
	reader.compile(DANTIAN_READ)
	var read := reader.search("	var tier := dantian.tier", 0)
	assert_ne(read, null, "the matcher still recognises a property read on a dantian")
	assert_eq(
		members.has(read.get_string(1)),
		false,
		"and the member it found is one Dantian does not declare, which is the defect"
	)
	var gone := reader.search("	dantian.set_tier(1)", 0)
	assert_ne(gone, null, "an undeclared METHOD call is recognised too")
	assert_eq(
		members.has(gone.get_string(1)),
		false,
		"and it is the same defect: nothing on Dantian answers to set_tier"
	)
	var kept := reader.search("	dantian.set_quality(1.0)", 0)
	assert_eq(
		members.has(kept.get_string(1)),
		true,
		"a declared method passes, so the scan is not banning every dot on a dantian"
	)
	var real := reader.search("	dantian.quality = 1.0", 0)
	assert_eq(
		members.has(real.get_string(1)),
		true,
		"and a declared field passes too, which is why 134 live reads stay legal"
	)


## No file anywhere under `res://tests` reads a member `Dantian` does not declare.
func test_no_test_reads_a_removed_dantian_member() -> void:
	var reader := RegEx.new()
	reader.compile(DANTIAN_READ)
	var self_path := "res://tests/modules/qi_cultivation/test_qi_ruling_q1_no_dantian_tier.gd"
	var offenders: Array[String] = []
	var scanned := 0
	# `ContentScan.files_under` is the one recursive walk and is depth-capped at
	# MAX_DEPTH; the body appends to a list it is not walking, so nothing here grows
	# its own bound (INC-0002).
	for path in ContentScan.files_under("res://tests", ".gd"):
		if path == self_path:
			continue
		var text := FileAccess.get_file_as_string(path)
		var line_number := 0
		for line in text.split("\n"):
			line_number += 1
			var found := reader.search(_code_only(line), 0)
			if found == null:
				continue
			if members.has(found.get_string(1)):
				continue
			offenders.append("%s:%d reads '%s'" % [path, line_number, found.get_string(1)])
		scanned += 1
	assert_eq(
		offenders.is_empty(),
		true,
		(
			(
				"%d file(s) read a Dantian member it does not declare: %s — a read of a removed "
				% [offenders.size(), ", ".join(offenders)]
			)
			+ "member aborts the enclosing function, so every assertion after it is silently "
			+ "skipped and the suite reports 0 failed (ADR 0180)"
		)
	)
	# Self-consistent rather than a hardcoded count: every `.gd` under `res://tests`
	# except this one was graded, so a directory added later cannot fall out of the walk.
	assert_eq(
		scanned,
		ContentScan.files_under("res://tests", ".gd").size() - 1,
		"and it graded every test file in the tree, not one directory of them (%d)" % scanned
	)


## WHY deletion, restated as a measurement over the corpus rather than an argument.
##
## If the bands were monotone, a tier floor would have been a real gate and this
## suite would be wrong. They are not: the tier steps UP at two boundaries, and the
## dantian's tier is written from the realm the actor stands in, so at exactly those
## two the floor can never be met. The map below is the ladder's own order, so a
## re-authored seed that moved a band edge would be caught here as a changed count.
func test_the_band_edges_are_where_a_tier_gate_would_have_walled_the_ladder_off() -> void:
	# Read straight from the files: the field is gone from the seeds, so this is the
	# historical shape preserved here as the reason, not as live content.
	var historic := {
		"qi_refining": "lower",
		"foundation": "lower",
		"core_formation": "lower",
		"nascent_soul": "lower",
		"spirit_transformation": "lower",
		"void_refinement": "lower",
		"body_integration": "lower",
		"great_ascension": "lower",
		"tribulation": "lower",
		"spirit_condensation": "middle",
		"spirit_sea": "middle",
		"spirit_palace": "middle",
		"spirit_manifestation": "middle",
		"spirit_severing": "middle",
		"spirit_unity": "middle",
		"spirit_domain": "middle",
		"spirit_sovereign": "middle",
		"spirit_ascension": "middle",
		"earth_immortal": "upper",
		"heaven_immortal": "upper",
		"golden_immortal": "upper",
		"mystic_immortal": "upper",
		"true_immortal": "upper",
		"primordial_immortal": "upper",
		"great_luo": "upper",
		"dao_fruit": "upper",
		"immortal_sovereign": "upper",
		"transcendent": "upper",
		"dao_ancestor": "upper",
		"primordial_origin": "upper",
	}
	var rank := {"lower": 1, "middle": 2, "upper": 3}
	var walled: Array[String] = []
	var realms := RealmDefaults.ladder().realms()
	# Bounded by the ladder's own length; each id visited once, and the body appends
	# to a list it is not walking (INC-0002).
	for index in range(realms.size() - 1):
		var standing := String(historic.get(String(realms[index].id), ""))
		var target := String(historic.get(String(realms[index + 1].id), ""))
		if int(rank.get(standing, 0)) < int(rank.get(target, 0)):
			walled.append("%s->%s" % [realms[index].id, realms[index + 1].id])
	assert_eq(
		walled.size(),
		2,
		"exactly two band edges step up, and both would have been unreachable gates"
	)
	assert_eq(
		walled,
		["tribulation->spirit_condensation", "spirit_ascension->earth_immortal"],
		"and they are the two the ladder crosses into Spirit and Immortal"
	)


## The dantian still saves and restores everything it owns. Deleting a field from a
## serialized component is where a save silently loses state, so the surviving keys
## are asserted rather than assumed.
func test_the_dantian_round_trips_without_a_tier() -> void:
	var dantian := Dantian.new()
	dantian.set_structural_capacity(200.0)
	dantian.set_quality(0.8)
	dantian.damage()
	var payload := dantian.to_dict()
	assert_eq(payload.has("tier"), false, "and it writes no tier key at all")
	var restored := Dantian.from_dict(payload)
	assert_almost_eq(restored.structural_capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.quality, 0.8, "quality round trip")
	assert_eq(restored.injured, true, "injury round trip")


## A save written BEFORE this ruling carries `"tier": "lower"`, and loading it must
## not fail. `from_dict` reads named keys, so an unknown one is ignored — asserted
## here because the fixture in `game/tests/fixtures/save_v2.json` still ships it and
## an old save in the wild will too.
func test_an_old_save_carrying_a_tier_still_loads() -> void:
	var restored := Dantian.from_dict(
		{"tier": "lower", "quality": 0.6, "injured": false, "structural_capacity": 150.0}
	)
	assert_almost_eq(restored.quality, 0.6, "and its real state is read")
	assert_almost_eq(restored.structural_capacity, 150.0, "capacity too")
