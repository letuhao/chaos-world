class_name ItemWorkbenchBody
extends ItemWorkbenchPlay

## The composition root's BODY half: the hero it builds, the module attach list it
## mounts on that hero, the hit seams it installs, and the read bridges it hands a
## screen for it.
##
## ## Why this is a base script and not a set of `ItemWorkbenchApp` methods
##
## Extracted from `item_workbench_app.gd` because that file passed the thousand-line
## ceiling. The cut is the one this class's own docblock already draws: the shell is
## "boot, the screen stack, the navigation bar, and the per-actor attach list", and
## this is everything on that list plus the seams. Two reasons to change, so two files
## (AGENTS.md, "one module = one reason to change").
##
## ## Why inheritance and not delegation
##
## **The public surface is the contract, and it does not move.** `adopt_actor` is
## public and is handed to `SoulDeath` and `CharacterCreationProgram` as a `Callable`
## from the shell's `_ready`, and `_mount_player_modules` is called by `restore_actor`
## in the shell — so moving either to another object would leave a caller naming a
## method that is not there. As a base class the root still answers every one of them,
## and `get_script_method_list()` on it reports the inherited declarations too, so
## `tests/app/test_screen_reachability.gd` still sees the whole door surface. **No
## public method was moved off that class or renamed**, and no signature changed.
##
## ## What stayed behind, and why those are not negotiable
##
##   - `_ready`, `_process`, `restore_actor` and `restored_from_save` all stayed in the
##     shell. Two suites read `item_workbench_app.gd` as TEXT: `tests/app/
##     test_status_clock.gd` requires `StatusLoop.new(` and a `func _process(` signature
##     to appear THERE and nowhere else under `res://src` (one tick caller is ADR 0106's
##     claim), and `tests/modules/save/test_cultivation_boot_round_trip.gd` slices that
##     file between `func restore_actor` and `func restored_from_save`. Both still hold.
##   - `adopt_actor` stayed in the shell because it re-points `_forge` and `_quests` and
##     calls `_live_screen()`, all of which are the shell's own screen wiring. Splitting
##     it would have meant moving the screen stack into this file.
##   - `_register_birth` stayed, and `tests/arch_rules/test_fact_ledger_writers.gd` is
##     why: it pins the exact set of files that call `WorldFact.record`, and this root is
##     the eighth. A birth moved here would silently under-count the content census.
##   - `BIRTH_FACT` stayed declared on `ItemWorkbenchApp`, because
##     `tests/app/test_lineage_birth_wiring.gd` reads it as `ItemWorkbenchApp.BIRTH_FACT`.
##
## ## The constants moved WITH their bodies, not with the class
##
## `STARTER_ITEMS`, `STARTING_CAST`, `READOUT_MAGNITUDE` and `READOUT_SHARE` are
## declared HERE because the bodies that use them are here, and a base class cannot
## name a subclass's constant. Nothing outside this file reads any of the four — the
## grep that established that is in the split's own commit — so no `ItemWorkbenchApp.
## <NAME>` spelling anywhere in the tree depends on where they sit.

# --- starter_items -------------------------------------------------------
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

# --- readout_consts ------------------------------------------------------
## The readout's bare swing. Deliberately NOT `CombatBoot.BARE_SWING_MAGNITUDE`: that is
## the priced value of an ordinary, unremarkable swing, and this one exists to make a
## WOUND reachable — `BodyWounds.add` divides severity by the target's integrity maximum,
## so at the ordinary magnitude a wound threshold of `0.05` may never be crossed in a
## sitting and the necrosis row this surface exists to render would always read "no
## meridian carries a wound". A demo swing is not a balance change: it is a different
## `TechniqueDef` that nothing in production casts.
const READOUT_MAGNITUDE := 12.0
## The shipped default elemental share, restated as a plain number because `ui/` may not
## read `CombatTuning` and `app/` should not reach into the `.tres` for one field.
const READOUT_SHARE := 0.8

# --- starting_cast -------------------------------------------------------
## **`elder_wei` is in this list, not decoration.** He is the only `story` tier individual,
## the only cast member whose ladder carries `advance_after`, and the only target of the
## authored `npc_tally` beat in `the_favour_of_elder_wei.tres` — so with him absent the
## whole stage-advance mechanic is correct, tested, and unreachable in play: the tally
## returns `unknown_npc` because nobody ever met him.
const STARTING_CAST: Array[StringName] = [
	&"elder_wei",
	&"gate_keeper_bo",
	&"smith_bearcutter",
	&"drifter",
]
## The one path this root persists the workbench's own state to. Declared here with
## the two verbs below rather than left in the shell, because the shell reaches them
## only by NAME — `Callable(self, "_save_state")` in the `ROUTE_WORKBENCH` arm of
## `_bind_route_screen` — so the lookup follows the root through the base chain.
##
## `SAVE_PATH` is spelled the same way in `item_state_store.gd`, which is the seam the
## UI program reads the slot back through; the two must name one file, and they do.
const SAVE_PATH := "user://item_workbench_state.json"

# --- readout_field -------------------------------------------------------
## The combat readout's drill body, minted once and kept (ADR 0174). Cached so a reader
## who re-enters the route strikes the SAME body and can watch a wound accumulate,
## which is the whole point of a wound being observable at all. Null until the readout
## route is bound, so an app that never opens the page mints no inhabitant.
var _readout_drills: Actor = null

# --- mount_and_attach ----------------------------------------------------
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
## ## Why it is now a one-line forward rather than its own list
##
## This method used to hold the first seven attaches and let `_build_actor` hold the rest,
## which is how a reborn body ended up reading eight ledgers nobody had re-attached. The
## whole sequence — this list, the cultivation tail and the technique seams — lives in
## [method _attach_body_modules] and is stated there in one place. This wrapper survives as
## the name the restore and `_ready` already call.


func _mount_player_modules(actor: Actor) -> void:
	_attach_body_modules(actor)


## ## THE ONE attach list. Read this before adding a module to a hero.
##
## Every per-actor binding this root owns happens here, in one sequence, and the three
## callers that need a complete hero — [method _build_actor] (fresh boot), [method
## restore_actor] (a saved body) and [method adopt_actor] (a reborn body) — all reach it
## through this one method. That is the whole fix, and it is structural rather than
## cosmetic: the audit found EIGHT bindings (`SocialApi`, `DestinyApi`, `EventApi`,
## `QuestApi`, `NpcBoot.install`, `CombatBoot.install`, `_bind_technique_seams` and
## `ElementsApi.apply_realm_modifiers`) present in `_build_actor`'s tail and absent from
## `adopt_actor`, so every rebirth left the Fate screen reading an empty ledger, the world
## map empty of open events, quests not progressing, npc bonds gone and the element realm
## multiplier degressed to R1 (ADR 0069's recorded failure). A duplicated list cannot fail
## that way: there is no second list to forget a line in.
##
## ## The ORDER is load-bearing and is preserved exactly as `_build_actor` documents it
##
##   1. `elements` — `attach`, which mounts the provider only when the actor has none and
##      refreshes the realm half either way. `ActorFactory.build` mounts it for a fresh body
##      and `Actor.from_dict` restores no provider at all, so this list is the one place that
##      can be right for both (ADR 0069). It reads the paths, so it runs after every
##      enrolment has written one.
##   2. `dual_cultivation`, then `fertility` — fertility adds to bases dual cultivation owns.
##   3. `items` — body training spends the realm's elixirs through the inventory.
##   4. `set_bonus` — derived from equipment, so it must never run before items.
##   5. `techniques` LAST — it resolves authored options through the items vocabulary (ADR 0056).
##   6. `social`, `destiny`, `event`, `quest` — ledgers. Destiny before event, because an
##      event's prize is a `DestinyApi.earn_fate` and that must land in a key that exists.
##   7. `npc` — injects the npc constructor and binds the roster to THIS actor.
##   8. `combat`, then the technique seams — a seam is only correct once the module it wires
##      is complete, and `TechniquesApi.attach` is what makes the codex exist for
##      `TechniqueDelivery` to write into.
##
## ## What is deliberately ABSENT, and why (ADR 0130)
##
## `ItemsApi`, `SetBonusApi` and `TechniquesApi` are on the list — a body that cannot hold
## an inventory has no kit, and `ItemsApi.attach` REPLACES the inventory, so a reborn body
## must be given an empty one rather than left without a bag at all. What does NOT cross a
## rebirth is the CONTENT: the arrival ledger is empty for a new body, the technique codex
## is rebuilt empty, and the set-bonus projection is re-derived from an empty equipment
## table. That is the design, not an omission — ADR 0130 says inventory and kit do not
## cross a rebirth, and a "fix" that copied the old body's stacks across would violate it.
##
## `_npc_settlement` is deliberately NOT restocked here. A reborn body re-binds the roster and
## the constructor but stands in no room, because `STARTING_CAST` is a boot-time fact about
## the settlement the slice OPENS on, not a property of a body.


func _attach_body_modules(actor: Actor) -> void:
	if actor == null:
		return
	# The world-scoped ledgers first, and in the SAME order the old `_mount_player_modules`
	# used: a soul and an anchor live in an injected store rather than on the actor (ADR 0127,
	# ADR 0146), so this is a READ of that store — which `_ready` has already published by
	# the time any of the three callers below reaches this method.
	SoulApi.attach(actor)
	AnchorApi.attach(actor)
	SocketApi.attach(actor)
	LootApi.attach(actor)
	DifficultyApi.attach(actor)
	# ## `race` and `bloodline` — the two lineage attaches that were MISSING here
	#
	# `Actor.from_dict` restores `module_data`, so `race_state` and `bloodline_state`
	# survive into the payload and the LEDGER is intact on a restore — `RaceGate` even
	# carries a catalog fallback for an unprojected body, which is why every GATE kept
	# answering across a save/load and the defect stayed invisible. The PROJECTION did
	# not survive: `Actor.from_dict` restores components and NEVER a `StatProvider`, and
	# the stat modifiers, the base-attribute grants, the affinities and the trait mirrors
	# a race and an awakened lineage contribute are rebuilt only by the attach. Nothing on
	# this list called it, so after ONE reload a stoneborn lost its +15% `max_health` and a
	# tideborn at 0.72 read awake while `bloodline_power` answered 0.0 — with no error
	# anywhere, because every reader that mattered was reading the ledger (BL-0746).
	#
	# Why the fresh branch did not hide this: `ActorFactory.build` attaches sect and clan,
	# and `CharacterCreationFlow._body` attaches `race` on the CREATION branch only. A
	# restored actor reaches neither, so the defect persisted on the only path a returning
	# player walks. Both attach calls belong HERE for the reason `ClanApi.attach` is
	# reachable through the composition root: this is the one list all three callers — the
	# fresh build, the restore and a rebirth — share, so a restore cannot skip it.
	#
	# Both are idempotent BY CONSTRUCTION rather than by luck: `RaceProjection.apply` and
	# `BloodlineProjection.apply` each strip their own prior contribution (the ledger
	# records what was granted, so the strip is exact) and rebuild from the ledger. So
	# running them on a fresh actor that `CharacterCreationFlow` already raced is net-zero,
	# and running them twice is the same state as once. FIRST on this list because every
	# ledger below can read a body plan, and `FertilityApi`'s gestation step does.
	RaceApi.attach(actor)
	BloodlineApi.attach(actor)
	# `attach`, not the bare refresh: `Actor.from_dict` restores components and NEVER a
	# `StatProvider`, so a restore or a body swap arrives with no provider and the realm MULT
	# would land on nothing. `attach` mounts it when absent and refreshes either way.
	ElementsApi.attach(actor)
	DualCultivationApi.attach(actor)
	FertilityApi.attach(actor)
	ItemsApi.attach(actor)
	SetBonusApi.attach(actor)
	TechniquesApi.attach(actor)
	SocialApi.attach(actor)
	DestinyApi.attach(actor)
	EventApi.attach(actor)
	QuestApi.attach(actor)
	NpcBoot.install(actor)
	# The domain twin, idempotent like every line on this list. `DomainBoot.install`
	# injects `DomainSpawner`'s actor constructor and the two items contacts
	# `DomainFixtures` needs; both default to refusing, so without this line a domain
	# answers `no_inventory_bridge` to every treasure and `spawn` can only return null.
	DomainBoot.install()
	CombatBoot.install(actor)
	_bind_technique_seams()
	# The economy program: four modules (`economy`, `market`, `holdings`, `custody`, `forage`)
	# and FIVE injected seams. Every one of them defaults to refusing or to an actor-scoped
	# mirror, so without this line the whole program is present, tested, and unreachable —
	# a rival cannot see a held resource node, a bidder cannot see a listed lot, and a
	# custody subject cannot be minted. `EconomyBoot.install` is idempotent like every other
	# line on this list. Placed AFTER `_bind_technique_seams` so the last thing installed is
	# the most recently written, which makes a failure here the newest thing a reader sees.
	EconomyBoot.install(actor)


# --- build_actor ---------------------------------------------------------
## A fresh hero with every path the shipped slice offers, the core resource
## pools, and a starting kit drawn from the shipped content tree.
##
## ## What this method owns, and what it no longer does
##
## **This used to hold the attach order itself, and that was the defect.** `restore_actor`
## and `adopt_actor` each re-typed their own shorter version of it, which is how EIGHT
## bindings came to exist in a body swap and nowhere else. The whole sequence is now
## [method _attach_body_modules], and this method reaches it exactly as the other two do —
## so a module added to a hero is added once, for a fresh body, a saved body and a reborn
## body alike.
##
## What stays here is what is genuinely ABOUT a first hero and about nothing else:
##   1. `build` — core pools and the sect ledger, which grants recognition and
##      never power (ADR 0084), so wiring it cannot hand a new actor an edge;
##   2. the three cultivation enrolments. The element realm refresh inside the attach
##      list reads the highest realm off these paths to write each element's multiplier;
##      refreshing it before a path exists writes nothing, which is exactly the silent
##      realm degression ADR 0069 records. So the enrolments come FIRST and the
##      refresh after, and the refresh reaches the provider through `attach`, which mounts
##      it only when the body has none;
##   3. the starting kit, which is the one thing a reborn or restored body does NOT get.
##      A new arrival begins with a bag; a reborn one gets an empty one, per ADR 0130.
##
## `_build_actor` is deliberately NOT re-run on a body swap — `adopt_actor` is the whole of
## that, and re-running this method would mint a second hero and stock a second kit.
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
	# Every remaining module, in the one order the whole composition root shares.
	_attach_body_modules(actor)
	# …and stock the place the player starts in, through the ONE room entry point
	# (`populate_room`), so the cast is standing in a location rather than merely
	# reachable. `NpcApi.populate`'s own cap bounds the room, and `replace_first`
	# defaults true, so this is a stock rather than an accumulation. It is a single
	# starting settlement, NOT a room system: no arrival re-stocks anywhere, because
	# nothing in this repo models a room or an arrival yet (see the report on
	# BL-0626). A place gets a cast when an author wires one, and until then the boot
	# path stands one up where the player already is. It runs AFTER
	# `_attach_body_modules` because `populate_room` re-runs `NpcBoot.install` itself.
	_npc_settlement = NpcBoot.populate_room(actor, STARTING_CAST, NpcApi.ROLE_NPC, &"mortal_plains")
	var inventory := ItemsApi.inventory(actor)
	for item_id in STARTER_ITEMS:
		var def := _resolve(item_id)
		if def != null:
			inventory.add(def, 1)
	return actor


# --- technique_seams -----------------------------------------------------
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
## ## Why `CombatBoot.resolve_hit` and not a bare `breakdown` (ADR 0154)
##
## This passed FIVE arguments, so `CombatSpine.resolve_hit`'s sixth — `ctx_builder` —
## was an empty `Callable` on every production hit. That is not a default, it is a hole:
## `QiDamage.builder` / `BodyDamage.builder` / `MindDamage.builder` were never called
## from `src/` at all, so `ctx.data` carried none of the authored inputs. `element_share`
## therefore read `0.0` on every strike, fell to `default_element_share` from the
## `.tres`, and the per-technique share that all 55 authored `.tres` files set was
## INERT; `aim_meridian` never arrived, so a `named` body aim resolved as `random`.
##
## Adding `ctx_builder_for` here closed that half and left the worse half open. Picking
## the BUILDER is not picking the MECHANISM: this call still went straight to
## `CombatEngineApi.breakdown`, and the spine reads the mechanism off
## `MechanismSlot.of(attacker)` at S4 (`spine.gd:112`). On the shipped player that slot
## is `QiDamage` — `_build_actor` enrols THREE paths, `has_body == has_mind`, so
## `CombatBoot.bind_mechanisms` takes its both-paths case on purpose — so a BODY
## technique fired from this screen ran `QiDamage` and `aim_meridian` rode along in
## `ctx.data` to be read by nothing. **That is what ADR 0161 recorded**: body and mind
## could not fire at all, not rarely, never.
##
## `CombatBoot.resolve_hit` is the one function that does BOTH halves from a single
## answer: `mechanism_for_hit` names the mechanism, that same name picks the
## `ctx_builder`, the mechanism is bound to the attacker for the scope of the call, and
## the previous binding is restored on return. Which mechanism runs and what it reads
## therefore cannot be selected by two rules and drift — and `combat_engine/spine.gd`
## still learns nothing about what a qi, a body or a mind hit is.
##
## ## Why THIS method and not reading `_hit_resolver` from the casting path
##
## `CombatBoot.install` already installs `Callable(CombatBoot, "resolve_hit")` as the
## per-hit seam, and it is the injectable form of the call below, so the alternative —
## `TechniqueCasting` invoking `_hit_resolver` — would need a second, parallel route for
## the SAME decision and would leave this method as a second answer to "how does one hit
## resolve", which is how the two halves came to disagree in the first place. Calling
## the static keeps ONE production route to the mechanism switch and makes it a direct
## expression of it: delete the call below and every hit reverts to the installed
## mechanism, visibly.
##
## `to_dict` is the descriptor form `CombatEngineApi.breakdown` returned — the very
## object it delegates to, `CombatOutcome.to_dict` (`api.gd:115`) — and it is the right
## return because `TechniqueCasting._resolve` accepts a `Dictionary` verbatim.
func _resolve_technique_hit(attacker: Actor, target: Actor, technique: TechniqueDef) -> Dictionary:
	return (
		CombatBoot
		. resolve_hit(attacker, target, technique, CombatEngineApi.tuning(), null)
		. to_dict()
	)


# --- soul_read -----------------------------------------------------------
## The soul and the last death, as primitives, for the soul and hearth page.
##
## `soul_summary()` on the play half already carries both, and it is the only read
## that puts the soul, the last death and the save in one payload — so this is that
## dictionary narrowed to the half the page renders, rather than a second read that
## could disagree with a probe asking the same question.
func _soul_read() -> Dictionary:
	var view := soul_summary()
	return {"soul": view.get("soul", {}), "last_death": view.get("last_death", {})}


# --- loot_bridge ---------------------------------------------------------
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


# --- readout_methods -----------------------------------------------------
## The combat readout's drill body (ADR 0174).
##
## ## Why a drill body exists at all, and why it is not a new mechanic
##
## `CombatEngineApi.resolve_hit` refuses a null defender, and a player-facing readout
## needs SOMETHING to strike. Minting it here rather than in the screen is forced: `ui/`
## may not name `ActorFactory`, which is a `PRIVATE_UNIT`. It is built through the same
## `spawn_npc` every other inhabitant goes through, so the drill body carries the same
## provider spine a real NPC does and a figure on the readout is a figure about a real
## `Actor`.
##
## Cached per app instance so a reader who re-enters the route strikes the same body
## twice and can watch a wound accumulate — which is the entire point of a wound being
## observable. A fresh body each time would make the wound ledger unreadable.
func _readout_target() -> Actor:
	if _readout_drills == null:
		_readout_drills = _build_readout_target()
	return _readout_drills


## ## Why the loadout is aimed at THIS body and not a second one
##
## `ROUTE_COMBAT_READOUT` and `ROUTE_TECHNIQUE_LOADOUT` are two surfaces on one process
## and there is exactly ONE foe in it: the drill body this root already mints and caches.
## The cast page asks for a target because `ui/` may neither read a present-foe roster
## (`npc` is not in `rules.UI_MODULES`) nor mint a body (`app/` is a `PRIVATE_UNIT`) —
## so a second drill would have been invented here, and then the Blow page and the Arts
## Set page would be about two different opponents with two independent wound ledgers.
## One body, one foe, both surfaces.
##
## `refresh_cast_target()` is the re-bind door: the drill is CACHED for the life of the
## app (so a wound accumulates and can be watched), which means it survives every route
## change — so nothing here is scoped by navigation at all, and a stale target cannot be
## produced by walking away from a fight. The drift that CAN happen is the app's own:
## [method adopt_actor] swaps the hero on a rebirth. That re-points the live screen
## through `setup`, and [method clear_cast_target] is what runs beside it, so the new
## body is aimed at by the next mount rather than inheriting the old hero's drill read.
func _cast_target() -> Actor:
	return _readout_target()


## Aim a mounted screen at the current foe, or take the aim away when there is none.
##
## Guarded with `has_method` rather than a bare `call`, because the ADR 0143 seams are
## screen-owned and a screen that drops one must degrade to the page's own `no_target`
## refusal — which the player can see and act on — rather than abort this arm and leave
## the route half-bound with no message at all. A missing seam is reported, never
## swallowed.
func _bind_target_screen(screen: Control, target: Variant = null) -> Dictionary:
	# Typed `Variant` and never inferred: `target` is untyped and this repo treats a
	# type inferred from one as an error. An explicit `target` is honoured verbatim so a
	# caller can aim at a body of its own choosing; omitting it means "whatever the
	# current encounter has", which is the only question this root can answer for a page
	# that has no notion of an encounter at all.
	var aimed: Variant = _cast_target()
	if target != null:
		aimed = target
	if not screen.has_method(&"bind_target"):
		return {"ok": false, "reason": "no_seam", "target": ""}
	# `null` through the seam is the documented unbind, so the cast page reports
	# "Nothing to aim at" rather than keeping a body nobody is in a room with.
	screen.call(&"bind_target", aimed)
	return {"ok": true, "reason": "", "target": "" if aimed == null else String(aimed.id)}


## Re-bind the mounted cast page at the current foe. Called on a rebirth, where the
## hero changed underneath the screen; a no-op on every other route, so it is safe to
## call unconditionally.
func refresh_cast_target() -> Dictionary:
	var screen := _live_screen()
	if screen == null or not screen.has_method(&"bind_target"):
		return {"ok": true, "reason": "not_mounted", "target": ""}
	return _bind_target_screen(screen)


## Take the aim away from every mounted page — the deterministic half of the seam, and
## what `bind_target(null)` is FOR. A screen that already holds a body is not reachable
## by navigation (`navigate_to` pops to root first), so this walks the stack's children
## rather than only the live screen: a page that outlives its route must not keep a
## target either. The walk is the stack's own `get_children()` and not its private
## `_screens` list, because this is `app/` and `app/` may not reach into `ui/`.
##
## ## The STALE TARGET is the bug this exists to prevent
##
## `TechniqueCasting.activate` PAYS before it resolves, so a page left aimed at a foe
## from an encounter that has ended is worse than an un-aimed page: the press would
## spend real qi and a real cooldown on a body the player was never shown. Unbinding is
## therefore not a courtesy — it is the state in which `act_cast` can refuse for free,
## which is the only layer positioned to refuse without spending (ADR 0185).
func clear_cast_target() -> Dictionary:
	var cleared := 0
	if _stack == null:
		return {"ok": true, "cleared": cleared, "target": ""}
	for node in _stack.get_children():
		var screen := node as Control
		if screen == null or not screen.has_method(&"bind_target"):
			continue
		screen.call(&"bind_target", null)
		cleared += 1
	# The DRILL goes with the aim. Dropping the ONE cache is what makes the next
	# `_cast_target()` mint a fresh body, so a foe that was present when the aim was
	# taken is never the body a later encounter aims at — and it drops the readout's
	# cache too, because both pages aim at that same one body.
	_readout_drills = null
	return {"ok": true, "cleared": cleared, "target": ""}


## The cast page's aim, as primitives, so a probe can ask "what would a press hit?"
## without reaching into a private field — the same contract `routes()` and `summary()`
## publish. `{}` when the page is not mounted.
func cast_target_summary() -> Dictionary:
	var screen := _live_screen()
	if screen == null or not screen.has_method(&"bind_target"):
		return {}
	return {
		"bound": true,
		"has_target": bool(screen.call(&"has_target")),
		"target_id": String(screen.call(&"target_id")),
	}


# --- world_bridge --------------------------------------------------------
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


# --- resolve_item --------------------------------------------------------
## Look a definition up by id through the items module's single resolver, so the
## app uses the same lookup as inventory, crafting, the generator and loot.
## Returns null rather than guessing, so a missing starter item never blocks the
## app.
func _resolve(item_id: StringName) -> ItemDef:
	return Crafting.resolve(item_id)


## Install the seam `DomainBoot.enter_domain` fires once a run exists. Idempotent, and
## installed beside `DomainBoot.install()` on the attach list because that is the ONE
## place `app/` installs domain seams.
##
## ## Why a `Callable` and not a reference
##
## `enter_domain` is a STATIC on `DomainBoot`, and the thing that has to stand the world up
## in the tree is the composition root — which is an INSTANCE. The repo already solved
## exactly this shape twice: `NpcApi.set_minter` and `CustodyApi.set_resolver` both take a
## `Callable` for the same reason, and `DomainSpawner.set_minter` forbids the alternative
## outright — a typed lambda whose body calls another script's static function killed the
## process on the shell's first frame (see `DomainBoot.install`). So this is
## `Callable(self, "_realize_domain_world")`, a bare method reference with no closure and
## no typed lambda.
func _install_domain_world_observer() -> void:
	DomainBoot.set_world_observer(Callable(self, "_realize_domain_world"))


## REALIZE the entered domain as a walkable world under the mounted domain screen, and
## answer what happened — or, called with `release`, FREE the world again.
##
## ## Why the screen is the parent
##
## The world has to be a `Node2D` somewhere it is actually DRAWN, and the domain screen is
## the only node in the tree that exists for the duration of a domain visit. Parenting it
## there means the ownership is the node that shows it: `ScreenStack.pop_to_root()` frees
## the screen, and the floor tiles, the walls, the navigation region, the inhabitants and
## the player go with it — no second owner to forget to clean up, which is the leak shape
## `tests/arch_rules/test_no_deferred_free.gd` records.
##
## ## Why nothing here is remembered
##
## The handle is NOT kept as a field. `teardown()` and the stack's own free find the world
## by the name `DomainBoot` publishes, so there is no second reference that can outlive the
## node — and no member on this root for `tools/arch`'s `app/` state rule to read.
##
## ## Why this takes a `StringName`
##
## `DomainBoot` reaches the parent back through this same seam, because it may not name a
## `ui/` type and guessing a second lookup would be a second thing that can disagree about
## where the world went. So one callable does both halves, and `release` is its other arm.
func _realize_domain_world(action: StringName = &"realize") -> Dictionary:
	var screen := _live_screen()
	if action == &"release":
		return {} if screen == null else DomainBoot.release_world(screen)
	var hero := _actor
	if hero == null:
		return {"ok": false, "reason": "no_actor"}
	if screen == null or String(screen.name) != ScreenRoutes.node_of(ROUTE_DOMAIN):
		# The run exists but nothing is showing the domain. REPORTED rather than drawn
		# somewhere the player cannot see: a world parented to an unrelated screen is a
		# world that outlives the visit that created it.
		return {"ok": false, "reason": "no_surface"}
	return DomainBoot.realize_world(screen, hero)


## The realized domain world, as primitives, or `{}` when nothing is realized. Published
## on the same contract as `routes()` and `summary()`: a probe asserts the wiring through
## a verb, never by reaching into a private field.
func domain_world_summary() -> Dictionary:
	var screen := _live_screen()
	if screen == null:
		return {}
	return DomainBoot.world_summary(screen)


# --- the file-backed state the UI program may not own ---------------------


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
