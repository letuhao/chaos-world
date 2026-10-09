extends TestCase

## ADR 0083's edge `tools/arch` cannot see, held as an assertion.
##
## `BARE_REF_UNITS` is `{ui, app, contracts}` — `modules/*` is deliberately excluded
## from the bare-reference resolver, because a scan over `core/` and the modules is a
## wall of false positives. The cost of that exclusion is stated in `rules.py`: a bare
## class reference out of `modules/*` is "not a load-bearing edge the gate sees".
##
## So the whole point of `ClanApi`'s `SOCIAL_FACADE` preload is that it is the single
## `res://` reference the resolver DOES read, which makes `clan -> social` a declared,
## cycle-checked edge. The moment somebody writes `SocialApi.apply_cause(...)` instead,
## the edge becomes invisible, the cycle check cannot see a future `social -> clan`, and
## a violation reports zero findings.
##
## `sect` pays for the same guard with `test_sect_social_edge.gd`. This is the clan
## copy, and it also pins the registry declaration, because a `preload` pointing at a
## module that is not registered is an undeclared dependency the gate fails on for a
## reason that has nothing to do with cycles.

const MODULE_ROOT := "res://src/modules/clan"
const FACADE := "res://src/modules/clan/api.gd"
## Matches a social class name — `SocialApi`, `SocialState`, `SocialBond`, `SocialGate`.
const SOCIAL_CLASS := "\\bSocial[A-Z]\\w*"
const SOCIAL_REF := "res://src/modules/social/"
## The single path the preload is allowed to name, spelled here rather than inlined at
## the assertion so the expected value and the constant under test cannot drift apart.
const SOCIAL_FACADE_PATH := "res://src/modules/social/api.gd"
## Every `src/modules` path, which is what "a module edge" means: a reference into a
## sibling module's source tree. `res://data/...` is authored CONTENT and is not one.
const MODULE_REF := "res://src/modules/"
## `enforce.RES_RE`'s pattern, copied because the point of the test is to hold the SAME
## shape the resolver reads rather than some stricter or looser one of our own.
const RES_PATTERN := "res://[^\"'\\s)]+"


## ## Every file in the module, named rather than globbed
##
## The point of the list is that it is reviewable: a file added to `modules/clan/`
## without a case here is a visible omission rather than an untested one.
func _module_files() -> Array[String]:
	return [
		"api.gd",
		"clan_catalog.gd",
		"clan_def.gd",
		"clan_facts.gd",
		"clan_gate.gd",
		"clan_heir.gd",
		"clan_projection.gd",
		"clan_state.gd",
		"clan_summary.gd",
		"provider.gd",
		"stats.gd",
	]


func _source(rel: String) -> String:
	## Typed rather than inferred: `FileAccess.get_file_as_string` is declared `String`,
	## but the compiler widens the call to Variant, and an untyped inference is an error
	## in this project. A text file cannot name a social class by accident, so the type
	## is stated rather than left to the inference.
	var text: String = FileAccess.get_file_as_string(rel)
	assert_ne(text, "", "readable: %s" % rel)
	return text


## ## The assertion the whole file exists for
##
## **ZERO hits, including in the facade itself.** `clan` does not name a social class
## anywhere — it reaches the module by preloading `social/api.gd` and calling
## `SOCIAL_FACADE.apply_cause(...)`, which is exactly what the `sect` and `nation`
## facades do. A single bare `SocialApi.`, `SocialState.` or `SocialBond.` would be an
## edge `_find_cycle` cannot see, so the assertion is "none", not "none but the facade".
##
## Comments and string literals are stripped first, because the docstrings in this
## module name the classes constantly and prose is not a dependency — the same
## `_code_only` the resolver itself uses in `enforce.py`.
func test_no_file_in_the_module_names_a_social_class_at_all() -> void:
	var pattern := RegEx.new()
	pattern.compile(SOCIAL_CLASS)
	var offenders: Array[String] = []
	for file_name in _module_files():
		var rel := "%s/%s" % [MODULE_ROOT, file_name]
		var body := _code_only(_source(rel))
		for match in pattern.search_all(body):
			var line := body.substr(0, match.get_start()).count("\n") + 1
			offenders.append("%s:%d names '%s'" % [file_name, line, match.get_string()])
	assert_eq(offenders, [], "clan may reach social only through api.gd, and never by class name")


## ## The one edge, and it is a `res://` reference
##
## **Exactly one SOCIAL reference.** The point of this file is the `clan -> social`
## edge, so the load-bearing half is that the facade holds ONE reference into `social/`
## and names `api.gd` with it. Whether that is also the facade's only `res://` of any
## kind is a claim about `api.gd` rather than about this edge, and the file no longer
## makes it.
func test_the_facade_reaches_social_through_a_single_named_reference() -> void:
	var social_refs: Array[String] = _refs_in(FACADE, SOCIAL_REF)
	assert_eq(social_refs, [SOCIAL_FACADE_PATH], "and it is social's api.gd, reached once")
	# Counted over SOCIAL references, not over every `res://` in the facade. The
	# previous form counted all paths and asserted `1`, which silently asserted that
	# the facade mentions nothing else at all — a claim about the file, not about this
	# edge, and it broke the moment a second line documented the same preload.
	assert_eq(social_refs.size(), 1, "and the facade holds one reference into social")


## The other ten files hold no `res://` INTO A MODULE at all, so there is no second
## module edge hiding in one of them. `ClanGate` reaches `bloodline` and `race` by bare
## class name, which is the documented `BARE_REF_UNITS` limitation — those two edges are
## held by the registry, not by a scan.
##
## Scoped to module paths rather than to every `res://` because `clan_catalog.gd` reads
## the authored content tree: `CLANS_ROOT` is `res://data/packs/clan/organizations`, spelled
## inside a
## backtick in the docstring above it and therefore matched by `RES_PATTERN` twice. That
## is a CONTENT path, not a dependency edge, and a scan that counted it was measuring the
## docstring rather than the graph.
func test_no_file_outside_the_facade_reaches_any_module_by_path() -> void:
	var offenders: Array[String] = []
	for file_name in _module_files():
		if file_name == "api.gd":
			continue
		var rel := "%s/%s" % [MODULE_ROOT, file_name]
		for ref in _refs_in(rel, MODULE_REF):
			offenders.append("%s -> %s" % [file_name, ref])
	assert_eq(offenders, [], "no second module edge hides outside the facade")


## ## The registration itself is asserted by `tools arch`, not from here
##
## ## What went wrong
##
## This file used to read `modules["clan"]["deps"]` out of `tools/arch/registry.json`
## and assert it contains `social`. It does — the moment the `preload` at the top of
## `api.gd` exists — but **a test cannot make it true.** The registry is a gate INPUT,
## not a test fixture: an agent ran this suite, saw the assertion fail, added `"social"`
## to the registry file, and that edit was never committed. The next agent then found a
## registry that declared the edge, a green suite, and no record that the declaration had
## ever been reviewed. This file must not be able to make that happen, so it no longer
## reads the registry — `uv run python -m tools arch` is where an undeclared or cyclic
## edge is reported, against the actual `res://` graph rather than one suite's reading
## of it, and `registry.json` is not a file a test gets to edit.
##
## ## What is still asserted here, and it is the half a test CAN own
##
## Nothing in this module names a social class, and the one path into `social/` is
## `api.gd` — both above. The half that remains is the other end: that `social` holds no
## path back into `clan`, which is what makes the one-way edge legal. Scanned from
## SOURCE rather than from the registry, on purpose: a declaration can be stale, code
## cannot.
func test_nothing_in_social_reaches_back_to_clan() -> void:
	var social_root := "res://src/modules/social"
	var offenders: Array[String] = []
	for file_name in DirAccess.get_files_at(social_root):
		if not file_name.ends_with(".gd"):
			continue
		var rel := "%s/%s" % [social_root, file_name]
		if not FileAccess.file_exists(rel):
			continue
		for ref in _refs_in(rel, "res://src/modules/clan"):
			offenders.append("%s -> %s" % [file_name, ref])
	assert_eq(offenders, [], "nothing in social reaches back to clan, so the edge cannot close")


## Every `res://` reference in `rel` that begins with `prefix`, in order of appearance.
##
## Scanned on RAW text rather than the stripped kind, because the reference lives inside
## a string literal — stripping literals is what makes the class-name scan above
## meaningful, and it would erase these. `prefix` of `""` therefore means "all of them",
## which is why the only caller that asks for every reference reads the raw file too.
func _refs_in(rel: String, prefix: String) -> Array[String]:
	var refs := RegEx.new()
	refs.compile(RES_PATTERN)
	var found: Array[String] = []
	for match in refs.search_all(_source(rel)):
		var ref: String = match.get_string()
		if prefix == "" or ref.begins_with(prefix):
			found.append(ref)
	return found


## ## The one place the multiplier's inputs are read
##
## `ClanGate` is documented as the only place `clan` reads the two modules beneath it,
## and the hinge added a second read of the founding line's purity to that same class.
## Asserted against the CODE (comments stripped), because both `clan_gate.gd` and
## `api.gd` name `BloodlineApi` in their prose, and prose is not a call.
##
## Deliberately narrow: `api.gd` also calls `BloodlineApi.purity_of` for the screen
## readout, so "only one file reads it" was never true and is not claimed. What IS
## claimed is that the MULTIPLIER reads the definition's own `founding_bloodline`, so a
## house with no founding line takes the floor branch rather than scaling by nothing.
func test_the_multiplier_reads_the_founding_line_in_the_gate() -> void:
	var gate := _code_only(_source("%s/clan_gate.gd" % MODULE_ROOT))
	assert_eq(
		gate.contains("BloodlineApi.purity_of(actor, def.founding_bloodline)"),
		true,
		"the hinge reads the founding line where the gate already reads it"
	)
	assert_eq(
		gate.contains("static func recognition_scale"),
		true,
		"and the factor is one named function rather than inlined at a call site"
	)


func _code_only(text: String) -> String:
	## Built from a default-constructed RegEx and an explicit `compile`, rather than
	## `RegEx.new(pattern)`. This build's parser widens an un-annotated `new()` call whose
	## argument is a plain string literal to Variant; the constructor then reports a
	## zero-argument signature and the file will not load. That is how this file failed
	## twice — once on this expression written with single quotes, once on a
	## double-quoted escape — and the escape below is therefore spelled `\\"`, identical
	## to `\"` once the literal is parsed, so there is no widening left to key on.
	var literals := RegEx.new()
	literals.compile('"[^"\n]*"')
	var replacement := ""
	var kept: Array[String] = []
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(literals.sub(line, replacement))
	return "\n".join(kept)
