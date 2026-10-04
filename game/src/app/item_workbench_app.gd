class_name ItemWorkbenchApp
extends ItemWorkbenchPlay

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
##
## ## The split into two files
##
## This file is the SHELL: boot, the screen stack, the navigation bar, and the
## per-actor attach list. `ItemWorkbenchPlay` is the PLAY half it inherits — the
## actor itself and the four clocks that answer for it (world period, anchor
## repair, death poll, autosave).
##
## **Inheritance, not delegation, and that is the whole reason it works.** Every verb
## on the play half is called on the mounted root — a screen asks the root to advance
## a period, a probe asks it for the world, a suite asks it who the actor is — so a
## delegation would leave every one of those callers naming a method that is not there.
## As a base script the root still answers all of them, and `get_script_method_list()`
## on it reports the inherited declarations too, so `tests/app/test_screen_reachability.gd`
## still sees the whole door surface. **No public method was moved off this class or
## renamed**, and no signature changed: the split is invisible to every caller.
##
## Two suites read this file as TEXT, so what stayed here is what they slice on:
## `tests/app/test_status_clock.gd` requires `StatusLoop.new(` and a `_process(` signature
## to appear HERE and nowhere else under `res://src` (one tick caller is ADR 0106's claim),
## and `tests/modules/save/test_cultivation_boot_round_trip.gd` slices this file between the
## `restore_actor` and `restored_from_save` declarations. Both still hold.
##
## **The declaration names above are written WITHOUT their `func ` prefix on purpose.**
## That suite finds its slice with `source.find("func restore_actor")`, so naming them here
## in prose would put the FIRST match above the real declarations and hand the slice a
## docblock instead of the restore body — the assertion would then read the wrong code.

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
## The quest journal (BL-0663/BL-0664). `QuestApi.accept` had zero production
## callers, so no player could ever be on a quest; this route plus `_quests` is
## what makes a quest something a player can SEE and take.
const ROUTE_QUEST := &"quest"
const ROUTE_BODY := &"body_cultivation"
const ROUTE_WORLD_MAP := &"world_map"
const ROUTE_CRAFTING := &"crafting"
const ROUTE_WORKBENCH := &"workbench"
const ROUTE_SET_BONUS := &"set_bonus"
## The domain surface. `screen_routes.gd` registers it with a nav key, so a player opens the
## screen — and with no arm in `_bind_route_screen` the screen mounted UNBRIDGED, which is
## worse than a missing route: `summary()` answers `{}`, every verb is dead and the header
## reads "Domains — none authored".
const ROUTE_DOMAIN := &"domain_explore"

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
## The ONE caller of `QuestApi.accept` (BL-0663). Held by the root so the quest
## screen can be bound to it on every mount; the screen itself may not name the
## program (`ui/` holds no `app/` type) and may not name the module without the
## facade, so this is the bridge ADR 0143 prescribes.
var _quests: QuestProgram = null
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
	_forge = SocketForgeProgram.new(_actor)
	_quests = QuestProgram.new(_actor)
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
	return {
		"ok": true,
		"reason": "",
		"recovered": bool(restored.get("recovered", false)),
		"generation": int(envelope.get("generation", 0)),
		"difficulty": String(envelope.get("difficulty", "")),
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
	_world = WorldPulse.new(body, BeatDirector.new())
	# Both seams are re-pointed at the NEW body rather than left on the old one. The
	# offer resolver names a `WorldPulse`, and `_ready` just replaced that object; a
	# seam left pointing at the first one would offer the reborn hero's beats into a
	# director still holding the hero who fell — a live call with a dead owner, which
	# is exactly the half-swapped-body failure this method exists to prevent.
	EventBeatWriter.set_offer_resolver(Callable(_world, "offer_event_beat"))
	WorldStage.set_location_publisher(Callable(EventApi, "set_location"))
	_forge = SocketForgeProgram.new(body)
	_quests = QuestProgram.new(body)
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
		_:
			screen.call("setup", _actor)


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
