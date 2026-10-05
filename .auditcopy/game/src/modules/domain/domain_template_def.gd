class_name DomainTemplateDef
extends Resource

## One authored domain TEMPLATE: the parameters a generator is allowed to work from
## (ADR 0050). Every magnitude here is AUTHORED DATA, never a value the generator
## computed from another number — a template that let the generator derive its own
## extent would make every template a special case of a curve nobody can edit.
##
## The template carries no rooms: `room_pool` is the SHARED room kit (ADR 0073), the
## same `RoomDef` resources a handcrafted domain is built from. A generated domain
## therefore has no separate vocabulary of shapes from a handcrafted one.
##
## `settlement` and `boss` are pinned by an author through `pins` and are NEVER
## auto-placed by the generator: they are STORY rooms, and a die that decides whether
## a town's tavern exists is a die nobody asked for.

## The authored id. Also the `DomainTemplateDef`'s identity in a content scan.
@export var template_id: StringName = &""

@export var display_name: String = ""

## The grid the generator partitions, in TILES. A zero component fails the generate
## loudly rather than falling back to a default the author did not choose.
@export var extent: Vector2i = Vector2i(48, 32)

## BSP. `min_leaf` is the smallest side a leaf may have; `max_depth` is a HARD cap —
## a cell at depth `max_depth` becomes a leaf without consulting the rng, so the leaf
## count is bounded even for a pathological rng sequence.
@export var min_leaf: int = 6

@export var max_depth: int = 5

## The fraction of a cell handed to its first child, per authored window. Splitting on
## the longer axis keeps the aspect ratio of a cell from drifting; the window keeps a
## split from producing a sliver.
@export var split_ratio_range: Vector2 = Vector2(0.4, 0.6)

## The chance of repeating the previous split axis instead of alternating. Authored:
## a strict alternation makes every tree perfectly regular and every map look tiled.
@export var repeat_axis_chance: float = 0.25

## Tiles of clear space kept inside every cell edge, so a corridor never runs through
## a room's wall.
@export var margin: int = 2

## Loop edges as a RATIO of the room count, then `loop_count` is resolved against it.
## `0.0` is a pure spanning tree — every room is reachable by exactly one path.
@export var loop_ratio: float = 0.12

## The most pairs of rooms this template will consider looping. A cap, so a large
## template cannot turn the candidate scan into the generator's whole runtime.
@export var max_loop_edges: int = 8

## The rectilinear gap, in TILES, two rooms may sit apart and still be loop
## candidates. Geometry, not a percentage of extent: it answers "close enough that a
## shortcut reads as one", which extent-independent.
@export var loop_gap_tiles: int = 6

## Corridor width in TILES. Corridors are drawn at this width between two room
## rects; `1` is a single-tile seam, which reads as a crack rather than a passage.
@export var corridor_tiles: int = 2

## Room-count bounds. Below `min_rooms` the generate fails loudly with the numbers.
@export var min_rooms: int = 4

@export var max_rooms: int = 24

## **"Every def this template carries is built on every seed, or the seed is REFUSED."**
##
## The opt-in half of the reachability claim. Carrying a def in `room_pool` says a
## player can reach it *somewhere*; it does not say every seed gets there. The
## generator deals the kit round-robin over the leaves a pin has NOT taken, so a seed
## whose leaves run out cannot build the tail of the kit at all — and a domain that
## silently drops one of its authored rooms is the failure this flag exists to refuse.
##
## Set it only where the template's own numbers guarantee it, i.e. where
## `min_rooms >= room_pool.size()` and every pin names a distinct pool def. It is
## OFF by default: a template with no pool, or with one whose defs exceed
## `min_rooms`, would refuse every seed and be a domain a player can never enter.
## `test_domain_template_leaf_budget.gd` asserts both directions — that the shipped
## templates satisfy the inequality this needs, and that a template breaching it
## refuses loudly rather than shipping a hole.
@export var requires_full_kit: bool = false

## The point the entry leaf is chosen by. A leaf whose INSIDE rect contains this
## point, else the lowest-index leaf in canonical order. Authored, never rolled.
@export var entry_anchor: Vector2i = Vector2i.ZERO

## The shared room kit this template draws from.
@export var room_pool: Array[RoomDef] = []

## Author-placed rooms. `settlement` and `boss` are pinned only; `entry`, `gate`,
## `arena` and `core` are placed BY RULE and an author pin on them is ignored.
@export var pins: Array[TemplatePin] = []


## The authored resolution of `loop_ratio`, clamped by `max_loop_edges` and by the
## number of candidate pairs the geometry actually produced. Derived from authored
## data only — no rng is consulted here or anywhere else in this class.
func loop_count_for(room_count: int) -> int:
	var want := int(round(float(room_count) * loop_ratio))
	return clampi(mini(want, max_loop_edges), 0, maxi(0, room_count - 2))


## The pin targeting `leaf_index`, or null. The first pin wins, so an author who pins
## the same index twice gets the first one, not a coin flip.
func pin_for(leaf_index: int) -> TemplatePin:
	for pin in pins:
		if pin.leaf_index == leaf_index:
			return pin
	return null


## Whether an author may place `room_kind` by pin. The structural kinds are placed by
## rule and an author pin on one is refused loudly rather than quietly overwriting
## geometry with a dice roll.
static func is_pinnable_kind(room_kind: StringName) -> bool:
	return room_kind == &"settlement" or room_kind == &"boss"
