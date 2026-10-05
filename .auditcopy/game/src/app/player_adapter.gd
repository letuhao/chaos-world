class_name PlayerAdapter
extends CharacterBody2D

## 2D player adapter: CharacterBody2D wrapping an Actor.
## Handles movement, camera, interaction, and combat/non-combat states.
## LLM-drivable: move_to(), interact(), attack() callable headlessly.

signal state_changed(new_state: int)
signal interacted(target_name: String)
signal combat_started
signal combat_ended

enum State { EXPLORATION, COMBAT }

const INTERACTION_RANGE := 64.0
## Distance under which a move target counts as reached and is cleared.
const ARRIVAL_EPSILON := 4.0
const COMBAT_SPEED_MULTIPLIER := 0.5
const SAVE_VERSION := 1
const DEFAULT_MOVE_SPEED := 200.0

const INPUT_ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"attack": [KEY_SPACE],
}

var _actor: Actor = null
var _state: int = State.EXPLORATION
var _map_bounds: Rect2 = Rect2(0, 0, 1024, 1024)
var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _interactables: Array[Node2D] = []
var _camera: Camera2D = null
var _sprite: Sprite2D = null
var _interaction_area: Area2D = null


func _init(actor: Actor = null) -> void:
	if actor != null:
		_actor = actor


func _ready() -> void:
	_ensure_input_actions()
	_bind_nodes()
	_setup_camera()
	_setup_interaction_area()


func _bind_nodes() -> void:
	if _camera != null:
		return
	_camera = get_node_or_null("Camera2D") as Camera2D
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_interaction_area = get_node_or_null("InteractionArea") as Area2D


func _setup_camera() -> void:
	if _camera == null:
		return
	_camera.limit_left = int(_map_bounds.position.x)
	_camera.limit_right = int(_map_bounds.end.x)
	_camera.limit_top = int(_map_bounds.position.y)
	_camera.limit_bottom = int(_map_bounds.end.y)
	_camera.enabled = true


func _setup_interaction_area() -> void:
	if _interaction_area == null:
		return
	_interaction_area.body_entered.connect(_on_interaction_area_entered)
	_interaction_area.body_exited.connect(_on_interaction_area_exited)


func _physics_process(_delta: float) -> void:
	step_movement()
	move_and_slide()


## The movement decision for one frame, with no physics integration. Split out of
## `_physics_process` so a headless test can assert on `velocity` where there is
## no physics space to slide against — asserting `global_position` after
## `move_and_slide()` only works inside a running SceneTree.
func step_movement() -> void:
	match _state:
		State.EXPLORATION:
			_handle_exploration_movement()
		State.COMBAT:
			_handle_combat_movement()


func _handle_exploration_movement() -> void:
	if _has_target:
		var direction := (_target_position - global_position).normalized()
		var distance := global_position.distance_to(_target_position)
		if distance < ARRIVAL_EPSILON:
			_has_target = false
			velocity = Vector2.ZERO
		else:
			velocity = direction * _move_speed()
	else:
		var input_dir := _input_direction()
		velocity = input_dir * _move_speed()


func _handle_combat_movement() -> void:
	var input_dir := _input_direction()
	velocity = input_dir * _move_speed() * COMBAT_SPEED_MULTIPLIER


func _input_direction() -> Vector2:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0
	return direction.normalized() if direction != Vector2.ZERO else direction


func _move_speed() -> float:
	if _actor == null:
		return DEFAULT_MOVE_SPEED
	return _actor.stats.derived(Stat.MOVE_SPEED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("attack") and _state == State.COMBAT:
		_perform_attack()


# --- LLM-drivable API ---------------------------------------------------------


func move_to(position: Vector2) -> void:
	_target_position = position
	_has_target = true


func interact() -> void:
	var target := _nearest_interactable()
	if target == null:
		return
	# ## THE MERCY PRESS, and why it is on the interaction key
	#
	# While fighting, the press on the opponent you are holding at arm's length is the
	# moment the authored fate `the_third_man_spared` names: *"stood at killing distance
	# with the advantage held and did not close."* Outside combat the same press is an
	# ordinary look at a thing, which is why the branch is on `_state` and not on the
	# target — an exploration press must keep meaning what it always meant.
	#
	# It resolves nothing and takes no life: it hands the CHOICE to `CombatBoot`, which
	# is the combat composition root and the only layer here allowed to name
	# `CombatApi.spare`. The state it writes — a terminal mercy on the loser's duel
	# record, which the next swing is refused against — is the module's, not this file's.
	# A mercy nobody bound or did not earn is refused by name and reported as it refuses,
	# for the same reason `attack` above does: a choice that did not happen is not a
	# silent no-op.
	if _state == State.COMBAT:
		var duellist := _defender_of(target)
		if duellist != null and _actor != null and CombatMercy.installed():
			var shown: Variant = CombatMercy.commit(_actor, duellist)
			var answered: Dictionary = shown if shown is Dictionary else {}
			if not bool(answered.get("ok", false)):
				push_warning(
					(
						"PlayerAdapter.interact: the mercy press was refused (%s)"
						% String(answered.get("reason", "unknown"))
					)
				)
			return
	interacted.emit(target.name)


func attack(target: Node2D = null) -> void:
	if _state != State.COMBAT:
		return
	if target == null:
		target = _nearest_interactable()
	if target == null:
		return
	# Combat resolution wired by the combat module facade: `CombatBoot` injects
	# `CombatApi.hit` into this seam (ADR 0126), so `app/` still names no module
	# here and the adapter gains no field for it. An unbound install is reported
	# rather than swallowed — a blow that never happened is not a silent no-op.
	if not CombatBoot.has_attack_resolver():
		push_warning(
			"PlayerAdapter.attack: no attack resolver is installed (CombatBoot.set_attack_resolver)"
		)
		return
	var defender := _defender_of(target)
	if defender == null or _actor == null:
		return
	CombatBoot.strike(_actor, defender)


func set_state(new_state: int) -> void:
	if new_state == _state:
		return
	_state = new_state
	state_changed.emit(new_state)
	if new_state == State.COMBAT:
		combat_started.emit()
	else:
		combat_ended.emit()


func actor() -> Actor:
	return _actor


func state() -> int:
	return _state


func set_map_bounds(bounds: Rect2) -> void:
	_map_bounds = bounds
	_setup_camera()


func add_interactable(node: Node2D) -> void:
	if not _interactables.has(node):
		_interactables.append(node)


func remove_interactable(node: Node2D) -> void:
	_interactables.erase(node)


## Register a node the player's next press will reach. Idempotent.
##
## ## Why the DOMAIN spells this out rather than waiting on the `InteractionArea`
##
## `DomainWorld.place_inhabitants` hands every creature a bare `Node2D` with
## `set_meta(&"actor", …)` — so the node exists and names who stands there, but it is not
## a physics body and the `InteractionArea`'s `body_entered` never fires for it. The area
## is the spatial layer, and ADR 0126 settled that combat is "a headless exchange and the
## spatial layer does not block it", so a fight must not be gated on a collision signal
## nothing emits. This is the registration the area would have done, made explicit.
func register_target(node: Node2D) -> void:
	add_interactable(node)


## Unregister every node, so a torn-down world cannot leave a freed `Node2D` on this
## adapter's list. `_nearest_interactable` skips invalid instances, so a stale entry is
## skipped rather than crashed on — but a list that only grows across a run is a leak, and
## the runner shares ONE process across every suite.
func clear_targets() -> void:
	_interactables.clear()


func _nearest_interactable() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INTERACTION_RANGE
	for node in _interactables:
		if not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = node
	return nearest


## The `Actor` a target node stands for, or null.
##
## ## Why a node can answer with an actor
##
## Combat resolves over two `Actor`s and needs no node (ADR 0126), but a spatial adapter
## is handed a `Node2D` because that is what an interaction produced. So the node is
## asked for its actor rather than the adapter guessing: a `set_meta(&"actor")` answer
## first (the convention every spawner in `app/` can set without a new base class), then a
## `PlayerAdapter` target's own wrapped actor. A node that carries neither is not a
## combatant — a chest, an interactable prop — so it is refused, not coerced.
func _defender_of(target: Node2D) -> Actor:
	if target == null or not is_instance_valid(target):
		return null
	# Explicitly typed: `get_meta` answers a `Variant`, and inferring from one is a
	# warning-as-error in this repo. `has_meta` first, because the engine ERRORS on a
	# missing key rather than answering the default.
	var wrapped: Variant = null
	if target.has_meta(&"actor"):
		wrapped = target.get_meta(&"actor")
	if wrapped is Actor:
		return wrapped as Actor
	if target is PlayerAdapter:
		return (target as PlayerAdapter).actor()
	return null


func _on_interaction_area_entered(body: Node2D) -> void:
	add_interactable(body)


func _on_interaction_area_exited(body: Node2D) -> void:
	remove_interactable(body)


func _perform_attack() -> void:
	var target := _nearest_interactable()
	if target == null:
		return
	attack(target)


# --- Save/load ----------------------------------------------------------------


func to_dict() -> Dictionary:
	var actor_dict := {}
	if _actor != null:
		actor_dict = _actor.to_dict()
	return {
		"version": SAVE_VERSION,
		"position": [global_position.x, global_position.y],
		"state": _state,
		"map_bounds":
		[
			_map_bounds.position.x,
			_map_bounds.position.y,
			_map_bounds.size.x,
			_map_bounds.size.y,
		],
		"actor": actor_dict,
	}


static func from_dict(data: Dictionary) -> PlayerAdapter:
	var actor_data: Dictionary = data.get("actor", {})
	var actor := Actor.from_dict(actor_data) if not actor_data.is_empty() else Actor.new(&"player")
	var adapter := PlayerAdapter.new(actor)
	var pos: Array = data.get("position", [0, 0])
	adapter.global_position = Vector2(float(pos[0]), float(pos[1]))
	adapter._state = int(data.get("state", State.EXPLORATION))
	var bounds: Array = data.get("map_bounds", [0, 0, 1024, 1024])
	adapter._map_bounds = Rect2(
		float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3])
	)
	return adapter


func summary() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y],
		"state": _state,
		"actor_id": "" if _actor == null else String(_actor.id),
		"actor_realm": "" if _actor == null else String(_actor.realm()),
		"interactable_count": _interactables.size(),
		"has_target": _has_target,
		"map_bounds":
		[
			_map_bounds.position.x,
			_map_bounds.position.y,
			_map_bounds.size.x,
			_map_bounds.size.y,
		],
	}


# --- Input setup --------------------------------------------------------------


static func _ensure_input_actions() -> void:
	for action_name in INPUT_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for key in INPUT_ACTIONS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action_name, event):
				InputMap.action_add_event(action_name, event)
