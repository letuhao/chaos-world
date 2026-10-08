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
##     calls `_live_screen()`. `_forge` and `_quests` are the shell's own wiring;
##     `_live_screen()` and `_stack` have since moved DOWN here, because this file's
##     `clear_cast_target` needs both and a base cannot read a subclass's (INC-0020).
##     Reading them from the shell is the legal direction, so `adopt_actor` itself did
##     not have to move.
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
##
## ## This is only reachable because the readout fires BODY, not qi
##
## The magnitude was never the thing standing between this surface and a wound: `QiDamage`
## emits no `effects[]` at all, so a qi blow wounds NOTHING at any magnitude and
## `CombatReadoutPanel._wound_line` was unreachable through the shipped app. Raising it
## would not have fixed that. `_readout_technique` in `item_workbench_readout.gd` now
## asks for the body path, and THIS is the magnitude that puts a wound in the ledger.
const READOUT_MAGNITUDE := 12.0
## The shipped default elemental share, restated as a plain number because `ui/` may not
## read `CombatTuning` and `app/` should not reach into the `.tres` for one field.
const READOUT_SHARE := 0.8
## The path the readout fires when nobody has chosen one. BODY, and the reason is the
## docblock above: it is the only mechanism that WRITES an effect (`body.wound` per struck
## site, ADR 0070), so it is the only one of the three whose readout row can render at all.
const READOUT_DEFAULT_PATH := PathState.BODY
## The meridian the readout's body swing aims at. `&"lung"` is a real meridian — three
## shipped `acupoints/minor_*.tres` name it — so this is not an invented aim id, and
## `_build_readout_target` unlocks all twenty channels, which ADR 0070 requires before a
## `named` aim is struck at all.
const READOUT_MERIDIAN := &"lung"
## The element the readout's qi swing carries, so `element_power_fire` is the term the
## elemental-share row is about rather than a second zero. Fixture arithmetic, same as
## [constant READOUT_MAGNITUDE]; it never reaches `game/data`.
const READOUT_ELEMENT := ElementStats.FIRE

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

## The domain surface. `screen_routes.gd` registers it with a nav key, so a player opens the
## screen — and with no arm in `_bind_route_screen` the screen mounted UNBRIDGED, which is
## worse than a missing route: `summary()` answers `{}`, every verb is dead and the header
## reads "Domains — none authored".
##
## DECLARED HERE, not in `item_workbench_app.gd`, because `_realize_domain_world` below
## reads it from a BASE of the shell that declares it, and a base cannot resolve a
## subclass constant (the same rule as the `READOUT_*` block above). The shell's
## `_bind_route_screen` still matches on it from a subclass, which is legal.
const ROUTE_DOMAIN := &"domain_explore"

# --- readout_field -------------------------------------------------------
## The combat readout's drill body, minted once and kept (ADR 0174). Cached so a reader
## who re-enters the route strikes the SAME body and can watch a wound accumulate,
## which is the whole point of a wound being observable at all. Null until the readout
## route is bound, so an app that never opens the page mints no inhabitant.
var _readout_drills: Actor = null

## The drill's own `StatusLoop` and the body it runs on — DECLARED HERE because this is the
## lowest link of the chain that touches them: `body.gd` writes both (below, in the unbind
## path) and `item_workbench_readout.gd` reads them in `bind_readout_drill` /
## `tick_readout_drill`. They were declared in that subclass, which made THIS file fail to
## parse and took down every suite process-wide (INC-0020).
var _drill_loop: StatusLoop = null
var _drill_body: Actor = null

## The screen stack the scene declares. Resolved by unique name in the shell's `_ready`;
## the root never builds a second one, because two stacks means two answers to "which
## screen is live".
##
## DECLARED HERE, not in `item_workbench_app.gd`: `clear_cast_target` below walks its
## children to unbind EVERY page, not only the live one, so this base needs the handle and
## a base cannot resolve a subclass field (INC-0020). The shell keeps ASSIGNING it, which
## is the same legal shape as `_quests`.
var _stack: ScreenStack = null

## The playfield a RESTORED body is stood into, and the body standing in it (ADR 0192).
## ONE stage and ONE adapter per root, in fields rather than a list: `WorldStage._current`
## and `._mounted_player` are STATIC, so a stage built per restore leaves the newest in
## `_current` and the previous adapter orphaned — the half-swapped world
## `CharacterCreationProgram._stand_in_the_world` refuses to create. A boot takes exactly
## one of the two branches, so each may keep its own. Singular fields, never
## `Array[WorldStage]`: `tools/arch`'s `APP_CONTENT_ARRAY_RE` reads a member array as the
## `state-table` signal, and the shell this file feeds carries `tick-loop`, so a list here
## would cross `APP_STATE_MIN_SIGNALS` for the whole unit.
##
## DECLARED HERE, not in `item_workbench_app.gd`: the only method that touches this pair
## is [method stand_restored_in_the_world] below, so this file is the lowest link of the
## chain that reaches them and a base cannot resolve a subclass field (INC-0020). The
## shell still calls it, under its own private name `_stand_restored_in_the_world`,
## because `restore_actor` reads the pair out of the ANSWER rather than the stage — and a
## subclass calling an inherited method is the legal direction.
var _restore_stage: WorldStage = null
var _restore_body: PlayerAdapter = null

## Mod event subscriptions (ADR 0184). Each row is `{event_bus, event_name,
## callable, mod_id}`; `_wire_subscriptions` resolves the bus by class name and
## connects the callable to the signal, guarded by `is_connected`.
var _mod_subscriptions: Array = []

## Content families with no overlay-capable catalog, recorded on each boot so
## the skip in `_wire_content_roots` is observable rather than silent (audit
## Gap 5). Cleared at the top of every `_wire_content_roots` call, so the array
## always reflects the most recent boot.
var _unwired_families: Array[StringName] = []

## Subscriptions whose bus name resolved to nothing, as `{mod_id, event_bus,
## event_name}` — the event-side twin of `_unwired_families` (ADR 0269). A mod
## subscription that cannot resolve is still SKIPPED rather than fatal, but it is
## never silent: each row is `push_warning`-ed naming the bus and the mod, and
## recorded here so the skip is assertable. Cleared at the top of every
## `_wire_subscriptions` call for the same reason as `_unwired_families`.
var _unresolved_buses: Array[Dictionary] = []

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


## The attach steps as pipeline phases, in the EXACT order the hardcoded list
## produced: one phase per attach call, each `run` the call itself wrapped so the
## pipeline can invoke it with the actor. The phase NAME is the contract — a mod's
## attach hook is staked to it (ADR 0184 §6) — so the names are module ids, never
## positions.
##
## ## Why the order is load-bearing
##
##   - `soul`, `anchor`, `socket`, `loot`, `difficulty` FIRST: a soul and an anchor
##     live in an injected store rather than on the actor (ADR 0127, ADR 0146), so
##     these are READS of that store — which `_ready` has already published by the
##     time any of the three callers reaches this list.
##   - `race`, `bloodline` next: `Actor.from_dict` restores `module_data` but NEVER
##     a `StatProvider`, so the stat modifiers, base-attribute grants, affinities and
##     trait mirrors a race and an awakened lineage contribute are rebuilt only by the
##     attach. Nothing on the old list called it, so after ONE reload a stoneborn lost
##     its +15% `max_health` and a tideborn at 0.72 read awake while `bloodline_power`
##     answered 0.0 — with no error anywhere, because every reader that mattered was
##     reading the ledger (BL-0746). Both are idempotent BY CONSTRUCTION (each strips
##     its own prior contribution, then rebuilds from the ledger), so a fresh body the
##     creation flow already raced is net-zero. Early because every ledger below can
##     read a body plan, and `FertilityApi`'s gestation step does.
##   - `elements` after the enrolments: `attach` reads the highest realm off the
##     cultivation paths to write each element's multiplier, so refreshing it before
##     a path exists writes nothing — the silent realm degression ADR 0069 records.
##     `attach`, not the bare refresh: `Actor.from_dict` restores no provider at all,
##     and `attach` mounts it when absent and refreshes either way.
##   - `dual_cultivation` then `fertility` — fertility adds to bases dual cultivation owns.
##   - `items` before `set_bonus` — the projection is derived from equipment, so it must
##     never run before items.
##   - `techniques` after the items family — it resolves authored options through the
##     items vocabulary (ADR 0056).
##   - `social`, `destiny`, `event`, `quest` — ledgers. Destiny before event, because
##     an event's prize is a `DestinyApi.earn_fate` and that must land in a key that
##     exists.
##   - `npc` — injects the npc constructor and binds the roster to THIS actor.
##   - `domain` — the idempotent twin. `DomainBoot.install` injects `DomainSpawner`'s
##     actor constructor and the two items contacts `DomainFixtures` needs; both
##     default to refusing, so without this line a domain answers `no_inventory_bridge`
##     to every treasure and `spawn` can only return null.
##   - `combat`, then `technique_seams` — a seam is only correct once the module it
##     wires is complete, and `TechniquesApi.attach` is what makes the codex exist for
##     `TechniqueDelivery` to write into.
##   - `economy` LAST — the last thing installed is the most recently written, which
##     makes a failure here the newest thing a reader sees.
func _attach_steps() -> Array[Dictionary]:
	return [
		{"name": &"soul", "run": func(a): SoulApi.attach(a)},
		{"name": &"anchor", "run": func(a): AnchorApi.attach(a)},
		{"name": &"socket", "run": func(a): SocketApi.attach(a)},
		{"name": &"loot", "run": func(a): LootApi.attach(a)},
		{"name": &"difficulty", "run": func(a): DifficultyApi.attach(a)},
		{"name": &"race", "run": func(a): RaceApi.attach(a)},
		{"name": &"bloodline", "run": func(a): BloodlineApi.attach(a)},
		{"name": &"elements", "run": func(a): ElementsApi.attach(a)},
		{"name": &"dual_cultivation", "run": func(a): DualCultivationApi.attach(a)},
		{"name": &"fertility", "run": func(a): FertilityApi.attach(a)},
		{"name": &"items", "run": func(a): ItemsApi.attach(a)},
		{"name": &"set_bonus", "run": func(a): SetBonusApi.attach(a)},
		{"name": &"techniques", "run": func(a): TechniquesApi.attach(a)},
		{"name": &"social", "run": func(a): SocialApi.attach(a)},
		{"name": &"destiny", "run": func(a): DestinyApi.attach(a)},
		{"name": &"event", "run": func(a): EventApi.attach(a)},
		{"name": &"quest", "run": func(a): QuestApi.attach(a)},
		# The conversation module (ADR 0862). Beside the other ledgers, and last of them:
		# it reads only its own `module_data` row and its own catalog, so it has no
		# ordering dependency on any of the above. It shipped with ZERO production
		# callers, so an actor never carried a dialogue row and `DialogueApi.start`
		# could not be reached from the shipped program at all - the shape BL-0663
		# closed for `quest`.
		{"name": &"dialogue", "run": func(a): DialogueApi.attach(a)},
		{"name": &"npc", "run": func(a): NpcBoot.install(a)},
		{"name": &"domain", "run": func(_a): DomainBoot.install()},
		{"name": &"combat", "run": func(a): CombatBoot.install(a)},
		{"name": &"technique_seams", "run": func(_a): _bind_technique_seams()},
		# Every organization of ANY kind (ADR 0271 / 0278). Beside `economy` and BEFORE
		# it, because the institution family is CONTENT plus REGISTRY rows and neither
		# depends on the economy's stores: `InstitutionBoot.install` discovers the
		# authored organizations and registers each KIND it finds. It shipped with
		# zero production callers, so a guild `.tres` a modder dropped into the family
		# was never read by anything the player runs.
		{"name": &"institutions", "run": func(_a): InstitutionBoot.install()},
		{"name": &"economy", "run": func(a): EconomyBoot.install(a)},
	]


## Build the boot's attach pipeline: one phase per attach step, in the order
## [method _attach_steps] declares. The pipeline holds no game state — only the order
## and the hook slots — so `app/`'s state scanners read it as wiring (ADR 0002). Hooks
## are added by the caller, AFTER the phases exist, so a hook staked to an unknown
## phase meets the pipeline's loud refusal rather than a silent skip.
func _attach_pipeline() -> AttachPipeline:
	var pipeline := AttachPipeline.new()
	for step in _attach_steps():
		pipeline.add_phase(step["name"], step["run"])
	return pipeline


## ## THE ONE attach list, now run through the pipeline (ADR 0184)
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
	var pipeline := _attach_pipeline()
	# The mod hooks (ADR 0184): every manifest attach hook staked to a phase name
	# is registered here, after the phases exist, so an unknown phase is the
	# pipeline's loud refusal, not a silent skip. An empty `Callable()` stub is
	# skipped by the pipeline, so a mod that has not bound its hook yet cannot
	# break a boot.
	var registrations := ModBoot.active_registrations
	for row in registrations.get("attach_hooks", []):
		pipeline.add_hook(StringName(row.get("phase", "")), row.get("callable", Callable()))
	pipeline.run(actor)
	# Register mod screens into the ScreenRegistry route table (ADR 0184 §6).
	# The ScreenStack mounts by id through ScreenRegistry.path_of(), so
	# registering here makes mod screens mountable via push_registered().
	ScreenRegistry.register_from_contexts(ModBoot.active_contexts)
	# Wire content roots into catalogs (ADR 0184 §5).
	_wire_content_roots(registrations.get("content_roots", {}))
	# Layer mod string catalogs over the base ones (ADR 0918).
	_wire_locale_roots(registrations.get("locale_roots", []))
	# Attach mod modules after all base phases (ADR 0184).
	_attach_mod_modules(pipeline, actor, registrations.get("modules", {}))
	# ## The authored starter kit, and why it is LAST (BL-0904 / BL-0909)
	#
	# A body whose bag opens empty has no row to select, no Generate to press and no Equip
	# to press, so every acquisition the game is built around starts from nothing. The kit
	# is [StarterKit]'s and the rows are `destiny`'s (`DestinyApi.starter_pack`), read here
	# because turning authored ids into real instances is the composition root's job and
	# not the module's.
	#
	# AFTER the mod modules, because a mod may install a destiny that REGISTERS a pack, and
	# a kit drawn before that registration would hand out the default the mod exists to
	# replace. It is a no-op on a restored body: the draw is a monotone world fact.
	var kit := StarterKit.grant(actor)
	if not bool(kit.get("ok", false)):
		push_warning(
			"ItemWorkbenchBody: the starter kit was refused (%s)" % String(kit.get("reason", ""))
		)
	elif not (kit.get("refused", []) as Array).is_empty():
		# Named, not swallowed: a kit naming an item the tree does not define is a content
		# bug, and a player promised it would otherwise open on a bag missing a row.
		push_warning("ItemWorkbenchBody: the starter kit could not deliver: %s" % str(kit["refused"]))
	# Wire mod event subscriptions onto the events buses (ADR 0184).
	_wire_subscriptions(registrations.get("subscriptions", []))


## Push content roots to their family catalogs (ADR 0184 §5). Each catalog
## scans its base root first, then the overlay roots in order, so mod content
## is visible. The `id_field` on each stack row is carried through to the
## catalog's scan. Families without overlay support are skipped — never a boot
## failure — but each is recorded in `_unwired_families` and announced with a
## `push_warning`, so the skip is never silent (audit Gap 5).
func _wire_content_roots(content_roots: Dictionary) -> void:
	_unwired_families.clear()
	for family in content_roots:
		var stack: Array = content_roots[family]
		match String(family):
			&"items":
				Crafting.set_overlay_roots(stack)
			&"quest":
				QuestCatalog.set_overlay_roots(stack)
			&"event":
				EventCatalog.set_overlay_roots(stack)
			&"world":
				WorldLocationCatalog.set_overlay_roots(stack)
			&"npc":
				NpcCatalog.set_overlay_roots(stack)
			&"race":
				RaceCatalog.set_overlay_roots(stack)
			&"techniques":
				TechniqueCatalog.set_overlay_roots(stack)
			&"elements":
				ElementCatalog.set_overlay_roots(stack)
			&"item_options":
				OptionCatalog.set_overlay_roots(stack)
			&"sects":
				SectCatalog.set_overlay_roots(stack)
			&"sect_doctrines":
				SectDoctrineCatalog.set_overlay_roots(stack)
			&"fates":
				FateCatalog.set_overlay_roots(stack)
			&"destinies":
				FateCatalog.set_overlay_roots(stack)
			# Every organization of ANY kind, base and mod overlay together (ADR 0184 §5).
			# This is the ONE family row that declares no module, because its machinery is
			# `core`-owned and a module facade for a core type would be an indirection with no
			# second owner. Unwired, a mod's `content_roots: [{family: "institutions"}]` fell
			# to the `:` arm below: recorded in `_unwired_families`, announced, and ignored —
			# the silent skip ADR 0184's own acceptance criterion forbids (DEF-0326).
			&"institutions":
				InstitutionDefCatalog.set_overlay_roots(stack)
			&"statuses":
				StatusCatalog.set_overlay_roots(stack)
			&"soul_arrivals":
				SoulCatalog.set_overlay_roots(stack)
			&"sets":
				SetCatalog.set_overlay_roots(stack)
			&"nations":
				NationCatalog.set_overlay_roots(stack)
			&"nation_territories":
				NationCatalog.set_overlay_roots(stack)
			&"market_shops":
				ShopCatalog.set_overlay_roots(stack)
			&"clans":
				ClanCatalog.set_overlay_roots(stack)
			&"holdings":
				ResourceNodeCatalog.set_overlay_roots(stack)
			&"body_weapons":
				WeaponKindCatalog.set_overlay_roots(stack)
			&"body_material_arts":
				MaterialArtCatalog.set_overlay_roots(stack)
			&"body_injury_tuning":
				InjuryCatalog.set_overlay_roots(stack)
			&"bloodlines":
				BloodlineCatalog.set_overlay_roots(stack)
			&"anchors":
				AnchorCatalog.set_overlay_roots(stack)
			&"difficulty":
				DifficultyCatalog.set_overlay_roots(stack)
			_:
				# Family has no overlay-capable catalog — warn and record, never
				# skip silently (audit Gap 5).
				var family_name := StringName(family)
				_unwired_families.append(family_name)
				push_warning(
					(
						"ItemWorkbenchBody: content family '%s' has no overlay catalog — skipped"
						% String(family_name)
					)
				)


## Layer every mod's string catalogs over the base ones (ADR 0918). Roots arrive in mod load
## order, so a later mod overrides an earlier one, and any of them overrides a core key — the
## only way a mod changes core wording is by shipping the same key, never by editing `src/`.
## Idempotent: `L.install_roots` records each root once, and a re-run of the boot pass is a
## no-op rather than a doubled translation.
func _wire_locale_roots(locale_roots: Array) -> void:
	L.install_roots(locale_roots)


## Attach mod modules after all base phases (ADR 0184). Each module name is
## looked up in the registry for its api path, then attached through the
## pipeline. Bounded by the module count — one pass, no loops.
func _attach_mod_modules(pipeline: AttachPipeline, actor: Actor, modules: Dictionary) -> void:
	if not bool(modules.get("ok", false)):
		return
	var registry: ModuleRegistry = modules.get("registry", null)
	if registry == null:
		return
	for name in modules.get("order", []):
		var module_name := String(name)
		var api_path := registry.api_path_of(module_name)
		if api_path != "":
			pipeline.attach_module(module_name, api_path, actor)


## Wire mod event subscriptions onto the events buses (ADR 0184). Each
## subscription is `{event_bus: String, event_name: String, callable: Callable,
## mod_id: String}`. The bus is resolved by class name — buses with a `shared()`
## accessor (NpcEvents, AuctionEvents, QuestEvents) use it; others get a fresh
## instance. Connections are guarded by `is_connected` so a repeated boot never
## double-connects (AGENTS.md).
##
## ## An unknown bus WARNS, and it stays a warning (ADR 0269)
##
## ADR 0242 decision 4 said an unknown bus "is skipped without crashing", which is
## still the BEHAVIOUR: a mod with one bad subscription must not take a boot down
## with it, and the tolerance is deliberate. What was missing is the other half of
## ADR 0184 decision 8 — never skip SILENTLY. A bus name that resolves to nothing
## means that mod's handler will never run, and until now nothing said so: a System
## whose entire economy is one subscription failed invisibly while every other
## subscription loaded cleanly.
##
## So each unresolvable bus is `push_warning`-ed NAMING both the bus and the mod
## that asked for it (stamped onto the row by `ModRuntime.finalize`, which is the
## only place that knows which mod a row came from), and recorded in
## `_unresolved_buses` so the skip is observable from a test and not only from a log.
## One row is one pass — the loop drains the array it was handed, so it terminates.
func _wire_subscriptions(subscriptions: Array) -> void:
	_mod_subscriptions = subscriptions
	_unresolved_buses.clear()
	for sub in subscriptions:
		if not (sub is Dictionary):
			continue
		var bus_name := String(sub.get("event_bus", ""))
		var event_name := StringName(sub.get("event_name", ""))
		var callable: Callable = sub.get("callable", Callable())
		if bus_name == "" or event_name == &"" or not callable.is_valid():
			continue
		var bus := _resolve_events_bus(bus_name)
		if bus == null:
			(
				_unresolved_buses
				. append(
					{
						"mod_id": String(sub.get("mod_id", "")),
						"event_bus": bus_name,
						"event_name": String(event_name),
					}
				)
			)
			push_warning(
				(
					"ItemWorkbenchBody: mod '%s' subscribed to unknown events bus '%s' (signal '%s')"
					% [String(sub.get("mod_id", "")), bus_name, String(event_name)]
				)
			)
			continue
		if not bus.is_connected(event_name, callable):
			bus.connect(event_name, callable)


## Resolve an events bus by class name. The factory is OPEN — no hardcoded
## dict. Resolution order:
##   1. Mod-registered custom buses (via `RegistrationContext.register_events_bus`)
##   2. `ClassDB.class_exists(bus_name)` — if the class exists, check for a
##      static `events()` or `shared()` accessor and call it; otherwise instantiate.
##   3. Return null for an unknown bus name (the caller skips it).
##
## ## A fresh instance is a DEAD subscription
##
## A bus handed out as `SomeEvents.new()` is a brand-new object per lookup: nothing
## holds the one a subscriber connects to and nothing emits on it, so `is_connected`
## reports the subscription connected FOREVER while no signal ever fires.
## Buses with a `shared()` accessor (NpcEvents, AuctionEvents, QuestEvents) return
## the process-wide instance a subscriber must reach.
func _resolve_events_bus(bus_name: String) -> RefCounted:
	# 1. Mod-registered custom buses take priority.
	if RegistrationContext.has_custom_bus(bus_name):
		return RegistrationContext.get_custom_bus(bus_name).call()
	# 2. Resolve by class name.
	if not ClassDB.class_exists(bus_name):
		return null
	# Check for a static events() or shared() accessor. `ClassDB` exposes no
	# `class_call`: the static-call spelling is `class_call_static` (boot repair).
	if ClassDB.class_has_method(bus_name, &"events"):
		return ClassDB.class_call_static(bus_name, &"events")
	if ClassDB.class_has_method(bus_name, &"shared"):
		return ClassDB.class_call_static(bus_name, &"shared")
	# 3. Otherwise instantiate.
	return ClassDB.instantiate(bus_name)


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


# --- restore_placement ---------------------------------------------------
## Stand `body` in the place its save CARRIES, and report what happened (ADR 0192).
##
## `WorldStage.new()` had exactly ONE hit in `game/src` — creation's `_stand_in_the_world`
## — so a RESTORED hero was rebuilt, fully mounted, and left standing NOWHERE. The event
## ledger's copy of the place stayed `EventApi.NOWHERE` (`""`) and `EventApi.available`'s
## location filter (`event/api.gd:93`) dropped every authored event before its trigger was
## read: `EventPrize.apply` was unreachable for EVERY returning player.
##
## **The place is READ, never DRAWN.** It comes from `WorldSpawnApi.current(body)` — the
## durable `world_spawn_state` ledger, which survives `Actor.to_dict`/`from_dict` because
## core writes every `module_data` key except two named ones (`core/actor.gd:301-307`) and
## restores all of them (`:397-398`). `WorldSpawnApi.random` is NEVER called here: a draw
## increments `visits` and rewrites `source`/`seed`/`display_name` on that ledger
## (`world_spawn_state.gd:145-158`), so "restore" would TELEPORT a returning player and
## persist the teleport as where they left off. Any diff bringing `random` in IS the bug.
##
## **The STAGE publishes; this never does.** `app/` installs `Callable(EventApi,
## "set_location")` and the stage fires it, so `app/` never writes `event`'s ledger and
## `event/` is never edited (ADR 0117). **An unlocatable body is REFUSED BY NAME, before
## any publish** — publishing `""` is legal, so a naive version writes a row, reports
## `ok`, and the bug looks fixed while `available()` stays empty all session.
##
## ## Why this is here and not in the shell's own `restore_actor`
##
## `restore_actor` STAYS in `item_workbench_app.gd`, because
## `tests/modules/save/test_cultivation_boot_round_trip.gd` slices this chain's shell
## between `func restore_actor` and `func restored_from_save` as TEXT. This method is
## neither of those two, so nothing reads its address; what it owns is a playfield and an
## adapter — the two fields above — and a declaration belongs in the lowest link of the
## chain that touches it. The shell calls it through its own private name
## `_stand_restored_in_the_world` and keeps its old signature, so the round trip is
## untouched either way.
func stand_restored_in_the_world(body: Actor) -> Dictionary:
	if body == null:
		return {"ok": false, "reason": "no_actor", "location_id": "", "world_told": false}
	var location_id := StringName(WorldSpawnApi.current(body).get("location_id", ""))
	if location_id == &"":
		return {
			"ok": false,
			"reason": "not_located",
			"located": false,
			"location_id": "",
			"world_told": false,
		}
	# Lazily, ONCE per root (the fields above), and PARENTED before the mount — `mount`
	# only calls `set_map_bounds` and assigns `global_position`, both legal unparented,
	# but `_world_entry()` is not: it answers null for a parentless body, so an
	# unparented mount reported `ok` with no interactables, no authored spawn and no
	# `_unhandled_input`. `WorldStage.stand_in_the_tree` is the `DomainWorld.place_player`
	# shape — construct, name, `add_child` under an authored `WorldEntry` — and is
	# idempotent, so a second arrival reuses the standing body instead of doubling it.
	if _restore_stage == null:
		_restore_stage = WorldStage.new()
	if _restore_body == null:
		_restore_body = PlayerAdapter.new(body)
	WorldStage.stand_in_the_tree(_restore_body)
	var answer := _restore_stage.mount(_restore_body, location_id)
	answer["world_told"] = bool(answer.get("world_told", false))
	answer["located"] = bool(answer.get("ok", false))
	return answer


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
## ## Why the learner is `ElementArts` and not a closure
##
## The wrapper pairs a TECHNIQUES read (is the root-refining art learned) with an
## ELEMENTS write (its one-time affinity grant) — the cross-module pair this root
## exists to own. It lives in `app/element_arts.gd` rather than as a lambda here so
## a test can call the exact callable the seam gets, and the seam keeps the
## dependency one-way.
##
## `ElementArts.install()` registers the arts' two sources (the opening grant and
## the repeatable refine) on the elements facade. Idempotent, so running per build
## is safe.
##
## Called from `_build_actor` and NOT from `_ready`: `_ready` runs once but a
## caller that rebuilds an actor (`ActorFactory` is public) would otherwise leave a
## freshly built actor with no seam, because a process-wide binding survives while
## the actor it was installed for does not. Installing here means every actor this
## root builds is wired, which is the property that was missing.
func _bind_technique_seams() -> void:
	ElementArts.install()
	TechniqueDelivery.install(Callable(ElementArts, "learn_with_root_grant"))
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


## One drill body, with the three mechanism inputs the shipped player already has. It
## is a body-cultivation actor because that is the one carrying an `acupoints` set, so a
## body technique resolves at a meridian against it rather than reporting "no location
## axis" — the readout's whole claim is that what the engine computes is what a player
## sees, and an input-less target would show less than production does.
##
## ## Why this function LIVES HERE and not in `item_workbench_readout.gd`
##
## Its only caller is `_readout_target` below, and this file is the lowest link of the
## chain that reaches it — declaring it in the readout made this BASE fail to parse and
## took every suite down process-wide (INC-0020).
##
## It is deliberately NOT inverted into a push from the readout, because the base's need
## for a drill is NOT gated on the readout having bound one. `ROUTE_TECHNIQUE_LOADOUT`
## aims the cast page through `_bind_target_screen` -> `_cast_target` -> here, and
## `refresh_cast_target` re-aims after a rebirth — neither opens `ROUTE_COMBAT_READOUT`,
## and `bind_readout_drill()` is called only inside that route's arm. A push would leave
## the cast page un-aimed until the reader happened to visit the combat readout, which is
## the ADR 0185 bug (`act_cast` refusing for free, `TechniqueCasting.activate` never
## reached) arriving again through a different door.
##
## ## Why `CombatBoot.install` is here and not one layer up
##
## The enrolment above is only the HALF of what the body needs to be struck. `install` is
## what calls `CombatEngineApi.attach_wounds`, and that call is the ONLY production writer
## of the `body_wounds` component — so without it `CombatEngineApi.wounds_of` answers
## null, `CombatReadoutScreen._wounds_payload` returns `{}`, and
## `CombatReadoutPanel.wounds_text` printed `No meridian carries a wound.` FOREVER, on a
## body that took every hit the reader ever threw at it. `effects[]` is not the wound:
## the row on the panel comes from the LEDGER, and nothing settles the ledger but the
## applier reading a bound one.
##
## The cache in `_readout_target` below exists precisely so a wound can
## ACCUMULATE — "a reader who re-enters the route strikes the same body twice and can
## watch a wound accumulate". It cannot accumulate without the ledger bound here, so this
## call is what makes that comment true rather than aspirational.
##
## Order matters and is the one `ui_driver.gd:197-201` documents: enrol the paths, THEN
## install — `bind_mechanisms` reads `acupoints` / `sea_of_consciousness` to choose a
## mechanism, and installing first measures every path's inputs as absent. `install` is
## idempotent, so a route re-entry cannot erase a wound earned on the previous visit.
##
## ## The sea, and why it is on BOTH ends
##
## `CombatBoot._runs_for` answers "may this attacker run `MindDamage`?" with
## `MindCultivationApi.sea(attacker) != null` (`combat_boot.gd:377`), so the ATTACKER needs
## a sea for the mind path to be reachable at all — and `MindDamage` divides by the
## DEFENDER's `structural_capacity`, so the drill needs one too or the erosion is
## `0.0 / 0.0`. Without both, `act_cycle_path` to mind silently fell back to the
## installed mechanism and the erosion row could never render, which is the same shape the
## wound row was in. `MindTraining.synchronize` sizes the sea off base attributes, so it
## runs after the enrolment — the same order `_reattach_components` uses.
##
## `unlock_for_realm` is what makes [constant READOUT_MERIDIAN] a real channel: ADR 0070
## is explicit that a `named` aim at a meridian this body has never unlocked is NOT struck
## at all, so a freshly enrolled body is a sheet of twenty closed channels and the aim
## would resolve to the empty site.
func _build_readout_target() -> Actor:
	var drill := ActorFactory.spawn_inhabitant(&"readout_drills")
	ActorFactory.with_body_cultivation(drill)
	drill.meridians.unlock_for_realm(&"qi_refining")
	ActorFactory.with_mind_cultivation(drill)
	MindCultivationApi.attach_sea(drill)
	MindTraining.synchronize(drill)
	CombatBoot.install(drill)
	return drill


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


## The screen currently on top of the stack, or null when nothing is mounted.
##
## DECLARED HERE rather than in `item_workbench_app.gd` because the cast-target lifecycle
## below is this file's and it asks this question four times: the base cannot resolve a
## subclass method. The shell's own callers (`adopt_actor`, `routes`, `summary`,
## `_announce_route`, the world-map handlers) read it from a subclass, which is legal and
## needs no change.
func _live_screen() -> Control:
	return null if _stack == null else _stack.call("current") as Control


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
	# **And its CLOCK goes with it (ADR 0195).** A `StatusLoop` left pointed at the
	# dropped body would tick a foe no player is shown, and the collapse window it holds
	# would be credited to whatever body was minted next — the exact carry-over
	# `StatusLoop.attach` resets the accumulator to avoid. The pair is the aim, so it is
	# dropped as the aim is.
	_drill_loop = null
	_drill_body = null
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
##
## ## The third slot is the one ADR 0167 could not reach
##
## `retreat` was complete, correct and reachable from no player, because the seam had
## nowhere to carry it: `grep retreat game/src/ui` returned nothing at all. It is
## `ItemWorkbenchPlay.retreat` bound here and nowhere else, so the panel that offers a
## chosen duration and the headless probe that drives it meet the SAME verb the wait
## button's path ends in (`advance_world`) — there is still one dispatcher for a period.
func _world_bridge() -> WorldPulseBridge:
	var bridge := WorldPulseBridge.new()
	bridge.read_state = Callable(self, "world_summary")
	bridge.advance = Callable(self, "advance_one_period")
	bridge.retreat = Callable(self, "retreat")
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
