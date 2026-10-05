extends TestCase

## ADR 0266: the `quest` bus. Three things about the CONTRACT itself, each of which a
## later edit could quietly break, so each is pinned here rather than in the module
## suite that only exercises one path through it.
##
## ## The claims
##
##   1. `shared()` is a STABLE process-wide instance. This is the whole reason the bus
##      exists: a mod subscription names the bus CLASS, and a bus handed out as
##      `SomeEvents.new()` is an object nobody holds and nobody emits on — a connection
##      `is_connected` reports as live forever while no signal ever fires. ADR 0242
##      decision 2 hands out five of the buses that way.
##   2. Every signal argument is a PRIMITIVE. No `Resource`, no `Actor`, no authored
##      content: the same line ADR 0114's `BeatSink` draws for a sink payload and
##      `DamageProposal.is_primitive_effect` enforces by refusing at construction.
##   3. Every signal DECLARED here is EMITTED by production code. A declared signal with
##      no producer is the state ADR 0093 describes and does not excuse, and it reads as a
##      working reference while granting nothing — the ADR 0065 defect in its purest form.
##
## The emission BEHAVIOUR lives in `tests/modules/quest/test_quest_events_emitted.gd`;
## the composition-root wiring lives in `tests/app/test_unknown_bus_warning.gd`.

## The signals this contract declares, read from the SCRIPT by the tests below rather
## than asserted against this list: a second copy of the declaration list is the
## duplication that let `decision_answered` drift out of the file it described. This
## list is the EXPECTATION, and the shape test compares the script against it.
const DECLARED: Array[StringName] = [&"quest_accepted", &"quest_completed", &"quest_refused"]

## The only directory a producer of these signals may live in. A quest fact is written
## by the modules that own it, but the ANNOUNCEMENT is `quest`'s, so the producer is in
## `quest/` — an announce from `app/` is the composition root speaking for a module it
## does not own.
const PRODUCER_ROOT := "res://src/modules/quest"

## Bound on the directory walk. A recursive walk with no depth cap is the hazard
## `test_no_unbounded_wait.gd` cannot see (AGENTS.md); this one is over a module
## directory, so the cap is never reached — it exists so a future edit cannot remove it.
const MAX_DEPTH := 4

## Every Variant type a signal argument is allowed to be. What the house buses use:
## `String` for an actor id, `StringName` for an authored id, `int` for a count.
## `TYPE_OBJECT` is deliberately absent, and so is `TYPE_VARIANT` — an UNTYPED argument
## would let a `Resource` through the same signature, so a weakening is a failure here
## rather than an invisible loosening.
const PRIMITIVE_ARGS: Array[int] = [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME]

# --- The shared instance --------------------------------------------------------


## THE claim. Two calls, one object: a subscriber that connected once must still be
## connected the next time the bus is asked for, and that is only true of a singleton.
func test_shared_is_one_instance_across_calls() -> void:
	var first := QuestEvents.shared()
	var second := QuestEvents.shared()
	assert_eq(first, second, "two calls, one bus — not two objects on the same contract")
	assert_eq(first is QuestEvents, true, "and it is the QuestEvents contract itself")


## A fresh instance is a DIFFERENT object from the shared one, which is the trap the
## shared accessor exists to remove. `NpcApi.events()` and `NpcEvents.shared()` are
## asserted to be the same object in `tests/modules/social/test_social_events.gd`; this
## is the negative of that, for a bus whose producer reaches it through `shared()`.
func test_a_fresh_instance_is_not_the_shared_one() -> void:
	assert_ne(QuestEvents.new(), QuestEvents.shared(), "constructing by hand yields a stranger")
	assert_eq(
		QuestEvents.shared(), QuestEvents.shared(), "while the accessor never yields a stranger"
	)


# --- Primitives only ------------------------------------------------------------


## No `Resource`, no `Actor`, no `Dictionary`: a contract boundary is exactly where a
## payload would otherwise smuggle shared mutable content past every layer rule, and a
## subscriber holding a `QuestDef` would hold an editor handle on shipped content.
func test_every_signal_argument_is_a_primitive() -> void:
	for entry in QuestEvents.new().get_script().get_script_signal_list():
		var signal_name := StringName(entry.name)
		var args: Array = entry.args
		assert_ne(args.is_empty(), true, "'%s' carries something to read" % String(signal_name))
		for arg in args:
			var arg_type := int(arg.type)
			assert_eq(
				PRIMITIVE_ARGS.has(arg_type),
				true,
				(
					"%s.%s is '%s' — only a primitive crosses this boundary (ADR 0114)"
					% [String(signal_name), String(arg.name), type_string(arg_type)]
				)
			)


## The argument COUNT is pinned alongside the type, because a widened payload passes the
## primitive check while still changing what every subscriber must read.
func test_the_declared_shape_is_exactly_three_signals() -> void:
	var declared: Array[StringName] = []
	for entry in QuestEvents.new().get_script().get_script_signal_list():
		declared.append(StringName(entry.name))
		assert_eq((entry.args as Array).size(), 3, "'%s' takes three ids" % String(entry.name))
	assert_eq(declared.size(), DECLARED.size(), "three signals, and no fourth")
	for name in DECLARED:
		assert_eq(declared.has(name), true, "'%s' is declared" % String(name))


# --- A declaration has a producer -----------------------------------------------


## A signal nothing emits is a lie in a contract file: it reads as a working reference
## and grants nothing. Three declared, three emitted, or this goes red at the name.
func test_every_declared_signal_is_emitted_by_production_code() -> void:
	var emitted := _emitting_sources()
	assert_ne(emitted.is_empty(), false, "the walk found the producer directory at all")
	for name in DECLARED:
		assert_ne(
			emitted.has(String(name)),
			false,
			(
				(
					"%s is declared on QuestEvents but emitted by no production code under %s — emit it, "
					+ "or delete the declaration"
				)
				% [String(name), PRODUCER_ROOT]
			)
		)


## And the direction: the producer is `quest/` itself. The facts a step watches are
## written by `sect`, `combat` and `clan`, which know nothing about `quest` — that is
## ADR 0113 and it must stay true, so none of those may be the one announcing. The bus
## CLASS name is required in the match, so an unrelated `bond_changed.emit(` in `quest/`
## could never satisfy this.
func test_the_producer_is_the_module_that_owns_the_completion() -> void:
	var producers := _emitting_files()
	assert_ne(producers.is_empty(), false, "production code does emit on this contract")
	for path in producers:
		assert_eq(
			path.begins_with(PRODUCER_ROOT),
			true,
			(
				(
					"%s announces a quest fact from outside src/modules/quest/ — the event-owning module "
					+ "announces it, and app/ is where SUBSCRIBERS live (ADR 0093)"
				)
				% path
			)
		)


# --- Helpers --------------------------------------------------------------------


## Every file under [constant PRODUCER_ROOT] whose CODE emits on this contract.
## Comments are stripped first, so a docblock naming a signal cannot make a file look
## like a producer — the hazard the arch detector's raw-text scan runs into, and the
## reason three house docblocks are worded around their own literals.
func _emitting_files() -> Array[String]:
	var found: Array[String] = []
	for path in _gd_files(PRODUCER_ROOT, 0):
		var code := _code_of(path)
		for name in DECLARED:
			if code.contains("QuestEvents." + String(name) + ".emit("):
				found.append(path)
				break
	return found


## `signal -> true` for every signal this contract declares, proven to have a producer.
func _emitting_sources() -> Dictionary:
	var out: Dictionary = {}
	for path in _emitting_files():
		var code := _code_of(path)
		for name in DECLARED:
			if code.contains("QuestEvents." + String(name) + ".emit("):
				out[String(name)] = true
	return out


## Every `.gd` under `root`, depth-capped at [constant MAX_DEPTH].
##
## The `while` here terminates on `DirAccess`'s empty sentinel — the one drain shape
## `test_no_unbounded_wait.gd` accepts — and the recursion carries the depth cap, which
## that scan cannot see. One level is enough in practice; the cap exists so a future edit
## cannot turn a cycle into an unbounded walk.
func _gd_files(root: String, depth: int) -> Array[String]:
	var found: Array[String] = []
	if depth > MAX_DEPTH:
		return found
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gd_files(path, depth + 1))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## A file's CODE, with comments stripped.
##
## The arch detector scans raw text, comments included, which is why several house
## docstrings are worded around their own literals — so a substring match against a
## docblock would pass on prose that asserts nothing.
## `test_quest_production_completion.gd` strips the same way for the same reason.
func _code_of(path: String) -> String:
	var out := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out
