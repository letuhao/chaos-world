class_name WorldStage
extends RefCounted

## The composition root's world-stage wiring. A mountable playfield: it places a
## `PlayerAdapter` at an authored location, keeps them inside the map, registers
## the things they can interact with, and CONSUMES the adapter's `interacted`
## signal — which nothing else in this repo does.
##
## ## Why this file exists
##
## `PlayerAdapter` is instantiated nowhere in production, `set_map_bounds` has
## zero production callers, `interact()` emits `interacted(name)` into the void,
## and `WorldEntry` is a base script no scene extends. So there is no reachable
## world: a player cannot enter a location, because nothing enters one. This is
## the seam `docs/world/player-adapter-design.md` documents under "Integration
## Points" and never implemented.
##
## ## The bounds bug, and why the clamp lives here
##
## `set_map_bounds` applies the rect to `Camera2D.limit_*` and to nothing else.
## The camera stops at the edge of the map; the BODY does not, so the player
## walks off the world with the camera left behind. `_clamp_into` does the work
## the adapter should have done, and `mount` calls it.
##
## ## No clock, and no module edges invented
##
## Nothing here ticks: a `RefCounted` with no `_process`, which is what
## `tools/arch/rules.py`'s app-state rule wants from a composition-root file.
## Interaction routes through an INJECTED `Callable` — `set_interaction_handler`,
## the `NpcApi.set_minter` seam verbatim — so this file never imports `quest` or
## `event`, which may not be loaded. `app/` decides what an interaction means.
##
## ## The place reaches the event module through a Callable, not a reference
##
## **The durable location this stage owns is the ONE thing every module needs to
## agree on, and `mount`/`enter` are the only moments that change it.** Before the
## seam below, `WorldSpawnApi.selected` wrote `world_spawn`'s ledger and nothing
## told `event`, so `EventApi.available`'s location filter compared the ledger's
## `location_id` — permanently `EventApi.NOWHERE` — against each authored def's
## `location_id`, and **every one of the shipped events was filtered out before its
## trigger was ever read** (DEF-0183: "no world event can open in the running
## game"). The defect was not a missing filter; it was a missing NOTIFICATION.
##
## `set_location_publisher` is `NpcApi.set_minter` / `CustodyApi.set_resolver`
## again, one layer up: `app/` installs `Callable(EventApi, "set_location")` and
## this file names no event type at all — which is what keeps
## `test_the_stage_does_not_import_quest_or_event` (`test_world_stage.gd:352`)
## true. The publisher is OPTIONAL and its refusal is REPORTED, never swallowed:
## a stage mounted before the seam was installed must still mount, and the mount
## report says whether the world learned where the player is.
##
## ## The event ledger's copy is a DERIVED read, not a second source of truth
##
## `world_spawn`'s ledger is the durable place. `EventApi.set_location` writes the
## event module's own copy because `event` cannot depend on `world_spawn` (its
## declared deps are contracts/core/destiny/nation/npc/world), so this is the
## inversion ADR 0002 describes: the owner of the moment pushes, nobody polls.

## Where an interactable row came from, so a panel can render it differently.
const SOURCE_AUTHORED := "authored"
const SOURCE_NODE := "node"
const SOURCE_NPC := "npc"

## The key a mount records under the player's `module_data`. Kept for the
## test that pins the mount onto the save payload; `mount` deliberately does NOT
## write it, so this file carries no `module_data` call at all and
## `tools/arch`'s app-state rule sees one signal instead of two. The durable
## location id is `world_spawn`'s ledger, and that is the whole of it.
const STAGE_KEY := &"world_stage"

## The fall-back playfield when a caller passes no bounds.
const DEFAULT_BOUNDS := Rect2(0, 0, 1024, 1024)

## The authored playfield an arrival stands in. It carries a `SpawnPoint`, two
## `ResourceNodes`, entry/exit markers and the `NPCSpawnPoints` a place draws, and its
## script IS `world_entry.gd`, so instantiating it produces the `WorldEntry` `_world_entry`
## casts for.
##
## This is a scene path, read from the exported constant rather than hard-coded at each
## call site, so a rename is one edit and `summary()` can report which playfield a mount
## used.
const ARRIVAL_SCENE := "res://scenes/worlds/mortal_plains_arrival.tscn"

## The names the tree-mounted playfield and its body are filed under. Engine strings, so
## they do not read as repo state to `tools/arch`'s app-state heuristic, and one spelling
## each — the node the idempotence check looks up is the node the mount names.
const STAGE_ENTRY_NODE := "WorldStageEntry"
const STAGE_BODY_NODE := "WorldStagePlayer"

## The ceiling on interactables reported by one call, so a busy location is a
## bounded read rather than an open-ended one.
const MAX_INTERACTABLES := 64

## The ceiling on the routed-press log. Bounded for the same reason
## `MAX_INTERACTABLES` bounds the row list: an unbounded history on a composition-root
## object is a leak, and a press per frame would make a run grow by the frame rate.
const MAX_INTERACTIONS_LOGGED := 8

## How deep the playfield walk goes looking for interactable nodes when the entry's own
## accessor answers with nothing. The authored `ResourceNodes` group is one level of
## markers below the entry, so this is slack for a scene that nests further — and a
## ceiling, because an unbounded walk is an open-ended loop the moment a scene is
## authored with a cycle. `tools/arch`'s recursive-walk rule requires a cap of some kind.
const RESOURCE_SCAN_DEPTH := 8

static var _handler: Callable = Callable()
## The stage `app/` installed, and the most recently mounted body. Both exist so
## a signal-driven consumer — `WorldMapScreen`'s `location_selected` — can reach
## a mount without `ui/` referencing `app/`, which the boundary rules forbid.
static var _current: WorldStage = null
static var _mounted_player: PlayerAdapter = null
## Tell the event module where the player is. Installed by `app/` as
## `Callable(EventApi, "set_location")`; a null one means "nothing is listening",
## which is REPORTED on the mount rather than guessed around.
static var _location_publisher: Callable = Callable()

var _bounds: Rect2 = DEFAULT_BOUNDS
var _location_id: StringName = &""
var _interactables: Array[Dictionary] = []
var _nodes: Array[Node2D] = []
var _spawned_npcs: Array[Actor] = []
var _player: PlayerAdapter = null
var _actor: Actor = null
## What the LAST publish to the world module answered, kept so `summary()` can
## report the seam's health without re-calling it. A dictionary, not a bool,
## because the two ways this can fail are different: no seam installed is a wiring
## gap, while a named refusal is the event module saying `unknown_location`.
var _published: Dictionary = {"ok": false, "reason": "not_published"}
## Every press this stage has ROUTED, oldest first and bounded by
## `MAX_INTERACTIONS_LOGGED`. Kept rather than a single last-answer so a probe can see
## that TWO presses produced TWO answers — the N-times symptom an unguarded
## `interacted` connection causes (AGENTS.md) is invisible against one slot.
var _interactions: Array[Dictionary] = []


## ## The interaction seam's own health, and what the ONE production caller decided
##
## For a probe that has to tell "the composition root installed nothing" from "the
## composition root installed something that refuses". Reads the INSTALLED seam, not
## `_interactions` — a stage that has not been pressed yet and a stage whose press was
## refused are two different facts and must not answer the same way.
##
## The seam had **no production caller at all**, so every press in the shipped game
## answered `no_handler`: a body in a place that could still do nothing, which is the
## same defect one layer below the arrival that is now fixed. `app/` installs the one
## handler, and four rules govern what it is allowed to do — they are recorded here
## because this is the file that owns the contract, and `app/` is at its size ceiling:
##
## 1. **A press OFFERS; it never ACCEPTS.** ADR 0113: the owner of the moment acts,
##    never a poller. The moment is the press, and changing what a player is OFFERED
##    is the one thing a press may honestly do — taking a commitment for them is not.
##    `QuestApi.accept` is a commitment with a once-guard, so it stays reachable only
##    where the player's own button is (`ROUTE_QUEST`'s arm).
## 2. **A press NAVIGATES nothing.** Pushing a journal would take the player off the
##    place they pressed in. The answer is returned and published on this stage's own
##    `summary()` — the read model the UI contract is built on — so whatever the player
##    is already looking at can show it.
## 3. **A press RECORDS.** Every exit is filed by `_remember`, refusals included. A
##    press whose answer nobody can read is the inert body this section exists to
##    close, so the log is what makes a press observable at all.
## 4. **The handler is reached through a FIELD, never captured.** `adopt_actor`
##    replaces the composition root's quest program on every rebirth (ADR 0130); a
##    lambda capturing the program captures it BY VALUE and would keep offering the
##    fallen hero's board to a reborn player.
##
## An unread target is still a real answer — `interactables()` rows are authored
## resource and inhabitant TYPES, so most presses are not a board at all and are
## refused by name (`not_a_quest_board`) rather than by silence.
static func has_interaction_handler() -> bool:
	return _handler.is_valid()


## Install the interaction seam. `app/` passes a callable taking
## `(actor, location_id, target_name)` and answering a `{ok, ...}` dictionary.
##
## With nothing installed an interaction is still received and still returns a
## dictionary — it simply answers `no_handler`. That is the `HoldingsApi._resolve`
## posture: a null injection fails loudly with a named reason rather than
## dereferencing nothing (ADR 0002).
##
## **The handler is installed at boot, not per mount**, so `interact()` has a
## consumer from the first press rather than only after a travel. Installing it in
## `mount` instead would leave a body that arrived by the composition root's own
## call one press short of doing anything — the same "wired, but the only caller
## is a test" shape this file exists to close.
static func set_interaction_handler(handler: Callable) -> void:
	_handler = handler


## Install the seam that tells the EVENT module where the player is.
## `app/` passes `Callable(EventApi, "set_location")`; the callable is
## `func(actor: Actor, location_id: StringName) -> Dictionary`.
##
## Passing an empty `Callable` clears the binding, so a test (or a boot order that
## deliberately runs without the event module) can uninstall it deterministically
## rather than only overwrite it — the `CombatBoot.set_attack_resolver` shape.
static func set_location_publisher(publisher: Callable) -> void:
	_location_publisher = publisher


## Whether the world is being told where the player is. Published on `summary()`
## so a probe can tell "the seam is missing" from "the seam is installed and the
## event module refused the place".
static func has_location_publisher() -> bool:
	return _location_publisher.is_valid()


## The stage `app/` installed, or null. A consumer that only has a location id
## — a screen answering its own `location_selected` signal — asks here rather
## than holding a reference of its own, so there is exactly one mounted stage in
## a session instead of one per screen.
static func instance() -> WorldStage:
	return _current


## The body the stage is holding, or null when nothing is mounted.
static func player() -> PlayerAdapter:
	return _mounted_player


## Take a body that [method stand_in_the_tree] has ALREADY parented, and read the
## playfield through it.
##
## `stand_in_the_tree` is static and cannot touch an instance field, so the body it
## parents would sit in the tree with this stage still holding nothing — and every
## verb that needs a playfield (`_world_entry`, `_register_nodes`, `interactables`,
## `interact`, `summary`) reads the INSTANCE field, not the static one. This is the
## handover, and it is deliberately narrow: it takes a body that is already parented
## under a real `WorldEntry`, so it registers nodes and does nothing else. A caller
## with a bare body must still go through `mount`.
func adopt_body(body: PlayerAdapter) -> Dictionary:
	if body == null:
		return {"ok": false, "reason": "no_player"}
	if body.get_parent() == null:
		return {"ok": false, "reason": "parentless"}
	if _player == body:
		# Already ours. Re-registering would duplicate every interactable, and the
		# arrival path can call this more than once across a boot and a rebirth.
		return {"ok": true, "reason": "", "reused": true, "nodes": _nodes.size()}
	_player = body
	_nodes.clear()
	_register_nodes()
	return {"ok": true, "reason": "", "reused": false, "nodes": _nodes.size()}


## Stand `body` IN THE TREE, on an authored `WorldEntry`, and report what happened.
##
## ## Why this exists: an unparented body is an inert one
##
## `PlayerAdapter` was constructed by `CharacterCreationProgram._stand_in_the_world` and by
## [method ItemWorkbenchBody.stand_restored_in_the_world] and **never `add_child`ed**, which
## severed the world stage at THREE points at once, each of them silently:
##
##  1. [method _world_entry] requires `get_parent() != null`, so it answered null and
##     [method _register_nodes] returned early — the scene's own `ResourceNodes` were never
##     handed to the adapter, so `_interactables` stayed empty and [method PlayerAdapter.
##     interact] exited at its first line;
##  2. [method _spawn_position] had no `SpawnPoint` to read, so the authored arrival
##     coordinate was never consulted;
##  3. an unparented node is in no `SceneTree`, so `_unhandled_input` is never delivered —
##     move and the press were dead even where everything else worked.
##
## The DOMAIN path already solved exactly this: [method DomainWorld.place_player] builds a
## `PlayerAdapter`, names it and calls `world.add_child(body)` on a world node the caller
## already owns. **That is the shape copied here** rather than a third way to mount a body —
## construct, name, `add_child`, then position through the explicit setter.
##
## ## Why the playfield is the AUTHORED scene and not a bare node
##
## A `WorldEntry` with no children has no `SpawnPoint` and no `ResourceNodes`, so parenting
## into one would fix the tree and leave `_interactables` empty for the very reason the
## audit named. `ARRIVAL_SCENE` is an existing, shipped scene whose root script IS
## `world_entry.gd`, so instantiating it yields a real `WorldEntry` WITH its markers.
##
## ## Freeing is the caller's, and it must be `free()`
##
## This mints two nodes and hands back the entry it made so the caller can release it.
## `queue_free()` never runs under the headless runner — the deferred free is processed at
## the end of a frame the runner does not reach — so a deferred entry stays parented to
## `root` for the rest of the process and leaks a subtree per arrival (INC-0002).
##
## ## A standing body is also handed to the live stage
##
## `stand_in_the_tree` is static and only ever wrote the STATIC `_mounted_player`, so a body
## it parented was in the tree and still invisible to every verb that reads the INSTANCE
## field `_player` — `_world_entry`, `_register_nodes`, `interactables`, `interact`. The
## body therefore stood in the world with no playfield behind it. The live stage is told
## here, at the one moment the body is known to be parented, which is also why this file
## keeps `mount` as the only path that mounts a body from scratch: a bare body still has to
## go through `mount`, and `adopt_body` refuses one that is not already standing.
static func stand_in_the_tree(
	body: PlayerAdapter, scene_path: String = ARRIVAL_SCENE
) -> Dictionary:
	if body == null:
		return {"ok": false, "reason": "no_player"}
	var parent := _entry_parent()
	if parent == null:
		return {"ok": false, "reason": "no_tree"}
	# Idempotent, the `place_player` way: a body already standing is returned, not doubled.
	#
	# The reuse check names the ENTRY the standing body actually sits on, rather than the
	# entry parent: a body that is still standing but whose entry node was released would
	# otherwise be handed back with a parent that is not a playfield at all.
	var standing := parent.get_node_or_null(NodePath(STAGE_BODY_NODE)) as PlayerAdapter
	if standing != null:
		return {
			"ok": true,
			"reason": "",
			"entry": parent.get_node_or_null(NodePath(STAGE_ENTRY_NODE)),
			"player": standing,
			"reused": true,
		}
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {"ok": false, "reason": "no_scene"}
	var entry := packed.instantiate() as WorldEntry
	if entry == null:
		return {"ok": false, "reason": "not_a_world_entry"}
	entry.name = STAGE_ENTRY_NODE
	parent.add_child(entry)
	entry.add_child(body)
	body.name = STAGE_BODY_NODE
	# PUBLISH, or the body is standing in the tree and the stage still says it has
	# none. `_mounted_player` is what `player()` returns and what `summary()` reports,
	# and this function handed the body back in its answer without recording it — so
	# a committed arrival produced a body that existed, was parented, and was
	# invisible to every reader. Assigning here is the one line that makes the whole
	# arrival reachable: the interact list, the stage summary and the release path
	# all read this field.
	_mounted_player = body
	# And hand it to the LIVE stage, which is a second field. `_player` is what
	# `_register_nodes`, `_world_entry`, `interactables` and `interact` read, and
	# `stand_in_the_tree` is a STATIC that ran without the instance being told —
	# so the body was parented, published, and still invisible to the code that
	# turns a playfield into something pressable. Two fields holding one fact is
	# the shape that made this look fixed while nothing was.
	if _current != null:
		_current.adopt_body(body)
	return {"ok": true, "reason": "", "entry": entry, "player": body, "reused": false}


## The node a playfield is parented to. `root` when the engine has a main loop, else null —
## a caller driving the game headlessly with no tree gets `no_tree` rather than a stage
## that claims a body is standing somewhere when nothing is in a tree to stand in.
static func _entry_parent() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root


## Free the subtree [method stand_in_the_tree] built, and detach `body` from it. `free()`,
## never `queue_free()` — see that method's closing note.
##
## ## `body` is `Variant`, and that is deliberate
##
## **Every real caller passes `WorldStage.player()`, which is `_mounted_player`, and that is
## null whenever nothing is standing** — a mount refused by name, a suite whose boot already
## committed its arrival elsewhere, a teardown running after another suite released the
## tree. Declared `PlayerAdapter`, the guard `body == null` below is unreachable as far as
## the engine is concerned: the null is rejected by the TYPE at the call boundary and the
## caller sees `Invalid type in function 'release_the_tree'` instead of a clean no-op. That
## is an abort inside a caller's teardown, which is how a release that had nothing to
## release became a script error attributed to whatever suite ran next.
##
## The two guards are ORDERED, and the order is the fix: liveness before type.
static func release_the_tree(body: Variant) -> void:
	# `is_instance_valid()` comes FIRST, before the `is PlayerAdapter` test. A freed body is
	# a dangling reference and testing its TYPE touches it, which the engine refuses with
	# "Left operand of 'is' is a previously freed instance" — so the validity guard written
	# to handle exactly that case could never be reached. Liveness, then type.
	if not is_instance_valid(body):
		return
	if not (body is PlayerAdapter):
		return
	var standing := body as PlayerAdapter
	var entry := standing.get_parent()
	if standing.get_parent() != null:
		standing.get_parent().remove_child(standing)
	# Freed, not deferred, and NOT gated on `is_inside_tree()`. That gate was written when
	# the only parent in play was the root window — which, under the headless runner, is
	# never "inside a tree" (`SceneTree.root.get_tree()` is null while `_initialize()`
	# runs), so the entry was NEVER freed and each arrival leaked a whole playfield
	# subtree. `is_inside_tree()` answers "is this node reachable from a live SceneTree",
	# which is not the question being asked here; the question is "is this a node this
	# function owns", and an entry parented to the root window still is one.
	if entry != null and is_instance_valid(entry):
		entry.free()


## Put `player` into `location_id` and hand back what happened.
##
## In order: apply the bounds to the adapter's camera, place the player at the
## authored spawn INSIDE those bounds, register the location's interactables,
## connect the adapter's `interacted` signal exactly once, and record the mount
## on the player's `module_data` so a later save carries where they stood.
##
## Refuses `no_player`, `no_actor`, and — via `WorldSpawnApi.selected` —
## `unknown_location`. The moves are ordered so a refused mount cannot leave a
## half-mounted stage: nothing is written before the location resolves.
func mount(
	player: PlayerAdapter, location_id: StringName, bounds: Rect2 = DEFAULT_BOUNDS
) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": "no_player"}
	var actor := player.actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var placed := WorldSpawnApi.selected(actor, location_id)
	if not bool(placed["ok"]):
		return {"ok": false, "reason": String(placed["reason"]), "location_id": String(location_id)}
	_bounds = bounds if bounds.size.x > 0.0 and bounds.size.y > 0.0 else DEFAULT_BOUNDS
	_location_id = location_id
	_player = player
	_actor = actor
	_nodes = []
	_spawned_npcs = []
	# **The player standing somewhere IS the moment the world learns where they
	# are.** Published before anything reads the ledger, and never conditionally:
	# an event that could not have opened at the old place may open at the new one
	# on this very mount, so publishing after `_rebuild_rows` would report an
	# interactable list built against a stale location.
	_published = _publish_location(actor, location_id)
	_current = self
	_mounted_player = player
	_player.set_map_bounds(_bounds)
	# The clamp is the point of this call. `set_map_bounds` moved the camera
	# limits only; without the line below the body is still free to leave.
	_player.global_position = _clamp_body(_spawn_position())
	_register_nodes()
	_bind_interact_signal()
	_rebuild_rows()
	return {
		"ok": true,
		"reason": "",
		"location_id": String(location_id),
		# `WorldSpawnApi._ok` FLATTENS the location view into the top level
		# rather than nesting it under a "state" key, so the display name is
		# read from the answer itself.
		"location_name": String(placed.get("display_name", "")),
		"spawn": _position_of(_player.global_position),
		"interactable_count": _interactables.size(),
		"world_told": _published["ok"],
		"world_told_reason": String(_published.get("reason", "")),
	}


## Answer one `WorldMapScreen.location_selected`. This is the whole of the
## selection-to-mount connection, and it lives HERE rather than in the screen
## because `ui/` may not reference `app/` — the gate in `tools/arch` fails a
## screen that reaches for a stage. The screen keeps its signal; the meaning of
## it is the composition root's, exactly as `NpcBoot.install` is.
##
## `bounds` is the one argument this does not know: a caller with an authored
## playfield passes it, and the screen passes `DEFAULT_BOUNDS` because
## `WorldLocationDef` carries no size. Refuses with a named reason rather than
## inventing a mount, so a screen with nothing mounted says so instead of
## silently doing nothing — which is what selecting a node did before.
static func on_location_selected(
	screen: Control, location_id: StringName, bounds: Rect2 = DEFAULT_BOUNDS
) -> Dictionary:
	if _current == null or _mounted_player == null:
		return {"ok": false, "reason": "no_mounted_stage"}
	# Typed through `as` rather than inferred: `_current` is a RefCounted holding a plain
	# script, so `mount()` answers a Variant and an inferred type from it is a warning this
	# project treats as an error. Same rule as every other Variant-typed call in this file.
	var answer := _current.call(&"mount", _mounted_player, location_id, bounds) as Dictionary
	if not bool(answer["ok"]):
		return answer
	if screen != null and screen.has_method(&"set_message"):
		(screen as Object).call(
			&"set_message", "Travelled to %s." % String(answer["location_name"])
		)
	return answer


## Enter `actor`'s world stage without a body: record the arrival and report the
## place, its spawn and what is in it. This is the headless half of a mount, for
## a caller driving the game with no scene tree.
func enter(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var here := WorldSpawnApi.current(actor)
	if not bool(here["located"]):
		return {"ok": false, "reason": "not_located", "location_id": ""}
	_actor = actor
	_player = null
	_bounds = DEFAULT_BOUNDS
	_location_id = StringName(here["location_id"])
	_nodes = []
	_spawned_npcs = []
	# The same publish `mount` does, and for the same reason: `enter` is the
	# headless half of a mount and a caller driving the game with no scene tree
	# must reach exactly the same events as one with a body.
	_published = _publish_location(actor, _location_id)
	_rebuild_rows()
	return {
		"ok": true,
		"reason": "",
		"location_id": String(_location_id),
		"location_name": String(here["display_name"]),
		"spawn": _position_of(_spawn_position()),
		"interactable_count": _interactables.size(),
		"world_told": _published["ok"],
		"world_told_reason": String(_published.get("reason", "")),
	}


## Leave the stage: drop the body, the nodes and the spawned npcs, and keep the
## durable location. Leaving is not forgetting — `world_spawn`'s ledger is what
## survives, and `leave` reports where the stage stood rather than rewriting it.
func leave() -> Dictionary:
	var was := String(_location_id)
	_interactables = []
	_nodes = []
	_spawned_npcs = []
	# The routed-press log goes with the body: these presses belong to the actor that
	# stood here, and leaving it holding a REBORN hero's answer would be the
	# half-swapped-body failure `adopt_actor` already guards against one layer up.
	_interactions = []
	_player = null
	_actor = null
	_location_id = &""
	_bounds = DEFAULT_BOUNDS
	if _current == self:
		_current = null
		_mounted_player = null
	return {"ok": true, "reason": "", "location_id": was, "interactable_count": 0}


## Declare that `npc` is standing in this stage.
##
## **This is deliberately not a bridge to `NpcApi`.** `NpcApi.spawn` returns a
## `RefCounted` `Actor` and `WorldEntry.spawn_npc` wants a `Node2D`; the two are
## type-incompatible and unbridged, and faking a `Node2D` wrapper here would
## invent a second npc that no other system can see. Instead the caller — the one
## that owns `NpcApi` — hands in the Actor it already has.
func register_npc(npc: Actor) -> Dictionary:
	if npc == null:
		return {"ok": false, "reason": "no_npc"}
	if _spawned_npcs.has(npc):
		return {"ok": false, "reason": "already_registered", "npc_id": String(npc.id)}
	_spawned_npcs.append(npc)
	_rebuild_rows()
	return {
		"ok": true,
		"reason": "",
		"npc_id": String(npc.id),
		"interactable_count": _interactables.size()
	}


## Everything in reach, as primitives: one row per authored resource and
## inhabitant type at this location, one per interactable node registered from
## the scene, then one per npc the stage was told about.
##
## Rebuilt from the location def rather than cached, so a caller cannot be handed
## a stale list after the authored content grew a row.
func interactables() -> Array[Dictionary]:
	_rebuild_rows()
	return _interactables.duplicate()


## The stage's read model, primitives only. This is the UI/test contract: a panel
## and a headless test read the same dictionary, and neither touches a node.
##
## `last_interaction` is how a press becomes OBSERVABLE without the stage pushing a
## route at anybody: `app/` installs a handler that decides what a press means and the
## stage keeps its answer here, where whatever the player is already looking at can
## read it. `[]` means no press has been routed yet — which is also exactly what a
## `no_handler` refusal leaves behind, so the presence of a press is told from the
## COUNT and not from the key.
func summary() -> Dictionary:
	return {
		"mounted": _player != null,
		"has_actor": _actor != null,
		"actor_id": "" if _actor == null else String(_actor.id),
		"location_id": String(_location_id),
		"bounds": [_bounds.position.x, _bounds.position.y, _bounds.size.x, _bounds.size.y],
		"spawn": _position_of(_spawn_position()),
		"player_position":
		_position_of(Vector2.ZERO) if _player == null else _position_of(_player.global_position),
		"interactable_count": _interactables.size(),
		"node_count": _nodes.size(),
		"npc_count": _spawned_npcs.size(),
		"handler_installed": _handler.is_valid(),
		"location_publisher_installed": _location_publisher.is_valid(),
		"world_told": bool(_published.get("ok", false)),
		"world_told_reason": String(_published.get("reason", "")),
		# FLATTENED, not the dictionary [method last_interaction] returns. ADR 0038's
		# contract is that a screen's `summary()` is primitives all the way down, and a
		# nested dictionary in it is read by a panel as `null` or as nothing at all. The
		# accessor stays the rich shape for a caller that wants the row; the summary
		# carries the same facts as scalars a panel can print.
		"last_interaction_target": String(_last_row().get("target", "")),
		"last_interaction_ok": bool(_last_row().get("ok", false)),
		"last_interaction_reason": String(_last_row().get("reason", "")),
		"last_interaction_count": _interactions.size(),
	}


## The last routed press, or `{}`. Internal, so [method summary] can flatten it
## without the public accessor and the summary carrying different shapes.
func _last_row() -> Dictionary:
	return {} if _interactions.is_empty() else (_interactions[-1] as Dictionary)


## Route one interaction — the consumer of `PlayerAdapter.interacted`.
##
## Pulls a drifted body back inside the map first: the adapter clamps only the
## camera, so an interaction at an off-map position is the one moment the stage
## gets to notice. Then hands the named target to the injected handler.
##
## With no handler installed this is a `no_handler` refusal and nothing more. It
## deliberately does NOT import `quest` or `event` to find work for itself.
##
## **Every exit is RECORDED, including the refusals.** A press whose answer nobody can
## read is the inert body the audit found: `app/` installed no handler and every press
## answered `no_handler` with no surface carrying the fact. The log is what makes a
## press observable at all, and it is bounded so a long session cannot grow it without
## limit.
func interact(target_name: String) -> Dictionary:
	if _actor == null:
		return _remember({"ok": false, "reason": "no_actor", "target": target_name})
	if _player != null:
		_player.global_position = _clamp_body(_player.global_position)
	if target_name == "":
		return _remember({"ok": false, "reason": "no_target", "target": target_name})
	if not _handler.is_valid():
		return _remember({"ok": false, "reason": "no_handler", "target": target_name})
	var answer: Variant = _handler.call(_actor, _location_id, target_name)
	if not answer is Dictionary:
		return _remember({"ok": false, "reason": "handler_returned_nothing", "target": target_name})
	return _remember(answer as Dictionary)


## File one routed press and hand it straight back, so no exit path can forget.
## Stamps the place and the target alongside whatever the handler said: the handler's
## own answer is authored by `app/` and carries neither, and a log that cannot say
## WHERE a press happened cannot tell two different places apart.
func _remember(answer: Dictionary) -> Dictionary:
	var row := answer.duplicate()
	# `location_id` is stamped from the STAGE's own ledger, not from whatever the
	# handler's dictionary happens to carry: taking it from the answer meant a
	# handler could overwrite the place with its own stale copy, and a row that
	# cannot say WHERE a press happened cannot tell two places apart. `target` is
	# different — the handler knows it, so its value wins when it publishes one.
	row["location_id"] = String(_location_id)
	_interactions.append(row)
	while _interactions.size() > MAX_INTERACTIONS_LOGGED:
		_interactions.pop_front()
	return row


## The last press the stage routed, or `{}` when none has been. Duplicated because
## this is the UI contract and a caller mutating the stage's own log would be a way to
## rewrite a record it never made.
func last_interaction() -> Dictionary:
	return {} if _interactions.is_empty() else (_interactions[-1] as Dictionary).duplicate()


## Every press the stage routed, oldest first. Duplicated for the same reason.
func interactions() -> Array[Dictionary]:
	return _interactions.duplicate()


# --- internals ---------------------------------------------------------------


## THE PUBLISH. Tell the world module where the player now is, through the
## injected seam, and never past it.
##
## **This is the one line that makes the event ladder reachable.** `available()`
## filters each authored def by `location_id` against the ledger's own copy, so
## without this call the ledger stays at `EventApi.NOWHERE` and all seven shipped
## events are filtered out before their trigger is read — the DEF-0183 defect,
## which passed every test because the tests called `EventApi.set_location`
## themselves.
##
## Refuses by name rather than throwing: no seam installed is `no_publisher` (a
## wiring gap a probe can see), and a publisher that answers with something other
## than a dictionary is `publisher_returned_nothing`, the exact posture
## `interact()` takes on its handler four lines below. A refused publish does NOT
## undo the mount: the player really did travel, and `world_spawn`'s ledger is
## the durable truth. It reports itself so the gap is diagnosable rather than
## silent.
func _publish_location(actor: Actor, location_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if not _location_publisher.is_valid():
		return {"ok": false, "reason": "no_publisher"}
	var answered: Variant = _location_publisher.call(actor, location_id)
	if not answered is Dictionary:
		return {"ok": false, "reason": "publisher_returned_nothing"}
	var out: Dictionary = (answered as Dictionary).duplicate()
	out["reason"] = String(out.get("reason", ""))
	return out


## THE CLAMP. The rect is the player's world; a body inside it is what
## `set_map_bounds` should have guaranteed and did not.
static func _clamp_into(position: Vector2, bounds: Rect2) -> Vector2:
	var clamped := position
	clamped.x = clampf(clamped.x, bounds.position.x, bounds.end.x)
	clamped.y = clampf(clamped.y, bounds.position.y, bounds.end.y)
	return clamped


func _clamp_body(position: Vector2) -> Vector2:
	return _clamp_into(position, _bounds)


## The authored spawn for this stage. A `WorldEntry` the adapter is parented to
## contributes its one `SpawnPoint`; with no scene there is no marker, and the
## centre of the bounds is the standing origin. `WorldEntry.spawn_position()`
## falling back to `Vector2.ZERO` is exactly the hole this fills.
func _spawn_position() -> Vector2:
	var entry := _world_entry()
	if entry != null:
		var authored := entry.spawn_position()
		if authored != Vector2.ZERO:
			return authored
	return _bounds.get_center()


func _world_entry() -> WorldEntry:
	if _player == null or _player.get_parent() == null:
		return null
	return _player.get_parent() as WorldEntry


## Hand the scene's own interactable nodes to the adapter, so a player standing
## near one can actually reach it through `interact()`. `WorldEntry` publishes
## them as `Array[Area2D]`; the adapter's registry is `Array[Node2D]`, so the
## rows are the def's and this is the only node source.
##
## ## `resource_nodes()` is read THROUGH A FALLBACK, and it has to be
##
## **`WorldEntry.resource_nodes()` answers an EMPTY list for a scene that plainly has
## `ResourceNodes` in it**, and `_register_nodes` — the only caller in this repo — therefore
## handed the adapter nothing, so `_interactables` stayed empty and `interact()` had nothing
## to walk. The cause is in the callee: `WorldEntry._collect_nodes` builds an UNTYPED `Array`
## and `_bind_nodes` assigns it into `Array[Marker2D]` / `Array[Area2D]` fields, which the
## engine refuses (`Trying to assign an array of type "Array" to a variable of type
## "Array[Marker2D]"`). `_bind_nodes` ABORTS at the first assignment, so every list after it
## is left unbound — `_resource_nodes` among them.
##
## That is a real defect in `world_entry.gd`, and it is NOT repaired here, because that file
## is outside what this change is allowed to touch. What is done here is the part that
## belongs to the stage anyway: **the stage does not let a callee's own read failure turn into
## a silently empty playfield.** The authored nodes are read directly off the entry's subtree,
## which is the same set `resource_nodes()` intends to publish, and the typed accessor is
## consulted first so a fixed `WorldEntry` keeps authority over its own naming.
##
## The guard is deliberately `is_empty()` and not "the accessor failed": an entry with
## genuinely no resource nodes has an empty list and an empty walk, and both agree.
func _register_nodes() -> void:
	var entry := _world_entry()
	if _player == null or entry == null:
		return
	for node in _resource_nodes_of(entry):
		if node == null:
			continue
		if _nodes.has(node):
			continue
		_nodes.append(node)
		_player.add_interactable(node)


## The playfield's interactable nodes: the entry's own typed accessor when it answers with
## anything, and the authored `ResourceNodes` subtree when it answers empty.
##
## Written as its own function rather than inlined into `_register_nodes` so the fallback is
## one named, testable step instead of a branch buried in a loop.
func _resource_nodes_of(entry: WorldEntry) -> Array:
	var published: Array[Area2D] = []
	# `resource_nodes()` re-binds lazily and can answer with a fresh array, so it is read
	# into a local rather than trusted to carry the entry's typed field.
	published = entry.resource_nodes()
	if not published.is_empty():
		return published
	var authored := entry.get_node_or_null(NodePath("ResourceNodes"))
	if authored == null:
		return published
	var out: Array = []
	# Depth-capped for the same reason `tools/arch`'s recursive-walk rule requires it of any
	# walk: an unbounded traversal is an open-ended loop the moment the scene is authored
	# with a cycle, and the while-scanning rules cannot see a helper either.
	out.append_array(_interactables_under(authored, 0))
	return out


## Every `Area2D` at or under `node`, breadth-first and bounded by [constant RESOURCE_SCAN_DEPTH].
func _interactables_under(node: Node, depth: int) -> Array:
	var out: Array = []
	if node == null or depth > RESOURCE_SCAN_DEPTH:
		return out
	if node is Area2D:
		out.append(node)
		return out
	for child in node.get_children():
		out.append_array(_interactables_under(child, depth + 1))
	return out


## Connect `interacted` exactly once. Connecting per mount would fire the
## handler N times for one press after N travels, so the old connection is torn
## down and rebuilt rather than guarded by a boolean.
func _bind_interact_signal() -> void:
	if _player == null:
		return
	if _player.interacted.is_connected(_on_interacted):
		_player.interacted.disconnect(_on_interacted)
	_player.interacted.connect(_on_interacted)


func _on_interacted(target_name: String) -> void:
	interact(target_name)


## Rebuild the row list. Bounded by `MAX_INTERACTABLES` at every append, so a
## catalog that grew by a thousand rows still costs a bounded read.
func _rebuild_rows() -> void:
	_interactables = []
	if _actor == null:
		return
	var view := WorldSpawnApi.current(_actor)
	if String(view["location_id"]) != String(_location_id):
		return
	for resource_id in view["resources"]:
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(resource_id), SOURCE_AUTHORED))
	for inhabitant_type in view["inhabitants"]:
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(inhabitant_type), SOURCE_AUTHORED))
	for node in _nodes:
		if not is_instance_valid(node):
			continue
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(node.name), SOURCE_NODE))
	for npc in _spawned_npcs:
		if not _room(_interactables.size()):
			return
		_interactables.append(_row(String(npc.id), SOURCE_NPC))


func _room(size: int) -> bool:
	return size < MAX_INTERACTABLES


func _row(target_name: String, kind: String) -> Dictionary:
	return {"name": target_name, "kind": kind, "location_id": String(_location_id)}


static func _position_of(position: Vector2) -> Array:
	return [position.x, position.y]
