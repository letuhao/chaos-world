class_name ItemWorkbenchApp
extends ItemWorkbenchRoutes

## The playable slice's BOOT: the actor and body it mounts, the save round trip, the
## creation program, and the rebirth path (ADR 0002, 0027, 0033).
##
## ## The five files, and which half this is
##
## Each half was extracted because a file passed the thousand-line ceiling: this is the
## SHELL that remains after the last one, and it holds only what a boot needs.
##
##   - [ItemWorkbenchRoutes] — the screen stack, the nav bar, the route table and the
##     binder. The BASE of this file.
##   - `ItemWorkbenchFight` — the fight verbs a route mounts.
##   - `ItemWorkbenchReadout` — the drill body, the one blow it resolves, its context row.
##   - `ItemWorkbenchBody` — the attach list, the fresh-hero build, the hit and readout
##     seams, and the read bridges a screen is handed for the hero.
##   - `ItemWorkbenchPlay` — the actor itself and the four clocks that answer for it.
##
## **Inheritance, not delegation, and that is the whole reason it works.** Every verb on
## any half is called on the mounted root, so a delegation would leave every caller
## naming a method that is not there. As base scripts the root still answers all of them,
## and `get_script_method_list()` reports inherited declarations too, so
## `tests/app/test_screen_reachability.gd` still sees the whole door surface. **No public
## method was moved off this class or renamed**, and no signature changed.
##
## The cut is one-way: the routes half names nothing declared here; this file reads it.
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


func _ready() -> void:
	# The app's OWN subtree — the nav bar included — is scene text with no call site of its own,
	# so it resolves here, before anything reads a label (the ADR 0918 pass, which `src/ui`
	# scenes get from `_bind_nodes`). An app scene under `game/scenes/` has no such hook.
	L.localize_tree(self)
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
	# ## The worldmap ledger (worldmap launch slice). Changed cells and the
	# ## resume point ride the envelope key it owns; the venture boot stages
	# ## both into this same instance, so the save and the screen cannot drift
	# ## into two answers about where the holes are or where the player stood.
	SaveApi.install_store(WorldmapLedger.WORLD_KEY, WorldmapLedger.new())
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
	# ## The world clock (ADR 0259), installed in the same block and for the same reason.
	#
	# A period count is true of the WORLD, not of whoever is carrying it, so per-actor storage
	# would be a copy every body could contradict — and a player who quit and returned would
	# resume at period zero holding a full ledger.
	#
	# ## THE STORE IS THE CLOCK, AND THAT IS THE WHOLE PERSISTENCE ARGUMENT
	#
	# `_world_clock` is installed here AS the `world_time` store rather than a `WorldLedgerStore`
	# view of the file, and the reason is that `_snapshot_world` reads `read_ledger()` off the
	# installed store: installing the live clock is therefore what puts the count on disk, with
	# **no change to any save code**. A `WorldLedgerStore` would have been correct for the
	# economy ledgers — whose truth lives in the file and is read from it — and wrong here,
	# because a clock's truth lives in the object the fold advances and the file is only where
	# it is KEPT. A store that re-read the file per advance would never see the count at all.
	#
	# **Before `publish_world` below, with the rest.** A world published before its store is
	# installed is a world nobody reads back — the ledger is believed saved and is not, which is
	# the silent-loss failure this whole class of fix exists to prevent. And because this is the
	# SAME object the fold advances, the restore and the advance cannot drift into two answers.
	if _world_clock == null:
		_world_clock = WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, _world_clock)
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
	# ## The world's OWN clock, and the reason it lives HERE (ADR 0259)
	#
	# `_world_clock` is this root's ONE `WorldClock` for the life of the process, and it is
	# handed to every fold this file builds — including the fresh one `adopt_actor` makes for
	# a reborn hero. That is the whole body-independence argument: a fold is replaced on a
	# body swap, so a clock created per fold would die with it and **the world would get
	# younger every time the hero changed**. The clock is a world fact (ADR 0127's argument,
	# applied to time), so it outlives the body and is not rebuilt with it.
	#
	## `publish_world` above has already pushed the persisted count into it (it is the
	# installed `world_time` store), so `attach_clock` reads the base off the clock itself —
	# no caller types a count, because a restore reads one and never authors one (ADR 0259
	# clause 5). A session that resumes at 5,000 periods continues from 5,000 rather than
	# counting from zero and overwriting the world's age on the first autosave.
	_world.attach_clock(_world_clock)
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
	# ADR 0901: both doors now open THROUGH the loading screen, which preloads
	# every route scene first. `_loading_boot` marks this pass so a later
	# manual visit to the loading route preloads without hijacking the player.
	# Headless runs never deliver a frame, so the steps drain inline there —
	# without that, every harness boot would stall on the loading route and
	# the pinned arrival behavior would go red for want of a frame. The
	# release lands on the menu for a returning player and on arrival for a
	# fresh boot, exactly as before.
	_loading_boot = true
	navigate_to(ROUTE_LOADING)
	if DisplayServer.get_name() == "headless":
		_drain_loading()
	if DisplayServer.get_name() == "headless":
		_drain_loading()


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


func restore_actor(slot: StringName = &"") -> Dictionary:
	var restored := SaveApi.restore(slot)
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
	tick_loading()


## Advance the loading screen one step. Not a clock: it loads one route scene
## and reads no delta, so the one-tick-caller rule (game time) does not apply.
## Headless runs never reach this — suites drive `load_step()` directly — so
## this is the live-only door, and a screen that is not loading is a no-op.


func tick_loading() -> void:
	if not _loading_boot:
		return
	var screen := _live_screen()
	if screen == null or not screen.has_method("load_step"):
		return
	var step := screen.call("load_step") as Dictionary
	if bool(step.get("done", false)):
		_finish_loading()


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
	_rebind_live_body(body)


## Point every loop, fold, seam, program and screen at `body`, which already
## carries its modules. Split out of `adopt_actor` so loading a journey reuses
## the identical rebind instead of growing a second one: two rebinds is how a
## future binding gets forgotten in one of them, which is the failure the
## method above exists to prevent. The attach list stays OUT — a rebirth mounts
## fresh modules while a load keeps the payload `restore_actor` mounted, and
## sharing that half would empty a loaded hero's bag.


func _rebind_live_body(body: Actor) -> void:
	_status_loop = StatusLoop.new(body)
	# Through `adopt_world`, not a bare assignment: the fresh fold's total starts at zero,
	# and the autosave's `_periods_seen` must reset with it or the first
	# `AUTOSAVE_PERIODS` world-moving periods after a rebirth read as `maxi(0, small -
	# large)` — zero periods moved, silently, on the save schedule (ADR 0179).
	adopt_world(WorldPulse.new(body, BeatDirector.new()))
	# ## The world clock goes WITH the fold, not through it (ADR 0259)
	#
	# `adopt_world` replaced the fold, so the fresh one needs the seam. `_world_clock` is
	# deliberately NOT republished here and deliberately NOT rebuilt: it holds the world's
	# LIVE count, which is exactly what must survive the hero's death, and republishing would
	# re-seed the fresh fold from the last SAVE rather than from the count that has moved
	# since — so the reborn hero would be born into a world younger than the one it just
	# left. The base is the clock's own current total.
	#
	# **This is the assertion a well-meaning convenience breaks.** A refactor that moved this
	# into `_world_clock = WorldClock.new()` would pass every single-actor test and quietly
	# reset the age of the world at every rebirth.
	_world.attach_clock(_world_clock)
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


## Open character creation, and answer whether it opened. **Opens the nav route the table
## already names**, so there is one door rather than two
## (ADR 0130). Boot calls this when no hero exists, which is why it is public with a production
## caller: `test_screen_reachability` fails a public mount nothing in `src/` calls, and
## `_ready` is that caller.


func open_creation() -> Dictionary:
	return {} if _creation == null else _creation.open()


## Whether a readable save exists. The boot menu's save seam: `ui/` may not
## name `SaveApi`, so the screen asks this root instead (ADR 0143).


func _boot_has_save() -> bool:
	return SaveApi.exists()


## Continue the saved journey: return to the home route.


func _boot_continue() -> bool:
	return navigate_to(ScreenRoutes.ROOT_ID)


## Begin anew: open the arrival route.


func _boot_new_game() -> Dictionary:
	return open_creation()


## Open another menu page from the boot menu. Settings and credits are plain
## routes; anything else is refused by `navigate_to` itself, which names an
## unknown route rather than opening it.


func _boot_open(route_id: StringName) -> bool:
	return navigate_to(route_id)


## Quit the game. The root owns the tree, so the menu asks here instead of
## quitting it — which is also what keeps a headless test alive: no suite
## ever calls this, because calling it would end the runner.


func _quit_game() -> Dictionary:
	get_tree().quit()
	return {"ok": true, "reason": ""}


## Every journey with its state, for the save menu. One row per roster slot:
## the module's summary plus whether it is the live one. Read-only; loading
## and erasing are the verbs below.


func list_slots() -> Array:
	var out: Array = []
	for slot in SaveApi.slots():
		var row := SaveApi.slot_summary(StringName(slot))
		row["is_live"] = StringName(slot) == SaveApi.live_slot()
		out.append(row)
	return out


## Load `slot`: make its journey live and stand its hero where the save says.
## Mirrors the restored half of `_ready` — publish that slot's world, rebuild
## its body with the same attach list, adopt it into the creation program so
## the menu answers about the right hero, and go home. Refuses an unknown
## slot and an empty one by name before moving anything.


func load_slot(slot: StringName) -> Dictionary:
	if not SavePaths.is_slot(slot):
		return {"ok": false, "reason": "unknown_slot", "slot": String(slot)}
	if not SaveApi.exists(slot):
		return {"ok": false, "reason": "empty_slot", "slot": String(slot)}
	var switched := SaveApi.set_live_slot(slot)
	if not bool(switched.get("ok", false)):
		return {"ok": false, "reason": String(switched.get("reason", "")), "slot": String(slot)}
	var published := SaveApi.publish_world(slot)
	if not bool(published.get("ok", false)):
		return {"ok": false, "reason": String(published.get("reason", "")), "slot": String(slot)}
	var outcome := restore_actor(slot)
	if not bool(outcome.get("ok", false)):
		return {"ok": false, "reason": String(outcome.get("reason", "")), "slot": String(slot)}
	_recovered_from_save = true
	if _creation != null:
		_creation.adopt(_actor)
	_rebind_live_body(_actor)
	navigate_to(ScreenRoutes.ROOT_ID)
	return {"ok": true, "reason": "", "slot": String(slot)}


## Forget `slot`'s files. The module refuses unknown slots and the live
## journey; this forwards its verdict verbatim.


func erase_slot(slot: StringName) -> Dictionary:
	return SaveApi.erase(slot)


## Every route scene, as plain paths. What the loading walk preloads: the
## screen may not read the route table itself (`ui/` never names `app/`), so
## the table is read once here and handed over as primitives.


func _finish_loading() -> void:
	if not _loading_boot:
		return
	_loading_boot = false
	if _creation.has_hero():
		navigate_to(ROUTE_BOOT)
	else:
		open_creation()


## Drain every load step inline. Headless runs never deliver a frame, so the
## per-frame tick below would stall every harness boot on the loading route
## and the pinned arrival behavior would go red for want of a frame. Bounded
## by the route count plus one; each step loads exactly one scene.


func _drain_loading() -> void:
	var screen := _live_screen()
	if screen == null or not screen.has_method("load_step"):
		return
	for i in ScreenRoutes.all().size() + 1:
		var step := screen.call("load_step") as Dictionary
		if bool(step.get("done", false)):
			break
	_finish_loading()


## The creation program's own view of itself, so a probe can assert reachability without
## reaching into a private field.


func creation_summary() -> Dictionary:
	return {} if _creation == null else _creation.summary()


## The route table this root publishes, so the navigation bar, a probe and a
## test all read the same list. Primitives only.


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


## Free the realized world on quit or reload. Released against the PLAYFIELD LAYER's
## slot: releasing against the screen would look for a subtree never under it.
func teardown() -> void:
	PlayfieldLayer.release_under(self)


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


func _world_open_events() -> Array[Dictionary]:
	if _world == null:
		return []
	return _world.open_events()


# --- The institution seams -------------------------------------------------------
#
# Three verbs, one actor, no state of their own. Each hands the screen the ANSWER and
# nothing else: the screen never names `InstitutionMembership` (it may, being a downward
# `core` read, but the ownership of the ACTOR is this root's), and no verb here
# interprets a refusal — a named reason reaches the player verbatim, which is the whole
# point of ADR 0083's third state.

## What the bound hero holds of every organization, as primitives. `{}` when they hold
## nothing, which is the FIRST state rather than a failure, so an unaffiliated hero reads
## "belonging to nothing" instead of a screen that refused to load.


func _read_institutions() -> Dictionary:
	return InstitutionMembership.summary(_actor)


## Enrol the bound hero in the organization the screen named. The verdict is returned
## unchanged, so the screen renders the module's own reason rather than a paraphrase of it.


func _join_institution(institution_id: String) -> Dictionary:
	return InstitutionMembership.join(
		InstitutionRegistry.instance(), _actor, StringName(institution_id)
	)


## Walk the bound hero out. The screen's seam takes NO organization id, so this leaves
## every house the hero holds — the total reading, and the only one that cannot be
## ambiguous about which organization a press meant.


func _leave_institution() -> Dictionary:
	return InstitutionMembership.leave(InstitutionRegistry.instance(), _actor)
