class_name ItemWorkbenchRoutes
extends ItemWorkbenchFight

## The route half of the playable slice's composition root: the screen stack, the
## navigation bar, the route table every reachable surface is named by, and the binder
## that points one mounted screen at the actor and the read model it renders.
##
## Extracted from [ItemWorkbenchApp] when that file passed gdlint's `max-file-lines`
## ceiling. This is the BASE of the app, so it may name nothing the app declares — the
## cut is computed and one-way, measured 2026-10-10.
##
## `navigate_to(route_id)` is the single navigation mechanism, called by the bar, by a
## screen asking for another screen, and by a headless probe pressing the same control a
## player presses. A screen the route table does not name cannot be reached, so "shipped"
## and "reachable" cannot drift.
##
## `_process` and `_status_loop` deliberately did NOT come here: `test_status_clock.gd`
## requires the loop's construction and the one tick call to live in one file, the app.

const ROUTE_LOOT := &"loot_encounter"

const ROUTE_SOCKET := &"socket_forge"
## The quest journal (BL-0663/BL-0664). `QuestApi.accept` had zero production
## callers, so no player could ever be on a quest; this route plus `_quests` is
## what makes a quest something a player can SEE and take.

const ROUTE_QUEST := &"quest"
## The conversation page (ADR 0862, DEF-0014). Unlike `ROUTE_QUEST` it needs NO seam:
## `dialogue` is in `rules.UI_MODULES`, and `DialogueApi.choose` moves the actor's OWN
## dialogue row — never another module's ledger — so the screen calls the facade itself.
## This arm exists so the route is bound at all: a listed route with no arm mounts an
## unbound screen.

const ROUTE_DIALOGUE := &"dialogue"

const ROUTE_BODY := &"body_cultivation"

const ROUTE_WORLD_MAP := &"world_map"

const ROUTE_CRAFTING := &"crafting"

const ROUTE_WORKBENCH := &"workbench"
## The main menu (boot slice). Continue returns to the saved journey, New Game
## opens arrival. Shown at boot for a returning player; a fresh boot still
## opens arrival directly (that behavior is pinned by
## `tests/app/test_creation_play_wiring.gd`).

const ROUTE_BOOT := &"boot"
## The loading screen (ADR 0901). It owns the boot window while every route
## scene preloads, then releases to the menu or arrival.

const ROUTE_LOADING := &"loading"
## The settings page (menu slice): difficulty presets with the root's own
## select seam.

const ROUTE_SETTINGS := &"settings"
## The save menu (saves slice): every journey with load and erase verbs.

const ROUTE_SAVE := &"save"

const ROUTE_SET_BONUS := &"set_bonus"
## The venture route (worldmap slice 1). The walkable generated scene: the
## screen is a pure consumer holding Callables, and the verbs below are the
## composition root's own doors into the boot seam — the ADR 0143 shape every
## other bound route uses.

const ROUTE_VENTURE := &"venture"

## The soul and hearth page. `soul` and `save` are not (and for `save` must never be)
## reachable from `ui/`, so its four verbs arrive as Callables in `_bind_route_screen`
## rather than as facades the screen calls by name.

const ROUTE_SOUL_HEARTH := &"soul_hearth"
## The combat readout (ADR 0174). Its strike seam and its drill body both arrive as
## Callables here, because `ui/` may neither name a `TechniqueDef` (a class in
## `modules/techniques/`) nor mint an `Actor` (`app/` is a `PRIVATE_UNIT`).

const ROUTE_COMBAT_READOUT := &"combat_readout"
## The technique loadout (ADR 0185). `bind_target` is the ADR 0143 seam the cast half
## runs on and had ZERO callers outside its own test, so the whole cast program was
## unreachable while its suite was green. This route's arm is the injection.

const ROUTE_TECHNIQUE_LOADOUT := &"technique_loadout"
## The gather surface (ADR 0097). `HoldingsApi.claim` had no production caller
## repo-wide, so no node was ever held and the harvest was unreachable; this is
## the route that reaches both, and the arm in `_bind_route_screen` is the one
## line that injects `ForageAction.gather` as the seam the screen cannot name.

const ROUTE_FORAGE := &"forage"
## The shop surface (ADR 0100 / DEF-0218). A PURE CONSUMER like the readout: the
## priced read model AND the verbs both require an `app/` type the screen may not
## name, so all three arrive as Callables here and the screen calls the read model
## `MarketApi` by bare name for its purse alone.

const ROUTE_MARKET := &"market"
## The auction surface (ADR 0102). HALF a consumer: `MarketApi.list` takes only the
## bound actor and two plain ids, so the screen escrows by name; the BID is
## `AuctionBids.bid`, an `app/` type, so only that one arrives as a Callable.

const ROUTE_AUCTION := &"auction"
## The fight page (ADR 0197). A PURE CONSUMER like the readout: all five verbs arrive on
## the ADR 0143 seam. The route was DECLARED in `screen_routes.gd` with no arm here, so
## the page refused `no_fight_seam` forever.

const ROUTE_FIGHT := &"fight"
## The custody page (ADR 0247 / DEF-0310). It shipped with NO arm of its own, on the
## reasoning that `custody` is in `rules.UI_MODULES` with no module reach and so needs no
## seam — which was true of its four VERBS and false of its subject list. `stage_capture`
## had no production caller, so the capture control was permanently disabled and the
## page's primary verb could never be pressed. This arm is the seam ADR 0247 added, and
## the reason it is one line rather than a new module: the module that owns the cast
## already publishes the read model, and `app/` is the one layer allowed to name both it
## and the screen.

const ROUTE_CUSTODY := &"custody"
## The clan page (ADR 0239 / DEF-0286). `ClanHeir.register` is the SOLE writer of
## `household_heir_registered` and had NO production caller. `ClanHeir` is a module
## interior behind a facade at its twelve-method cap, so BOTH halves of the seam arrive
## as Callables: `commit` (the verb a press runs) and `available` (the gate that decides
## whether to offer it). One half alone would force the screen to re-derive the gate.

const ROUTE_CLAN := &"clan"

## The institutions page (ADR 0271 / 0278). The family published a registry, a catalog, a
## generic founding verb, a ledger and a projection, and `core/` published NO
## actor-scoped surface — so this screen shipped with three Callables that nothing bound
## and refused `no_join_seam` / `no_leave_seam` by name. `InstitutionMembership` is that
## surface. All three halves arrive as methods rather than bare static references because
## every one of them takes the BOUND ACTOR, which `ui/` may not mint — the same reason
## `ROUTE_COMBAT_READOUT` above passes `Callable(self, ...)` for its blow.

const ROUTE_INSTITUTION := &"institution"

## The floor (DEF-0309). `MarketApi.drop`, `take` and `settle` shipped a bounded,
## decaying, per-location container of realized instances and nothing in the shipped
## program could reach it: `market_screen.gd` stated the omission out loud and left
## it there. This route opens it, and it is bound by the PLAIN default arm — all three
## verbs take the bound actor plus plain ids, so the granted `market` facade reach is
## enough on its own and there is NO seam to inject here.

const ROUTE_FLOOR := &"floor"

## The world fact id a completed birth records, in `WorldFact`'s own flat namespace and
## with NO prefix (ADR 0113: a prefixed id "reads as a working reference and silently
## grants nothing"). Recorded against the CHILD, so it rides the child's own save
## payload rather than the mother's status — which is the only reason a birth can leave a
## trace at all, given ADR 0089 keeps statuses out of `Actor.to_dict`.
##
## **It grants nothing.** A fact is a thing that happened, not a thing that pays out; the
## counter it moves would be a destination in `destiny`, and no fate in this build is
## authored against it. That is deliberate — a blank fact is still answerable, and it is
## the honest answer for "a birth happened" until content decides what a birth is FOR.

const BIRTH_FACT := &"child_born"

## The cast standing in the settlement the slice opens on. Every id is an authored
## `.tres` under `res://data/npc/cast`, never a literal def, so a reader can open the
## file and see the person (ADR 0074). Sized under `NpcApi.MAX_ROOM_POPULATION` on
## purpose: it is a starting settlement, not a full population.
##

## `_actor`, `_world`, `_death`, `_death_armed`, `_last_death` and `_npc_settlement`
## are NOT re-declared here: they belong to the inherited play half, and a redeclaration
## would SHADOW the base's copy, so `_ready` below would assign a field the play half's
## `poll_death` / `advance_world` / `soul_summary` never read — a split that looks
## mechanical and silently runs on two different actors.
## The composition root's status clock (ADR 0106). It holds no state of its own —
## only the actor it ticks — so wiring it here is what ADR 0056 means by "app/ wires".

var _status_loop: StatusLoop = null
## Every child a birth has produced, keyed by the child's OWN actor id, each row a
## primitive: `{actor_id, race, parent_id, lineages}`.
##
## ## Why a Dictionary and never an `Array[Actor]`
##
## `tools/arch`'s `APP_CONTENT_ARRAY_RE` reads a member `Array[Actor]` as the
## `state-table` signal, and this file already carries `tick-loop` from `_process`, so a
## member array would cross `APP_STATE_MIN_SIGNALS` and FAIL the boundary check. That is
## the check being right rather than fussy: a table of living bodies IS feature state,
## and `app/` wires. So this holds only what a panel and a probe can READ, and the
## lineages it reports are read back off the child through the modules that own them —
## this file keeps no copy of a race or a purity.
##
## ## Why `app/` holds it at all (BL-0748)
##
## There is no registry in this repo for a person the content tree did not author.
## `NpcApi.spawn` REFUSES an id the catalog does not ship (`api.gd:157`), so a newborn
## with no authored `NpcDef` cannot enter the roster through the facade — and inventing a
## def for one would be authoring content to work around a wiring bug. This is therefore
## the SMALLEST CORRECT SEAM: the one composition-root-owned table that already exists for
## exactly this shape of question (`_npc_settlement`, `_last_death`), holding no authority
## over anything. What a newborn SHOULD be — a named individual in a settlement, an heir in
## a household, a settler with a place — is a content and schema decision and is filed for
## the orchestrator rather than invented here.

var _born: Dictionary = {}
## The boot-time arrival program (ADR 0130). Opens the SAME nav route the bar uses, and only
## when no hero exists yet — a returning player with a restored body boots straight to the
## workbench.

var _creation: CharacterCreationProgram = null
## Whether the live actor came from a save rather than from creation. A boot flow reads this
## through [method restored_from_save] to decide whether to offer arrival at all.

var _recovered_from_save: bool = false
## `_restore_stage` and `_restore_body` are NOT declared here: they keep ONE stage and
## ONE adapter per root for the restored-body playfield (ADR 0192), and the one method
## that touches both is the body half's `stand_restored_in_the_world` — which this shell
## still calls by the private name `_stand_restored_in_the_world` from `restore_actor`,
## so the save round trip reads unchanged. Declared down there because a BASE cannot
## resolve a subclass field (INC-0020), and this file's own text reads `restore_actor`
## and `restored_from_save` as one slice.
##
## The nav bar the scene declares, resolved by unique name in `_ready`. It stayed here
## while `_stack` moved down to the body half: nothing in an inherited half reads the bar,
## because the bar is presentation over a route only this shell sets.

var _nav: NavBar = null
## The pinned home screen at the bottom of the stack, and the one screen pushed
## over it. Both are cleared the moment the stack drops them, so a stale handle
## can never outlive the node it names.

var _root_screen: Control = null

var _feature_screen: Control = null
## The socket forge's gameplay half. It owns the forge's round trip, so a screen
## the stack has since freed is a no-op rather than a crash.

var _forge: SocketForgeProgram = null
## The ONE caller of `QuestApi.accept` (BL-0663). Held by the root so the quest
## screen can be bound to it on every mount; the screen itself may not name the
## program (`ui/` holds no `app/` type) and may not name the module without the
## facade, so this is the bridge ADR 0143 prescribes.
##
## ## `_quests` is DECLARED in `item_workbench_readout.gd`, which is what READS it
##
## `[method ItemWorkbenchReadout._interact_in_the_world]` is a BASE-half method, and a base
## cannot resolve a subclass member: declaring the field here as well is a hard `already
## exists in parent class` parse error, and one parse error takes down every suite
## process-wide (INC-0020). This shell only ASSIGNS it — in `_ready` and again in
## [method adopt_actor] — and a subclass assigning an inherited member is legal, so the
## field keeps its whole life across the split.

var _route: StringName = &""
## Whether the boot loading pass is still running. Guards `_finish_loading`
## so a later manual visit to the loading route preloads (harmless, cached)
## without hijacking the player back to the menu.

var _loading_boot := false

## ## The world's persisted period count (ADR 0259) — ONE instance, this root's whole life.
##
## Declared HERE rather than in the play half because both places that need it are in this
## half: `_ready` installs it as the `world_time` store and builds the first fold against it,
## and `adopt_actor` builds every later fold against the SAME instance. A field the base
## declared would be readable from both (INC-0020's rule — declare a member in the BASE only)
## with no upside, since nothing in the base touches it.
##
## **It is never rebuilt and never re-restored after boot.** Rebuilding it per fold is what
## would make the world get younger when the hero does, and re-restoring it per body swap
## would re-seed the world from the last SAVE rather than from the count that has moved since
## — see the `adopt_actor` site, which is the assertion that keeps both true.
##
## ## IT IS ALSO THE SAVE'S `world_time` STORE
##
## Installing this object as the store is what persists the count: `SaveApi._snapshot_world`
## reads `read_ledger()` off the installed store, and `SaveApi.publish_world` restores it by
## calling `write_ledger`. That is why no save code changed — the clock rides the existing
## mechanism (ADR 0259 clause 2), and the fold and the save cannot drift into two answers
## because they are the same object.

var _world_clock: WorldClock = null


func _route_scene_paths() -> Array:
	var out: Array = []
	for route in ScreenRoutes.all():
		var path := String(route.get("scene", ""))
		if not path.is_empty():
			out.append(path)
	return out


## Release the boot window once loading completes. Guarded by `_loading_boot`
## so a later manual visit to the loading route preloads without hijacking
## the player: without the flag, pressing the Loading nav button mid-game
## would end at the menu instead of staying where the player is.


func routes() -> Array[Dictionary]:
	return ScreenRoutes.summary()


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
			# ADR 0089's combat-exit purge. `StatusLoop` is an `app/` type and `app` is
			# a `PRIVATE_UNIT`, so the screen cannot reach it — this is the one legal door,
			# the same shape the quest screen's accept seam uses. The root HOLDS the loop,
			# so the purge and the per-frame tick are the SAME wire over the SAME actor
			# and cannot disagree about which body is being cleaned.
			screen.call("bind_combat_exit", Callable(self, "_purge_combat_scope"))
		ROUTE_SOCKET:
			screen.call("setup", _actor)
			_forge.bind(screen)
		ROUTE_QUEST:
			# The quest journal is the ONE screen that needs the accept seam bound
			# or its rows are dead controls: `act_accept` refuses `no_quest_seam`
			# rather than quietly doing nothing. `QuestProgram` is the single caller
			# of `QuestApi.accept` (BL-0663), so this arm is the whole reason a
			# player can take a quest at all.
			screen.call("setup", _actor)
			_quests.bind(screen)
		ROUTE_DIALOGUE:
			# No seam to bind: the screen reads `DialogueApi.current` and calls
			# `start` / `choose` itself, which is why `dialogue` was added to
			# `rules.UI_MODULES`. The arm is still required — a route in the table with
			# no arm here would mount a screen nobody ever told which actor to render.
			screen.call("setup", _actor)
		ROUTE_CRAFTING:
			# Recipes are pushed in, never discovered by `ui/`: `ItemsApi` publishes
			# no catalog, so which recipes are listed is a composition-root call
			# (ADR 0043).
			screen.call("setup", _actor)
			screen.call("set_recipes", RecipeCatalog.offerable(_actor))
			# The clock seam (ADR 0167, BL-0815): a craft is an ACTION, so it pays world
			# time through this bridge. Wiring it here is what makes the crafting route
			# cost a period rather than run free.
			screen.call("set_bridge", _crafting_bridge())
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
			# **AND THE PLAYER CAN ACTUALLY GO THERE.** `location_selected` was emitted
			# and connected by nobody, so clicking a node highlighted it and stopped and
			# the hero stayed pinned to the arrival's draw for the whole session. What a
			# click means, and why four of the eight authored `.tres` were unreachable, is
			# stated at `_on_world_location_selected` below.
			if (
				screen.has_signal(&"location_selected")
				and not screen.is_connected(&"location_selected", _on_world_location_selected)
			):
				screen.connect(&"location_selected", _on_world_location_selected)
		ROUTE_DOMAIN:
			# The domain screen is a PURE CONSUMER: `domain` is not in `rules.UI_MODULES`
			# and `app/` is a private unit, so it may name neither `DomainApi` nor
			# `DomainBoot`. `DomainBoot.bridge()` is the seam, as `_loot_bridge` and
			# `_world_bridge` are for their screens.
			screen.call("setup", _actor)
			screen.call("bind_bridge", DomainBoot.bridge())
			# **And the world is REALIZED as soon as a run exists.** See
			# [method _realize_domain_world] and `DomainBoot.set_world_observer`: this
			# arm installs the observer once, `enter_domain` fires it, and the world is
			# parented under the screen the stack is showing — which is this one. The
			# call below is the other half: it catches a run that was already entered
			# before this route was opened, and is a documented no-op otherwise.
			_install_domain_world_observer()
			_realize_domain_world()
		ROUTE_COMBAT_READOUT:
			# ADR 0174. The screen cannot resolve a blow itself: `resolve_hit` takes a
			# `TechniqueDef`, and `ui/` may reach `techniques` only through its facade, so
			# a typed technique in a screen is a bare cross-module edge the arch gate
			# refuses. It also cannot mint its own drill body. Both arrive here, on the
			# ADR 0143 seam the quest and soul screens already use.
			#
			# `_readout_blow` resolves through `CombatBoot.resolve_hit` — the SAME
			# production entry point `_resolve_technique_hit` uses, so what the readout
			# shows is what a live cast would produce, mechanism selection and
			# `ctx_builder` included (ADR 0161).
			screen.call("setup", _actor)
			screen.call(
				"bind_strike",
				Callable(self, "_readout_blow"),
				_readout_target(),
				Callable(self, "_readout_context")
			)
			# ADR 0195: the drill's OWN clock, declared on the readout half beside
			# the body it ages. Without it nothing ticked the drill — the three combat
			# ticks rode `_status_loop`, which holds the HERO — so severity on the drill
			# could only rise and no collapse window could advance on anything a player
			# strikes.
			bind_readout_drill()
			# The TECHNIQUE SELECTOR, guarded by `has_method` for the reason
			# `_bind_target_screen` guards its own: a screen without the seam degrades to
			# its own `no_select_seam` refusal, which the reader can see and act on,
			# rather than this arm aborting with the route half-bound and no message.
			# It exists because one fixed technique cannot show three mechanisms — qi's
			# `QiDamage` writes no `effects[]` at all and `MindDamage` is gated out
			# without a sea, so the wound and erosion rows were both unreachable.
			if screen.has_method("bind_technique"):
				screen.call(
					"bind_technique",
					Callable(self, "set_readout_path"),
					Callable(self, "_readout_armed")
				)
		ROUTE_TECHNIQUE_LOADOUT:
			# ADR 0185. THE ARM THAT MAKES THE CAST PROGRAM REACHABLE. `bind_target`
			# is the ADR 0143 seam, exactly as `bind_strike` above is, and it had no
			# production caller at all: `act_cast` fell through `_refuse_no_target`
			# on every real press. One call here is the whole fix.
			#
			# The target is `_cast_target()`, NOT a second foe concept: it is the ONE
			# drill body `CombatReadoutScreen` already strikes, handed over by the same
			# root that minted it. `ui/` may not mint an `Actor` (`app/` is a
			# `PRIVATE_UNIT`) and may not read a foe roster, so a second one could only be
			# invented here — and two bodies on one page is a cast that lands somewhere the
			# player was never shown. Read through `_bind_target_screen` so a screen without
			# the seam degrades to the refusal instead of aborting this arm.
			screen.call("setup", _actor)
			_bind_target_screen(screen)
		ROUTE_FIGHT:
			screen.call("setup", _actor)
			bind_fight_screen(screen)
		ROUTE_SOUL_HEARTH:
			# The soul and the save cannot be named by a screen, so they arrive as
			# Callables off this root's own inherited verbs — the ADR 0143 seam, and
			# `soul_summary()` is already the one read that carries both plus the last
			# death. The raise and the select are the root's own doors (ADR 0146,
			# ADR 0129), handed over the same way. `ui/` reaches `difficulty` and
			# `anchor` by facade and only those two; it reaches `save` through here,
			# which is the whole of ADR 0128's player-facing surface.
			screen.call("setup", _actor)
			screen.call("bind_soul", Callable(self, "_soul_read"), Callable(self, "save_summary"))
			screen.call(
				"bind_hearth", Callable(self, "raise_anchor"), Callable(self, "select_difficulty")
			)
		ROUTE_FORAGE:
			# The gather surface (ADR 0097). `HoldingsApi.claim` had NO production
			# caller repo-wide, so a node was never held and
			# `ForageAction.workable` could never be true — the harvest verb behind
			# sixteen authored nodes was reachable by nothing a player could press,
			# while `tools data audit` reported `gather` live because this file's
			# sibling `app/forage_action.gd` is a call site a scan can see.
			#
			# `claim` and `release` need nothing from here: `holdings` is declared in
			# `rules.UI_MODULES`, so the screen calls `HoldingsApi` by name. The
			# HARVEST goes through `ForageAction`, an `app/` type and therefore a
			# `PRIVATE_UNIT` this screen may not name — so it arrives as a `Callable`,
			# which is ADR 0143's seam and the same one `ROUTE_QUEST` and
			# `ROUTE_SOUL_HEARTH` use. Passed as a bare static-function reference and
			# not a lambda, for the access-violation reason `EconomyBoot._install_granter`
			# documents.
			screen.call("setup", _actor)
			screen.call("bind_harvest", Callable(ForageAction, "gather"))
		ROUTE_MARKET:
			# The shop surface (ADR 0100 / DEF-0218). `ShopCounter.at_location`
			# publishes the priced shelf and the `can_buy` a shop panel needs, and
			# called itself "the door a caller actually walks through" while nothing
			# in the shipped program ever did. `ShopCounter` is `app/`, and `app` is
			# the only entry in `rules.PRIVATE_UNITS`, so the screen may neither name
			# the type nor read through it.
			#
			# The VERBS are the stronger reason. `MarketApi.buy(shop_actor, player,
			# rows)` and `sell(shop_def, shop_actor, player, rows)` both take a shop
			# `Actor`, and the only thing that can mint one is `ShopCounter.counter`,
			# which caches per shop id precisely so the goods LEAVE the merchant. A
			# screen that minted its own counter would hand every caller a full
			# shelf and make the spread testable but the game nonsense — and a
			# screen may not mint an `Actor` at all, since `ActorFactory` is `app/`.
			# So `_market_buy` / `_market_sell` below resolve the counter and forward
			# by SHOP ID, which is the one identifier both sides can hold.
			#
			# `MarketApi` itself needs no seam: `market` is declared in
			# `rules.UI_MODULES`, so the screen reads its purse by bare name exactly as
			# `ForageScreen` reads `HoldingsApi.claim`.
			screen.call("setup", _actor)
			screen.call("at_location", _market_location())
			screen.call(
				"bind_market",
				Callable(ShopCounter, "at_location"),
				Callable(self, "_market_buy"),
				Callable(self, "_market_sell")
			)
		ROUTE_AUCTION:
			# The auction surface (ADR 0102). `AuctionReadModel` published a
			# primitives-only row for every lot in the world — `required_bid`,
			# `high_bid`, `high_bid_amount` — and no screen read any of it, so who
			# was winning an auction was computed and invisible.
			#
			# **This route is HALF a consumer, and the half is the point.** The ESCROW
			# (`MarketApi.list`) takes only the bound actor and two plain ids, so the
			# screen calls it by bare name — `market` is a declared `UI_MODULES` grant,
			# the same reach `ForageScreen` has on `HoldingsApi.claim`. The BID is
			# `AuctionBids.bid`, an `app/` type this screen may not name, and it is
			# also the ONLY place the bid decision exists: it derives
			# `AuctionState.bid_ceiling(purse, tags)` from the bidder's appetite tag
			# and refuses `auction_ceiling_below_required` for a shallow purse. A
			# screen that re-derived any of that would be a second price path
			# (ADR 0094), so the verb arrives whole and the player chooses WHETHER to
			# bid rather than typing an amount.
			#
			# The SETTLEMENT is the third half and was the missing one: `settle_lot`
			# shipped with ADR 0102 and had no caller outside a test, so a lot could be
			# bid on forever and a won lot stayed `open` with its escrow in limbo. It
			# needs two things a screen cannot produce — the `Actor` holding the escrow
			# and a resolver turning a bidder's `actor_id` back into a live wallet —
			# so both arrive here. `_auction_bidder_of` is `AuctionStanding._body`, the
			# SAME resolution that credits a won sale, so the bidder who is PAID is
			# found by the one lookup that already knows who they are.
			screen.call("setup", _actor)
			screen.call("bind_auction", Callable(AuctionBids, "bid"))
			screen.call("bind_settlement", Callable(self, "_auction_bidder_of"), _actor)
		ROUTE_FLOOR:
			# THE ARM THAT MAKES THE FLOOR REACHABLE (DEF-0309), and it is the PLAIN
			# default on purpose. `MarketApi.drop`, `take` and `settle` all take the
			# bound actor plus plain ids — `location_id`, `drop_id`, `periods` — so
			# `market` being a `UI_MODULES` grant is the WHOLE of what the screen needs,
			# exactly as the custody arm needs nothing. A seam here would be a Callable
			# wrapping a facade call the screen may already make by name.
			#
			# The location is still handed over rather than left to the screen, for the
			# reason `_market_location` gives: `world_spawn` is not in `UI_MODULES`, so
			# a screen may not ask where the hero is standing.
			screen.call("setup", _actor)
			screen.call("at_location", _market_location())
		ROUTE_CLAN:
			# THE ARM THAT MAKES THE HEIR REGISTRATION REACHABLE (ADR 0239 / DEF-0286).
			# `app/clan_registry.gd` documented this missing seam line for line and had no
			# caller until now. `install` is idempotent and its report is deliberately NOT
			# read here: a page mounted without a seam refuses `no_register_seam` in its own
			# words, which a probe asserts — refusing to mount would make that a silent hole.
			screen.call("setup", _actor)
			ClanRegistry.install()
			screen.call(
				"bind_register",
				Callable(ClanRegistry, "commit"),
				Callable(ClanRegistry, "available")
			)
		ROUTE_INSTITUTION:
			# THE ARM THAT MAKES JOIN AND LEAVE PRESSABLE (ADR 0271 / 0278).
			# `InstitutionScreen.bind_institutions(reader, joiner, leaver)` shipped with
			# all three seams unbound and every verb refusing by name, so a guild, a hunt
			# and a farmers' circle were three rows a player could read and not one verb
			# they could press. The three Callables are `InstitutionMembership`'s own
			# public verbs over the bound actor, and `install()` has already run from the
			# attach pipeline, so the kinds the screen lists are the ones this boot
			# registered rather than the ones the content directory happens to hold.
			screen.call("setup", _actor)
			screen.call(
				"bind_institutions",
				Callable(self, "_read_institutions"),
				Callable(self, "_join_institution"),
				Callable(self, "_leave_institution")
			)
		ROUTE_CUSTODY:
			# THE ARM THAT MAKES THE PAGE'S PRIMARY VERB PRESSABLE (ADR 0247 / DEF-0310).
			# `CustodyScreen.stage_capture` and `stage_transfer` are the only doors into
			# capture and transfer, and before this line NOTHING in `game/src` called either
			# — so `_capture_subject` was never set, the capture control was permanently
			# disabled, and a captive was a ledger row with no player-reachable way to write
			# one. The screen was right that ADR 0104 leaves capture CONDITIONS to the caller;
			# what was missing was a caller, and the decision of what one IS.
			#
			# ADR 0247's answer: a claim is produced by a terminal stage advance on an
			# individual whose `NpcDef` authors a custody term. So what the page needs is the
			# LIST of capturable individuals, and the module that owns the catalog is `npc`.
			#
			# ## Why this is a SEAM and not `NpcApi` named by the screen
			#
			# `npc` is not in `rules.UI_MODULES`, so a screen may not name `NpcApi` — and
			# `custody` is in it with no module reach, so the custody screen still calls
			# `CustodyApi` by bare name for every verb it owns. One read model over a seam is
			# the ADR 0143 shape, identical to `ROUTE_FORAGE` above and `ROUTE_CLAN` two
			# arms up: `app/` is the one layer allowed to name the cast, the facade and the
			# screen at once.
			#
			# ## Why a closure here, when the seams above are bare static references
			#
			# `EconomyBoot._install_minter` and `NpcBoot` both document why a typed lambda
			# whose body calls another script's static function killed the process with an
			# access violation on the shell's first frame. That is why the OTHER seams here
			# hand over a bare static reference. This one is different: the screen wants a
			# `Callable() -> Array`, and the value it needs is one KEY of a facade read rather
			# than a whole facade verb — `NpcApi` already sits on the twelve-method cap, so
			# the cast is published as `presence_here()["capturable"]`. There is no bare
			# reference to hand over because there is no method to hand it over.
			#
			# `_capturable_cast()` is the seam-free equivalent and is what the binding hands
			# over, so an unwired custody page says "nothing to capture" rather than crashing.
			screen.call("setup", _actor)
			screen.call("bind_capture_options", _capturable_cast)
		ROUTE_BOOT:
			# THE ARM THAT MAKES THE MAIN MENU PRESSABLE. `ui/` may not name
			# the `save` module (ADR 0128), so whether a save exists arrives
			# as a Callable off this root — the ADR 0143 seam, the same shape
			# `ROUTE_SOUL_HEARTH` uses for its save read. The movements arrive
			# the same way: home for Continue, arrival for New Game. A screen
			# mounted without this arm refuses every press by name instead
			# of calling into a void Callable.
			screen.call("setup", _actor)
			screen.call(
				"bind_menu",
				Callable(self, "_boot_has_save"),
				Callable(self, "_boot_continue"),
				Callable(self, "_boot_new_game"),
				Callable(self, "_boot_open"),
				Callable(self, "_quit_game")
			)
		ROUTE_SETTINGS:
			# THE ARM THAT MAKES DIFFICULTY PRESSABLE OUTSIDE THE HEARTH.
			# `DifficultyApi.views()` publishes preset rows "for a settings
			# screen" and had no settings screen; the setter arrives as the
			# root's own verb because `select` takes the bound actor.
			screen.call("setup", _actor)
			screen.call("bind_difficulty", Callable(self, "select_difficulty"))
		ROUTE_SAVE:
			# THE ARM THAT MAKES JOURNEYS LOADABLE AND FORGETTABLE (ADR 0903).
			# `ui/` may not name the `save` module, so list, load and erase
			# all arrive as Callables off this root. A screen mounted without
			# this arm refuses every press by name instead of calling into
			# void Callables.
			screen.call("setup", _actor)
			screen.call(
				"bind_save",
				Callable(self, "list_slots"),
				Callable(self, "load_slot"),
				Callable(self, "erase_slot")
			)
		ROUTE_LOADING:
			# ADR 0901. The screen preloads every route scene; the art layers
			# hang here so a missing file degrades plate by plate to the dark
			# fallback, never a crash. `begin_load` resets the walk; the steps
			# are then driven by `tick_loading` on this root's frame, or
			# drained inline below when no frame will ever come (headless).
			screen.call("setup", _actor)
			screen.call(
				"set_layers",
				"res://assets/loading/loading_wallpaper.png",
				"res://assets/loading/fairy.png",
				"res://assets/loading/sword.png"
			)
			screen.call("begin_load", _route_scene_paths())
		ROUTE_VENTURE:
			# The venture screen walks a generated place. The screen holds
			# Callables and plain nodes; the verbs below are this root's own
			# doors into the boot seam, and the screen passes itself on every
			# call so each verb finds the world that screen is showing. The
			# boot keeps no handle: freeing the screen frees the world with it.
			screen.call("setup", _actor)
			screen.call(
				"bind_venture",
				Callable(VentureBoot, "open"),
				Callable(VentureBoot, "close"),
				Callable(VentureBoot, "step"),
				Callable(VentureBoot, "destroy"),
				Callable(VentureBoot, "read"),
				Callable(VentureBoot, "return_from_domain"),
				Callable(VentureBoot, "set_debug")
			)
			# Encounters answer through their own seam: walking offers through
			# `step`, and fate answers here, so each half degrades alone.
			screen.call(
				"bind_encounter",
				Callable(VentureBoot, "answer_fate"),
				Callable(VentureBoot, "dismiss_encounter")
			)
			# Raising ground is its own seam with its own refusal.
			screen.call("bind_build", Callable(VentureBoot, "build"))
			# The fight seam: strike the live band and take what it drops,
			# through the boot's own verbs so the screen never names the
			# modules. Each half degrades alone when unbound (the screen
			# darkens the row), which is why they bind here, not in the boot.
			screen.call(
				"bind_fight", Callable(VentureBoot, "strike"), Callable(VentureBoot, "take")
			)
			# Slice 3: the descent seam. The scene asks it when a node names
			# a domain template; the actor it enters onto is this root's own,
			# which is why the seam is installed here and not in the boot.
			WorldmapApi.install_domain(
				Callable(self, "_venture_domain_enter"), Callable(self, "_venture_domain_leave")
			)
			# Boss runtime: the same actor's band. Entered when a descended
			# node names a loot domain, abandoned on the way back with
			# rewards kept — so a boss fought underground still pays.
			WorldmapApi.install_loot(
				Callable(self, "_venture_loot_enter"), Callable(self, "_venture_loot_leave")
			)
			# DEF-0374: the far arrival plays the loading screen. A named root
			# method carries the live screen in, because a lambda cannot and
			# the seam takes only the crossing.
			WorldmapApi.install_transition(Callable(self, "_venture_transition"))
			# DEF-0372: tolls spend for real. The evaluator reads the edge
			# price and charges this root's actor; a short purse refuses
			# with the coins untouched.
			WorldmapGates.register("toll_bridge", Callable(self, "_venture_toll"))
		_:
			screen.call("setup", _actor)


## The capturable half of the cast, for the custody screen's capture seam.
##
## A named method rather than a lambda inline at the call site, for the reason every other
## seam in this file documents: a lambda whose body calls another script's static function
## killed the process with an access violation on the shell's first frame. A named static
## has no closure environment to get wrong.


func _capturable_cast() -> Array:
	return NpcApi.presence_here().get("capturable", []) as Array


## The venture descent seam (worldmap slice 3). The scene asks it when a node
## names a domain template; the run is entered onto THIS root's actor through
## the same production entry point the domain route uses, so a descent and an
## Enter press mint the same kind of run. A leave passes straight through:
## the discovered set the module keeps is the state the return preserves.


func _venture_domain_enter(template_id: String, seed: int) -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	return DomainBoot.enter_domain(_actor, StringName(template_id), seed)


func _venture_domain_leave() -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	return DomainBoot.leave_domain(_actor)


## The venture loot-band seam. Entered when a descended node names a loot
## domain, abandoned on the way back; the module keeps unclaimed rewards, so
## walking out never loses what fell. Same actor, same reason as the domain
## seam above: the run is written onto this root's body.


func _venture_loot_enter(domain_id: String, tier: int, seed: int) -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	return LootApi.enter_domain(_actor, StringName(domain_id), tier, seed)


func _venture_loot_leave() -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	return LootApi.abandon(_actor)


## The toll evaluator (DEF-0372). Reads the edge's `toll.amount` and spends
## numeraire from THIS root's actor, atomically: `consume_item` is
## all-or-nothing, so a short purse refuses with the coins untouched. No toll
## means free passage; no actor means no one to charge. Installed for the
## `toll_bridge` hook, where the gate table's contract (bool or `{ok}`)
## already covers the verdict shape.


func _venture_toll(edge: Dictionary, _context: Dictionary):
	var amount := int((edge as Dictionary).get("toll", {}).get("amount", 0))
	if amount <= 0:
		return {"ok": true, "reason": ""}
	if _actor == null:
		return {"ok": false, "reason": "no_actor"}
	EconomyApi.attach(_actor)
	var coin := EconomyValuation.numeraire_id()
	if EconomyApi.purse(_actor) < amount:
		return {"ok": false, "reason": "unpaid_toll"}
	if not ItemsApi.consume_item(_actor, coin, amount):
		return {"ok": false, "reason": "unpaid_toll"}
	return {"ok": true, "reason": "", "paid": amount}


## The venture transition seam (DEF-0374). Carries the live screen into the
## boot's loading drive: the seam names the crossing, and only the root
## knows which screen is showing it.


func _venture_transition(from_node: String, to_node: String, edge: Dictionary) -> Dictionary:
	return VentureBoot.transition(_live_screen(), from_node, to_node, edge)


## Free everything this root built that is not a node the stack owns. Idempotent, and
## safe to call after an aborted test — the headless runner shares ONE process across every
## suite, so a leak here is a leak everywhere.
##
## The world is detached and freed with `remove_child()` then `free()`, never
## `queue_free()`: the runner drives tests from `SceneTree._initialize()` and never
## processes a frame, so a deferred free leaks for the life of the process. That is the
## shape that took a run to 67 GB resident (INC-0004/INC-0005).


func _market_location() -> StringName:
	if _actor == null:
		return &""
	var here := WorldSpawnApi.current(_actor)
	if not bool(here.get("located", false)):
		return &""
	return StringName(here.get("location_id", ""))


## The live `Actor` an auction's bidder id names, or null. `MarketApi.settle_lot`'s
## resolver, handed to `AuctionScreen` by the `ROUTE_AUCTION` arm.
##
## ## Why this delegates to `AuctionStanding` rather than resolving again
##
## A lot records its bidders as a plain `actor_id` string — "a bid is a PROMISE and
## promises outlive the room" (ADR 0102) — so settlement has to turn an id back into a
## wallet at the moment it pays. `AuctionStanding._body` is the SHIPPED answer to
## exactly that question: a minted shop counter, the tracked npc roster, or the player
## `EconomyBoot.install` recorded. Reading it twice would be two lookups that could
## disagree about who a bidder is, and the second one is the one that decides who gets
## paid. `AuctionStanding.can_credit` is the same resolution with no side effect, and
## it is what makes this callable a stable seam rather than a private detail.


func _on_route_requested(route_id: StringName) -> void:
	navigate_to(route_id)


## A screen asked for another screen. Same mechanism as the bar, so there is one
## navigation mechanism rather than two.


func _on_world_map_requested() -> void:
	navigate_to(ROUTE_WORLD_MAP)


## The world map says where the player clicked; this root decides that a click is a
## journey. The meaning is `app/`'s because `ui/` may not name a stage — the reason
## `WorldStage.on_location_selected` lives where it does rather than in the screen.
##
## **This is the wire that made four of the eight authored events reachable.** The
## arrival draws one of four authored locations, so before this line the hero was
## pinned to it for the rest of the session and every event authored for
## `spirit_peaks`, `transcendent_realm` or `immortal_court` was filtered out of
## `EventApi.available` in every real run. The stage's mount republishes the new place
## to the event module through the seam `_ready` installed.
##
## No bounds are passed: `WorldLocationDef` carries no size, so the stage falls back to
## its own default playfield rather than this root inventing one. A refused journey is
## `no_mounted_stage` — nothing has committed a body yet — and the screen repaints
## either way so no highlight is left lying about where the player is.


func _on_world_location_selected(location_id: StringName) -> void:
	var screen := _live_screen()
	WorldStage.on_location_selected(screen, location_id)
	if screen != null:
		screen.call("refresh")


## Mark the live route on the bar, so the player can see where they are without
## inferring it from button styling.


func _announce_route() -> void:
	if _nav != null:
		_nav.set_active(_route)
		# The menu owns the screen: the nav bar stays hidden behind it, so a
		# title never reads as a tab strip with a label under it. Arrival
		# keeps its bar — the boot probe and the pinned reachability suites
		# drive nav buttons from there, so hiding it would trade the debug
		# feel for a red gate.
		_nav.visible = _route != ROUTE_BOOT


## ## The world bridge, and the FOURTH slot (BL-0906)
##
## An OVERRIDE of the inherited builder rather than an edit to it: the base assembles the
## three verb slots, this one assembles those and adds the read slot. It calls `super()` so
## the verb wiring stays literally the parent's — a hand-written second copy of three
## `Callable(self, ...)` lines would be a second place for the root's own seams to drift.
##
## **Why a slot, when `world_summary()` already carries `open_event_rows`** — because the
## count and the rows are different ANSWERS, and the panel must be able to say which it
## got. `active_events` answers "how many"; a roster of rows answers "which, at what stage,
## held how long, paying what". Publishing them inside a payload the screen already reads
## would have been a smaller diff, and it would have left a missing seam indistinguishable
## from a quiet world, because `[]` is both. A named slot is checkable from `has_events()`,
## which is what makes the empty state honest rather than merely empty.
##
## The callable is `WorldPulse.open_events`, delegated: the rows are the event module's read
## model, and `app/` is the one layer allowed to hold them on a screen's behalf. The bridge
## binds the METHOD; the screen still never names the module.


func _world_bridge() -> WorldPulseBridge:
	var bridge: WorldPulseBridge = super()
	bridge.events = Callable(self, "_world_open_events")
	return bridge

## Every world event that is open right now, as primitives, for the bridge's read slot.
## `[]` when no world is attached — which the bridge and the panel both read as "wired,
## nothing open", the honest answer for a root that has not built a pulse yet.
