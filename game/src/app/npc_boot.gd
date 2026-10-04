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
## ## The cast is CONTENT, and it is read here (BL-0626)
##
## `install` is the one seam that runs before anything can spawn, so it is where the
## authored tree is read. Before this, `NpcCatalog` was filled only by `install(defs)`
## — a TEST seam — so `NpcApi.spawn` refused every id at `api.gd:131` and a player
## could meet nobody. The read is a `load_authored()` scan, not a literal list, so a new
## cast member is a `.tres` and never a code edit (ADR 0074).
##
## It runs BEFORE the null guard on purpose: the cast is process-wide content and is
## not per-player, so an `install(null)` still brings the shipped tree in rather than
## leaving the catalog empty for the next caller. Reading it does not `attach` anything
## and touches no actor, so it cannot half-bind a roster the way `set_minter` + `attach`
## could.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. Decay is driven from `StatusLoop`, which is already the
## composition root's single time wire (ADR 0089); inventing a second `_process` would
## be the stateful-`app/` shape `tools/arch/rules.py` rejects. `attach` is idempotent, so
## calling it on boot and again after a load is the intended usage, not a mistake.


## ## It also closes the EVENT SEAM, because the composition root is where inversions live
##
## Two injections, both the `set_minter` shape ADR 0002 describes:
##
## 1. **`EventBeatWriter.set_tally_resolver(Callable(NpcApi, "tally"))`.** An authored
##    `npc_tally` beat used to be written into `module_data["npc_state"]` by the event
##    module itself — a second writer for a table `NpcApi.tally` owns, so the
##    `advance_verb` check and the `MAX_TALLY_KEYS` cap applied to one path and not the
##    other. `event/` cannot name `NpcApi` (it declares `npc`, and reaching through a
##    facade from another module's writer is the coupling ADR 0093 exists to prevent),
##    so the composition root injects the verb and `event/` names no npc type at all.
##    **Unconditional**, unlike `install`'s null-player return below: the writer's
##    `push_error` on a missing resolver is the loud failure BL-0658 needs.
## 2. **A subscriber on `NpcApi.events().stage_advanced`.** ADR 0093 promises "a
##    subscriber connects from its own boot function, which `app/` calls" — and until
##    this line, SEVEN signals had ZERO subscribers, so a promise in a docstring was
##    the whole of the contract. The sink is [method NpcLedger.record] below: an
##    in-memory audit trail of who moved and what drove them, and the first thing that
##    proves the bus is live.
static func _install_event_seams() -> void:
	# The direct Callable, not a lambda that forwards to it: `NpcApi.tally` is a
	# STATIC verb and a typed lambda over it is the shape that once killed the shell
	# on its first frame (see `install`'s note on `ActorFactory.spawn_npc`).
	EventBeatWriter.set_tally_resolver(Callable(NpcApi, "tally"))
	# ADR 0093 line 21, verbatim in shape. `is_connected` first because `install` is
	# idempotent and a load may re-run it: a second connect to the same Callable is an
	# error, not a second ledger.
	var events := NpcApi.events()
	if not events.stage_advanced.is_connected(NpcLedger.advanced):
		events.stage_advanced.connect(NpcLedger.advanced)


## Install the constructor, read the authored cast, and bind the roster to `player`.
## Safe to call again after a load: the catalog read is idempotent and `attach` rebuilds
## the live registry and re-announces the restored cast.
static func install(player: Actor) -> void:
	# The event seams FIRST and unconditionally. They name no actor and bind no roster,
	# so they cannot half-install anything — and a beat that arrives before a player is
	# attached would otherwise be refused with nothing installed to fix it.
	_install_event_seams()
	# Content first, and unconditionally — see the section note above. `load_authored`
	# short-circuits on its second call, so a boot and a later re-install cost one scan.
	NpcCatalog.instance().load_authored()
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
