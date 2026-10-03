class_name ItemWorkbenchApp
extends Control

## Composition root for the playable slice (ADR 0002, 0027, 0033).
##
## The only place that knows concrete module types and the attach order. It
## builds one actor, mounts the screen stack the scene already declares, and
## injects file-backed persistence — the UI program itself never names a module
## type or touches the filesystem.
##
## Every surface a player can reach is named by `ScreenRoutes`, and this root is
## the only thing that mounts one: `navigate_to(route_id)` is the single
## navigation mechanism, called by the navigation bar, by a screen that asks for
## another screen, and by a headless probe that presses the same control a player
## presses. A screen the route table does not name cannot be reached at all, so
## "shipped" and "reachable" cannot drift apart.

const SAVE_PATH := "user://item_workbench_state.json"
## Enough real content to exercise every activation channel on first run.
##
## `curr_spirit_coin` is here because the economy's numeraire is a HELD item, not an integer
## balance (ADR 0094): `EconomyExchange` physically moves the stack, so a player who cannot
## obtain one cannot trade at all. `starter` is the only route that both roots the acquisition
## graph AND is actually granted here — `gather` is graph-rooted but `ItemSources.KINDS` marks
## it `shipped: false`, so a gather source would still be runtime-unreachable.
const STARTER_ITEMS: Array[StringName] = [
	&"armor_iron_helm",
	&"accessory_iron_bangle",
	&"armor_iron_ore",
	&"curr_spirit_coin",
]
## The routes whose screen needs more than `setup(actor)`. Every other route is a
## `UiScreen`, which is bound by the default arm below.
const ROUTE_LOOT := &"loot_encounter"
const ROUTE_SOCKET := &"socket_forge"
const ROUTE_BODY := &"body_cultivation"
const ROUTE_WORLD_MAP := &"world_map"
const ROUTE_CRAFTING := &"crafting"
const ROUTE_WORKBENCH := &"workbench"
const ROUTE_SET_BONUS := &"set_bonus"

## The cast standing in the settlement the slice opens on. Every id is an authored
## `.tres` under `res://data/npc/cast`, never a literal def, so a reader can open the
## file and see the person (ADR 0074). Sized under `NpcApi.MAX_ROOM_POPULATION` on
## purpose: it is a starting settlement, not a full population.
const STARTING_CAST: Array[StringName] = [&"gate_keeper_bo", &"smith_bearcutter", &"drifter"]

## What [code]NpcBoot.populate_room[/code] answered at boot: how many bodies stood up
## and who they are. Held so a probe can read the cast without reaching past `app/` —
## the live instances themselves stay in `npc`'s own registry, which is where ADR 0092
## says a room's occupants live.
var _npc_settlement: Dictionary = {}

var _actor: Actor = null
## The composition root's status clock (ADR 0106). It holds no state of its own —
## only the actor it ticks — so wiring it here is what ADR 0056 means by "app/ wires".
var _status_loop: StatusLoop = null
## The world's clock and the ONE place a beat reaches a sink (ADR 0117, DEF-0111).
## A director with no production instance is the same defect as a facade with no
## callers: `add_sink` / `offer` were tested and a player could never reach them.
var _world: WorldPulse = null
## The death resolver (ADR 0130). Polled from [method _process] like every other clock here,
## because a module may not declare its own frame driver (DEF-0111) and a FOURTH `_process`
## fails `tests/app/test_status_clock.gd`.
var _death: SoulDeath = null
## The actor id the death poll is currently watching. Armed on adoption and re-armed on a body
## swap, so a poll never fires twice for the same body and never fires for a replaced one.
var _death_armed: String = ""
## The last resolved death, as primitives, so `summary()` can report what happened without a
## screen re-deriving it.
var _last_death: Dictionary = {}
## The boot-time arrival program (ADR 0130). Opens the SAME nav route the bar uses, and only
## when no hero exists yet — a returning player with a restored body boots straight to the
## workbench.
var _creation: CharacterCreationProgram = null
## Whether the live actor came from a save rather than from creation. A boot flow reads this
## through [method restored_from_save] to decide whether to offer arrival at all.
var _recovered_from_save: bool = false

## The stack and the bar the scene declares. Resolved by unique name; the root
## never builds a second one, because two stacks means two answers to "which
## screen is live".
var _stack: ScreenStack = null
var _nav: NavBar = null
## The pinned home screen at the bottom of the stack, and the one screen pushed
## over it. Both are cleared the moment the stack drops them, so a stale handle
## can never outlive the node it names.
var _root_screen: Control = null
var _feature_screen: Control = null
## The socket forge's gameplay half. It owns the forge's round trip, so a screen
## the stack has since freed is a no-op rather than a crash.
var _forge: SocketForgeProgram = null
var _route: StringName = &""


func _ready() -> void:
	_stack = get_node_or_null("%ScreenStack") as ScreenStack
	if _stack == null:
		push_error("ItemWorkbenchApp: the scene must carry a ScreenStack named %ScreenStack")
		return
	_nav = get_node_or_null("%NavBar") as NavBar

	# The world-scoped stores, installed BEFORE anything reads them: a soul outlives its body
	# and an anchor stands in a place, so neither may live in `actor.module_data` (ADR 0127,
	# ADR 0146, and ADR 0101's argument that a per-actor copy of a world fact is a bug). The
	# save's store is the real one; a test installs the in-memory ledger instead.
	#
	# **Stores before actors, on purpose.** `publish_world` and `restore_actor` both read them,
	# and the actor mirror is written by every attach below — so installing a store after an
	# attach would leave that attach reading an empty ledger and silently writing it back.
	SoulApi.set_store(SaveStore.new())
	AnchorApi.set_store(SaveStore.new())
	SaveApi.install_store("soul", _world_store())
	SaveApi.install_store("anchor", _world_store())
	# A newborn is minted through a Callable rather than built inline, because
	# `fertility` may not name `app/` (BL-0280). Without this the child is a bare
	# `Actor.new()` with no health pool, so it cannot be damaged or healed. Installed
	# beside the other seams, before anything can conceive.
	ActorFactory.install_fertility_actor_builder()
	# A restored world is published BEFORE any `Actor.from_dict`, so a body built from a save
	# finds its soul and its anchors already in place rather than starting empty.
	SaveApi.publish_world()
	# The save is read AFTER the stores are installed and the world published, because that is
	# the only point at which a restore can actually read a ledger — and BEFORE a fresh hero is
	# built, because the envelope carries the actor payload this recovers: building first and
	# restoring over it would leave a fresh hero's providers on a restored body. A save with no
	# readable slot answers a refusal, which is a new game rather than an error.
	if not bool(restore_actor().get("ok", false)):
		_actor = _build_actor()
	# The per-actor modules, mounted over whichever body now stands. One list, called from both
	# the fresh build and the restore, because two copies of an order that is load-bearing is
	# two places for it to drift.
	_mount_player_modules(_actor)
	# The death resolver, injected rather than constructed here so it names no `app/` type and
	# stays a plain value object a test can drive. It holds no state and declares no
	# `_process`: THIS function polls it, which is what keeps the tree at exactly three frame
	# drivers (`tests/app/test_status_clock.gd`).
	_death = SoulDeath.new(mint_body, adopt_actor)
	_death_armed = ""
	# The status clock is built last, because it can only tick the actor every
	# other attachment has already made complete (ADR 0106).
	_status_loop = StatusLoop.new(_actor)
	# The world's clock, after the actor and wired to a director of its OWN: it is not
	# a module and shares no ledger with the status clock.
	_world = WorldPulse.new(_actor, BeatDirector.new())
	_forge = SocketForgeProgram.new(_actor)
	# The boot-time arrival program. It opens the SAME route the nav bar uses rather than
	# pushing a second copy of the scene: two doors to one screen means a screen the route
	# table does not know about, which is what 	est_screen_reachability exists to catch.
	_creation = CharacterCreationProgram.new(_stack, CharacterCreationFlow.new(), navigate_to)
	if not _mount_home():
		return
	if _nav != null and not _nav.route_requested.is_connected(_on_route_requested):
		_nav.route_requested.connect(_on_route_requested)
	# Boot OPENS creation when no hero has been created yet. This is the one
	# production caller `open_creation` had: the docstring above it claimed a
	# shipped title flow would call it, and none existed, so the door was only
	# ever openable from a test. A hero that already exists boots straight to the
	# workbench, which is the returning-player path and is why the check is here
	# rather than unconditional.
	if not _creation.has_hero():
		open_creation()


## The one world store this root installs into the soul and the anchors.
##
## **One instance, shared, never one per module.** Both ledgers are read through the same
## `read_ledger` / `write_ledger` object so they land in ONE `envelope.world` payload and are
## written and restored together. Two stores would mean two independent ledgers, and a save
## carrying one of them is a save that lost the other.
##
## Built fresh per boot rather than cached in a static, because a second boot must not inherit
## the first one's world — the same per-slot reasoning ADR 0128 applies to the store itself.
func _world_store() -> SaveStore:
	return SaveStore.new()


## Restore the live slot, or answer that there is nothing to restore.
##
## **This is the READ half of the save, and without it the write half is decoration.** `persist`
## was wired at boot and `restore` was not, so cultivation progress, the soul and the anchors were
## written every period and never observed on the next session — a save that nobody reads is a
## file, not a save. ADR 0128 called the envelope "built to round-trip"; this is the round trip.
##
## Called from `_ready` BEFORE the actor is built, because the envelope carries the actor
## payload this is here to recover: building a fresh hero first and restoring over it would
## leave the fresh hero's paths mounted on a restored body.
##
## Returns `{ok, reason, recovered, generation}`. **A corrupt primary recovers the backup
## silently** — the player has no backup choice to make, so a dialog reporting an error they
## cannot act on would be noise — while `recovered` and `reason` stay observable to a probe.
func restore_actor() -> Dictionary:
	var restored := SaveApi.restore()
	if not bool(restored.get("ok", false)):
		# A new game, not an error. The caller builds a fresh hero and the shell plays on.
		return {"ok": false, "reason": String(restored.get("reason", "no_readable_save")), "recovered": false, "generation": 0}
	var envelope := restored.get("envelope", {}) as Dictionary
	var payload := envelope.get("actor", {}) as Dictionary
	if payload.is_empty():
		return {"ok": false, "reason": "no_actor_payload", "recovered": bool(restored.get("recovered", false)), "generation": int(envelope.get("generation", 0))}
	var actor := Actor.from_dict(payload)
	if actor == null:
		return {"ok": false, "reason": "actor_unreadable", "recovered": bool(restored.get("recovered", false)), "generation": int(envelope.get("generation", 0))}
	_actor = actor
	_recovered_from_save = true
	# The saved body needs its providers re-mounted and its items deserialized. The payload
	# carries both, and a body with neither is a body whose stats never resolve -- silently,
	# because core never names a module and so cannot re-attach one.
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	DualCultivationApi.attach(actor)
	FertilityApi.attach(actor)
	ElementsApi.apply_realm_modifiers(actor)
	ItemsApi.attach(actor)
	SetBonusApi.attach(actor)
	TechniquesApi.attach(actor)
	_mount_player_modules(actor)
	return {
		"ok": true,
		"reason": "",
		"recovered": bool(restored.get("recovered", false)),
		"generation": int(envelope.get("generation", 0)),
		"difficulty": String(envelope.get("difficulty", "")),
	}


## Whether the live actor came from a save rather than from creation. A boot flow asks this to
## decide whether to offer character creation at all.
func restored_from_save() -> bool:
	return _recovered_from_save


## The save's own condition, as primitives, so a status line can report that saving happened
## without asking permission and without naming the backup.
func save_summary() -> Dictionary:
	return SaveApi.summary()


## Mount every module a hero carries, over an actor that already exists.
##
## ## Why this is a separate method and not part of `_build_actor`
##
## **A restored body needs the same providers as a fresh one, and forgetting that is silent.**
## `Actor.from_dict` rebuilds the actor's own state — stats, pools, paths, ledgers — but it
## does not re-attach the modules that CONTRIBUTE to those stats, because core never names a
## module. So a restored hero without this line has no item bag, no technique codex and no
## set-bonus projection, and nothing reports an error: every screen that reads them answers
## empty. That is the shape DEF-0151 records for a module that is "built and unwired".
##
## ## Why the order is unchanged
##
## It is `_build_actor`'s order, verbatim, because the order is load-bearing and documented
## there: body before the element realm refresh, items before set bonus and techniques,
## techniques last, destiny before event. Copying the sequence into a second literal would let
## the two drift, so there is one list and the fresh build calls it too.

func _mount_player_modules(actor: Actor) -> void:
	SocketApi.attach(actor)
	LootApi.attach(actor)
	DifficultyApi.attach(actor)
	SoulApi.attach(actor)
	AnchorApi.attach(actor)
	SocialApi.attach(actor)
	DestinyApi.attach(actor)


## The one tick caller in the game (ADR 0106, read against ADR 0089).
##
## ## Why this frame and not a status-specific one
##
## A status nobody can tick is decoration: with no production caller, no burn spent
## a pulse and nothing expired, and the readout had nothing to show. `_physics_process`
## would have been the wrong answer in a different way — a status is a game-time
## concept, not a simulation one, and a fixed 60 Hz would age it differently
## depending on what else the frame did. So the idle process callback it is.
##
## `delta` is the engine's, always. Nothing here reads `Time.get_ticks_*`: whoever
## owns time passes the elapsed time down, so a status ticks identically under a
## headless test, a replay and a frame that hitched (ADR 0089).
##
## ## Why `ui/` can never grow this
##
## `ui/` is a pure consumer, and a `_process` there would be a second clock — two
## callers means a status ages at two different rates depending on which screen is
## mounted. This is the sentence that survives the ADR: ONE tick caller, in `app/`,
## passing an explicit `delta`. Anything that wants statuses ticked calls
## `StatusApi.tick_statuses` with a delta it was given, never with a clock of its own.
func _process(delta: float) -> void:
	# A no-op on a null actor rather than a crash: the root can be mounted before it
	# built one, and a frame that cannot advance anything is not a reason to stop the
	# whole UI. `StatusLoop.tick` refuses that same case by name.
	if _status_loop == null or delta <= 0.0:
		return
	_status_loop.tick(delta)
	# The WORLD's clock, same frame, same delta: a world that aged on a different
	# cadence from a status is a world whose pace nobody could reason about (ADR 0089,
	# one layer up). `WorldPulse` turns seconds into whole periods, no clock of its own.
	if _world != null:
		_world.pull(delta)
	# Death and autosave ride the SAME frame and the SAME delta, for the same reason the world
	# clock does: a second cadence means a save that lands on a different schedule from a status,
	# which nobody could reason about. Neither adds a frame driver of its own.
	poll_death()
	poll_save(delta)


## Advance the world by exactly `periods` whole periods, with no elapsed time — the
## player-facing half of the tick. `EventApi.advance` refuses `periods <= 0` by
## design (ADR 0085), so nothing accrues without a caller saying how much.
func advance_world(periods: int) -> Dictionary:
	return (
		{"ok": false, "reason": "no_world"} if _world == null else _world.advance_periods(periods)
	)


## Advance the world by exactly ONE period. **The verb a screen's "wait a season"
## button and a headless probe both call**, so neither has to know the cadence or
## pass an argument a driver would hand over as a string.
func advance_one_period() -> Dictionary:
	return advance_world(1)


## The world's own view of itself, published beside [method summary] so a probe can
## tell a dead director from a quiet one without reaching into the pulse.
func world_summary() -> Dictionary:
	return {} if _world == null else _world.summary()


## Resolve a death for the current body, once.
##
## **Armed on the actor id, so one body dies once.** A poll that fired on every frame would
## charge the soul repeatedly for a single wound, and re-arming after a body swap is the only
## reason a rebirth can happen at all. Called from [method _process] and directly by tests and
## probes, so the rule is testable without driving frames.
##
## A body with no lives left stays in place rather than being swapped for null: there is nowhere
## to swap TO, and a null actor would take every screen with it.
func poll_death() -> Dictionary:
	if _death == null or _actor == null:
		return {}
	if _death_armed != String(_actor.id):
		_death_armed = String(_actor.id)
		return {}
	if not _death.is_dead(_actor):
		return {}
	_last_death = _death.resolve(_actor)
	# Re-arm whatever stands now, so a guardian death does not re-fire next frame and a rebirth
	# arms the NEW body rather than the one that fell.
	_death_armed = String(_actor.id)
	# A death is a thing that happened to the world, so it is saved immediately rather than
	# waiting for the next boundary: the run state that matters most is the state at death.
	SaveApi.persist(_actor, String(DifficultyApi.current_id(_actor)))
	return _last_death


## The last resolved death, as primitives. `{}` before anything has died.
func last_death() -> Dictionary:
	return _last_death.duplicate(true)


## Write the save if the clock says one is due.
##
## **The player never decides when this happens.** The clock counts whole periods and the save
## lands on a boundary they never see, which is the requirement rather than a limitation
## (ADR 0128). Called from [method _process] with the engine's delta; no module reads a clock.
func poll_save(delta: float) -> Dictionary:
	if not SaveApi.clock.pull(delta):
		return {}
	return SaveApi.persist(_actor, String(DifficultyApi.current_id(_actor)))


## Mint a fresh body for `arrival_id` — the composition root's half of a rebirth.
##
## The body is built through the SAME arrival table character creation uses, so a returning
## soul arrives the way a first one does and there is one rule for "how does a hero arrive"
## rather than two. Refuses an arrival the catalog does not define rather than minting a hero
## nothing can explain.
func mint_body(arrival_id: String, incarnation: int) -> Dictionary:
	var arrival := StringName(arrival_id)
	if SoulCatalog.instance().arrival_definition(arrival) == null:
		return {"ok": false, "reason": "unknown_arrival"}
	return CharacterCreationFlow.build_forced(arrival, incarnation)


## Make `body` the current actor, re-binding everything that held the old one.
##
## **A half-swapped body is the failure this exists to prevent**: the game would read two
## different actors — a screen on the old one, the soul on the new — and no assertion fails,
## because both are individually valid. Every holder is re-pointed here, in one place, so a
## future binding cannot be forgotten silently.
func adopt_actor(body: Actor) -> void:
	if body == null:
		return
	_actor = body
	SocketApi.attach(body)
	LootApi.attach(body)
	DifficultyApi.attach(body)
	SoulApi.attach(body)
	AnchorApi.attach(body)
	_status_loop = StatusLoop.new(body)
	_world = WorldPulse.new(body, BeatDirector.new())
	_forge = SocketForgeProgram.new(body)
	_death_armed = ""
	_last_death = {}
	if _live_screen() != null:
		_live_screen().setup(body)


## Open character creation, and answer whether it opened.
##
## **Opens the nav route the table already names**, so there is one door rather than two
## (ADR 0130). Boot calls this when no hero exists, which is why it is public with a production
## caller: `test_screen_reachability` fails a public mount nothing in `src/` calls, and
## `_ready` is that caller.
func open_creation() -> Dictionary:
	return {} if _creation == null else _creation.open()


## The creation program's own view of itself, so a probe can assert reachability without
## reaching into a private field.
func creation_summary() -> Dictionary:
	return {} if _creation == null else _creation.summary()


## The soul, the difficulty, the anchors and the save, as primitives, so a probe can assert the
## wiring without reaching into a module.
func soul_summary() -> Dictionary:
	return {
		"soul": SoulApi.soul(_actor),
		"difficulty": String(DifficultyApi.current_id(_actor)),
		"anchors": AnchorApi.summary(_actor),
		"last_death": _last_death,
		"save": SaveApi.summary(),
	}


## The route table this root publishes, so the navigation bar, a probe and a
## test all read the same list. Primitives only.
func routes() -> Array[Dictionary]:
	return ScreenRoutes.summary()


## Who is standing in the settlement this root stocked at boot (BL-0626).
##
## Published for the same reason `routes()` is: a probe or a test must be able to
## READ what the boot did without reaching into `npc`'s registry or re-deriving the
## cast list. The answer is `populate_room`'s own dictionary verbatim — a count, the
## location id, and one read-model row per npc — so nothing here can disagree with
## what was actually minted.
func npc_presence() -> Dictionary:
	return _npc_settlement.duplicate(true)


## Open `route_id` and make it the live screen. The single navigation mechanism:
## the navigation bar calls it, a screen that asks for another screen calls it,
## and nothing pushes onto the stack by any other route.
##
## Returns false when the table names no such route or its scene stops loading,
## so an unreachable screen is a reported refusal rather than a silent hole.
func navigate_to(route_id: StringName) -> bool:
	if _stack == null or not ScreenRoutes.has(route_id):
		return false
	if route_id == _route:
		return true
	# One level is ever stacked over the home screen, so this unwinds at most one
	# screen. The home screen is never popped: the workbench is where the player
	# keeps state, and a route change must not destroy it.
	_stack.call("pop_to_root")
	_feature_screen = null
	if route_id != ScreenRoutes.ROOT_ID:
		var screen := _instantiate_route(route_id)
		if screen == null:
			return false
		_feature_screen = _stack.call("push", screen) as Control
		if _feature_screen == null:
			return false
	_route = route_id
	_announce_route()
	return true


## The route the live screen serves, or "" before the first mount.
func current_route() -> StringName:
	return _route


## Everything the shell is showing, as primitives: the stack, the live screen and
## the navigation bar. `nav_probe` reads this rather than the app's own opinion of
## itself.
func summary() -> Dictionary:
	var live := _live_screen()
	return {
		"route": String(_route),
		"actor_id": "" if _actor == null else String(_actor.id),
		"feature": "" if _feature_screen == null else String(_feature_screen.name),
		"stack": _stack.summary() if _stack != null else {},
		"screen": live.call(&"summary") if live != null else {},
		"nav": _nav.summary() if _nav != null else {},
		# The world's half of the shell, published because this root is the only place
		# the two composition-root wires meet.
		"world": world_summary(),
	}


## Re-read the socket program's read model and hand it to the mounted forge.
## Published because a caller that stocks items behind the screen's back has to
## be able to repaint it; a no-op when the forge is not the live screen.
func refresh_socket_screen() -> void:
	if _forge == null or _route != ROUTE_SOCKET or not _forge.is_live():
		return
	_forge.refresh()


## A fresh hero with every path the shipped slice offers, the core resource
## pools, and a starting kit drawn from the shipped content tree.
##
## The attach order is load-bearing and is the only place it exists:
##   1. `build` — core pools and the sect ledger, which grants recognition and
##      never power (ADR 0084), so wiring it cannot hand a new actor an edge;
##   2. the body path — it enrols the actor, and the element realm refresh below reads
##      the highest realm off the actor's paths to write each element's realm
##      multiplier. Refreshing the element realm before a path exists writes nothing,
##      which is exactly the silent realm degression ADR 0069 records;
##   3. dual cultivation, then fertility — fertility adds to the fertility and
##      potency bases dual cultivation owns, so it must follow it;
##   4. the element realm half, because it reads the paths step 2 wrote. The PROVIDER
##      itself is mounted by `ActorFactory.build` — step 1 — so this is
##      `apply_realm_modifiers` and never `attach`, or the stat is contributed twice;
##   5. items, because body training spends the realm's elixirs through the
##      inventory and an action must never find no bag to spend from;
##   6. techniques LAST, because the technique module resolves its authored
##      options through the items module's `OptionCatalog` and applies them
##      through `ItemEffects` — the items vocabulary has to exist first (ADR 0056).
##   7. social state, then the npc boot. Social belongs to EVERY actor, the player
##      included (ADR 0091) — attaching it here rather than only inside the npc
##      constructor is what makes the symmetry real: one ledger type answers for
##      the player and for every inhabitant. `NpcBoot.install` then injects the npc
##      constructor and binds the roster to this actor (ADR 0092); without it
##      `NpcApi.spawn` can only ever return null.
func _build_actor() -> Actor:
	var actor := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	ActorFactory.with_body_cultivation(actor)
	# The other two cultivation paths, enrolled the same way. A player who cannot
	# open the qi or mind screen has not got two paths, they have got one — and
	# both screens mount bound to an actor they cannot read otherwise.
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	DualCultivationApi.attach(actor)
	# A species is a `race` module term for an inhabitant; the hero has none, so
	# the species contribution is skipped rather than invented.
	FertilityApi.attach(actor)
	# The element provider is mounted by `ActorFactory.build`, so the player already
	# carries it; this line REFRESHES the realm half and must never re-attach. It sits
	# after step 2 for exactly that reason — see `ActorFactory._refresh_element_realm`
	# and ADR 0069's "attach once" rule. A second `attach` here would stack a second
	# `ElementProvider` (`ActorStats.add_provider` appends unguarded), and then
	# `element_power_<e>` — the channel ADR 0088 makes status potency read — would be
	# computed twice, silently doubling an npc's debuff on every landed blow.
	ElementsApi.apply_realm_modifiers(actor)
	ItemsApi.attach(actor)
	# After `ItemsApi.attach`, as its own docstring requires: set bonus reads the
	# items vocabulary, so it must never run first.
	SetBonusApi.attach(actor)
	# Techniques LAST: they read the items vocabulary written above, never the
	# other way round (ADR 0056 — app/ wires the module, the module owns it).
	TechniquesApi.attach(actor)
	SocialApi.attach(actor)
	# Fate is earned, never chosen, so birth only normalizes an EMPTY ledger and
	# grants nothing: this is the composition-root entry point that makes the
	# ledger exist before any earn call site writes to it. Without it the module
	# is unwired — `DestinyApi._ledger` lazily self-attaches on first write, so
	# the codex screen reads zero for an actor that was never attached, and a
	# quest or event grant lands in a key nothing initialized (ADR 0065).
	DestinyApi.attach(actor)
	# The world ledger, attached here for the same reason `DestinyApi.attach` above:
	# ADR 0117 named `EventApi` a facade with ZERO production callers, so nothing
	# owned the moment ADR 0114 requires an owner of. Attaching normalizes an EMPTY
	# ledger and grants nothing, and it is the one place the attach order exists, so a
	# world event's prize — a `DestinyApi.earn_fate` through `EventPrize` — lands in a
	# key that already exists. After `DestinyApi.attach`, because that is what it
	# creates. It does NOT start anything: `EventApi.advance` still has no production
	# caller and must not gain one until a caller owns a PERIOD COUNT (ADR 0085's
	# pull-based tick, DEF-0111) — recorded in `docs/deferred.jsonl`.
	EventApi.attach(actor)
	# Quests, for the same reason: `QuestBeatHandler` is a registered sink, and a
	# handler reading an un-attached ledger sees no active quest and claims nothing.
	QuestApi.attach(actor)
	# The npc boot, and the LAST thing the actor is handed: it injects the npc
	# constructor, reads the authored cast off disk (`NpcCatalog.load_authored`) and
	# binds the roster to this actor (ADR 0092, BL-0626). Without the read, `spawn`
	# refuses every id it is handed and a player meets nobody; without the install,
	# the read alone buys a catalog nothing can mint from.
	NpcBoot.install(actor)
	# …and stock the place the player starts in, through the ONE room entry point
	# (`populate_room`), so the cast is standing in a location rather than merely
	# reachable. `NpcApi.populate`'s own cap bounds the room, and `replace_first`
	# defaults true, so this is a stock rather than an accumulation. It is a single
	# starting settlement, NOT a room system: no arrival re-stocks anywhere, because
	# nothing in this repo models a room or an arrival yet (see the report on
	# BL-0626). A place gets a cast when an author wires one, and until then the boot
	# path stands one up where the player already is.
	_npc_settlement = NpcBoot.populate_room(actor, STARTING_CAST, NpcApi.ROLE_NPC, &"mortal_plains")
	CombatBoot.bind_mechanisms(actor)
	# After every attach above: a seam is only correct if the module it wires is
	# already complete, and `TechniquesApi.attach` is what makes the codex exist for
	# `TechniqueDelivery` to write into.
	_bind_technique_seams()
	var inventory := ItemsApi.inventory(actor)
	for item_id in STARTER_ITEMS:
		var def := _resolve(item_id)
		if def != null:
			inventory.add(def, 1)
	return actor


## Bind the two seams the techniques module needs from OUTSIDE its own directory.
##
## ## Why these live here and not in the techniques module
##
## `app/` is the composition root and may depend on anything by construction
## (`tools/arch/rules.py`, `LAYER_DEPS["app"] == {"*"}`). Both seams below exist
## because the edge they carry is NOT legal where the mechanic lives:
##
##   - **delivery** — `modules/items/item_use.gd` has to turn a
##     `category = &"technique"` item into a `CodexEntry`. Naming `TechniquesApi`
##     from `items` would be an `items -> techniques` edge the registry does not
##     declare, and a bare class reference out of `modules/*` is not even an edge
##     the checker sees (`BARE_REF_UNITS` excludes `modules/*`), so it would have
##     been UNDECLARED rather than real. `TechniqueDelivery` is the resolver seam;
##     this call is what makes it live.
##   - **casting** — `TechniqueCasting.activate` resolves its hit through an
##     injected `resolver` rather than naming `CombatEngineApi`, for the identical
##     reason (`technique_casting.gd` says so at length). Without this binding an
##     active technique fires, pays its qi, starts its cooldown and returns an
##     EMPTY damage descriptor, because nothing ever handed it the spine.
##
## ## Why `bind_learner` and not a closure
##
## `TechniqueDelivery.bind_learner` already forwards to `TechniquesApi.learn`, so
## binding it is passing the module's own entry point rather than a lambda defined
## in here. If a future edit needs the root's own logic in the loop, that is a
## closure over THIS root — and the seam still keeps the dependency one-way.
##
## Called from `_build_actor` and NOT from `_ready`: `_ready` runs once but a
## caller that rebuilds an actor (`ActorFactory` is public) would otherwise leave a
## freshly built actor with no seam, because a process-wide binding survives while
## the actor it was installed for does not. Installing here means every actor this
## root builds is wired, which is the property that was missing.
func _bind_technique_seams() -> void:
	TechniqueDelivery.install(Callable(TechniqueDelivery, "bind_learner"))
	TechniqueCasting.set_resolver(Callable(self, "_resolve_technique_hit"))


## The damage resolver `TechniqueCasting.activate` is handed, for the same reason
## the delivery seam above exists and for the same edge it cannot draw itself.
##
## ## Why the resolver is a method here and not a lambda
##
## A lambda would work and would be shorter, but it would be unreadable at the call
## site three lines later. As a method the signature — three actors/def in, one
## descriptor out — is stated where a reader is already looking, and it can be
## passed to a test as `Callable(app, "_resolve_technique_hit")` to prove the wiring
## without a fight.
##
## ## Why `rng` is null
##
## A null rng means NO randomness and every attack lands (`CombatEngineApi
## .resolve_hit` documents it, ADR 0067). That is the correct default for a shell
## with no combat system driving it: a technique must produce a real, readable
## damage descriptor, and a random miss in a probe or a screen would report "0
## damage" for a technique that works perfectly. A caller that wants the roll
## injects its own rng through the same seam.
##
## `breakdown` is the descriptor form and is the right return: `TechniqueCasting
## ._resolve` accepts a `Dictionary` verbatim and this is exactly one.
func _resolve_technique_hit(attacker: Actor, target: Actor, technique: TechniqueDef) -> Dictionary:
	return CombatEngineApi.breakdown(attacker, target, technique, CombatEngineApi.tuning(), null)


## Push the one route the shell mounts at boot and never pops, so `ui_cancel`
## always lands somewhere.
func _mount_home() -> bool:
	var screen := _instantiate_route(ScreenRoutes.ROOT_ID)
	if screen == null:
		push_error("ItemWorkbenchApp: the home route '%s' will not load" % ScreenRoutes.ROOT_ID)
		return false
	_root_screen = _stack.call("push", screen) as Control
	_route = ScreenRoutes.ROOT_ID
	_announce_route()
	return true


## Load one route's scene, name it for the route it serves, and bind it to the
## app's actor. Naming it is what lets the live screen say which route it is in
## the node tree, not only in the shell.
func _instantiate_route(route_id: StringName) -> Control:
	var scene_path := ScreenRoutes.scene_of(route_id)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("ItemWorkbenchApp: route '%s' has no scene at %s" % [route_id, scene_path])
		return null
	var screen := packed.instantiate() as Control
	if screen == null:
		push_error("ItemWorkbenchApp: route '%s' instantiates to no Control" % route_id)
		return null
	screen.name = ScreenRoutes.node_of(route_id)
	_bind_route_screen(route_id, screen)
	return screen


## Bind one mounted screen to the app's actor, plus whatever read model it is a
## pure view of. A screen that needs more than `setup(actor)` names it here; this
## is the only place a gameplay type and a screen type meet.
func _bind_route_screen(route_id: StringName, screen: Control) -> void:
	match route_id:
		ROUTE_WORKBENCH:
			# The workbench is a plain view that also needs the persistence the UI
			# program is not allowed to own (ADR 0027).
			screen.call(
				"setup", _actor, Callable(self, "_save_state"), Callable(self, "_load_state")
			)
		ROUTE_LOOT:
			screen.call("setup", _actor)
			screen.call("bind_bridge", _loot_bridge())
		ROUTE_SOCKET:
			screen.call("setup", _actor)
			_forge.bind(screen)
		ROUTE_CRAFTING:
			# Recipes are pushed in, never discovered by `ui/`: `ItemsApi` publishes
			# no catalog, so which recipes are listed is a composition-root call
			# (ADR 0043).
			screen.call("setup", _actor)
			screen.call("set_recipes", RecipeCatalog.offerable(_actor))
		ROUTE_BODY:
			screen.call("setup", _actor)
			# The body screen's World Map button is a real navigation door, so the
			# route it opens is the same one the navigation bar opens.
			# Guarded like the app's own connections: safe today only because every
			# navigation instantiates a fresh screen, and an unguarded connect would
			# start duplicating handlers the moment one is ever reused or cached.
			if (
				screen.has_signal(&"world_map_requested")
				and not screen.is_connected(&"world_map_requested", _on_world_map_requested)
			):
				screen.connect(&"world_map_requested", _on_world_map_requested)
		ROUTE_SET_BONUS:
			# The set screen renders exclusively from a snapshot the composition
			# root supplies, so it needs BOTH: the actor like every other screen,
			# and the snapshot nothing else feeds it.
			screen.call("setup", _actor)
			screen.call("apply_snapshot", SetBonusApi.inspect(_actor))
		ROUTE_WORLD_MAP:
			screen.call("setup", _actor)
			screen.call("bind_world", _world_bridge())
		_:
			screen.call("setup", _actor)


## The loot program's public surface, as plain callables. The UI program may only
## reach a gameplay module through that module's facade, so the bridge keeps every
## module type on this side of the boundary. It carries no strike and no damage figure:
## a domain fight is `CombatApi.exchange`, which the loot screen calls by name because
## `combat` is declared in `rules.UI_MODULES` (ADR 0076).
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


## The world's clock, as plain callables — the same shape as `_loot_bridge` and for the
## same reason, but the reasoning is sharper here because there is no module to name.
##
## `app` is a PRIVATE unit (`tools/arch/rules.py`), so no screen may reference it, and
## `event` is not in `rules.UI_MODULES`, so no screen may name `EventApi`. The world's
## period tick therefore has exactly one legal seam: the composition root handing over two
## verbs as callables. Neither verb is invented — `advance_one_period` and `world_summary`
## already existed on this class.
##
## ## Why the screen does not get the numbers for free
##
## `WorldPulse.PERIOD_SECONDS` and `PERIOD_FACT` are `app/`'s and unreachable from `ui/`.
## A screen that duplicated them would be a second copy of a rate, which is the failure
## `tests/core/test_realm_rate.gd` exists to catch in GDScript and which no rule catches in
## a panel. So the clock arrives through this bridge or it does not arrive.
##
## ## Why `advance_one_period` and not `EventApi.advance`
##
## Calling the event module from a screen would make a SECOND dispatcher for one moment: it
## would skip the ambient news, the one-open-per-pull budget and the institution settling
## that `WorldPulse.pull` owns. The pulse is the only thing allowed to decide what a period
## means, so a screen asks the pulse and not the module.
func _world_bridge() -> WorldPulseBridge:
	var bridge := WorldPulseBridge.new()
	bridge.read_state = Callable(self, "world_summary")
	bridge.advance = Callable(self, "advance_one_period")
	return bridge


## The navigation bar asks; this root decides. One request in, one screen out.
func _on_route_requested(route_id: StringName) -> void:
	navigate_to(route_id)


## A screen asked for another screen. Same mechanism as the bar, so there is one
## navigation mechanism rather than two.
func _on_world_map_requested() -> void:
	navigate_to(ROUTE_WORLD_MAP)


## Mark the live route on the bar, so the player can see where they are without
## inferring it from button styling.
func _announce_route() -> void:
	if _nav != null:
		_nav.set_active(_route)


func _live_screen() -> Control:
	return null if _stack == null else _stack.call("current") as Control


## Look a definition up by id through the items module's single resolver, so the
## app uses the same lookup as inventory, crafting, the generator and loot.
## Returns null rather than guessing, so a missing starter item never blocks the
## app.
func _resolve(item_id: StringName) -> ItemDef:
	return Crafting.resolve(item_id)


func _save_state(payload: Dictionary) -> String:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return "cannot open %s" % SAVE_PATH
	file.store_string(JSON.stringify(payload))
	file.close()
	return ""


func _load_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
