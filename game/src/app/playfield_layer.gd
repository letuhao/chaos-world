class_name PlayfieldLayer
extends Node2D

## The 2.5D playfield, and the reason the game is visible at all.
##
## ## Why this exists and what it replaces
##
## Until now the realized world was parented UNDER A UI SCREEN:
## `item_workbench_body.gd` called `DomainBoot.realize_world(screen, hero)` with
## `screen` being the live `UiScreen` — a `Control` inside a `VBoxContainer` of
## labels. A `Node2D` world with a `Camera2D` therefore rendered *inside a
## control's rect, behind that control's own children*, competing for the same
## pixels as the label list it was supposed to sit behind. The world was
## real, correct, and effectively invisible.
##
## This node is the base of the composition root: the world is parented HERE,
## and the UI is a `CanvasLayer` sibling drawn OVER it. One layer owns the
## playfield; the other owns the chrome. Neither is a child of the other, so a
## screen can never occlude the world by existing.
##
## ## Why a plain Node2D and not a SubViewport
##
## A `SubViewport` would give the world its own draw surface and force the UI
## into a second viewport with its own input path — two coordinate spaces, two
## focus trees, and a resolution policy to keep in sync. The world and the UI
## only need different DRAW ORDER and different INPUT OWNERSHIP, and a
## `CanvasLayer` on the UI side already gives both: a higher `layer` draws on
## top, and a canvas layer takes input ahead of the layer below it.
##
## ## Zoom lives here, and it is zoomable on purpose
##
## `DEFAULT_ZOOM` is the framing AGENTS.md records: half the world area a
## Diablo-style isometric shows at the same resolution, because Diablo's sprites
## are small and this repo's painted art is high quality. It is a DEFAULT, not a
## lock — `set_zoom` re-frames at runtime and the value is never written back
## into content. A camera scale that only one constant may change is a
## coordinate system wearing a camera costume.
##
## Contract: `summary()` is the testable surface, primitives only, and answers
## `{}` before `_ready` so a headless reader never sees a half-built layer.

const DEFAULT_ZOOM := 2.0
const MIN_ZOOM := 0.75
const MAX_ZOOM := 6.0
## The node the world is realized under. Named because `DomainWorld` publishes
## its subtree by name and a probe reads it back through `DomainBoot.world_summary`.
const WORLD_SLOT := &"WorldSlot"

var _camera: Camera2D = null
var _slot: Node2D = null


func _ready() -> void:
	_bind_nodes()
	_camera = _ensure_camera()
	set_zoom(DEFAULT_ZOOM)


## The nearest `PlayfieldLayer` at or above `from`, or null.
##
## ## Why this walks up and never reads `current_scene`
##
## `get_tree().current_scene` is only set for the scene the engine BOOTED. Any caller that
## mounts this shell another way — the headless harness parents it under `root`, which is how
## every UI suite drives it — gets null there, and a lookup that trusted it answered "no
## world layer" for a shell that plainly carries one. That refused every realization while
## every gate stayed green, which is the quiet lie INC-0016 is about.
##
## ONE function, called from both `navigate_to()` and `teardown()`: two copies of a lookup
## are two things that can disagree about where the playfield is.
static func find_from(from: Node) -> PlayfieldLayer:
	var host: Node = from
	while host != null:
		var layer := host.get_node_or_null(^"%PlayfieldLayer") as PlayfieldLayer
		if layer != null:
			return layer
		host = host.get_parent()
	return null


## Free whatever realized world stands above `from`. One path, because `navigate_to()`
## and `teardown()` both need it and two copies can disagree about what is standing.
static func release_under(from: Node) -> void:
	var layer := find_from(from)
	if layer != null:
		DomainBoot.release_world(layer.world_slot())


func _bind_nodes() -> void:
	if _slot == null:
		_slot = get_node_or_null(NodePath(PlayfieldLayer.WORLD_SLOT)) as Node2D


## The node a realized world is parented to. NOT the layer itself: the camera is
## a child of this node, so a world parented here would be drawn in the camera's
## transformed space and would slide when the camera moves. The slot is a plain
## sibling of the camera, which is what keeps world coordinates and screen
## coordinates the same thing.
func world_slot() -> Node2D:
	_bind_nodes()
	if _slot == null:
		# Created on demand, NOT silently: a caller that reaches here with no authored
		# `WorldSlot` would otherwise get a fresh empty node and read "the world layer
		# exists but holds nothing" — a shape indistinguishable from the wiring never
		# having happened. Minting the node here hid that; the scene authors it instead.
		push_error(
			(
				(
					"PlayfieldLayer: no node named '%s'; the scene must author the world slot, "
					+ "or a realized world is parented somewhere nobody can see"
				)
				% PlayfieldLayer.WORLD_SLOT
			)
		)
		_slot = Node2D.new()
		_slot.name = PlayfieldLayer.WORLD_SLOT
		add_child(_slot)
	return _slot


## The camera, created on demand so a headless reader that asks before `_ready`
## still gets a node it can inspect rather than null.
func camera() -> Camera2D:
	_bind_nodes()
	if _camera == null:
		_camera = _ensure_camera()
	return _camera


## Re-frame the playfield. `value` is a magnification: 2.0 shows half the world
## area 1.0 would. Clamped to a range that can still see the playfield, because
## a camera that can zoom to nothing is a way to lose the player.
func set_zoom(value: float) -> void:
	var clamped := clampf(value, MIN_ZOOM, MAX_ZOOM)
	var cam := camera()
	if cam == null:
		return
	cam.zoom = Vector2(clamped, clamped)


func zoom() -> float:
	var cam := camera()
	return 0.0 if cam == null else cam.zoom.x


## Bound the camera to `bounds` so it stops at the edge of a realized world
## instead of showing the void past it. Applied to the CAMERA limits only: the
## player body is clamped separately, because a camera that stops at the edge
## while the body walks on is the bounds bug WorldStage documents.
func set_bounds(bounds: Rect2) -> void:
	var cam := camera()
	if cam == null:
		return
	cam.limit_left = int(bounds.position.x)
	cam.limit_top = int(bounds.position.y)
	cam.limit_right = int(bounds.end.x)
	cam.limit_bottom = int(bounds.end.y)


## Everything this layer shows, as primitives, so a headless run can assert the
## world is mounted and framed without reading pixels.
func summary() -> Dictionary:
	_bind_nodes()
	if _slot == null and _camera == null:
		return {}
	var cam := camera()
	return {
		"zoom": 0.0 if cam == null else cam.zoom.x,
		"default_zoom": DEFAULT_ZOOM,
		"has_world": world_slot().get_child_count() > 0,
		"world_children": world_slot().get_child_count(),
		"camera_enabled": cam != null and cam.enabled,
		"camera_position": [] if cam == null else [cam.global_position.x, cam.global_position.y],
		"limits":
		(
			[]
			if cam == null
			else [
				cam.limit_left,
				cam.limit_top,
				cam.limit_right,
				cam.limit_bottom,
			]
		),
	}


## The camera as a child of THIS node, so panning the camera moves the VIEW and
## not the world. A camera parented to the world it watches would chase itself.
func _ensure_camera() -> Camera2D:
	var existing := get_node_or_null(^"Camera2D") as Camera2D
	if existing != null:
		existing.enabled = true
		return existing
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.enabled = true
	# The camera is added BEFORE the slot so the slot is drawn in world space and
	# the camera transforms only the view.
	add_child(cam)
	move_child(cam, 0)
	return cam
