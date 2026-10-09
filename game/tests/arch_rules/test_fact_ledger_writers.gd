extends TestCase

## The world fact ledger's WRITER SET, as code.
##
## `uv run python -m tools gate_reach check` decides whether an authored gate can
## ever open by comparing the demand against the total every PRODUCER offers - the
## authored `.tres` beats, plus the code-owned ids in `res://src`. That arithmetic is
## only a proof if this file list is the whole producer set, and that is what this
## file holds true.
##
## The chain it pins, one link per test:
##
##   1. `WorldFact.record` is the only verb that writes the ledger - the ONE write
##      `WorldFact`'s own docblock claims and `EventBeatWriter` calls nothing else for.
##   2. Exactly the files below call it, and each takes its fact id either out of a
##      value object a `.tres` authored (`beat["fact"]`, `claim.fact`) or out of a
##      `const` it declares in the same file.
##   3. So there is no third way an id reaches the ledger: no call site invents one,
##      and no id is in the ledger that the content census has not read.
##
## WHY IT HAS TO BE A TEST AND NOT A NOTE. The failure this closes is silent and
## one-directional: a fourth writer naming an id the census cannot resolve would make
## it report a satisfiable gate as dead, and every future author would be told to
## lower a `need` that was fine. A census with no ceiling on its own input is a
## validator that reads as an all-clear, which is the ADR 0066 shape with a checksum.
##
## IT IS NOT VACUOUS, and the proof is that it fired THREE times: `character_creation_flow.gd`
## appeared as a third writer while this file was being written, and a filtered
## `--suite destiny` run cannot see either of the other two because neither file lives
## under `res://src/modules/destiny`. The list is what made each visible instead of
## letting the census under-count it silently, and it fired a third time in the wrong
## direction: the eighth writer (`app/item_workbench_app.gd`) shipped and was NOT
## appended, so the set assertion went RED while every other suite stayed green.
##
## WHAT IT DOES NOT CATCH, stated because overclaiming is worse than the hazard:
##   - An id assembled at run time (`"killed_" + species`). A literal is refused and a
##     same-file `const` is required otherwise, so a computed id shows up as neither -
##     and `code_owned_supply` in `tools/gate_reach.py` will not count it either. The
##     two agree by construction here rather than by enforcement.
##   - A demand that is not a world fact. `DestinyState` counters, sect standing and
##     npc tallies are separate monotonic stores with their own producers; the census
##     says nothing about them, and DEF-0168 already records that a fate naming a
##     counter nothing increments refuses silently.
##   - `res://tests`, deliberately. A test writing the ledger is building its own
##     fixture, not the game's, and half the suites here do it on purpose.

const SRC_ROOT := "res://src"
## The only files allowed to call the ledger's one writer, each with why its id is
## readable by the content census:
##   - `event_beat_writer.gd` reads `beat["fact"]`; a `.tres` authored that beat.
##   - `beat_director.gd` reads `WorldBeat.fact`; a caller authored that claim, and
##     ADR 0114 makes the caller name the occurrence.
##   - `character_creation_flow.gd` declares `const FACT_ID` and writes it directly, so
##     the census reads that one out of GDScript source. It is listed rather than
##     refused for exactly that reason.
##   - `clan_facts.gd` / `combat_facts.gd` / `sect_facts.gd` are ADR 0137's
##     module-owned producers: the owning module records a fact when the action that
##     earns it succeeds. Each declares every id it owns as a same-file `const` named
##     AT the `record` call, which is the shape `code_owned_supply` already resolves.
##     They are KNOWN writers but deliberately NOT in `CODE_OWNED_WRITERS` below: that
##     list's contract is a const spelled exactly `FACT_ID`, and a module owning more
##     than one fact cannot honour it. Their const-to-call wiring is asserted in
##     `tests/modules/{sect,clan,combat}` instead, and the census does not care which of
##     the two spellings a writer uses.
##   - `soul_death.gd` is the seventh: ADR 0130 §Decision records a soul's death as a
##     world fact with a code-owned id, and it owns exactly ONE fact, so the single
##     `const FACT_ID` spelling is available to it and it is a code-owned producer in the
##     strict sense. It is listed in BOTH lists for that reason, which is what the
##     `CODE_OWNED_WRITERS` contract test below checks.
##   - `item_workbench_app.gd` is the eighth, and it is here for a reason the author
##     already wrote down: a completed birth records `child_born` against the CHILD
##     (ADR 0089 keeps statuses out of `Actor.to_dict`, so the child's own save payload is
##     the only place a birth can leave a trace). Its own docstring says the fact grants
##     nothing and that "the counter it moves would be a destination in `destiny`" - which
##     is a statement about what the fact is not attached to, NOT a statement that it is
##     not a producer. Writing it is what makes the fact answerable, which is what
##     `WorldFact` requires of a row: it is KNOWN to exist, and it has no fate reading it
##     yet. Omitting it is exactly the silent under-count this file exists to stop.
##   - `starter_kit.gd` is the ninth: `grant` records `starter_kit_drawn` against the
##     actor once, AFTER the delivery, so a refusal to fill the bag cannot mark the draw
##     as done (BL-0904). It declares the id as a same-file `const FACT := &"starter_kit_drawn"`
##     and passes that name to the call, which is the shape `code_owned_supply` already
##     resolves - `gate_reach report` counts it at `src/app/starter_kit.gd:53 (1, code
##     const)`. Like the three module producers it is KNOWN but NOT in
##     `CODE_OWNED_WRITERS`: that list's contract is a const spelled exactly `FACT_ID`,
##     and this one is spelled `FACT`. It is listed rather than refused for the same
##     reason as the others - it IS a producer, and a name missing from this list is not
##     an oversight to fix by adding a name but a producer the census cannot see.
## ## THE COUNT IS NINE AND THE PROSE IN `core/world_fact.gd` AND
## ## `destiny_projection.gd` HAD SAID SIX. Both were wrong the same way: ADR 0130's
## ## soul-death fact and the birth fact both shipped after the enumeration was written,
## ## and each landed in a `KNOWN_WRITERS` entry without its row being appended above.
## ## `starter_kit.gd` was the third to land that way and the ninth writer, which is what
## ## this assertion caught. The hazard is not a stale number in a docstring - it is that
## ## the TEST and the PROSE were asserting two different producer sets, so a reader who
## ## believed the prose would have believed two shipped producers did not exist. The
## ## enumeration is pinned here and nowhere else on purpose: one list, asserted, is the
## ## only shape that cannot drift.
## A name NOT in this list is not an oversight to fix by adding a name: it is a
## producer the census cannot see until it is taught to read it, in the same change.
const KNOWN_WRITERS: Array[String] = [
	"res://src/app/beat_director.gd",
	"res://src/app/character_creation_flow.gd",
	"res://src/app/item_workbench_app.gd",
	"res://src/app/soul_death.gd",
	"res://src/app/starter_kit.gd",
	"res://src/modules/clan/clan_facts.gd",
	"res://src/modules/combat/combat_facts.gd",
	"res://src/modules/event/event_beat_writer.gd",
	"res://src/modules/sect/sect_facts.gd",
]
## Writers whose id is a same-file `const`, and therefore a producer the census has to
## read out of GDScript rather than out of content. Asserted by test so that moving a
## `const` into another file, or writing the id inline instead, is a deliberate act
## with a failure attached rather than a silent change to the census's model.
const CODE_OWNED_WRITERS: Array[String] = [
	"res://src/app/character_creation_flow.gd", "res://src/app/soul_death.gd"
]
## The call this rule is about. Assembled from fragments so the literal-guard test
## below, which searches for it, cannot match this file's own spelling of it.
const CALL := "World" + "Fact.record"
## A `record` whose id argument is a string literal: `(` then the actor expression,
## then `,` then a quote. The FIRST argument is free and the id is not, which is the
## asymmetry the rule turns on. Both spellings are literals - `&"x"` a StringName,
## `"x"` a String - so both are refused.
const LITERAL_ID := '\\(\\s*[A-Za-z_][A-Za-z0-9_.]*\\s*,\\s*&?"'
## `const NAME := &"value"`, the other legal spelling of a fact id reaching the writer.
## Pinned as a named shape so `code_owned_supply` in `tools/gate_reach.py` has a
## documented pattern to read rather than one nobody wrote down. The two copies can
## still drift - nothing makes Python read this constant - so changing either one is a
## reason to change the other in the same commit.
##
## NOT anchored with `^`. A `^` needs the engine's multiline flag to mean "start of
## line", and that flag is a second thing to get right for no gain: every other
## detector in this directory reads source a LINE AT A TIME with the comment half
## stripped, and `_string_consts` does the same, so an unanchored pattern over one
## code line is already exactly "a line that declares a fact id". `["]` rather than
## `\"` so the pattern does not depend on which quote style the formatter chose.
const STRING_CONST := '\\s*const\\s+([A-Z0-9_]+)\\s*:?=\\s*&["]([a-z0-9_]+)["]'
## The const a writer must actually pass for its id to count as CODE-OWNED.
## `character_creation_flow.gd` also declares `ORIGIN_GROUP := &"origin"`, which is a
## destiny source string and never reaches the ledger, so this file must NOT demand
## that every StringName const in a writer is a fact id. Naming the one that is keeps
## the census's reader narrow: it resolves `FACT_ID` and ignores its neighbours.
const CODE_OWNED_ID_NAME := "FACT_ID"


func test_only_the_known_files_write_the_fact_ledger() -> void:
	var scanned := 0
	var writers: Array[String] = []
	for path in _gdscript_files(SRC_ROOT):
		scanned += 1
		if _call_sites(FileAccess.get_file_as_string(path)).is_empty():
			continue
		writers.append(path)
	writers.sort()
	assert_eq(scanned > 0, true, "the scan still walks res://src")
	assert_eq(
		writers,
		KNOWN_WRITERS.duplicate(),
		(
			(
				"these files call the ledger's one writer: %s. A NEW one is a producer that "
				% str(writers)
			)
			+ (
				"`uv run python -m tools gate_reach check` cannot see, because it reads "
				+ "authored content. Teach the census the new producer in the same change, or "
				+ "the ceiling it computes is wrong and a satisfiable gate will be reported "
				+ "dead."
			)
		)
	)


func test_no_production_call_site_names_a_fact_id_as_a_literal() -> void:
	# The census resolves two spellings and no others: an id read out of a value
	# object, or a `const` the same file declares. A literal written straight into the
	# call is a producer no content file declares and no const names, so nothing can
	# account for it.
	var scanned := 0
	var offences := 0
	for path in _gdscript_files(SRC_ROOT):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains(CALL):
			continue
		scanned += 1
		for entry in _literal_ids(text):
			offences += 1
			assert_eq(
				entry["line"] > 0,
				false,
				(
					(
						"%s:%d hardcodes a fact id into the ledger: %s"
						% [path.replace("res://", ""), entry["line"], entry["text"]]
					)
					+ (
						". Move the id into authored content, or declare it as a `const` "
						+ "this file names and list the file in CODE_OWNED_WRITERS."
					)
				)
			)
	assert_eq(scanned > 0, true, "at least one file still calls the writer")
	assert_eq(offences, 0, "every writer takes its fact id from a value object or a const")


func test_every_code_owned_writer_declares_its_id_where_the_census_reads_it() -> void:
	# The census learns a code-owned fact by reading `const NAME := &"id"` out of the
	# same file that calls the writer. Both halves are asserted: the writer is listed
	# as code-owned, and its const exists in the shape the census's reader expects.
	# Without the second half the list is a claim with nothing under it.
	var pattern := RegEx.new()
	var compiled := pattern.compile(STRING_CONST)
	assert_eq(compiled, OK, "the fact-id const pattern compiles")
	for path in CODE_OWNED_WRITERS:
		assert_eq(
			KNOWN_WRITERS.has(path), true, "%s is code-owned, so it is also a known writer" % path
		)
		var text := FileAccess.get_file_as_string(path)
		var fact_ids: Array[String] = []
		for entry_const in _string_consts(text, pattern):
			if String(entry_const["name"]) == CODE_OWNED_ID_NAME:
				fact_ids.append(String(entry_const["value"]))
		assert_eq(
			fact_ids.size() > 0,
			true,
			(
				("%s is listed as a code-owned producer but declares no " % path)
				+ (
					'`const %s := &"fact_id"`, so `gate_reach` cannot read its fact id out of '
					% CODE_OWNED_ID_NAME
				)
				+ "the source."
			)
		)
		# And the const has to REACH the writer, or it is decoration: a fact id nothing
		# passes to `record` supplies nothing. Named so a failure says which call is
		# ignoring it rather than only that somewhere one is.
		var passed := false
		for call in _call_sites(text):
			if _id_argument(call["text"]) == CODE_OWNED_ID_NAME:
				passed = true
		assert_eq(
			passed,
			true,
			(
				(
					"%s declares `const %s` but never passes it to %s, so it is not a "
					% [path, CODE_OWNED_ID_NAME, CALL]
				)
				+ "code-owned producer and should not be in CODE_OWNED_WRITERS."
			)
		)


func test_the_two_detectors_still_fire() -> void:
	# A guard that has stopped matching is a guard that reads as an all-clear, so every
	# detector is exercised on strings rather than on the tree. Prose naming the rule
	# must not match either, or this file would fail the rule it states.
	var via_object: String = "var written := %s(actor, claim.fact, claim.amount)\n" % CALL
	assert_eq(_call_sites(via_object).size(), 1, "a real call is found")
	assert_eq(
		_call_sites("## %s is the one write path.\nvar x := 1\n" % CALL).size(),
		0,
		"a comment naming the call is not a call"
	)
	assert_eq(_literal_ids(via_object).size(), 0, "an id read off a value object is not a literal")
	var named_string_name: String = '\tvar w := %s(actor, &"beast_tamed")\n' % CALL
	assert_eq(_literal_ids(named_string_name).size(), 1, "a hardcoded StringName is found")
	var named_string: String = '\tvar w := %s(actor, "killed_boar")\n' % CALL
	assert_eq(_literal_ids(named_string).size(), 1, "a plain String id is found too")
	var free_actor: String = "\tvar w := %s(self.actor, beat.fact)\n" % CALL
	assert_eq(_literal_ids(free_actor).size(), 0, "the actor argument is not constrained")
	# The const spelling is a literal in the file but NOT at the call site, which is
	# the whole distinction: the census can resolve the former and not the latter.
	var via_const: String = (
		'const FACT_ID := &"character_created"\nvar w := %s(actor, FACT_ID, 1)\n' % CALL
	)
	assert_eq(_literal_ids(via_const).size(), 0, "a named const at the call site is legal")
	assert_eq(_id_argument("record(actor, FACT_ID, 1)"), "FACT_ID", "and it resolves to it")


func test_the_known_writer_set_is_inside_the_scan() -> void:
	# `KNOWN_WRITERS` is a claim about paths; this turns the claim into a check that
	# those paths exist and are scanned. Without it a rename would leave the writer-set
	# assertion failing for the wrong reason - or, worse, vacuously passing.
	var scanned := _gdscript_files(SRC_ROOT)
	for path in KNOWN_WRITERS:
		assert_eq(scanned.has(path), true, "%s is inside the scan" % path)


## Every real call, as `{"line": int, "text": String}`.
##
## A comment is not a call: the code half of a line is what is read, so this file's own
## docblock - and every other file that discusses the rule in prose - survives it.
func _call_sites(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lines := text.split("\n")
	for index in lines.size():
		var code: String = lines[index].split("#")[0]
		if code.contains(CALL) and code.contains("("):
			out.append({"line": index + 1, "text": code.strip_edges()})
	return out


## Every call whose id argument is a string literal.
func _literal_ids(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pattern := RegEx.new()
	pattern.compile(LITERAL_ID)
	var lines := text.split("\n")
	for index in lines.size():
		var code: String = lines[index].split("#")[0]
		if not code.contains(CALL):
			continue
		if pattern.search(code) != null:
			out.append({"line": index + 1, "text": code.strip_edges()})
	return out


## The id argument of one call, as written: `claim.fact`, `FACT_ID`, `&"x"`.
##
## The SECOND comma-separated field after the open paren, because the first is the
## actor and the rule turns on the second. Used to prove a declared const is the one
## actually reaching the writer rather than merely declared nearby.
func _id_argument(call_text: String) -> String:
	var open := call_text.find("(")
	if open < 0:
		return ""
	var fields := call_text.substr(open + 1).split(",")
	if fields.size() < 2:
		return ""
	return fields[1].strip_edges()


## Every `const NAME := &"value"` a file declares, as `{"name": String, "value": String}`.
##
## One code line at a time with the comment half stripped, so prose about a const is not
## a const and an indented mention inside a docblock is not one either.
func _string_consts(text: String, pattern: RegEx) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lines := text.split("\n")
	for index in lines.size():
		var code: String = lines[index].split("#")[0]
		var found := pattern.search(code)
		if found == null:
			continue
		# `const` has to OPEN the line: an unanchored pattern would happily read
		# `var x := notconst y` or a dictionary entry as a const declaration.
		if not code.strip_edges().begins_with("const"):
			continue
		out.append({"name": found.get_string(1), "value": found.get_string(2)})
	return out


## Every `.gd` under `root`, recursively.
##
## A `while` over `DirAccess` is the one shape `test_no_unbounded_wait.gd` accepts as
## terminating, and a `for` over the collected list is used everywhere else, so this is
## the same walk every other rule in this directory performs.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
