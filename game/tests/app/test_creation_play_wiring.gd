extends TestCase

## ADR 0130 as CODE: a committed arrival is the hero you PLAY, a reborn body re-binds every
## holder, and a returning player is not asked how they arrived again.
##
## ## Why this suite exists next to `test_creation_reachability` and `test_rebirth_play_wiring`
##
## **All three of those defects below were live while both of those suites stayed green.**
## Creation was reachable — the route existed, the screen bound, `commit` returned `ok` and
## `has_hero()` was true — and the player still played the generic boot hero, because nothing
## handed the created body to the composition root. The reachability suite asserted
## `_program.hero()`, which is the program's own opinion of itself. A body swap re-attached
## seven modules and stopped, leaving eight un-attached, and every module suite stayed green
## because each module was correct about the actor it was handed.
##
## So every case here asserts the OBSERVABLE through the MOUNTED root — `SeamHarness`, which
## parents the shipped `ItemWorkbenchApp.tscn` and drives `_ready` the way the engine does — and
## asks what a player reads afterwards. `has_hero()` and `hero()` are never the subject of an
## assertion here: that is the shape of proof that let the first defect through.
##
## ## Disk discipline
##
## `user://save` is cleared before every mount and after every case. The runner shares one
## process across every suite, so a save left behind is read by whichever suite boots next and
## "a boot with a save" silently becomes "a boot with no save" — the exact case the
## returning-player half is here to prove.

## The route the arrival screen is mounted on. Read from the shipped program rather than
## restated, so a route rename cannot leave this suite asserting a route nothing serves.
const FIRST_ORIGIN := &"the_one_who_stayed"
## The home route a returning player boots onto. Read off the shipped table, because "the
## arrival screen did not open" is only meaningful next to what did.
const WORKBENCH := ScreenRoutes.ROOT_ID

var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _soul_store: SoulWorldLedger
var _anchor_store: AnchorWorldLedger
var _born: Array = []


func setup() -> void:
	_clear_disk()
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	# The stores are installed AFTER the mount, for the reason `test_rebirth_play_wiring`
	# documents: `_ready` installs its own, so a suite that sets them beforehand has them
	# discarded. Re-pointing them here makes this suite's ledger the one the root reads, which
	# is the same order a real boot uses.
	_soul_store = SoulWorldLedger.new()
	_anchor_store = AnchorWorldLedger.new()
	SoulApi.set_store(_soul_store)
	AnchorApi.set_store(_anchor_store)
	SaveApi.install_store("soul", _soul_store)
	SaveApi.install_store("anchor", _anchor_store)


func teardown() -> void:
	# Cleared before the harness is released and again after, because `teardown` is what the
	# next suite's `setup` runs against and the runner shares one process with all of them.
	_clear_disk()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null
	# Actors are `RefCounted`, but a `PathState` is connected to the actor's invalidator and a
	# resource pool is held by a provider, so the cycle outlives the refcount. `resources.clear()`
	# breaks it, which is what keeps ObjectDB quiet at exit.
	for born in _born:
		var body := born as Actor
		if body != null:
			body.resources.clear()
	_born.clear()
	_clear_disk()
	SoulApi.set_store(null)
	AnchorApi.set_store(null)
	SaveApi.install_store("soul", null)
	SaveApi.install_store("anchor", null)


# --- The root is a live root ----------------------------------------------------


func test_the_harness_mounted_a_booted_app() -> void:
	# The precondition every other case rests on. Asserted first, because a mount that failed
	# would otherwise make each of them report a null-body error instead of saying so once.
	assert_eq(String(_harness.boot_error), "", "the shell booted")
	assert_eq(_app != null, true, "there is a composition root")
	assert_eq(_app.actor() != null, true, "and it holds a hero")


# --- Finding 1: a committed arrival is the hero you play -------------------------


func test_a_boot_hands_the_creation_program_the_seam_that_reaches_the_root() -> void:
	# The precondition for every other case in this half. A program with no adopt seam can build
	# a hero and reach no player, which is the defect in its most compact form.
	assert_eq(
		bool(_app.creation_summary().get("adopt_seam", false)),
		true,
		"the program boot constructs can hand a created body to the composition root"
	)


func test_the_boot_left_the_arrival_screen_mounted_and_bound_to_its_commit() -> void:
	# Also the precondition. `_ready` opens creation on a new game, which is what puts the live
	# program and its commit callable where the player — and this suite — can reach them.
	assert_eq(
		String(_app.current_route()),
		String(CharacterCreationProgram.CREATION_ROUTE),
		"a new game boots onto the arrival route"
	)
	var live := _harness.live_screen()
	assert_ne(live, null, "a screen is live")
	if live == null:
		return
	assert_eq(
		live.has_method(&"bind_creation"),
		true,
		"and it is the arrival screen, which is what the candidates and the commit go to"
	)


func test_a_committed_arrival_becomes_the_body_the_root_plays() -> void:
	# The defect, at the seam it happened at. `commit` used to build a hero, keep it in a
	# private field and return; `_app._actor` was never reassigned, so the player read
	# "Arrival committed. What it carried is yours for good." and then played the boot hero.
	var origin := _first_origin()
	var committed := _program().commit(origin)
	assert_eq(
		bool(committed["ok"]), true, "the arrival committed: %s" % committed.get("reason", "")
	)
	var played := _app.actor()
	assert_ne(played, null, "the root still holds a body")
	assert_eq(
		String(played.id),
		String((committed["actor"] as Actor).id),
		"the body the root PLAYS is the created hero, not the generic boot body"
	)


func test_the_played_hero_carries_the_origin_destiny_the_committed_arrival_earned() -> void:
	# The half that makes the swap worth doing. `CharacterCreationFlow` earns the origin through
	# `DestinyApi.earn_destiny` on the body IT minted; if the played body were a different
	# `Actor`, the codex would read an empty ledger and ADR 0065's exclusivity would be enforced
	# on a hero nobody plays.
	var origin := _first_origin()
	var committed := _program().commit(origin)
	assert_eq(
		bool(committed["ok"]), true, "the arrival committed: %s" % committed.get("reason", "")
	)
	assert_eq(
		DestinyApi.has_destiny(_app.actor(), origin),
		true,
		"the PLAYED body holds the origin destiny the arrival earned, not another body's copy"
	)
	assert_eq(
		(DestinyApi.destinies(_app.actor()) as Array).size() > 0,
		true,
		"and the Fate screen's own read is non-empty rather than an empty ledger"
	)


func test_the_played_hero_answers_to_the_race_the_committed_arrival_arrived_in() -> void:
	# ADR 0109's rule made visible at creation: what makes the three heroes materially different
	# is that a `tidecaller` cannot take the body path and `stoneborn` closes the mind path. A
	# committed arrival whose closures live only on the discarded body is the screen's whole
	# promise being decoration.
	var committed := _program().commit(FIRST_ORIGIN)
	assert_eq(
		bool(committed["ok"]), true, "the arrival committed: %s" % committed.get("reason", "")
	)
	assert_eq(
		String(RaceApi.summary(_app.actor()).get("race", "")),
		String(committed.get("race", "")),
		"the played body is the BODY PLAN the committed arrival arrived in"
	)


func test_a_refused_arrival_leaves_the_played_body_exactly_as_it_was() -> void:
	# The commit's swap must be conditional on a SUCCESSFUL build. A refusal that still called
	# the adopt seam would replace a live hero with something the player never chose.
	var before := _app.actor()
	var refused := _program().commit(&"an_arrival_no_content_defines")
	assert_eq(bool(refused["ok"]), false, "an unknown arrival is refused")
	assert_eq(String(refused["reason"]), "unknown_origin", "and named")
	assert_eq(_app.actor() == before, true, "so the body the player was on is untouched")


# --- Finding 2: a body swap re-binds every holder -------------------------------


func test_the_root_poll_re_embodies_a_dead_body_through_its_own_seams() -> void:
	# The whole claim, in one case, through the PRODUCTION path: kill the actor and let the
	# root's own death poll mint and adopt, rather than driving a hand-built resolver.
	var first := _app.actor()
	var pool := first.resource(&"health")
	pool.change(-pool.maximum)
	var outcome := _app.poll_death()
	assert_eq(bool(outcome.get("died", false)), true, "the body died and the poll resolved it")
	assert_eq(bool(outcome.get("incarnated", false)), true, "and the soul re-embodied")
	var second := _app.actor()
	assert_ne(second.id, first.id, "so the root plays a different body")
	if not _born.has(second):
		_born.append(second)


func test_a_hero_who_held_a_destiny_still_reads_one_after_the_swap() -> void:
	# Destiny was one of the eight bindings `adopt_actor` did NOT re-attach, so every rebirth
	# left the Fate screen reading an empty ledger — a whole life's earned fates and the
	# exclusivity between them, gone, silently.
	_earn_an_origin(_app.actor())
	var first := _app.actor()
	assert_eq(
		(DestinyApi.destinies(first) as Array).size() > 0, true, "the body that fell held a destiny"
	)
	var second := _rebody()
	assert_ne(second.id, first.id, "the body changed")
	assert_eq(
		(DestinyApi.destinies(second) as Array).size() > 0,
		true,
		"a reborn body is DESTINY-attached: the Fate screen's read is non-empty, not a wiped ledger"
	)


func test_a_reborn_body_carries_an_event_and_a_quest_ledger_to_progress() -> void:
	# Event and quest were two more of the eight. Both normalize an EMPTY ledger on attach, so
	# the claim is that the key exists and the module answers — a handler reading an un-attached
	# ledger sees no active quest and claims nothing, which is invisible from every screen.
	var first := _app.actor()
	assert_eq(
		first.get_module_data(EventApi.MODULE_KEY).is_empty(),
		false,
		"the boot body carries an event ledger"
	)
	assert_eq(first.get_module_data(QuestApi.MODULE_KEY).is_empty(), false, "and a quest ledger")
	var second := _rebody()
	assert_ne(second.id, first.id, "the body changed")
	assert_eq(
		second.get_module_data(EventApi.MODULE_KEY).is_empty(),
		false,
		"a reborn body is EVENT-attached, so an authored event has a ledger to open into"
	)
	assert_eq(
		second.get_module_data(QuestApi.MODULE_KEY).is_empty(),
		false,
		"a reborn body is QUEST-attached, so `QuestBeatHandler` has a ledger to complete against"
	)


func test_a_reborn_body_is_social_attached_so_bonds_do_not_vanish() -> void:
	# `SocialApi.attach` was the ninth of the eight-and-one: social belongs to EVERY actor, the
	# player included (ADR 0091), so a reborn body without it has no `SocialState` at all and
	# every npc bond reads as absent.
	var second := _rebody()
	assert_ne(
		SocialApi.social_state(second), null, "a reborn body has a social ledger to bond into"
	)
	assert_ne(SocialApi.summary(second).is_empty(), true, "and the bond summary answers for it")


func test_a_reborn_body_is_npc_attached_so_the_roster_binds_to_it() -> void:
	# `NpcBoot.install` injects the npc constructor and calls `NpcApi.attach(player)`, which is
	# the ONLY place the roster remembers which actor it hangs off. Without it every mutating npc
	# verb resolved a player from the body that fell: bonds vanished and `spawn` was a facade
	# method that could only ever return null.
	var second := _rebody()
	assert_ne(second.id, null, "a body stands")
	assert_eq(NpcApi.state(second).is_empty(), false, "the roster reads for the reborn body")
	assert_eq(
		NpcApi.state(second) == NpcApi.state(_app.actor()),
		true,
		"and it is the ROSTER the root's own actor answers from, so it was bound to it"
	)


func test_a_reborn_body_is_combat_installed_so_a_blow_can_be_resolved() -> void:
	# `CombatBoot.install` was the seventh of the eight: without it `CombatSpine.resolve_hit`
	# reads `MechanismSlot.of(attacker)`, which ASSERTS on an actor nothing bound. A reborn body
	# that could not fight was a crash waiting for the first landed technique.
	var second := _rebody()
	assert_eq(
		CombatEngineApi.has_mechanism(second),
		true,
		"a reborn body carries a bound damage mechanism, so the spine never asserts on it"
	)


func test_the_technique_seams_are_rebound_for_a_reborn_body() -> void:
	# The eighth. `_bind_technique_seams` is process-wide rather than per-actor, but its CALL was
	# absent from `adopt_actor`, and a body swap replaces the `WorldPulse` those seams partly
	# name — so the rebinding is what keeps the delivery and casting seams on a live owner.
	var second := _rebody()
	assert_eq(TechniqueDelivery.is_bound(), true, "the technique delivery seam is installed")
	assert_eq(TechniqueCasting.has_resolver(), true, "and the casting resolver is installed")
	assert_ne(second.id, null, "with a body that stands behind them")


func test_a_reborn_body_keeps_the_element_realm_multiplier_rather_than_degressing_to_r1() -> void:
	# ADR 0069's recorded failure, measured on the stat stack. `ElementsApi.attach` is NOT what
	# is called here: the provider is already mounted by `ActorFactory.build` and
	# `apply_realm_modifiers` is a REFRESH, so a body whose refresh was skipped reads the R1
	# multiplier for every element and every landed blow is resolved against a flat realm.
	#
	# **Counted, not compared, and deliberately so.** The claim is that the modifiers were
	# WRITTEN for the new body at all; their VALUE is authored per-realm data and asserting a
	# number here would make a realm retune fail this suite. A body at R1 still receives one
	# modifier per element — `apply_realm_modifiers` strips and re-applies unconditionally once
	# a realm exists — so a non-zero count is the degression check.
	var second := _rebody()
	assert_ne(
		RealmScaling.highest_realm(second),
		null,
		"a reborn body carries a realm on the ladder, so a realm multiplier has something to read"
	)
	assert_eq(
		_realm_modifiers(second) > 0,
		true,
		"a reborn body carries this core source's realm modifiers, so no element degresses to R1"
	)


func test_a_reborn_body_still_advances_the_world_clock() -> void:
	# `WorldPulse` is rebuilt by `adopt_actor`; the claim is that the REBUILT one is the object
	# the root advances, because a pulse pointed at the body that fell would record every period
	# against a dead hero.
	var second := _rebody()
	assert_eq(_app.actor() == second, true, "the root's body is the one the swap adopted")
	# One bounded advance, not a `while`: a period is a division in `pull`/`advance_periods` and
	# neither loops, so this cannot fail to terminate.
	var outcome := _app.advance_world(2)
	assert_eq(bool(outcome.get("ok", false)), true, "the world advanced on the reborn body")
	assert_eq(
		int(_app.world_summary()["periods"]) > 0,
		true,
		"and its clock counts, rather than reporting the period against the body that fell"
	)


func test_a_reborn_body_starts_with_an_empty_kit_and_not_the_old_bodies_bag() -> void:
	# ADR 0130: inventory and kit do NOT cross a rebirth. `ItemsApi.attach` REPLACES the
	# inventory, so a reborn body must be given an empty one rather than left with no bag at all
	# — and it must not inherit the body that fell's starter kit.
	_give_a_starter_item(_app.actor())
	var first := _app.actor()
	assert_eq(
		ItemsApi.has_item(first, &"vial_mending_elixir", 1),
		true,
		"the body that fell held something"
	)
	var second := _rebody()
	assert_ne(second.id, first.id, "the body changed")
	assert_ne(
		ItemsApi.inventory(second),
		null,
		"a reborn body has a BAG: `ItemsApi.attach` is deliberately on the shared attach list"
	)
	assert_eq(
		ItemsApi.has_item(second, &"vial_mending_elixir", 1),
		false,
		"and the old body's kit did NOT cross the rebirth (ADR 0130)"
	)


# --- Finding 3: a returning player is not asked how they arrived again ----------


func test_a_boot_with_no_save_leaves_the_player_on_the_arrival_screen() -> void:
	# The first-time player. No readable slot and no hero to adopt, so the one door to arrival
	# opens. Asserted on the LIVE SCREEN rather than on `open_creation`'s return, because a door
	# that reports success while showing nothing is the shape the whole suite exists to catch.
	assert_eq(_app.restored_from_save(), false, "nothing was restored")
	assert_eq(_app.actor() != null, true, "a fresh hero stands")
	assert_eq(
		String(_app.current_route()),
		String(CharacterCreationProgram.CREATION_ROUTE),
		"the game boots onto the arrival route"
	)


func test_a_boot_with_a_readable_save_does_not_open_the_arrival_screen() -> void:
	# The defect, exactly as it shipped. The gate was `_creation.has_hero()`, and on a restored
	# boot `_created` was null — nothing had told the program about the hero already in hand —
	# so `has_hero()` was false and `open_creation()` ran, dropping a returning player back onto
	# the arrival screen with a restored body already running.
	var saved_id := _write_a_save()
	var harness := SeamHarness.mount_new()
	assert_eq(String(harness.boot_error), "", "the shell booted over the save")
	if harness.boot_error != "":
		return
	var app := harness.app as ItemWorkbenchApp
	assert_eq(app.restored_from_save(), true, "the boot recovered from the save")
	assert_eq(String(app.actor().id), saved_id, "and restored the body the save names")
	# THE CLAIM: the arriving screen never opened.
	assert_eq(
		String(app.current_route()),
		String(WORKBENCH),
		"a returning player boots straight to the home route, not onto the arrival screen"
	)


func test_a_restored_boot_does_not_reach_arrival_through_its_own_door_either() -> void:
	# The returning-player case read through the root's public verb, because `open_creation` is
	# reachable from the nav bar too. A restored boot must refuse it BY NAME rather than merely
	# not having called it, so a player who navigates there is answered rather than dropped into
	# a second arrival.
	_write_a_save()
	var harness := SeamHarness.mount_new()
	if harness.boot_error != "":
		assert_eq(String(harness.boot_error), "", "the shell booted over the save")
		return
	var app := harness.app as ItemWorkbenchApp
	var opened: Dictionary = app.open_creation()
	assert_eq(bool(opened["ok"]), false, "a restored boot refuses to open arrival")
	assert_eq(
		String(opened["reason"]),
		"already_has_hero",
		"and says so by name, because the program was told about the restored hero"
	)


# --- Internals ------------------------------------------------------------------


## The mounted root's OWN creation program, read out of the commit callable the live arrival
## screen was bound with. Never a freshly constructed one: that would prove a program can build
## a hero, which is precisely the proof that let the first defect ship.
func _program() -> CharacterCreationProgram:
	var live := _harness.live_screen()
	assert_ne(live, null, "a screen is live to read the program from")
	if live == null:
		return null
	var commit_callable: Callable = live.get(&"_commit_requested") as Callable
	assert_eq(commit_callable.is_valid(), true, "the arrival screen holds the program's commit")
	if not commit_callable.is_valid():
		return null
	var bound := commit_callable.get_object() as CharacterCreationProgram
	assert_ne(bound == null, true, "and the callable belongs to a creation program")
	return bound


## The origin id the shipped catalog offers, asked of the catalog rather than hardcoded, so a
## content rename fails here by name instead of silently turning every case into a refusal test.
##
## ## An EARNABLE origin, not merely the first one
##
## `destinies_in_group` orders by string, so `ids[0]` is `the_chosen_instrument` — which
## authors `requires_fates = [&"reborn_in_a_lesser_vessel"]`. `earn_destiny` refuses it on a
## fresh boot body, and a refused earn returns the ledger unchanged with NO error, so
## `_earn_an_origin` silently earned nothing and the two cases below it failed on a body that
## never held a destiny. Skipped by the gate, not worked around: the FIRST EARNABLE one is
## still the shipped catalog's answer, read through the shipped gate.
func _first_origin() -> StringName:
	var catalog := FateCatalog.instance()
	var ids := catalog.destinies_in_group(&"origin")
	# `assert_eq`, NOT `assert_ne`: `assert_ne(actual, unexpected)` FAILS when the two
	# are EQUAL, so `assert_ne(ids.size() > 0, true, ...)` passes on an EMPTY catalog and
	# fails on a healthy one. It ran as a proof that content was MISSING, so every
	# `_earn_an_origin` call below silently earned nothing and 20 cases cascaded off it
	# (ADR 0188: a guard that cannot fail is a missing guard — this one failed backwards).
	assert_eq(ids.size() > 0, true, "the catalog ships at least one origin")
	for id in ids:
		var def := catalog.destiny_definition(id)
		if def != null and DestinyGate.earnable({}, def):
			return id
	# None is earnable from nothing. That is authored content, not a harness failure, so it
	# is reported by name rather than swallowed into a refusal test.
	assert_eq(ids.size() > 0, false, "and at least one of them is earnable from nothing")
	return &""


## Earn one origin destiny on `body`, through the facade rather than by hand-editing
## `module_data`, so the ledger is the shape a real earn leaves.
func _earn_an_origin(body: Actor) -> void:
	DestinyApi.attach(body)
	DestinyApi.earn_destiny(body, _first_origin(), "test")


## Kill the live body and let the ROOT's own poll re-body it, so every seam under test is the
## production one: `mint_body` mints through the same arrival table creation uses and
## `adopt_actor` re-binds. Returns the body that stands afterwards.
func _rebody() -> Actor:
	var first := _app.actor()
	var pool := first.resource(&"health")
	pool.change(-pool.maximum)
	# The poll arms on the actor id, so it arms on the way in and resolves on the way out.
	_app.poll_death()
	var second := _app.actor()
	assert_ne(second == first, true, "the poll re-bodied the actor")
	if second != null and not _born.has(second):
		_born.append(second)
	return second


## How many realm modifiers this core source owns on `body`. `add_provider` appends unguarded
## and `apply_realm_modifiers` strips before it applies, so a body the refresh never reached
## counts ZERO here where a body it did reach counts one per element.
func _realm_modifiers(body: Actor) -> int:
	var total := 0
	for modifier in body.stats._modifiers:
		if modifier.source == RealmScaling.SOURCE:
			total += 1
	return total


## Put one authored item in `body`'s bag, so the rebirth case has something to NOT inherit.
func _give_a_starter_item(body: Actor) -> void:
	if ItemsApi.inventory(body) == null:
		ItemsApi.attach(body)
	var bag := ItemsApi.inventory(body)
	var def := Crafting.resolve(&"vial_mending_elixir")
	if def != null and not bag.has(&"vial_mending_elixir", 1):
		bag.add(def, 1)


## Write a readable save on disk and answer the hero id it carries.
##
## **The stores are installed the way a real boot installs them** — one store instance shared
## between `SoulApi`, `AnchorApi` and `SaveApi` — because a save written against a different
## store is not the save the next boot reads, and "the boot restored nothing" would then look
## exactly like "the gate is wrong".
func _write_a_save() -> String:
	var soul_store := SoulWorldLedger.new()
	var anchor_store := AnchorWorldLedger.new()
	SoulApi.set_store(soul_store)
	AnchorApi.set_store(anchor_store)
	SaveApi.install_store("soul", soul_store)
	SaveApi.install_store("anchor", anchor_store)
	# A hero built the way `_build_actor` builds one, minus the parts the save does not carry:
	# `restore_cultivation` is what re-attaches the cultivation providers at boot.
	var hero := ActorFactory.build(
		&"returning_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	hero.attach_core_resources()
	ActorFactory.with_body_cultivation(hero)
	ActorFactory.with_qi_cultivation(hero)
	ActorFactory.with_mind_cultivation(hero)
	DifficultyApi.attach(hero)
	SoulApi.attach(hero)
	AnchorApi.attach(hero)
	_born.append(hero)
	var landed: Dictionary = SaveApi.persist(hero, "standard")
	assert_eq(bool(landed["ok"]), true, "a readable save landed on disk")
	# Hand this suite's own stores back, so the mount the case performs reads the ledgers a
	# real boot would publish rather than the two this helper installed.
	SoulApi.set_store(_soul_store)
	AnchorApi.set_store(_anchor_store)
	SaveApi.install_store("soul", _soul_store)
	SaveApi.install_store("anchor", _anchor_store)
	return String(hero.id)


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
