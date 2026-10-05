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
## 2. **Five subscribers on `NpcApi.events()`** — `stage_advanced`, `npc_tracked`,
##    `npc_restored`, `bond_changed` and `presence_changed`, all landing in
##    [method NpcLedger]. ADR 0093 promises "a subscriber connects from its own boot
##    function, which `app/` calls" — and until this line, SEVEN signals had ZERO
##    subscribers, so a promise in a docstring was the whole of the contract.
##
## ## `bond_changed` is reached on the SAME bus, not through `social/api.gd`
##
## `social/` owns the bond ledger and may NOT depend on `npc/` (it declares `contracts`
## and `core`), so it publishes `bond_changed` on `NpcEvents.shared()` — the leaf-layer
## bus `contracts/npc_events.gd` owns, which is why that accessor exists at all.
## Connecting through `SocialApi` instead would have been an inversion AND would have
## needed a thirteenth facade verb.
##
## ## Every connect is guarded, and `npc_transient` deliberately is not here
##
## `install` is idempotent and a load re-runs it, so each `.connect(` sits behind an
## `is_connected` check against the exact static Callable: a second connect to the same
## Callable is an engine error, and a lambda would defeat the guard entirely because
## `is_connected` compares identity.
##
## `npc_transient` is the one signal left unwired. No consumer for it exists anywhere in
## the tree, so it keeps a written reservation in
## `tests/modules/npc/test_npc_event_contract.gd` rather than gaining a row-logger here —
## the `decision_answered` precedent (BL-0793): a blessed seam with no implementor is a
## rumour of a system that does not exist. `npc/api.gd:195` still emits it, so if a real
## consumer is ever built the reservation is what that work removes.
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
	if not events.npc_tracked.is_connected(NpcLedger.tracked):
		events.npc_tracked.connect(NpcLedger.tracked)
	if not events.npc_restored.is_connected(NpcLedger.restored):
		events.npc_restored.connect(NpcLedger.restored)
	if not events.bond_changed.is_connected(NpcLedger.bond):
		events.bond_changed.connect(NpcLedger.bond)
	if not events.presence_changed.is_connected(NpcLedger.presence):
		events.presence_changed.connect(NpcLedger.presence)
	# ## THE PURSUIT SEAM — where an NPC first forms an impression of the player (ADR 0256)
	#
	# `npc_tracked` fires from `NpcApi.spawn` with the def id and the authored tier, which
	# is the one moment in the whole engine that is unambiguously "you two have met". That
	# makes it the honest place to seed a first impression, and seeding it here rather than
	# in a caller means **every** meeting path gets one, including `populate_room`.
	#
	# ## Why it seeds and does nothing else
	#
	# `PursuitApp.meet` is idempotent (`apply_once` refuses a second write), costs one
	# bounded dictionary row, and **writes only to the npc's own ledger**. It cannot move
	# the player's ledger and it cannot be re-triggered into a different answer, so this
	# subscription cannot become a farm — the anti-farm rule is `apply_once`'s existence
	# check, not a check here.
	#
	# ## And the tier is honoured at the seam, not deep in the module
	#
	# A `transient` is pure population: the seed row is written and forgotten with them,
	# and nothing derived from it is ever published. That is the whole of the transient
	# promise and keeping it at the seam means a new call site cannot forget it.
	#
	# `install` is idempotent and a load re-runs it, so this sits behind the same
	# `is_connected` guard against the exact static Callable as every row above — a lambda
	# would defeat the guard, because `is_connected` compares identity.
	if not events.npc_tracked.is_connected(Callable(NpcBoot, "_seed_first_impression")):
		events.npc_tracked.connect(Callable(NpcBoot, "_seed_first_impression"))
	# ## THE SOCIAL GATE SEAM — where an NPC's warmth answers to `regard` (ADR 0264)
	#
	# `NpcGates.evaluate` takes `Callable(player: Actor, requirement: Dictionary) ->
	# Dictionary`, and `SocialApi.gate` already *is* that signature — so this binds the static
	# function itself rather than a lambda that forwards to it, the same rule (and the same
	# shell crash) as `EventBeatWriter.set_tally_resolver` above.
	#
	# **Installed HERE, beside the other event seams, and UNCONDITIONALLY**: it binds no actor
	# and reads nothing, so a beat arriving before a player is attached cannot half-install it.
	# `install` is idempotent and `set_social_gate` stores a dead `Callable` as none, so
	# re-running this is free and cannot stack two readers.
	#
	# ## Why a seam rather than a preload inside `npc/`
	#
	# `npc` already declares `social` in `registry.json`, so a direct call would pass
	# `tools arch` — and would still be the wrong shape, because the def's authored gate is a
	# requirement `npc/` must never interpret (ADR 0076's one-evaluator rule). The `Callable`
	# keeps `NpcGates` to "pass a dictionary through and report the verdict", so the only
	# answer to "is this gate satisfied" in the repo stays `SocialGate`.
	NpcGates.set_social_gate(SocialApi.gate)


## ## THE MEETING HANDLER. Narrow on purpose: it reads a tier and calls one verb.
##
## ## Why an empty projection, and why that is correct
##
## The seed is handed `{}`, so **every NPC meets the player with the plain `BASE`
## impression** unless a caller has supplied a real projection via `PursuitApp.meet`. The
## race/bloodline/clan/sect terms are therefore *available* but not *assumed*, and an NPC
## never gains an impression advantage for a fact this handler cannot see. A richer
## projection is a content decision a caller makes deliberately, not a default this seam
## guesses at — and guessing would mean this file reaching into four modules' internals,
## which is the dependency the facade rule exists to prevent.
##
## ## WHY THIS HANDLER CAN ASK FOR THE BODY, AND WHY `spawn`'s ORDER IS THE CONTRACT
##
## This handler runs from `npc_tracked`, and it needs the npc's `Actor` — the impression
## is a component ON that body. `NpcApi.spawn` therefore emits that signal **after**
## `NpcRegistry.set_present`, so `NpcApi.resident()` below finds the body this spawn just
## stood up.
##
## ## It used to be emitted before, and that minted TWO bodies for one individual (BL-0799)
##
## The signal is a roster ADDITION, and it fired at `api.gd:175` — sixteen lines above the
## `set_present` at `api.gd:191`. So at this instant the npc was on the roster and on no
## roster-payload, but **not yet in the live table**. `resident()` took its
## mint-a-fresh-body branch and called `spawn()` **re-entrantly, inside the outer
## `spawn()`**: the inner call passed the `existing == null` test (the entry exists now),
## minted a second `Actor` and published it under a second instance key, and the outer
## call published its own.
##
## The damage was not cosmetic. A room held one npc **more** than it was stocked with, and
## `despawn` released only one of the pair — so `summary` kept answering `Present` for
## somebody who had walked out of the room. Four suites failed on exactly that. None of
## their counts was a stale fixture: the room really did hold a body nobody asked for, and
## the fix belongs in `spawn`, not in a test's expectation.
static func _seed_first_impression(npc_id: String, _tier: StringName) -> void:
	var player := NpcApi._current_player
	if player == null:
		return
	var npc := NpcApi.resident(StringName(npc_id))
	if npc == null:
		return
	PursuitApp.meet(player, StringName(npc_id), {})


## Install the constructor, read the authored cast, and bind the roster to `player`.
## Safe to call again after a load: the catalog read is idempotent and `attach` rebuilds
## the live registry and re-announces the restored cast.
static func install(player: Actor) -> void:
	# The event seams FIRST and unconditionally. They name no actor and bind no roster,
	# so they cannot half-install anything — and a beat that arrives before a player is
	# attached would otherwise be refused with nothing installed to fix it.
	_install_event_seams()
	# **And the roster reader, for the same reason (DEF-0261).** `where_is` is the
	# tracked where-the-player-is fact a panel keys its roster on, and `ui/` may reach
	# NEITHER `npc` nor `world_spawn` through a facade (neither is in `rules.UI_MODULES`),
	# so the seam has to be filled here rather than from a route arm. `install` is the one
	# function that runs on a fresh boot, on a restore AND on a rebirth, so the roster is
	# live on all three paths and not only the one a route-bind would have covered.
	#
	# **The install is idempotent because the reader refuses a duplicate**, exactly the
	# `WorldFact.subscribe` rule: a second root in the same process must not take the
	# seam away from the first, or the roster would silently answer for the wrong player.
	# The refusal is not an error, so the return is deliberately unused here.
	NpcRosterBridge.install_room_reader(Callable(NpcBoot, "where_is"))
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
	# ## The PERSONAL-Cause seam (ADR 0091, ADR 0108) — the OTHER half of the kinship path
	#
	# `SocialFavour`'s four seams (bond key, debt reader, mercy probe, teacher) had **no
	# production caller**: grepping `SocialFavourApp.` outside `game/tests` returned only the
	# definition file itself. Every personal-cause verb therefore ran on its unbound
	# fallback, and `BrotherhoodOath.bond_key` — the resolution the whole mirror depends on —
	# degraded to `actor.id`, filing every mirror under a row no gate, consent ledger or panel
	# would ever read. `Seduction.REQUIRED_STANDING` is 6.0 read off a PERSONAL bond, so the
	# lineage producer sat behind a floor nothing could clear (BL-0717 / BL-0751).
	#
	# **Installed HERE, beside the roster, because it is the one install that runs on a fresh
	# boot, on a restore AND on a rebirth.** A route-bind would have covered one of the three
	# and left a returning player with an unbound seam — the shape the DEF-0261 note above
	# already names. `KinshipApp.install` delegates to `SocialFavourApp.install`, whose four
	# seams each have a DEFAULT body over a facade `app/` may name, so the call needs no
	# arguments and cannot half-bind.
	#
	# **Idempotent**, and AFTER `NpcApi.attach(player)` so `BrotherhoodOath.bond_key`'s prefix
	# scan over `NpcRegistry` has a live roster to walk. Installing before the roster would
	# bind a correct Callable whose first few calls still resolved nothing.
	KinshipApp.install()


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
##
## ## `location_id` reaches the SPAWN, or `npcs` is empty (BL-0715)
##
## It used to reach only the read on the last line, and every row the write produced
## recorded `location_id: ""` — so the filter dropped all of them and the settlement panel
## was handed `spawned: 4, npcs: []` while four bodies stood in the room. A `spawned` count
## beside an empty `npcs` is not a partial answer, it is a self-contradiction, so `spawned`
## counts exactly the rows the panel can see: every body minted here is stamped with this
## place, and the two numbers agree.
static func populate_room(
	player: Actor,
	def_ids: Array[StringName],
	role: StringName = &"npc",
	location_id: StringName = &""
) -> Dictionary:
	install(player)
	var spawned := NpcApi.populate(def_ids, role, true, location_id)
	return {
		"spawned": spawned.size(),
		"location_id": String(location_id),
		"npcs": NpcApi.presence_here(location_id).get("npcs", []),
	}


## ## `where_is` — the TRACKED where-the-player-is fact, and the door a screen keys on
##
## ## Why this exists, and why it is NOT [method populate_room]'s answer
##
## `populate_room` returns a BOOT-TIME settlement: one room, minted once, never
## restocked (`item_workbench_body.gd` says so in its own docblock, because
## `STARTING_CAST` is a fact about the settlement the slice OPENS on rather than a
## property of a body). A screen that keyed a roster on that dict would show a stale
## cast as though it were the room the player was standing in — which is worse than
## showing no roster at all, because a player cannot tell a stale list from a true one.
##
## So the composition root keeps the CURRENT room as a first-class, tracked fact and a
## screen keys on THAT. The two are different facts and this function is the honest one:
## it reads the durable location ledger (`world_spawn`), which the world map writes when
## the player travels and the arrival path writes when a hero is born.
##
## ## Why it is monotone-safe, and why it is not a `WorldFact` row
##
## A `WorldFact` is a thing that HAPPENED and may never be lowered (ADR 0065), and its
## row stores an integer count — so "which room am I standing in" is not a fact in that
## ledger's sense. Moving rooms lowers one answer and raises another. The two facts are
## kept apart on purpose: `WorldFact` counts arrivals, this reports the one place that is
## current. **No second copy of the location is kept here** — the value is READ from
## `world_spawn`'s own ledger on every call, so this file cannot drift from it.
##
## ## The roster rides this function, so the room and the cast are one answer
##
## [method where_is] returns the place AND the presence for that exact place, in one
## read. A caller cannot pair this location with a cast read somewhere else and get a
## roster for the wrong room, because there is no way to hold the half and re-read the
## other half later.
static func where_is(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"has_actor": false,
			"location_id": "",
			"display_name": "",
			"located": false,
			"here": _no_room(),
		}
	# `WorldSpawnApi` is the module that OWNS "where is this actor" — it is the durable
	# ledger, it survives a save, and it is what `WorldStage.mount` writes on a journey.
	# Re-deriving a room here would be a second answer to one question.
	var place := WorldSpawnApi.current(actor)
	var location_id := StringName(String(place.get("location_id", "")))
	var located := bool(place.get("located", false)) and location_id != &""
	# **An unlocated hero gets the EMPTY room, never the everywhere answer.** This is the
	# single most dangerous line in the function: `NpcApi.presence_here("")` means
	# "everywhere", so passing an empty id here would hand a hero standing nowhere the
	# cast of every populated room in the settlement — which is precisely the
	# borrowed-neighbour's-cast defect this feature exists to refuse, wearing a location
	# filter as a disguise. So the empty-room payload is the answer unless there is a
	# real place to filter by.
	var here: Dictionary = (
		(read_model(actor, location_id) as Dictionary).get("here", _no_room())
		if located
		else _no_room()
	)
	return {
		"has_actor": true,
		"location_id": String(location_id) if located else "",
		"display_name": String(place.get("display_name", "")),
		"located": located,
		"here": here,
	}


## The empty presence payload, spelled once so "a room with nobody in it" and "no room
## at all" cannot disagree about their shape. A player who walks into an empty place
## must see an EMPTY roster, never the neighbours' — so this is `count: 0` with an empty
## `npcs` array and never a borrowed list.
static func _no_room() -> Dictionary:
	return {"location_id": "", "count": 0, "truncated": false, "npcs": []}


## The whole npc read model for one screen: who is here, and who the player has met.
##
## Deliberately does NOT call `install`. This is a read, and `install` -> `attach` clears
## the live registry — so a panel polling for state would empty the room it is rendering.
## A read binds nothing; it reads whatever the last `install` left in place.
##
## ## `location_id` defaults to everywhere, and that default is the whole point (BL-0715)
##
## This used to call `presence_here()` with no argument and no way to ask, which is what
## let the spawn/read mismatch live: a screen that could only ever ask "who is ANYWHERE"
## cannot tell "the room is empty" from "the read is filtering the room out". Defaulting
## to `""` stays legitimate — an everywhere answer is a real question — but it is now a
## choice at the call site rather than the only shape the verb has. Still no `install`.
static func read_model(player: Actor, location_id: StringName = &"") -> Dictionary:
	var roster := NpcApi.state(player)
	return {
		"has_actor": player != null,
		"roster": roster,
		"here": NpcApi.presence_here(location_id),
		"bond_with": SocialApi.summary(player),
	}
