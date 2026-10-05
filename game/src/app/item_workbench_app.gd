class_name ItemWorkbenchApp
extends ItemWorkbenchFight

## Composition root for the playable slice (ADR 0002, 0027, 0033).
##
## The only place that knows concrete module types and the attach order. It builds one
## actor, mounts the screen stack the scene already declares, and injects file-backed
## persistence — the UI program never names a module type or touches the filesystem.
##
## Every surface a player can reach is named by `ScreenRoutes`, and this root is the
## only thing that mounts one: `navigate_to(route_id)` is the single navigation
## mechanism, called by the bar, by a screen that asks for another screen, and by a
## headless probe that presses the control a player presses. A screen the route table
## does not name cannot be reached at all, so "shipped" and "reachable" cannot drift.
##
## ## The split into FOUR files
##
## This file is the SHELL: boot, the save round trip, the screen stack, the navigation
## bar, and the route-to-screen binding. It inherits THREE halves, each extracted
## because this file passed the thousand-line ceiling and would have passed it again:
##
##   - `ItemWorkbenchReadout` — the drill body a reader strikes, the one blow it
##     resolves, and the combat context row beside it.
##   - `ItemWorkbenchBody` — the attach list, the fresh-hero build, the hit and readout
##     seams, and the read bridges a screen is handed for the hero.
##   - `ItemWorkbenchPlay` — the actor itself and the four clocks that answer for it.
##
## **Every addition is charged against that ceiling.** Two wires added here — the
## interaction seam and travel — took this file back over 1000 lines, so each carries
## its rule here and its RATIONALE in the file that owns the contract
## (`WorldStage.has_interaction_handler`), not at the call site.
##
## **Inheritance, not delegation, and that is the whole reason it works.** Every verb on
## any half is called on the mounted root, so a delegation would leave every caller
## naming a method that is not there. As base scripts the root still answers all of them,
## and `get_script_method_list()` reports inherited declarations too, so
## `tests/app/test_screen_reachability.gd` still sees the whole door surface. **No
## public method was moved off this class or renamed**, and no signature changed.
##
## Three suites read files in this chain as TEXT, so what stayed in the SHELL is what
## they slice on: `tests/app/test_status_clock.gd` requires `StatusLoop.new(` and a
## `_process(` signature HERE and nowhere else under `res://src` (one tick caller is
## ADR 0106's claim), and `tests/modules/save/test_cultivation_boot_round_trip.gd`
## slices this file between the `restore_actor` and `restored_from_save` declarations.
## Both still hold. So did the third: `tests/arch_rules/test_fact_ledger_writers.gd`
## pins the exact set of files calling the fact ledger's one writer, and this root is
## the eighth — which is why `adopt_actor` and `_register_birth` stayed. Both restore
## declarations are named above WITHOUT their `func ` prefix on purpose: that suite
## finds its slice by that literal, and naming them in prose would put the FIRST match
## above the real declarations.

## The routes whose screen needs more than `setup(actor)`. Every other route is a
## `UiScreen`, which is bound by the default arm below.
const ROUTE_LOOT := &"loot_encounter"
const ROUTE_SOCKET := &"socket_forge"
## The quest journal (BL-0663/BL-0664). `QuestApi.accept` had zero production
## callers, so no player could ever be on a quest; this route plus `_quests` is
## what makes a quest something a player can SEE and take.
const ROUTE_QUEST := &"quest"
const ROUTE_BODY := &"body_cultivation"
const ROUTE_WORLD_MAP := &"world_map"
const ROUTE_CRAFTING := &"crafting"
const ROUTE_WORKBENCH := &"workbench"
const ROUTE_SET_BONUS := &"set_bonus"

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
	# The three economy ledgers, in the SAME block and for the SAME reason (ADR 0165). They were
	# the last world facts still living in a bare in-memory dictionary, so a claimed vein, a
	# listed lot and an open custody claim died at quit while `SaveApi` faithfully wrote
	# `world["holdings"] = {}` for a key nothing read back. Each is a `WorldLedgerStore` over the
	# envelope key it owns — one per key, so they can never normalize each other's shape — and
	# `EconomyBoot._install_stores` picks them up through `SaveApi.store_for` and installs the
	# very same instances, leaving the in-memory seam for a suite that installs no save store.
	SaveApi.install_store(
		"holdings", WorldLedgerStore.new("holdings", HoldingsState.SCHEMA_VERSION)
	)
	SaveApi.install_store("market", WorldLedgerStore.new("market", MarketState.SCHEMA_VERSION))
	SaveApi.install_store("custody", WorldLedgerStore.new("custody", CustodyState.SCHEMA_VERSION))
	# ## The world-scoped POLITY ledger (DEF-0119), installed in the same block and for the
	# ## same reason.
	#
	# A polity is a thing that outlives the actor who founded it (ADR 0083), so its
	# ledger cannot live in `actor.module_data` — that is the one persistence root in the
	# repo and it dies with the body, which is exactly what a debt between two institutions
	# must not do. `WorldPolityLedger` is the world root; this is its per-key `SaveStore`
	# view, the same `WorldLedgerStore` shape the three economy ledgers use, over the
	# `world["polity"]` envelope key.
	#
	# **Before `publish_world` below, with the rest.** A world published before its store
	# is installed is a world nobody reads back — the ledger is believed saved and is not,
	# which is the silent-loss failure this whole class of fix exists to prevent.
	SaveApi.install_store(
		WorldPolityLedger.WORLD_KEY,
		WorldLedgerStore.new(WorldPolityLedger.WORLD_KEY, WorldPolityLedger.SCHEMA_VERSION)
	)
	# ## The one place a fact becomes a fate counter (ADR 0149)
	#
	# `core/world_fact.gd` publishes a post-write hook slot and names nothing in it —
	# `tools arch` holds `core/` to `{"core", "contracts"}`, so the subscriber has to be
	# installed from out here, the composition root. This is that line, and it is the ONLY
	# one: every fact in the game is written by `WorldFact.record`, so a hook installed here
	# is reached by the director, `CombatFacts`, `ClanFacts`, `SectFacts`,
	# `EventBeatWriter` and `CharacterCreationFlow` alike.
	#
	# It used to be dispatched from `BeatDirector.offer` instead, which is the composition
	# root's beat path and looked like the right seam. It is not: the director's only
	# production caller is `WorldPulse.offer`, and that offers the period fact and the four
	# ambient roster facts — none of which any fate reads. All six real producers called
	# `WorldFact.record` directly and bypassed it, so 0 of the 8 authored pairs could ever
	# fire while every suite driving the director's path stayed green.
	#
	# BEFORE anything can record a fact, because a subscriber installed after the first
	# record has already missed that occurrence, and the ledger is monotone: there is no
	# going back for it. `subscribe` refuses a duplicate, so a second boot of this root
	# cannot install two bridges and double every counter from here on.
	DestinyProjection.subscribe_to_fact_ledger()
	# ## The other half of the same fix (ADR 0149): a quest completes where a FACT is written
	#
	# `quest` subscribes to the same hook slot, for the same reason and with the same
	# measurement behind it. `QuestApi.advance` — the only verb that completes a quest —
	# had exactly ONE production caller, `BeatDirector`, whose only production offer
	# point is `WorldPulse.offer`: `world_period_elapsed` plus the four
	# `WorldAmbient` roster facts. **No authored quest step watches any of those five.**
	# Every authored step watches `sect_post_held`, `oaths_discharged`,
	# `household_heir_registered`, `third_man_spared` or `duels_won` — all written by
	# module writers that bypass the director by design (ADR 0137) — so a player could
	# satisfy every step of a quest in play and it never completed. Every quest in
	# `data/quest/quests/` was unfinishable.
	#
	# Beside the destiny line and BEFORE anything can record a fact, for the reasons
	# above it: the ledger is the one chokepoint all eight writers reach, the director
	# is not, and a subscriber installed after a record has already missed that
	# occurrence — permanently, the ledger being monotone. `subscribe` refuses a
	# duplicate, so a second boot of this root installs no second bridge.
	QuestFactProjection.subscribe_to_fact_ledger()
	# The third subscriber, and the door the last audit found unwired: a `systemic` or
	# `emergent` quest is not OFFERED (`QuestApi.offered` skips every non-`authored`
	# kind, and that filter is what `kind` means), so nothing ever ENTERED one and
	# `what_the_rotation_cost`, `the_short_road` and `the_severed_calling` had no
	# production door at all. They ARRIVE instead: when a fact they watch makes every
	# required step true, the world accepts the quest itself, through the existing
	# `QuestApi.accept` — no new facade verb, no board, no second copy of `advance`.
	# Subscribed AFTER `QuestFactProjection` so an arrival is in the active set when
	# that advance runs, and the quest completes on the SAME fact that made it
	# enterable rather than waiting for another one. The test runner shares one
	# process, so the test suite tears this one down in its own teardown.
	QuestArrivalProjection.subscribe_to_fact_ledger()
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
	# NO second `_mount_player_modules` here. Both branches already mount: `restore_actor`
	# calls it at the end of its own body, and `_build_actor` reaches the same list through
	# `_attach_body_modules`. Calling it a third time is not "safe by construction" —
	# `ItemsApi.attach` REPLACES the inventory, so on the fresh branch this discarded the
	# four STARTER_ITEMS `_build_actor` had just granted and handed a new player an EMPTY
	# bag. Measured, not inferred: `tools boot` reported `rows_at_boot: 0` and the claim
	# half's `rows_now: 2`, on a run with no save file present, so the fresh branch is the
	# one that ran. The list is still the single source of order; it is simply reached once.
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
	# a module and shares no ledger with the status clock. Built on the INHERITED
	# `_world`, which the play half's `advance_world` / `world_summary` read — a local
	# copy here would leave the screen advancing a clock the root does not hold.
	_world = WorldPulse.new(_actor, BeatDirector.new())
	# The event module's beats go through the director, and this is the seam that makes
	# that true. `EventBeatWriter` records the ledger itself, so re-offering from
	# `WorldPulse` would double-count a monotone fact (ADR 0117 line 51); routing the
	# event module's OWN offer instead is the only ordering that is both once and
	# resolved. `Callable`, not a reference, for the reason `NpcApi.set_minter` gives.
	EventBeatWriter.set_offer_resolver(Callable(_world, "offer_event_beat"))
	# The durable place reaches the event module from the one place that OWNS the
	# moment of arrival (`WorldStage.mount` / `enter`), through an injected callable.
	# Without this line `EventApi.available` filtered every authored event out on
	# `location_id` before reading a trigger, so no world event could open in play
	# (DEF-0183). Installed HERE rather than in `_build_actor` so a restored body and
	# a reborn one are both covered, and before `_mount_home` so the first screen a
	# player mounts a body on already has it.
	WorldStage.set_location_publisher(Callable(EventApi, "set_location"))
	# ADR 0170 (a) and ADR 0173 (c): the ARRIVAL is the observation, and the world fold is
	# what folds the arriving place's clock. Installed HERE, beside the place publisher and
	# for the same reason — a stage mounted before this line ran would enter a place whose
	# clock had never moved, which is the "wired, but only a test can reach it" shape
	# `set_interaction_handler` names. The epoch reader is the second half of ADR 0170's
	# overlay: a READ that says which history this place is currently living, and which
	# must answer for a place nobody is standing in — so it is a reader, not a fold.
	WorldStage.set_reconciler(Callable(_world, "observe_place"))
	WorldStage.set_epoch_reader(Callable(_world, "place_state"))
	_forge = SocketForgeProgram.new(_actor)
	_quests = QuestProgram.new(_actor)
	_install_interaction_handler()
	# The boot-time arrival program. It opens the SAME route the nav bar uses rather than
	# pushing a second copy of the scene: two doors to one screen means a screen the route
	# table does not know about, which is what 	est_screen_reachability exists to catch.
	#
	# `adopt_actor` goes in as the FOURTH argument, and that is the whole of the creation
	# wiring: a committed origin has to become the body the player then plays. Without it the
	# screen promised an exclusivity and the player got the generic boot hero. Injected rather
	# than named because `app/` is a `PRIVATE_UNIT` (`tools/arch/rules.py`) and this program
	# must not reach into the root it is part of — the same seam `SoulDeath` takes a rebirth
	# through.
	_creation = CharacterCreationProgram.new(
		_stack, CharacterCreationFlow.new(), navigate_to, adopt_actor
	)
	# **A hero restored from a save is adopted into the program, so the boot gate below can ask
	# the right question.** The gate used to be `not _creation.has_hero()`, and on a restored
	# boot `_created` is null — nothing had told the program about the hero already in hand — so
	# `has_hero()` was false and a returning player was dropped back onto the arrival screen
	# with a restored body already running. `restored_from_save()` existed for exactly this and
	# had no caller; `CharacterCreationProgram.adopt` exists for exactly this and had no
	# caller. Both are now on the line they were written for.
	#
	# **Guarded by `restored_from_save()`, because unguarded it inverted the fix.** A brand-new
	# boot builds a hero at `_build_actor()` a few lines earlier, so `_actor` is non-null
	# either way — adopting unconditionally made `has_hero()` true on EVERY boot, the gate
	# below became unreachable, and a new player was sent straight to the workbench with no
	# arrival, no origin and no body. The comment above describes the half that was fixed;
	# this condition is the half that made it true.
	if restored_from_save():
		_creation.adopt(_actor)
	if not _mount_home():
		return
	if _nav != null and not _nav.route_requested.is_connected(_on_route_requested):
		_nav.route_requested.connect(_on_route_requested)
	# Boot OPENS creation only for a player with NO hero — neither created nor restored. This is
	# the one production caller `open_creation` had: the docstring above it claimed a shipped
	# title flow would call it, and none existed, so the door was only ever openable from a
	# test. The condition is the hero, not the file: a new game gets the arrival screen, and a
	# returning player boots straight to the workbench.
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
		return {
			"ok": false,
			"reason": String(restored.get("reason", "no_readable_save")),
			"recovered": false,
			"generation": 0
		}
	var envelope := restored.get("envelope", {}) as Dictionary
	var payload := envelope.get("actor", {}) as Dictionary
	if payload.is_empty():
		return {
			"ok": false,
			"reason": "no_actor_payload",
			"recovered": bool(restored.get("recovered", false)),
			"generation": int(envelope.get("generation", 0))
		}
	var actor := Actor.from_dict(payload)
	if actor == null:
		return {
			"ok": false,
			"reason": "actor_unreadable",
			"recovered": bool(restored.get("recovered", false)),
			"generation": int(envelope.get("generation", 0))
		}
	_actor = actor
	_recovered_from_save = true
	# The saved body needs its providers re-mounted and its items deserialized. The payload
	# carries both, and a body with neither is a body whose stats never resolve -- silently,
	# because core never names a module and so cannot re-attach one.
	#
	# `restore_cultivation` attaches what the payload CARRIED and does not re-enrol: the
	# enrolment verbs overwrite `paths[path_id]`, so reusing them here reset every restored
	# rank, stage and progress back to `qi_refining` and shrank the sea with it. That made
	# the read half erase what the write half had just saved. It also gates the attach on
	# the path, because `MindCultivationApi.attach` mints a sea when the component is
	# absent -- an ungated restore hands a body a Sea of Consciousness it was never
	# enrolled in (BL-0523).
	ActorFactory.restore_cultivation(actor)
	# The per-actor mounts, so this method is self-contained: a caller that drives a
	# restore directly gets a body as complete as a fresh one. `_ready` calls the same
	# list again for the fresh branch, and that second call is safe by construction --
	# every verb in the list normalizes an existing ledger rather than appending, so
	# mounting twice is the same state as mounting once. `ItemsApi.attach` is the one
	# that is NOT safe twice (it replaces the inventory), which is why
	# `_attach_body_modules` replaces it and the payload's `item_state` is what a second
	# mount restores -- exactly the branch this save took.
	_mount_player_modules(actor)
	# The restored body is put where its save SAYS it was (ADR 0192) — AFTER the attach
	# list, because `EventApi.attach` normalizes the whole event ledger. Additive keys
	# only: `test_cultivation_boot_round_trip` slices this function as TEXT.
	var standing := _stand_restored_in_the_world(actor)
	return {
		"ok": true,
		"reason": "",
		"recovered": bool(restored.get("recovered", false)),
		"generation": int(envelope.get("generation", 0)),
		"difficulty": String(envelope.get("difficulty", "")),
		"located": bool(standing.get("located", false)),
		"location_id": String(standing.get("location_id", "")),
		"world_told": bool(standing.get("world_told", false)),
	}


## Whether the live actor came from a save rather than from creation. A boot flow asks this to
## decide whether to offer character creation at all.
##
## **This had zero callers, and the gate that replaced it was wrong.** The boot line asked
## `_creation.has_hero()` instead, which on a restored boot was false because nothing had told
## the program about the body already in hand — so a returning player was sent back through
## arrival. Boot now adopts the live actor into the program above, which makes `has_hero()`
## the answer to "does this player have a hero at all", and this accessor remains the direct
## read for a probe that wants to know which of the two produced it.
func restored_from_save() -> bool:
	return _recovered_from_save


## Stand `body` in the place its save CARRIES, and report what happened (ADR 0192).
## The implementation is the body half's, beside the fields that keep ONE stage and ONE
## adapter per root; a subclass calling an inherited private method is legal, and the
## whole of the reasoning — why the place is READ rather than drawn, and why an
## unlocatable body is refused by name before any publish — moved with it to
## `_stand_restored_in_the_world` in `item_workbench_body.gd`.
func _stand_restored_in_the_world(body: Actor) -> Dictionary:
	return stand_restored_in_the_world(body)


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
##
## ## What this frame is FOR, now that the world has no clock
##
## **There is no real-time clock for the world (ADR 0167, ADR 0173).** Idle is frozen:
## the world moves only when the player acts, through [method ItemWorkbenchPlay.advance_world]
## and nothing else, so `_world.pull(delta)` is gone from here rather than merely unused.
## What stays is the TURN TIER — combat decay, social bonds, technique upkeep and
## gestation are measured in real seconds, and combat is the one thing that spends one
## (ADR 0173 "Where combat's real seconds enter"). Death polls on this frame because a
## death is not a cadence: it is a thing that happened, and it saves the instant it does.
func _process(delta: float) -> void:
	# A no-op on a null actor rather than a crash: the root can be mounted before it
	# built one, and a frame that cannot advance anything is not a reason to stop the
	# whole UI. `StatusLoop.tick` refuses that same case by name.
	if _status_loop == null or delta <= 0.0:
		return
	# ## The tick's REPORT is read, not discarded (BL-0716, BL-0748)
	#
	# This line used to be `_status_loop.tick(delta)` with the whole dictionary thrown
	# away, and `FertilityApi.advance` returns the child it minted under `born`. So a
	# birth was COMPUTED and DROPPED: the child existed only inside
	# `PregnancyStatus.offspring`, which `advance` erases at the end of the postpartum
	# stage about ten seconds later — and ADR 0089 means it could never ride a save
	# either, because statuses are session-only. A child was built correctly (race
	# resolved, per-lineage purity blended, the factory spine installed by BL-0280) and
	# then ceased to exist. Nothing read the key: grepping `born` across `game/src` found
	# exactly one hit, the write.
	#
	# Reading it here is what makes the birth OBSERVABLE, and `_register_birth` below is
	# what makes the child EXIST. It is this frame because this is the only tick caller
	# (ADR 0106) and a second clock for births is the ADR 0089 defect one layer down.
	var tick := _status_loop.tick(delta)
	for child in tick.get("born", []) as Array:
		_register_birth(child as Actor)
	# The DRILL rides the same frame and the same delta (ADR 0195). Its whole
	# implementation is the readout half's, beside the body it ages — which is why the
	# call is made here rather than through a one-line forwarder of its own: this file is
	# at the thousand-line ceiling, a second frame-adjacent wrapper costs eight lines to
	# say nothing, and `tick_readout_drill` is inherited so the root answers it by name
	# either way. Still exactly ONE tick caller.
	tick_readout_drill(delta)
	# The FIGHT's opponent rides the same frame (ADR 0197). `StatusLoop` holds one actor,
	# so the opponent cannot ride `_status_loop` without resetting the hero's collapse
	# window every frame. A second INSTANCE is not a second clock: one more call on the
	# one frame, handed that frame's delta, no-op with no live fight.
	tick_fight(delta)
	# No world pull and no autosave here, and neither was a rounding error in a frame
	# driver: the world has no real-time clock at all (ADR 0167, ADR 0173), so there is
	# nothing for a delta to convert, and the autosave counts PERIODS and rides the
	# action path with them (ADR 0179, `ItemWorkbenchPlay.advance_world`). Death keeps
	# the frame because a death is an EVENT rather than a cadence.
	poll_death()


## Give a newborn a home, or say out loud that it has none.
##
## ## What this does, in order, and why each step is here
##
## 1. **Record the fact.** `WorldFact.record` is the repo's ONE monotone ledger of "a
##    thing happened" (ADR 0113) and it is the one of those places the child can reach
##    TODAY and survive a save: it writes into the parent's `module_data["world_facts"]`,
##    which `Actor.to_dict` round-trips. This is also the only step that gives the birth a
##    durable identity — the count is monotone, so the fact of the first child is
##    answerable from `since` long after the status that carried the actor is gone.
## 2. **Record the lineage, read back through the modules that own it.** The row is
##    primitives assembled by CALLING `RaceApi` and `BloodlineApi` on the child, never by
##    copying a value `fertility` computed — so a projection this root could not see is
##    visible rather than assumed, and `app/` stores no second copy of either ledger.
## 3. **Refuse a child that is not a child.** `resolve_offspring` mints through an
##    injected builder and `push_error`s when that builder returns null, so a null here is
##    a wiring fault. It is reported and NOT recorded: a ledger that claims a birth no
##    body happened for is worse than one that says nothing.
##
## ## Why the roster is deliberately NOT reached for
##
## `NpcApi.spawn` refuses an id `NpcCatalog` does not ship, and a newborn has no authored
## `NpcDef` — minting one would be authoring content to cover a wiring bug, and the roster
## entry would then be a claim about content this fix does not own. `WorldStage.register_npc`
## is the other candidate and is worse: it is a LIVE-IN-ROOM index that `leave()` empties,
## so a child registered there would vanish on the next travel — the same ten-second
## window this defect is about, moved rather than closed. Both are filed for the
## orchestrator instead, with the seam stated above.
##
## Returns `{ok, reason, actor_id}` so a probe and a caller can name what happened rather
## than infer it from a table's size. Private on purpose: the composition root is the only
## layer that may name `Actor` and a module's birth, and a public verb here would need a
## caller `src/` does not have.
func _register_birth(child: Actor) -> Dictionary:
	if child == null:
		return {"ok": false, "reason": "no_child", "actor_id": ""}
	var actor_id := String(child.id)
	# `resolve_offspring` names the child `"<mother>_offspring"`, so a second birth in the
	# same run would collide on this key and silently overwrite the first. Keying by the
	# id alone would drop a child; keying by the sequence never can, and the id is carried
	# in the row so a reader can still tell who was who.
	var key := "%s#%d" % [actor_id, _born.size()]
	# The purity map is read through the facade rather than from the status, for the reason
	# the class docstring gives: absence is zero concentration, not a missing key, so this
	# loop sees exactly the lineages the child's own ledger carries.
	var lineages := {}
	for lineage_id in BloodlineApi.awake(child):
		lineages[String(lineage_id)] = BloodlineApi.purity_of(child, lineage_id)
	_born[key] = {
		"actor_id": actor_id,
		"race": String(RaceApi.race_of(child)),
		"faction": String(child.faction),
		"parent_id": "" if _actor == null else String(_actor.id),
		"lineages": lineages,
		"sequence": _born.size(),
	}
	# LAST, so a fact is never recorded for a row that was not written. Monotone, so a
	# re-registration cannot double-count — `WorldFact.record` is the ledger's only verb.
	WorldFact.record(child, BIRTH_FACT, 1)
	return {"ok": true, "reason": "", "actor_id": actor_id}


## Make `body` the current actor, re-binding everything that held the old one.
##
## ## A half-swapped body is the failure this exists to prevent
##
## The game would read two different actors — a screen on the old one, the soul on the new —
## and no assertion fails, because both are individually valid.
##
## ## The re-binding is `_attach_body_modules`, not a list of its own
##
## **This method used to re-attach only seven modules and stop**, which is how a reborn body
## ended up with an empty destiny ledger, an empty world-event ledger, no quest ledger, no npc
## roster bound to it, no combat mechanism, no technique seams and a realm-flat element
## multiplier — ADR 0069's recorded failure, happening after every single rebirth. The
## docstring here claimed "every holder is re-pointed, so a future binding cannot be forgotten
## silently", and nothing made that true: the list it claimed to describe existed only as this
## method's body. There is now no list here to forget a line in.
##
## ## What a reborn body does NOT get, and why (ADR 0130)
##
## The old body's inventory, kit, technique codex and set bonuses do not cross the rebirth.
## `_attach_body_modules` mounts the modules those live on — an EMPTY bag, an EMPTY codex, a
## re-derived set projection — because a body with no bag at all has no kit to lose, and
## `ElementsApi.apply_realm_modifiers` must still run so the new body's realm is not R1-flat.
## The world-scoped things the soul, the anchors, the world fact ledger and the institutional
## claims are untouched by any of this: a death costs the soul and never the world.
func adopt_actor(body: Actor) -> void:
	if body == null:
		return
	_actor = body
	# The ONE attach list, shared verbatim with the fresh build and the restore.
	_attach_body_modules(body)
	_status_loop = StatusLoop.new(body)
	# Through `adopt_world`, not a bare assignment: the fresh fold's total starts at zero,
	# and the autosave's `_periods_seen` must reset with it or the first
	# `AUTOSAVE_PERIODS` world-moving periods after a rebirth read as `maxi(0, small -
	# large)` — zero periods moved, silently, on the save schedule (ADR 0179).
	adopt_world(WorldPulse.new(body, BeatDirector.new()))
	# Both seams are re-pointed at the NEW body rather than left on the old one. The
	# offer resolver names a `WorldPulse`, and `_ready` just replaced that object; a
	# seam left pointing at the first one would offer the reborn hero's beats into a
	# director still holding the hero who fell — a live call with a dead owner, which
	# is exactly the half-swapped-body failure this method exists to prevent.
	EventBeatWriter.set_offer_resolver(Callable(_world, "offer_event_beat"))
	WorldStage.set_location_publisher(Callable(EventApi, "set_location"))
	# And the ADR 0170 seams, for the reason the two lines above are re-pointed: they name
	# a `WorldPulse` and `_ready` just replaced that object with the reborn hero's. A seam
	# left on the old fold would fold the FALLEN hero's clock against the new one's
	# periods — a live call with a dead owner, which is the half-swapped-body failure this
	# method exists to prevent.
	WorldStage.set_reconciler(Callable(_world, "observe_place"))
	WorldStage.set_epoch_reader(Callable(_world, "place_state"))
	_forge = SocketForgeProgram.new(body)
	_quests = QuestProgram.new(body)
	_death_armed = ""
	_last_death = {}
	# ADR 0185. A REBIRTH is the one event that can leave a STALE cast aim: the page
	# on screen was aimed at a foe the FALLEN hero was fighting, and the body behind it
	# has just been replaced. Unbinding here means the new body's first mount is aimed by
	# `ROUTE_TECHNIQUE_LOADOUT`'s arm rather than inheriting the old hero's aim — and it
	# costs nothing, because `act_cast` refuses an un-aimed page for free and
	# `TechniqueCasting.activate` is never reached.
	clear_cast_target()
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


## The route table this root publishes, so the navigation bar, a probe and a
## test all read the same list. Primitives only.
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


## Free everything this root built that is not a node the stack owns. Idempotent, and
## safe to call after an aborted test — the headless runner shares ONE process across every
## suite, so a leak here is a leak everywhere.
##
## The world is detached and freed with `remove_child()` then `free()`, never
## `queue_free()`: the runner drives tests from `SceneTree._initialize()` and never
## processes a frame, so a deferred free leaks for the life of the process. That is the
## shape that took a run to 67 GB resident (INC-0004/INC-0005).
func teardown() -> void:
	var screen := _live_screen()
	if screen != null:
		DomainBoot.release_world(screen)


## ADR 0089's combat-exit purge, handed to the loot screen as a `Callable`.
##
## ## Why the composition root is the one that may call it
##
## `StatusLoop.exit_combat` is `app/`, and `app` is a `PRIVATE_UNIT`
## (`tools/arch/rules.py:35`), so `ui/` may name neither the type nor the verb. This is
## the same seam ADR 0143 gives the quest screen's accept verb, and it is called from the
## `ROUTE_LOOT` arm above at every mount.
##
## ## Why it resolves the loop HERE rather than capturing it
##
## `adopt_actor` REPLACES `_status_loop` on every rebirth (ADR 0130). A callable bound to
## the first loop object would keep purging a body that no longer exists, while the player
## played a reborn one and carried the burn past every fight — the F-6 defect still
## present under a new name. Reading the field per call is what makes the seam survive a
## body swap.
##
## ## Why an absent loop is a no-op, not a crash
##
## The root mounts the loot route from `_ready`, which builds `_status_loop` before
## `_mount_home`, so this is unreachable in the shipped boot. It is refused BY NAME rather
## than assumed, because the alternative is a screen that cannot leave a fight at all if
## the wiring is ever reordered — and walking away from a boss must never depend on a
## bookkeeping step.
func _purge_combat_scope() -> Array[String]:
	if _status_loop == null:
		return []
	return _status_loop.exit_combat()


## The market row the hero is standing in, as a shop `location_id`.
##
## ## Why the root answers this rather than the screen
##
## `ShopDef.location_id` is authored content that differentiates a travelling merchant
## without a second price formula, and `ShopCatalog.at_location` is the ONE answer to
## "which shops are in this room". The id itself lives on `WorldSpawnApi.current`,
## which is `world_spawn/api.gd` — and `world_spawn` is NOT in `rules.UI_MODULES`, so
## a screen may not ask. The composition root asks it on the screen's behalf and hands
## over a plain `StringName`, which is all the screen ever needed.
##
## ## An unlocated hero reads as NO location, not a guess
##
## `WorldSpawnApi.current` publishes `located: false` for a body nobody has moved, and
## "nowhere in particular" is a representable state rather than a failure. A defaulted
## location here would be the caravan-trades-everywhere defect ADR 0100 names, so the
## honest answer is an empty id and the screen renders an empty market row.
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
func _auction_bidder_of(bidder_id: String) -> Actor:
	if bidder_id == "":
		return null
	return AuctionStanding.body_of(bidder_id)


## Buy `rows` from the shop named by `shop_id`, on behalf of `player`.
##
## ## Why the shop id crosses the seam and the `Actor` does not
##
## `MarketApi.buy(shop_actor, player, rows)` needs a merchant `Actor`, and only
## `ShopCounter.counter` can mint one — it resolves the authored def, realizes the
## def's own seeded stock, funds the purse from that stock's worth, and CACHES the
## result per shop id so the goods a merchant has already sold stay sold. A screen
## cannot mint an `Actor` (`ActorFactory` is `app/`) and must not build its own
## counter, so the root resolves the cached merchant here and the screen only ever
## holds the id a content author wrote.
##
## The screen does the pricing, and so does the settlement: it picks a line off the
## shelf `ShopCounter.summary` already priced, and `MarketApi.buy` prices that same row
## through the same `MarketTransfer.quote`. What the panel showed is what the verb
## charges, by construction rather than by agreement.
func _market_buy(shop_id: StringName, player: Actor, rows: Array) -> Dictionary:
	var counter := ShopCounter.counter(shop_id)
	if counter == null:
		return {"ok": false, "reason": ShopCounter.UNKNOWN_SHOP, "coins": 0}
	return MarketApi.buy(counter, player, rows)


## Sell `rows` to the shop named by `shop_id`, on behalf of `player`.
##
## `MarketApi.sell` additionally takes the `ShopDef` so it can enforce the authored
## `buys` list and refuse `shop_will_not_buy` — which is how a black market is authored
## rather than priced. The root resolves the def from the same catalog the counter came
## from, so the two halves can never disagree about which shop was meant.
func _market_sell(shop_id: StringName, player: Actor, rows: Array) -> Dictionary:
	var counter := ShopCounter.counter(shop_id)
	if counter == null:
		return {"ok": false, "reason": ShopCounter.UNKNOWN_SHOP, "coins": 0}
	return MarketApi.sell(ShopCatalog.instance().definition(shop_id), counter, player, rows)


## The navigation bar asks; this root decides. One request in, one screen out.
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
