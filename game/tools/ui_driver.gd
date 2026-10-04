extends SceneTree

## Headless UI driver (ADR 0039). Runs a screen with no window, applies a script
## of commands, and prints one JSON document per step plus a final state.
##
## This is the code path a player drives: it calls the screen's public `setup`,
## `act_*` and `summary` methods rather than reaching into widgets, so an LLM
## reading this output sees exactly what a human sees. Nothing here bypasses the
## facade-only rule, so the driver cannot drive a screen the player could not.
##
## Usage:
##   godot --headless --path game -s res://tools/ui_driver.gd -- \
##     --screen res://src/ui/screens/body_cultivation_panel.tscn \
##     --path body --cmd summary --cmd act_cultivate
##
## Commands: `summary`, `refresh`, `focus_initial`, or any `act_<verb>` the
## screen exposes. An unknown verb is reported, never silently ignored.

const ACTOR_ID := &"cli_hero"
const EXIT_OK := 0
const EXIT_ERROR := 1
## Large enough for the seed items plus whatever a caller grants. The default
## inventory slot count fills up during seeding, which made `grant` silently add
## nothing.
const SLOT_CAPACITY := 512
## The session file. An LLM drives the game over many invocations, so the actor
## has to survive between them or no progress is ever observable.
const SESSION_PATH := "user://ui_cli_session.json"
## The readout's demo swing, priced so one press wounds without necrosing.
##
## ## Why the magnitude is `0.05` and it is a BODY swing now
##
## `BodyWounds.add` divides a strike's damage by the target's `body_integrity.maximum`,
## and `BodyDamage` prices a hit as `magnitude x ATTACK_PHYSICAL x <point multiplier>` —
## so the magnitude is multiplied by the thrower's own offense stat rather than being the
## damage. The harness hero is built `{PHYSIQUE: 20, COMPREHENSION: 10}`, so
## `ATTACK_PHYSICAL` reads `40.0` and one blow at `0.05` carries a severity of `0.2`.
##
## At the old `12.0` that was 600 damage, a severity of `6.0`, and **necrosis on the
## first press** — a permanent, irreversible loss (ADR 0070), which makes the wound arc
## this surface exists to show unreadable after one click. `0.05` is the middle of the
## band: one blow wounds (`WOUND_THRESHOLD` `0.05`), several accumulate visibly, and
## necrosis arrives after about six — which is the arc, in order, rather than all at
## once. Every figure here is fixture arithmetic and none of it reaches `game/data`.
const DRILL_MAGNITUDE := 0.05
const DRILL_SHARE := 0.8
## The meridian the demo swing is aimed at.
##
## `body_cultivation`, not `qi_cultivation`, and that is the difference between a readout
## that prints a row and one that cannot: `QiDamage` emits no `effects[]` and its whole
## floor is the S8 chip, so every qi blow on a real `commonborn` reads `S4 proposed 0.00`
## and `S6 amount 1.00` — the chip floor doing all the work and the mechanism doing none.
## `BodyDamage` emits one `body.wound` effect per struck site (ADR 0070), so a body
## technique is the ONLY way this surface can render a wound, and a wound row is half
## of what the panel exists for.
##
## `&"lung"` is a real meridian — `game/data/body_cultivation/acupoints/minor_0.tres`,
## `minor_12.tres` and `minor_24.tres` all name it — so this is not an invented aim id.
## See the report for the authored-data consequence: no shipped `.tres` sets
## `aim_meridian`, so in production every body technique still resolves `random`.
const DRILL_MERIDIAN := &"lung"

var _screen: Node = null
var _actor: Actor = null
## The combat readout's drill body, built once in `_bind_read_models` and kept for the
## life of the run. A wound is a fact about a body that persists, so a fresh body per
## invocation would make the wound row unreadable.
var _drills: Actor = null
var _failures: Array[String] = []


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var screen_path := _option(argv, "--screen")
	if screen_path.is_empty():
		_emit({"event": "error", "error": "--screen is required"})
		quit(EXIT_ERROR)
		return
	_screen = _instantiate(screen_path)
	if _screen == null:
		_emit({"event": "error", "error": "could not instantiate %s" % screen_path})
		quit(EXIT_ERROR)
		return
	_bootstrap_actor(argv)
	_bind_read_models()
	_emit(
		{
			"event": "ready",
			"screen": screen_path,
			"name": String(_screen.name),
			"fresh": not _loaded_session,
		}
	)
	for command in _commands(argv):
		_run_command(command)
	_save_session()
	_emit({"event": "final", "summary": _screen.summary()})
	quit(EXIT_OK if _failures.is_empty() else EXIT_ERROR)


# --- Actor ------------------------------------------------------------------

var _loaded_session := false


## Build or resume the actor the screen renders. Screens drive real gameplay
## state, so the driver hands them a real actor on a real path rather than a
## stub. A saved session is resumed unless `--fresh` asks for a clean one, which
## is what makes progress observable across invocations.
func _bootstrap_actor(argv: PackedStringArray) -> void:
	if not _screen.has_method("setup"):
		return
	_actor = Actor.new(ACTOR_ID, {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	ItemsApi.attach(_actor, SLOT_CAPACITY)
	var path_id := _option(argv, "--path")
	var fresh := argv.has("--fresh")
	if not fresh and _restore_session(path_id):
		_screen.call("setup", _actor)
		return
	_attach_path(path_id)
	_stock_seed_items()
	_screen.call("setup", _actor)


## Give a screen whatever read model it asks for by name. Some screens are not a
## plain view of the actor: `loot_encounter` takes a [LootBridge] of plain
## callables, because `loot` is not one of the modules `rules.UI_MODULES` declares
## and `ui/` may not name `LootApi`. Without this the driver instantiated the
## screen, bound nothing, and every verb read as "not available" — so a live
## feature measured as dead, and BL-0320 was filed against the game when the fault
## was the instrument. Mirrors `ItemWorkbenchApp._bind_route_screen`, which is the
## production site for the same wiring.
func _bind_read_models() -> void:
	if _actor == null:
		return
	if _screen.has_method("bind_bridge"):
		LootApi.attach(_actor)
		_screen.call("bind_bridge", _loot_bridge())
	if _screen.has_method("bind_strike"):
		_drills = _build_drills()
		# The same composition-root verbs the app uses, in the same order: enrol the
		# paths, THEN install. `CombatBoot.bind_mechanisms` reads `acupoints` /
		# `sea_of_consciousness` off the actor to choose a mechanism, and
		# `ActorFactory` enrols only after `build` returns — so installing first
		# measures every path's inputs as absent.
		ActorFactory.with_body_cultivation(_actor)
		ActorFactory.with_qi_cultivation(_actor)
		CombatBoot.install(_actor)
		CombatBoot.install(_drills)
		_screen.call(
			"bind_strike",
			Callable(self, "_drill_blow"),
			_drills,
			Callable(self, "_drill_context")
		)


## The drill body the readout strikes, built through the SAME composition-root verbs
## `ItemWorkbenchApp._build_readout_target` uses (ADR 0174): `spawn_inhabitant` plus a
## body enrolment, so the target carries an `acupoints` set and a wound ledger and a
## body technique lands at a real meridian. It lives here for the reason `_loot_bridge`
## does — a screen cannot mint an `Actor`, because `app/` is a `PRIVATE_UNIT`.
##
## Built ONCE and kept: a fresh body per invocation would make the wound ledger
## unreadable, because a wound is a fact about a body that persists.
func _build_drills() -> Actor:
	var drill := ActorFactory.spawn_inhabitant(&"readout_drills")
	ActorFactory.with_body_cultivation(drill)
	return drill


## One blow for the readout, resolved through the SAME production entry point
## `ItemWorkbenchApp._readout_blow` calls — `CombatBoot.resolve_hit` — with a null rng
## so nothing random happens and every blow lands. A demo swing on the BODY path at a
## magnitude priced so one press wounds without necrosing — see [constant
## DRILL_MAGNITUDE].
func _drill_blow(attacker: Actor, defender: Actor) -> Dictionary:
	if attacker == null or defender == null:
		return {}
	var def := _drill_def()
	return CombatBoot.resolve_hit(attacker, defender, def, CombatEngineApi.tuning(), null).to_dict()


## The readout's companion read: `{band, actor, mechanism}`, all primitives — the same
## shape `ItemWorkbenchApp._readout_context` hands the same screen, and for the same
## reason: the band roll and the stat line are separate facade reads and the mechanism is
## `CombatBoot`'s own per-hit answer, and none of the three is a field of `to_dict()`.
##
## Re-asking `mechanism_for_hit` here rather than stashing what the strike chose is
## deliberate: it is the SAME named question with the SAME inputs, so the two answers
## cannot disagree, and a screen that received the mechanism as a fourth field on the
## outcome payload would be trusting a value the engine never wrote.
func _drill_context() -> Dictionary:
	return {
		"band": CombatEngineApi.band(_actor, _drills, CombatEngineApi.tuning(), null),
		"actor": CombatEngineApi.summary(_actor),
		"mechanism": CombatBoot.mechanism_for_hit(_actor, _drill_def()),
	}


## The drill swing's authored inputs, built once for the life of the run so the strike
## and the context read literally the same def.
func _drill_def() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = PathState.BODY
	def.magnitude = DRILL_MAGNITUDE
	def.element_share = DRILL_SHARE
	def.aim_meridian = DRILL_MERIDIAN
	return def


func _loot_bridge() -> LootBridge:
	var bridge := LootBridge.new()
	bridge.list_domains = Callable(LootApi, "domains")
	bridge.enter_domain = Callable(LootApi, "enter_domain")
	bridge.leave_domain = Callable(LootApi, "abandon")
	bridge.pickup = Callable(LootApi, "pickup")
	bridge.pickup_all = Callable(LootApi, "pickup_all")
	bridge.reclaim = Callable(LootApi, "reclaim")
	bridge.read_state = Callable(LootApi, "summary")
	return bridge


## Give the actor the items every realm gate needs, so a caller is not stuck at
## R1 forever with no way to satisfy the breakthrough gate. Data-driven, not a
## shortcut: these are the real realm items the facade checks for.
func _stock_seed_items() -> void:
	for def_id in _seed_item_ids():
		# The authored definition, via the game's one stable-id resolver
		# (ADR 0007). A fabricated `ItemDef.new()` stub is NOT equivalent: it made
		# this harness report a seeded pill the realm gate could not see, which
		# reads exactly like a broken gate.
		var def := Crafting.resolve(def_id)
		if def == null:
			_emit({"event": "error", "command": "seed", "error": "no such item: " + def_id})
			_failures.append("seed")
			continue
		ItemsApi.inventory(_actor).add(def, 999)


func _seed_item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for path_id in PathState.ALL:
		# `training_item` is qi and mind's channel elixir; `strengthening_item` is
		# body's. Seeding only one leaves the other path unable to train a channel.
		for seed_id in [
			&"breakthrough_item",
			&"strengthening_item",
			&"training_item",
			&"recovery_item",
			&"sea_catalyst",
		]:
			var seed: Variant = _realm_seed(path_id, seed_id)
			if seed != null and seed != "":
				var item_id := StringName(seed)
				if not out.has(item_id):
					out.append(item_id)
	return out


## Ask a path's realm seed for one item id. The driver reads the seed object
## directly because the harness may build an actor; a screen never does this.
func _realm_seed(path_id: StringName, field: StringName) -> Variant:
	var state := _actor.path(path_id)
	if state == null:
		return null
	match path_id:
		PathState.BODY:
			return BodyRealmSeed.for_realm(state.rank_id).get(field)
		PathState.QI:
			return QiRealmSeed.for_realm(state.rank_id).get(field)
		PathState.MIND:
			return MindRealmSeed.for_realm(state.rank_id).get(field)
	return null


# --- Session ---------------------------------------------------------------


## Restore the saved actor if one exists and its path still matches. A path
## mismatch starts fresh rather than restoring a body actor into a mind screen.
func _restore_session(path_id: String) -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	if String(data.get("path", "")) != _canonical_path(path_id):
		return false
	var restored := Actor.from_dict(data.get("actor", {}))
	if restored == null:
		return false
	_actor = restored
	# Re-attach the path's components WITHOUT enrolling it again: `_attach_path`
	# would `set_path` a fresh R1 state and discard everything just restored.
	_reattach_components(path_id)
	_loaded_session = true
	return true


## Persist the actor so the next invocation resumes where this one stopped.
func _save_session() -> void:
	if _actor == null or not _screen.has_method("setup"):
		return
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"path": _current_path(), "actor": _actor.to_dict()}))
	file.close()


func _current_path() -> String:
	for path_id in PathState.ALL:
		if _actor.path(path_id) != null:
			return String(path_id)
	return ""


## The canonical path id for a `--path` value. The caller's short name and the
## module's path id differ (`qi` vs `qi_cultivation`), and the session file has to
## store one form or a resume never matches.
func _canonical_path(path_id: String) -> String:
	match path_id:
		"body":
			return String(BodyPath.PATH_ID)
		"qi":
			return String(QiPath.PATH_ID)
		"mind":
			return String(MindPath.PATH_ID)
		_:
			return path_id


## Enrol the actor on one cultivation path. Each module's facade owns the attach
## order, so the driver never reaches past it.
func _attach_path(path_id: String) -> void:
	if path_id.is_empty():
		return
	match path_id:
		"body":
			_actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
		"qi":
			_actor.set_path(PathState.new(QiPath.PATH_ID, &"qi_refining"))
		"mind":
			_actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
		_:
			_fail("unknown path '%s'" % path_id)
			return
	_reattach_components(path_id)


## Attach the path's runtime components. Every facade's `attach` is idempotent, so
## this is safe on a fresh actor and on a restored one alike; unlike `_attach_path`
## it never enrols a path, so it cannot discard restored progress.
func _reattach_components(path_id: String) -> void:
	match path_id:
		"body":
			BodyCultivationApi.attach(_actor)
			BodyCultivationApi.attach_acupoints(_actor)
			BodyTraining.synchronize(_actor)
		"qi":
			QiCultivationApi.attach(_actor)
			QiTraining.synchronize(_actor)
		"mind":
			MindCultivationApi.attach(_actor)
			MindCultivationApi.attach_sea(_actor)
			MindTraining.synchronize(_actor)


# --- Commands ---------------------------------------------------------------


func _run_command(command: String) -> void:
	match command:
		"summary":
			_emit({"event": "summary", "value": _screen.summary()})
		"refresh":
			if _screen.has_method("refresh"):
				_screen.call("refresh")
			_emit({"event": "refresh", "value": _screen.summary()})
		"focus_initial":
			if _screen.has_method("focus_initial"):
				_screen.call("focus_initial")
			_emit({"event": "focus_initial", "focus_target": _focus_target()})
		_:
			_run_action(command)


## `act_cultivate` calls `act_cultivate()`. A verb the screen does not expose is
## reported, so a typo in a script fails loudly instead of passing silently.
##
## `call:<method>` reaches any public screen method with an optional payload, so
## a caller can drive selection helpers (`select_key`) that are not `act_*` and
## pass arguments to a zero-arg action. `grant:<item_id>` and `realm:<id>` seed
## the actor directly, which is what makes the game playable from a terminal.
func _run_action(command: String) -> void:
	if command.begins_with("call:"):
		_run_call(command.substr(5))
		return
	if command.begins_with("grant:"):
		_run_grant(command.substr(6))
		return
	if command.begins_with("realm:"):
		_run_realm(command.substr(6))
		return
	if command.begins_with("commit:"):
		_run_commit(command.substr(7))
		return
	# `strike` is `act_strike()`, `cultivate` is `act_cultivate()`. The CLI takes the
	# BARE VERB because that is the name every screen already publishes in its
	# `summary().enabled` table — `enabled.strike` is `strike`, not `act_strike`,
	# across every screen in `ui/screens/` — so a verb a screen declares it can
	# perform must be the same word the terminal drives, or the readout advertises a
	# verb no command line can reach. A screen exposing `act_strike` therefore
	# answers `--cmd strike`, which is what a caller reading its own summary expects.
	var action := command if command.begins_with("act_") else "act_" + command
	if not _screen.has_method(action):
		_emit({"event": "error", "command": command, "error": "no such action"})
		_failures.append(command)
		return
	var result: Variant = _screen.call(action)
	_emit({"event": "action", "command": command, "result": _jsonable(result)})


## `call:select_key=foo` or `call:equip_slot=accessory_a`. The payload is the part
## after the first `=`; without one the method is called with no arguments.
func _run_call(spec: String) -> void:
	var method := spec
	var args: Array = []
	var split := spec.find("=")
	if split >= 0:
		method = spec.substr(0, split)
		args.append(spec.substr(split + 1))
	if not _screen.has_method(method):
		_emit({"event": "error", "command": "call:" + method, "error": "no such method"})
		_failures.append(method)
		return
	var result: Variant
	if args.is_empty():
		result = _screen.call(method)
	else:
		result = _screen.call(method, args[0])
	_emit({"event": "action", "command": "call:" + method, "result": _jsonable(result)})


## `grant:item_id` puts a stack of a real item in the actor's inventory, so a
## caller can satisfy a realm gate instead of being stuck at R1.
func _run_grant(def_id: String) -> void:
	if def_id.is_empty():
		_emit({"event": "error", "command": "grant", "error": "no item id"})
		_failures.append("grant")
		return
	var inventory := ItemsApi.inventory(_actor)
	if inventory == null:
		# A screen with no `setup` (the character sheet) never triggered
		# `_bootstrap_actor`, so the inventory is not attached yet.
		ItemsApi.attach(_actor, SLOT_CAPACITY)
		inventory = ItemsApi.inventory(_actor)
	if inventory == null:
		_emit({"event": "error", "command": "grant", "error": "no inventory"})
		_failures.append("grant")
		return
	# Resolve the AUTHORED definition through the one stable-id resolver the game
	# itself uses (ADR 0007), so a grant is indistinguishable from a real drop.
	# Fabricating a bare `ItemDef.new()` here once made this harness lie: it
	# reported `granted: 999` for a pill the realm gate still called missing.
	var def := Crafting.resolve(StringName(def_id))
	if def == null:
		_emit({"event": "error", "command": "grant", "error": "no such item: " + def_id})
		_failures.append("grant")
		return
	# `add` returns the LEFTOVER, not the amount added, so 0 means it all fit.
	var leftover := inventory.add(def, 999)
	_emit(
		{
			"event": "action",
			"command": "grant:" + def_id,
			"result":
			{
				"granted": 999 - leftover,
				"leftover": leftover,
				"inventory_count": inventory.count(StringName(def_id)),
			},
		}
	)


## `realm:rank_id` moves the actor onto a realm directly, so a caller can reach a
## late game state without playing every step up to it.
func _run_realm(rank_id: String) -> void:
	var state := _actor.path(_current_path_id())
	if state == null:
		_emit({"event": "error", "command": "realm", "error": "actor is on no path"})
		_failures.append("realm")
		return
	state.rank_id = StringName(rank_id)
	_refresh_after_move()
	_emit({"event": "action", "command": "realm:" + rank_id, "result": String(state.rank_id)})


## `commit:<index>` runs `WorldAnchor.commit(actor, index)` — the same core entry
## point a high-tier breakthrough runs, and the ONLY thing that creates an
## `AscensionState`, commits to a world, or grows the inside world.
##
## `realm:` sets `PathState.rank_id` and stops there. That shortcut moves the
## rank WITHOUT the milestone that rank is supposed to have earned, so every
## screen reading core's committed state rendered "No ascent begun" and every
## ascent verb refused — a state the shipped game cannot actually reach. The
## refusal was correct; the driver was manufacturing an impossible state and the
## refusal read as a dead end. Two independent reports hit this before it was
## fixed. `commit:` performs the real milestone so the ascent, the inside world
## and the R28+ gates are drivable from a terminal.
func _run_commit(argument: String) -> void:
	if _actor == null:
		_emit({"event": "error", "command": "commit", "error": "no actor"})
		_failures.append("commit")
		return
	var index := argument.to_int()
	if index == 0 and argument.strip_edges() != "0":
		_emit({"event": "error", "command": "commit", "error": "commit needs a realm index"})
		_failures.append("commit")
		return
	WorldAnchor.commit(_actor, index)
	_refresh_after_move()
	_emit(
		{
			"event": "action",
			"command": "commit:" + argument,
			"result":
			{
				"index": index,
				"ascension": _actor.ascension != null,
				"world": _actor.world != null,
			},
		}
	)


func _current_path_id() -> StringName:
	for path_id in PathState.ALL:
		if _actor.path(path_id) != null:
			return path_id
	return &""


## Re-synchronise the modules after a direct state change so the screen renders
## the new realm instead of a stale one.
func _refresh_after_move() -> void:
	match _current_path_id():
		PathState.BODY:
			BodyTraining.synchronize(_actor)
		PathState.QI:
			QiTraining.synchronize(_actor)
		PathState.MIND:
			MindTraining.synchronize(_actor)
	if _screen.has_method("refresh"):
		_screen.call("refresh")


func _focus_target() -> String:
	var view: Dictionary = _screen.summary()
	return String(view.get("focus_target", ""))


# --- Plumbing ---------------------------------------------------------------


## Mount the scene under the tree root.
##
## **A composition root needs its `_ready()` driven by hand.** The runner is a
## `SceneTree` whose `_initialize()` returns before the first frame, so `root` is not
## yet inside the tree and the engine never delivers `_ready()` — a leaf screen does
## not care, because the driver reaches it through its public verbs, but a root that
## BUILDS its actor and wires its modules would answer every command with the state it
## had before boot. `SeamHarness._mount` already does exactly this and says why
## (`tests/ui/seam_harness.gd`), so the two agree instead of the CLI silently
## measuring an unbooted app.
func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	if node != null and node.get_parent() == null:
		root.add_child(node)
		if node.has_method("_ready"):
			node.call("_ready")
	return node


func _option(argv: PackedStringArray, name: String) -> String:
	var index := argv.find(name)
	if index < 0 or index + 1 >= argv.size():
		return ""
	return argv[index + 1]


## Commands are every `--cmd <verb>` pair, in order.
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
	return out


## `JSON.stringify` rejects raw Objects, so reduce anything it cannot encode to a
## primitive. Keeping the output machine-readable is the point of this driver.
func _jsonable(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_DICTIONARY, TYPE_ARRAY:
			return JSON.stringify(value, "  ")
		_:
			return str(value)


func _emit(payload: Dictionary) -> void:
	print("UIJSON ", JSON.stringify(payload))


func _fail(message: String) -> void:
	_failures.append(message)
