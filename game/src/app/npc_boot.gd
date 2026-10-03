class_name NpcBoot
extends RefCounted

## The composition root's npc wiring (ADR 0074, ADR 0092). Wiring, not rules: `app/`
## injects the constructor and binds the roster; the `npc` module owns what tracking,
## staging and spawning mean.
##
## ## Why this file exists
##
## `NpcApi.spawn` needs two things the module cannot know for itself: a constructor to
## mint an `Actor`, and the player whose `module_data` carries the roster. `set_minter`
## and `attach` are the injection points, and until something called them `spawn` was a
## facade method that could only ever return null. A feature nobody can start is
## decoration — the same failure ADR 0089 measured for statuses.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. Decay is driven from `StatusLoop`, which is already the
## composition root's single time wire (ADR 0089); inventing a second `_process` would
## be the stateful-`app/` shape `tools/arch/rules.py` rejects. `attach` is idempotent, so
## calling it on boot and again after a load is the intended usage, not a mistake.


## Install the constructor and bind the roster to `player`. Safe to call again after a
## load: `attach` rebuilds the live registry and re-announces the restored cast.
static func install(player: Actor) -> void:
	if player == null:
		return
	# The one place that knows the concrete constructor. Passing the facade verb as a
	# Callable keeps `npc/` free of any reference to `ActorFactory` (ADR 0002).
	# The one place that knows the concrete constructor. Handing the facade the
	# static function itself, rather than a lambda that forwards to it, is what
	# `npc/` needs to stay free of any reference to `ActorFactory` (ADR 0002) —
	# and it is also the only form the engine boots: a typed lambda whose body
	# calls into another script's static function killed the process with an
	# access violation on the shell's first frame, with nothing in the log.
	# `spawn_npc` takes the minter's two arguments positionally and defaults the
	# rest, so the direct Callable and the former wrapper were equivalent.
	NpcApi.set_minter(ActorFactory.spawn_npc)
	NpcApi.attach(player)


## Advance every social bond's decay by `delta` seconds. Called from the same tick that
## drives `Actor.tick_statuses`, because a bond that decays on a different clock from a
## status that expires is a bond whose timing nobody can reason about.
##
## Returns the number of bonds this actor holds, so a caller can tell "no bonds, nothing
## to age" from "aged one", and a broken clock shows up as a zero rather than as silence.
static func tick(actor: Actor, delta: float) -> int:
	if actor == null or delta <= 0.0:
		return 0
	var state := SocialApi.social_state(actor)
	if state == null:
		return 0
	var before := state.bond_count()
	SocialApi.tick(actor, delta)
	return before


## Stock a room with its authored population and report who is standing there. The one
## entry point a room load calls.
##
## `install` runs first and it DOES clear the live registry, which is the point here: a
## room load is entitled to replace the cast, and `populate`'s own `replace_first` then
## mints the new one. A read never does this — see `read_model`.
static func populate_room(
	player: Actor,
	def_ids: Array[StringName],
	role: StringName = &"npc",
	location_id: StringName = &""
) -> Dictionary:
	install(player)
	var spawned := NpcApi.populate(def_ids, role)
	return {
		"spawned": spawned.size(),
		"location_id": String(location_id),
		"npcs": NpcApi.presence_here(location_id).get("npcs", []),
	}


## The whole npc read model for one screen: who is here, and who the player has met.
##
## Deliberately does NOT call `install`. This is a read, and `install` -> `attach` clears
## the live registry — so a panel polling for state would empty the room it is rendering.
## A read binds nothing; it reads whatever the last `install` left in place.
static func read_model(player: Actor) -> Dictionary:
	var roster := NpcApi.state(player)
	return {
		"has_actor": player != null,
		"roster": roster,
		"here": NpcApi.presence_here(),
		"bond_with": SocialApi.summary(player),
	}
