extends TestCase

## **No owner may ask the relation graph a question** (BL-0199).
##
## This is the arch-level proof, and it exists because `tools arch` cannot see this
## edge. `BARE_REF_UNITS` (`tools/arch/rules.py`) is `{"ui", "app", "contracts"}` —
## it excludes `modules/*` — so a bare `RelationsApi` reference written inside
## `modules/sect/` reports ZERO violations, and `_find_cycle` is fed by
## `registry.json` alone, so a code-only cycle is invisible to it. That is the same
## limitation ADR 0083 documents for `nation -> sect`, and the same shape of answer:
## a structural test that reads the source.
##
## ## What would fail if somebody wrote the back edge
##
## The dependency has to be one-way. Owners WRITE their own stance; the graph READS
## it. The moment an owner reads back, `sect -> relations -> sect` is a cycle, the
## module graph stops being a DAG, and the program's rule "one module = one reason to
## change" has been broken by a convenience read that the owner could have had from
## its own ledger.
##
## The scan is over EVERY `.gd` under the three owner modules, never a chosen list,
## so a new file cannot opt out by not being on it — and the comment strip means a
## module that DOCUMENTS the rule is not reported for obeying it in prose.

## The owner modules the rule governs. A module is not named because it is a
## relation holder; it is named because it is an owner whose stance this graph reads.
const OWNER_ROOTS: Array[String] = [
	"res://src/modules/world",
	"res://src/modules/sect",
	"res://src/modules/nation",
]

## Any mention of the facade's own name is a back edge. A bare class name is the
## shape the resolver would miss, so it is the shape the scan looks for first.
const BACK_EDGE_NAMES: Array[String] = ["RelationsApi", "RelationGraph", "RelationKey"]

## Any `relations` symbol at all: the module path, the namespace, a load of the
## facade, a `relations` local, a `relations` key. A back edge written any other way
## than by class name still comes through one of these.
const BACK_EDGE_TOKENS: Array[String] = ["relations", "res://src/modules/relations"]


## The headline case. Every `.gd` under every owner module, read as CODE, and any hit
## on any back-edge name is an offender. The offender list is printed rather than
## merely counted, because a scan that fails should name the file it found.
func test_no_owner_module_names_this_module_or_any_relations_symbol() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for root in OWNER_ROOTS:
		for path in _module_files(root):
			scanned += 1
			var code := _strip_comments(FileAccess.get_file_as_string(path))
			for line in code.split("\n"):
				var stripped := line.strip_edges()
				if stripped == "":
					continue
				for name in BACK_EDGE_NAMES:
					if _names_a_token(stripped, name):
						offenders.append("%s: %s" % [path.get_file(), stripped])
						break
				if not offenders.is_empty() and offenders[-1].ends_with(stripped):
					continue
				for token in BACK_EDGE_TOKENS:
					if _names_a_token(stripped, token):
						offenders.append("%s: %s" % [path.get_file(), stripped])
						break
	assert_eq(
		offenders.is_empty(),
		true,
		(
			(
				"an owner must never ask the relation graph a question: `sect -> relations -> "
				+ "sect` is a cycle, and BARE_REF_UNITS excludes modules/* so the gate cannot "
				+ "see it. Owners write their own stance; the graph reads it. Offenders: %s"
			)
			% ", ".join(offenders)
		),
	)
	# A walk that visited nothing would pass vacuously, which is the shape of bug this
	# suite exists to stop being fooled by.
	assert_eq(
		scanned >= 20, true, "the walk visited the owners' files, so the verdict is not empty"
	)


## The narrower claim, pinned separately so a failure says which half broke: the
## three class names are the ones the gate would miss, and a `res://` path into this
## module is the one it would see. Both are forbidden, and the second is forbidden
## because a declared `res://` edge from `sect` to `relations` is legal for
## `tools arch` while still being a back edge in the design.
func test_the_back_edge_is_absent_by_both_spellings_a_bare_name_and_a_res_path() -> void:
	for root in OWNER_ROOTS:
		for path in _module_files(root):
			var code := _strip_comments(FileAccess.get_file_as_string(path))
			for name in BACK_EDGE_NAMES:
				assert_eq(
					code.contains(name),
					false,
					(
						"%s names '%s'; the gate cannot see this edge, so the test must"
						% [path.get_file(), name]
					),
				)
			assert_eq(
				code.contains("res://src/modules/relations"),
				false,
				(
					(
						"%s preloads this module's facade; a declared edge from an owner to the "
						% path.get_file()
					)
					+ "graph is still a back edge in the design"
				),
			)


## The other direction holds too, and it is the one the gate DOES check: `relations`
## reaches each owner through exactly one `preload` of that owner's facade, **and
## nowhere else in the module**. A second seam — into an owner internals file, or a
## second file reaching the same owner — would be a second reason for this module to
## change when that one does.
##
## Counted across the WHOLE module rather than per file, so the assertion says what
## the architecture is: one seam into `sect`, not one seam per file that happens to
## have one.
func test_this_module_reaches_each_owner_only_through_one_loaded_facade() -> void:
	var counts: Dictionary = {}
	for path in _module_files("res://src/modules/relations"):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for owner in ["world", "sect", "nation"]:
			var seam := 'preload("res://src/modules/%s/api.gd")' % owner
			counts[owner] = int(counts.get(owner, 0)) + code.count(seam)
	for owner in ["world", "sect", "nation"]:
		assert_eq(
			int(counts.get(owner, 0)),
			1,
			"the module declares exactly one seam into %s, and it is that owner's facade" % owner,
		)
	# And every `res://` edge out of this module lands on an owner facade rather than
	# on an internals file, which is the facade rule the gate enforces for a sibling
	# module (`tools/arch/enforce.py`: a module may reference another only through
	# its `api.gd`).
	var bodies: Array[String] = []
	for path in _module_files("res://src/modules/relations"):
		bodies.append(_strip_comments(FileAccess.get_file_as_string(path)))
	for owner in ["world", "sect", "nation"]:
		var internals := _other_res_edges(bodies, "res://src/modules/%s/" % owner, 'api.gd"')
		assert_eq(
			internals,
			[],
			(
				(
					"%s reaches into %s past its facade; a module may reference a sibling only "
					% ["relations", owner]
				)
				+ "through modules/<x>/api.gd"
			),
		)


## Every `res://` edge into `prefix` that is NOT the owner's facade file, as whole
## tokens rather than substrings — so `res://src/modules/sect/api.gd` does not read
## as a reach into `res://src/modules/sect/sect_state.gd`.
func _other_res_edges(
	bodies: Array[String], prefix: String, facade_suffix: String
) -> Array[String]:
	var found: Array[String] = []
	for body in bodies:
		var from := 0
		while from <= body.length():
			var at := body.find(prefix, from)
			if at < 0:
				break
			var tail := ""
			var end := body.find('"', at)
			if end > at:
				tail = body.substr(at, end - at + 1)
			if not tail.ends_with(facade_suffix):
				found.append(tail)
			from = at + 1
	return found


## The rule the graph itself obeys: it never WRITES to an owner. A read model that
## could record a stance would be a second writer of the truth it reports, and a
## disagreement between the two would be invisible until somebody compared them.
func test_this_module_publishes_no_write_verb_and_touches_no_actor_ledger() -> void:
	var banned: Array[String] = [
		"set_module_data",
		"set_stance",
		"declare_war",
		"declare_schism",
		"move_standing",
		"set_base",
		"add_base",
		"Stat.Op.FLAT",
	]
	for path in _module_files("res://src/modules/relations"):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for verb in banned:
			assert_eq(
				code.contains(verb),
				false,
				(
					(
						"%s reaches for '%s'; the graph reads owners and stores none of them, so it "
						% [path.get_file(), verb]
					)
					+ "has no verb that writes one"
				),
			)
	# The counter-proof: it really does read them, so the scan above is not passing
	# because the file is empty.
	var code := _strip_comments(
		FileAccess.get_file_as_string("res://src/modules/relations/relation_graph.gd")
	)
	for owner in ["world", "sect", "nation"]:
		assert_eq(
			code.contains('preload("res://src/modules/%s/api.gd")' % owner),
			true,
			"and it does read the %s facade" % owner,
		)


## ADR 0085 and DEF-0111 as they apply here: the graph owns no clock, no `rng` and no
## process loop. A graph that aged its own edges would be storing them, which is the
## one thing this module refuses to do.
func test_this_module_owns_no_clock_and_no_rng() -> void:
	for path in _module_files("res://src/modules/relations"):
		var code := _strip_comments(FileAccess.get_file_as_string(path))
		for banned in [
			"Time.get_ticks",
			"get_tree()",
			"_process(",
			"_physics_process(",
			"randf(",
			"randi(",
		]:
			assert_eq(
				code.contains(banned),
				false,
				(
					"%s uses '%s'; the graph owns no clock and no rng (DEF-0111)"
					% [path.get_file(), banned]
				),
			)


# --- Plumbing --------------------------------------------------------------


## Whether `line` names `word` as a WHOLE token. The word boundaries are what keep
## `sect_id` and `RelationsApi`-adjacent prose out of the verdict: the rule is about
## a back edge, which is an identifier, not a substring.
##
## ## The search window IS the bound
##
## `from` advances past every hit and `find` returns -1 once it passes the end of
## `line`, so the loop states its own termination rather than being a `while true:`
## whose only exits are `return`s. GDScript's flow analysis cannot prove that
## returns, refuses to compile the file, and one unanalysable function once took a
## 407-line suite down to zero assertions.
func _names_a_token(line: String, word: String) -> bool:
	var from := 0
	while from <= line.length():
		var at := line.find(word, from)
		if at < 0:
			break
		var before_ok := at == 0 or not _is_word_char(line.substr(at - 1, 1))
		var after_at := at + word.length()
		var after_ok := after_at >= line.length() or not _is_word_char(line.substr(after_at, 1))
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


func _is_word_char(text: String) -> bool:
	return (
		text == "_"
		or (text >= "a" and text <= "z")
		or (text >= "A" and text <= "Z")
		or (text >= "0" and text <= "9")
	)


## Every `.gd` under `root`, found iteratively. A recursive `DirAccess` returned an
## empty list under this runner once, and an empty scan makes every assertion above
## pass vacuously.
func _module_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif entry.ends_with(".gd"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Code with every comment removed, so a module that DOCUMENTS the rule it obeys is
## not reported for obeying it in prose.
func _strip_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
