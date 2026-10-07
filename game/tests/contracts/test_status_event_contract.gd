extends TestCase

## ADR 0902 (P5/P13): the `status` bus and the refused log it feeds. Three things about
## the CONTRACT itself, each of which a later edit could quietly break, so each is pinned
## here rather than in a module suite that only exercises one door:
##
##   1. `shared()` is a STABLE process-wide instance. This is the whole reason the bus
##      exists: a subscriber that connected once must still be connected the next time
##      the bus is asked for, and a bus handed out as `StatusEvents.new()` is an object
##      nobody holds and nobody emits on.
##   2. Every signal argument is a PRIMITIVE. No `Actor`, no `Resource`, no `Dictionary`:
##      `String` for a host id, `StringName` for an authored id, `int` for a handle.
##   3. Every signal DECLARED here is EMITTED by production code. A declared signal with
##      no producer reads as a working reference while granting nothing — the ADR 0065
##      defect in its purest form. The producers are the doors a status is actually
##      applied through: the status module's facade, `combat_engine`'s S12 stage, and
##      `combat`'s element-riding exchange site, and the scan names all three so a
##      fourth door cannot be added silently.
##
## The runtime BEHAVIOUR lives where each door lives:
## `tests/modules/status/test_status_lifecycle.gd` (the facade, the verbs, the readback),
## `tests/modules/combat_engine/test_status_apply_events.gd` (the spine's S12) and
## `tests/modules/status/test_status_meters.gd` (the meter's pulse-fed crossing).

## The expectation the shape test compares the SCRIPT against, never a second copy the
## file could drift from silently.
const DECLARED: Array[StringName] = [
	&"status_applied", &"status_resisted", &"status_meter_fired", &"status_counter_fired"
]

## The only directories a producer may live in (ADR 0902, P5): the status module owns
## the facade door, `combat_engine` owns the spine's S12 stage, and `combat` owns the
## exchange's element-riding door. An announce from `app/` would be the composition
## root speaking for a module it does not own.
const PRODUCER_ROOTS: Array[String] = [
	"res://src/modules/status",
	"res://src/modules/combat_engine",
	"res://src/modules/combat",
]

## Each declaration's spelling at a production emit site: every announce goes through
## the bus's own static helper, so a file that merely NAMES a signal in prose cannot
## satisfy the scan.
const EMITS: Dictionary = {
	&"status_applied": "note_applied(",
	&"status_resisted": "note_resisted(",
	&"status_meter_fired": "note_meter_fired(",
	&"status_counter_fired": "note_counter_fired(",
}

## Bound on the directory walk: a recursive walk with no depth cap is the hazard
## `test_no_unbounded_wait.gd` cannot see (AGENTS.md). One level is enough in practice.
const MAX_DEPTH := 4

## Every Variant type a signal argument is allowed to be. `TYPE_OBJECT` is deliberately
## absent, and so is `TYPE_VARIANT`: an UNTYPED argument would let a `Resource` through
## the same signature, so a weakening is a failure here rather than an invisible loosening.
const PRIMITIVE_ARGS: Array[int] = [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME]

# --- The shared instance --------------------------------------------------------


## THE claim: two calls, one object.
func test_shared_is_one_instance_across_calls() -> void:
	var first := StatusEvents.shared()
	var second := StatusEvents.shared()
	assert_eq(first, second, "two calls, one bus — not two objects on the same contract")
	assert_eq(first is StatusEvents, true, "and it is the StatusEvents contract itself")


func test_a_fresh_instance_is_not_the_shared_one() -> void:
	assert_ne(StatusEvents.new(), StatusEvents.shared(), "constructing by hand yields a stranger")


# --- Primitives only ------------------------------------------------------------


func test_every_signal_argument_is_a_primitive() -> void:
	for entry in StatusEvents.new().get_script().get_script_signal_list():
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


## The argument COUNT is pinned alongside the type: a widened payload passes the
## primitive check while still changing what every subscriber must read.
func test_the_declared_shape_is_exactly_four_signals() -> void:
	var declared: Array[StringName] = []
	for entry in StatusEvents.new().get_script().get_script_signal_list():
		declared.append(StringName(entry.name))
		assert_eq(
			(entry.args as Array).size(), 4, "'%s' takes four primitives" % String(entry.name)
		)
	assert_eq(declared.size(), DECLARED.size(), "four signals, and no fifth")
	for name in DECLARED:
		assert_eq(declared.has(name), true, "'%s' is declared" % String(name))


# --- A declaration has a producer -----------------------------------------------


## A signal nothing emits is a lie in a contract file. Four declared, four emitted, or
## this goes red at the name.
func test_every_declared_signal_is_emitted_by_production_code() -> void:
	var emitted := _emitting_sources()
	assert_eq(emitted.is_empty(), false, "the walk found the producer directories at all")
	for name in DECLARED:
		assert_ne(
			emitted.has(String(name)),
			false,
			(
				(
					"%s is declared on StatusEvents but emitted by no production code under "
					+ "%s — emit it, or delete the declaration"
				)
				% [String(name), ", ".join(PRODUCER_ROOTS)]
			)
		)


## And the direction: the producer is one of the apply doors. `app/` is where
## SUBSCRIBERS live; a module that owns no apply site has nothing to announce here.
func test_the_producers_are_the_apply_doors() -> void:
	var producers := _emitting_files()
	assert_eq(producers.is_empty(), false, "production code does emit on this contract")
	for path in producers:
		var owned := false
		for root in PRODUCER_ROOTS:
			if path.begins_with(root):
				owned = true
		assert_eq(owned, true, "%s announces a status fact from outside its doors" % path)


# --- Helpers --------------------------------------------------------------------


## Every file under the producer roots whose CODE emits on this contract. Comments are
## stripped first, so a docblock naming a helper cannot make a file look like a producer.
## The two-part match is deliberate: the file must NAME this bus class AND call one of
## its announce helpers.
func _emitting_files() -> Array[String]:
	var found: Array[String] = []
	for root in PRODUCER_ROOTS:
		for path in _gd_files(root, 0):
			var code := _code_of(path)
			if not code.contains("StatusEvents"):
				continue
			for name in DECLARED:
				if code.contains(String(EMITS[name])):
					found.append(path)
					break
	return found


## `signal -> true` for every declaration proven to have a producer.
func _emitting_sources() -> Dictionary:
	var out: Dictionary = {}
	for path in _emitting_files():
		var code := _code_of(path)
		for name in DECLARED:
			if code.contains(String(EMITS[name])):
				out[String(name)] = true
	return out


## Every `.gd` under `root`, depth-capped at [constant MAX_DEPTH].
##
## The `while` here terminates on `DirAccess`'s empty sentinel — the one drain shape
## `test_no_unbounded_wait.gd` accepts — and the recursion carries the depth cap, which
## that scan cannot see. The cap exists so a future edit cannot turn a cycle into an
## unbounded walk.
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


## A file's CODE, with comments stripped: a substring match against a docblock would
## pass on prose that asserts nothing.
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
