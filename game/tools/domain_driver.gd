extends SceneTree

## Headless domain driver (ADR 0231, ADR 0232). Enters a domain through the same seam a
## screen drives, applies a list of verbs, and prints one JSON document per step plus a
## final state.
##
## ## It reads the BRIDGE, never a node
##
## Every verb goes through `DomainBoot.bridge()` — the same `Callable` set
## `ui/screens/domain_explore.gd` is handed. So anything this driver can play, a player
## can play, and the driver cannot measure wiring no screen reaches. It names
## `DomainBoot` because `game/tools/` is the `harness` arch unit: it may reach module
## internals and `app/`, and a GDScript file that could not would be testing a different
## program (ADR 0072's own "the map is testable without a display").
##
## Usage (never invoked by path — `tools domain drive` goes through `godot.run_godot`):
##   godot --headless --path game -s res://tools/domain_driver.gd -- \
##     --seed 20260904 --template ember_grotto --cmd map --cmd summary
##
## Every emitted line is prefixed `DOMAINJSON ` and carries `event`, `seed` and
## `template_id`. First is `ready`, last is `final`.

const PREFIX := "DOMAINJSON "
const EXIT_OK := 0
const EXIT_ERROR := 1
## The seed `DomainBridge.DEFAULT_SEED` publishes for the screen's own buttons. Read
## THROUGH the bridge's class rather than restated, so a change there cannot desynchronise
## the CLI's default from the UI's (ADR 0066).
const ACTOR_ID := &"domain_driver_hero"
## Large enough that a fixture's reward and a `grant:` both fit; the default inventory slot
## count fills during seeding and makes a grant silently add nothing.
const SLOT_CAPACITY := 512
## The maximum number of verbs one transcript may carry. A REAL guard, not a budget: the
## transcript is a list, so a `--cmd` repeated in a loop by a caller would otherwise walk
## off the end of the arena. One extra verb is REFUSED BY NAME and exits non-zero, so the
## failure is loud rather than a silent truncation (AGENTS.md: every loop gets a real guard).
const MAX_COMMANDS := 512
## The bridge actions this driver exposes, and how many arguments each takes. Declared as
## data rather than as a `match` with 12 arms so `tools domain --help` and the refusal
## message below are read from ONE list: a verb added here is a verb `--help` names.
const VERB_ARGS: Dictionary = {
	"enter": 1,
	"visit": 1,
	"arm": 3,
	"attempt": 3,
	"claim": 2,
	"leave": 0,
	"map": 0,
	"rooms": 0,
	"minimap": 0,
	"summary": 0,
	"band": 0,
	"read": 0,
	"templates": 0,
	"kill": 1,
	"gate": 0,
	"abandon": 0,
}

## The verbs the bridge does NOT publish and this driver adds, each named for the reason.
## `arm`/`attempt`/`claim` are the bridge's three fixture verbs spelled short; `map` is
## `read_active`; `rooms`/`minimap`/`summary`/`templates` are its reads; `band`/`kill`/
## `gate`/`abandon` are `DomainRunApi`, the module's SECOND facade (ADR 0230's run), which
## exists precisely because `api.gd` is at its twelve-method cap and cannot grow four more.
var _bridge: DomainBridge = null
var _actor: Actor = null
var _template_id: StringName = &""
var _seed: int = 0
## Every violated invariant, as `step: text`. Accumulated rather than aborting on the first
## so one run reports the whole transcript's defects, and emitted in `final` so the Python
## side can name the offending line (ADR 0232).
var _violations: Array[String] = []
## A per-step index so a violation can be pointed at the transcript line that caused it.
var _step: int = 0


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	_seed = int(_option(argv, "--seed"))
	_template_id = StringName(_option(argv, "--template"))
	if _template_id == &"":
		var first := _first_template()
		if first == &"":
			_emit({"event": "error", "seed": _seed, "template_id": "", "error": "no_actor"})
			quit(EXIT_ERROR)
			return
		_template_id = first
	_actor = Actor.new(ACTOR_ID, {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(_actor, SLOT_CAPACITY)
	# `DomainBoot.install` is idempotent and `enter_domain` calls it anyway, but the READ
	# verbs below (`templates`, `map`) must not mint anything — so the constructor is
	# installed here, explicitly, once.
	DomainBoot.install()
	_bridge = DomainBoot.bridge()
	_emit(
		{
			"event": "ready",
			"seed": _seed,
			"template_id": String(_template_id),
			"actions": VERB_ARGS.keys()
		}
	)
	for command in _commands(argv):
		_step += 1
		_run_command(command)
	_emit(
		{
			"event": "final",
			"seed": _seed,
			"template_id": String(_template_id),
			"summary": DomainApi.summary(_actor),
			"violations": _violations
		}
	)
	# **A violated invariant exits non-zero** (ADR 0232). A driver that only prints is a
	# viewer, and the caller cannot tell a viewer from a passing run.
	quit(EXIT_OK if _violations.is_empty() else EXIT_ERROR)


## The first authored template id, in `DomainApi.templates()`' own canonical order, so a
## transcript that names no template still drives the same domain on every machine.
func _first_template() -> String:
	for entry in DomainApi.templates():
		return String(entry.get("template_id", ""))
	return ""


# --- Verbs --------------------------------------------------------------------


func _run_command(command: String) -> void:
	var verb := command
	var argument := ""
	var split := command.find("=")
	if split >= 0:
		verb = command.substr(0, split)
		argument = command.substr(split + 1)
	if not VERB_ARGS.has(verb):
		_fail("no_such_verb", "the bridge publishes no verb '%s'" % verb)
		return
	match verb:
		"enter":
			_do_enter()
		"visit":
			_call(&"visit", [_actor, StringName(argument)])
		"arm":
			_fixture(&"arm_fixture", argument.split("|"), 3)
		"attempt":
			_fixture(&"attempt_fixture", argument.split("|"), 3)
		"claim":
			_fixture(&"claim_fixture", argument.split("|"), 2)
		"leave":
			_call(&"leave", [_actor])
		"map":
			_call(&"read_active", [_actor])
		"rooms":
			_emit_value(&"rooms", "rooms", _bridge.call_list(&"rooms", [_actor]))
		"minimap":
			_call(&"minimap", [_actor])
		"summary":
			_emit_value(&"summary", "summary", DomainApi.summary(_actor))
		"band":
			_emit_value(&"band", "band", DomainRunApi.band(_actor))
		"kill":
			_do_kill(argument)
		"gate":
			_emit_value(&"gate", "gate", DomainRunApi.exit_gate(_actor))
		"abandon":
			_emit_value(&"abandon", "abandon", DomainRunApi.abandon_band(_actor, "driver"))
		"templates":
			_emit_value(&"templates", "templates", DomainApi.templates())


## Generate and enter the named template, then PUBLISH what was entered. The refusal is
## the finding: `generate_and_enter` answers `{ok: false, reason}` by name
## (`generation_refused`, `no_such_template`) and a transcript that asked to enter a domain
## it did not enter has failed, whatever the rest of the run says.
func _do_enter() -> void:
	var entered := DomainBoot.enter_domain(_actor, _template_id, _seed)
	_emit_value(&"enter", "enter", _jsonable_map(entered))
	if not bool(entered.get("ok", false)):
		_fail("enter_refused", "enter_domain refused: %s" % String(entered.get("reason", "")))
		return
	_assert_inside("after enter")


## Record a decided kill. `DomainRunApi.record_kill` is the ONE verb that advances a run
## (ADR 0229), so a kill whose boss id is not the open door is a refusal the transcript
## must see rather than a silent no-op.
func _do_kill(boss_id: String) -> void:
	var answered := DomainRunApi.record_kill(_actor, boss_id, ACTOR_ID)
	_emit_value(&"kill", "kill", answered)
	if not bool(answered.get("ok", false)):
		_fail(
			"kill_refused",
			"record_kill refused '%s': %s" % [boss_id, String(answered.get("reason", ""))]
		)
		return
	_assert_band_consistent("after kill")


func _fixture(action: StringName, parts: PackedStringArray, wanted: int) -> void:
	if parts.size() != wanted:
		_fail(
			"bad_arity",
			"%s takes %d arguments joined by '|', got %d" % [action, wanted, parts.size()]
		)
		return
	var args: Array = [_actor]
	for part in parts:
		args.append(StringName(part))
	var result := _bridge.call_action(action, args)
	_emit_value(action, "fixture", result)
	if not bool(result.get("ok", false)):
		_fail("fixture_refused", "%s refused: %s" % [action, String(result.get("reason", ""))])


func _call(action: StringName, args: Array) -> void:
	_emit_value(action, action, _bridge.call_action(action, args))


func _emit_value(verb: StringName, kind: String, value: Variant) -> void:
	_emit(
		{
			"event": "verb",
			"seed": _seed,
			"template_id": String(_template_id),
			"verb": String(verb),
			"kind": kind,
			"value": _jsonable(value)
		}
	)


## `enter_domain` returns `inhabitants` as live `Actor`s, which `JSON.stringify` refuses.
## Reduce the array to the count a caller can read rather than dropping the key, so a
## transcript diffs. Returns the DICTIONARY, not `_jsonable(...)`: the emit path stringifies
## it, and re-stringifying here made this function's declared return type a lie.
func _jsonable_map(answer: Dictionary) -> Dictionary:
	var out := answer.duplicate()
	if out.has("inhabitants"):
		out["inhabitants"] = []
		out["inhabitant_count"] = answer.get("inhabitant_count", 0)
	return out


# --- Invariants (ADR 0232) ----------------------------------------------------


## A transcript that entered and is not inside is the defect this whole file exists to
## catch: `generate_and_enter` returned `ok` and no map is active, which is exactly the
## state ADR 0231 calls a viewer rather than a driver.
func _assert_inside(when: String) -> void:
	if DomainApi.summary(_actor).is_empty():
		_fail(
			"entered_but_not_inside", "the actor carries no domain %s; enter_domain said ok" % when
		)


## The band, a kill and the gate must agree with each other. Each is read through its own
## facade read (`summary()["run"]` and `DomainRunApi.exit_gate`) rather than from the
## record_kill answer the driver already has, so a disagreement between the WRITE path and
## the READ path is what fires — one caller echoing its own return value proves nothing.
func _assert_band_consistent(when: String) -> void:
	var view := DomainRunApi.band(_actor)
	var gate := DomainRunApi.exit_gate(_actor)
	if view.is_empty():
		_fail("no_band", "the actor holds no band %s, so a kill cannot have advanced one" % when)
		return
	var remaining := int(view.get("remaining_count", 0))
	var cleared := bool(view.get("cleared", false))
	if remaining > 0 and cleared:
		_fail(
			"band_inconsistent",
			"%s: the band still holds %d boss(es) and is also cleared" % [when, remaining]
		)
	if remaining == 0 and not cleared:
		_fail("band_inconsistent", "%s: the band is empty and is not cleared" % when)
	if bool(gate.get("gate_open", false)) != cleared:
		_fail(
			"gate_inconsistent",
			(
				"%s: exit_gate says the exit is %s while the band says cleared=%s"
				% [when, "open" if bool(gate.get("gate_open", false)) else "closed", cleared]
			)
		)


func _fail(kind: String, message: String) -> void:
	var line := "step %d: %s" % [_step, message]
	_violations.append(line)
	_emit(
		{
			"event": "violation",
			"seed": _seed,
			"template_id": String(_template_id),
			"kind": kind,
			"step": _step,
			"message": message
		}
	)


# --- Plumbing -----------------------------------------------------------------


## Commands are every `--cmd <verb>` pair, in order. Bounded by [constant MAX_COMMANDS]:
## the list is walked with a counted `for`, so it terminates on any input including one
## containing a verb repeated to infinity.
func _commands(argv: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	var collecting := false
	for arg in argv:
		if arg == "--cmd":
			collecting = true
			continue
		if collecting:
			out.append(arg)
			collecting = false
			if out.size() >= MAX_COMMANDS:
				_fail("too_many_commands", "a transcript may carry at most %d verbs" % MAX_COMMANDS)
				break
	return out


func _option(argv: PackedStringArray, name: String) -> String:
	var index := argv.find(name)
	if index < 0 or index + 1 >= argv.size():
		return ""
	return argv[index + 1]


## `JSON.stringify` rejects raw Objects (the `Actor`s `enter_domain` hands back and any
## `Resource` reached through one), so reduce anything it cannot encode to a primitive.
func _jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_DICTIONARY, TYPE_ARRAY:
			return JSON.stringify(value, "  ")
		_:
			return str(value)


func _emit(payload: Dictionary) -> void:
	var stamped := payload.duplicate()
	stamped["step"] = _step
	print(PREFIX, JSON.stringify(stamped))
