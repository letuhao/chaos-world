extends TestCase

## A committed body breakthrough attempt outlives the session that committed it.
##
## ## Why this suite and not another assertion on `module_data`
##
## `test_body_attempt_once_only.gd` already round-trips the record through
## `Actor.to_dict()` / `Actor.from_dict()`. That is the PAYLOAD. What was missing is the
## thing a player actually loses: `test_body_save_round_trip.gd` also stops at `to_dict()`,
## so no suite drove an attempt through `SaveApi.persist` — the envelope that a boot
## reads — and back. A payload that round-trips through the wrong door proves nothing
## about the door the game uses.
##
## So every case here goes out through `SaveApi.persist` and comes back through
## `SaveStore.restore()`'s `envelope.actor`, the same two calls the autosave makes. The
## disk is cleared in `setup()` and `teardown()` because these are real writes to
## `user://save`, and the runner shares one process across every suite.
##
## ## Why the seed is CHOSEN rather than hoped for
##
## `begin_breakthrough` / `resolve_breakthrough` take no generator, so they commit and
## roll against seed 0. Asserting "the hero advanced" on that is a coin flip dressed as
## a test. The cases below that need a determinate outcome therefore commit through
## `BodyAdvancement.start_attempt` with a seed chosen to win — which is strictly the
## stronger claim, because it proves the save carried the ROLL (`rng_state`) and not
## merely the fact that an attempt existed. The facade's own pair is exercised on the
## invariants that hold for either outcome.

var _play: BodyPlayFixture
var _born: Array = []


func setup() -> void:
	_play = BodyPlayFixture.new()
	_clear_disk()
	SaveApi.reset_clock()


func teardown() -> void:
	for born in _born:
		var body := born as Actor
		if body != null:
			# Actors are RefCounted, but a `PathState` is connected to the actor's
			# invalidator, so the cycle outlives the refcount. The shape
			# `tests/modules/save/` uses for the same reason.
			body.resources.clear()
	_born.clear()
	_clear_disk()
	SaveApi.reset_clock()


# --- The round trip ------------------------------------------------------------


## **Acceptance criterion 1, the headline.** A hero at the brink of its next realm
## commits an attempt through the shipped facade, the game autosaves, the process ends,
## and a body rebuilt from the envelope still holds THE SAME attempt — not a fresh one,
## and not none.
##
## The id is compared, not a boolean. "An attempt exists" would also be true of a
## re-rolled or re-sequenced record, and the whole point is that this is the attempt the
## pill was already spent on.
func test_an_attempt_committed_before_a_save_is_the_one_resolved_after_it() -> void:
	var hero := _prepared()
	var committed := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(committed.is_empty(), false, "the facade commits an attempt")
	var attempt_id := String(committed.get("attempt", ""))
	assert_ne(attempt_id.is_empty(), false, "which carries an attempt id")
	assert_eq(
		BodyCultivationApi.begin_breakthrough(hero).is_empty(),
		true,
		"and a second cannot start while the first is committed"
	)

	var reloaded := _reload_through_the_save(hero)
	assert_ne(reloaded, null, "the envelope rebuilt a body")
	if reloaded == null:
		return

	var restored := BodyAdvancement.active_attempt(reloaded)
	assert_ne(restored == null, true, "the attempt is in flight after the reload")
	if restored == null:
		return
	assert_eq(
		String(restored.attempt_id),
		attempt_id,
		"and it is THE SAME attempt, not a new one the reload minted"
	)
	assert_eq(
		String(restored.target_rank),
		String(committed.get("target", "")),
		"fighting for the realm the pill bought"
	)
	# The facade's own resolve, then the seed-independent proof that it ENDED the
	# attempt: whichever way the roll fell, the record must be terminal here. A
	# stranded attempt is the exact failure this feature exists to remove.
	BodyCultivationApi.resolve_breakthrough(reloaded)
	_assert_resolved(reloaded)


## The claim above cannot be satisfied by a `true` the caller cannot predict, so the
## determinate form commits with a seed CHOSEN to beat the authored chance and then
## resolves with NO generator at all: the roll must come back out of the record, which is
## what makes a save-spanning attempt resolve as it was paid for rather than as the body
## happens to look on reload.
func test_the_saved_roll_is_the_roll_that_resolves_it() -> void:
	var hero := _prepared()
	var chance := float(BodyAdvancement.preview(hero).get("chance", 0.0))
	assert_ne(chance, 0.0, "the fixture commits against a real chance")
	var winning := _seed_beating(chance)
	assert_ne(winning, 0, "a winning seed exists for this chance")
	var started := BodyAdvancement.start_attempt(hero, _rng(winning))
	assert_ne(started == null, true, "the attempt committed")
	if started == null:
		return
	var target := String(started.target_rank)

	var reloaded := _reload_through_the_save(hero)
	assert_ne(reloaded, null, "the envelope rebuilt a body")
	if reloaded == null:
		return

	# No rng: `_replay` must rebuild the generator from `rng_state`, which is the one
	# number the save had to carry for this to be the same trial.
	assert_eq(BodyAdvancement.resolve_attempt(reloaded), true, "the stored roll won, as committed")
	assert_eq(
		String(reloaded.path(BodyPath.PATH_ID).rank_id),
		target,
		"so the hero stands in the realm the attempt fought for"
	)


## **Acceptance criterion 4, across the save boundary.** The award is a cumulative
## `set_base(get_base + reward)`, so a payload that lost `outcome_granted` would pay the
## realm's rewards a second time on the next boot — and a save is exactly when a player
## reloads expecting not to be paid twice.
func test_the_award_is_not_paid_twice_across_a_second_save() -> void:
	var hero := _prepared()
	var chance := float(BodyAdvancement.preview(hero).get("chance", 0.0))
	var winning := _seed_beating(chance)
	assert_ne(winning, 0, "a winning seed exists for this chance")
	var started := BodyAdvancement.start_attempt(hero, _rng(winning))
	assert_ne(started == null, true, "the attempt committed")
	if started == null:
		return
	var reloaded := _reload_through_the_save(hero)
	if reloaded == null:
		return
	assert_eq(BodyAdvancement.resolve_attempt(reloaded), true, "granted")
	var physique := reloaded.stats.get_base(Stat.PHYSIQUE)
	var fibres := reloaded.stats.get_base(&"muscle_fiber")
	var rank := String(reloaded.path(BodyPath.PATH_ID).rank_id)
	# An award really landed, or "unchanged" below would be trivially true.
	assert_ne(fibres > 0.0, true, "a reward key was paid (%s)" % fibres)

	# A SECOND save, taken after the award, is the case that pays twice if the flag
	# does not travel. One save of an ungranted record is not this test.
	var after_the_award := _reload_through_the_save(reloaded)
	assert_ne(after_the_award, null, "a second envelope rebuilt a body")
	if after_the_award == null:
		return
	assert_eq(
		BodyAdvancement.resolve_attempt(after_the_award), true, "and it reports the same answer"
	)
	assert_eq(after_the_award.stats.get_base(Stat.PHYSIQUE), physique, "physique paid once")
	assert_eq(after_the_award.stats.get_base(&"muscle_fiber"), fibres, "no reward key paid twice")
	assert_eq(
		String(after_the_award.path(BodyPath.PATH_ID).rank_id), rank, "still exactly one realm on"
	)


## The spend is part of what survives. A reloaded attempt resolves without a second pill,
## and a hero whose pack is empty on the far side of the save is not the one who paid for
## it — which is the difference between a durable attempt and a deferred charge.
func test_the_pill_is_spent_once_and_is_not_spent_again_on_reload() -> void:
	var hero := _prepared()
	var seed := _play.seed_for(hero)
	assert_ne(seed, null, "the target realm authors a pill")
	var before := _pill_count(hero, seed.breakthrough_item)
	assert_ne(before > 0, true, "the hero holds the pill a breakthrough is priced by")
	var committed := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(committed.is_empty(), false, "the attempt commits")
	assert_eq(_pill_count(hero, seed.breakthrough_item), before - 1, "and spends exactly one")

	var reloaded := _reload_through_the_save(hero)
	assert_ne(reloaded, null, "the envelope rebuilt a body")
	if reloaded == null:
		return
	assert_eq(
		_pill_count(reloaded, seed.breakthrough_item),
		before - 1,
		"the spent pill is still spent after the reload: no second charge is owed"
	)


## The read model the screen renders from has to survive the save too, or the affordance
## is only available in the session that created the attempt — which is precisely the
## session it was built to outlive.
func test_the_read_model_reports_the_committed_attempt_after_the_save() -> void:
	var hero := _prepared()
	var committed := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(committed.is_empty(), false, "the attempt commits")
	var attempt_id := String(committed.get("attempt", ""))

	var reloaded := _reload_through_the_save(hero)
	assert_ne(reloaded, null, "the envelope rebuilt a body")
	if reloaded == null:
		return
	var view := BodyCultivationApi.panel_state(reloaded)
	assert_eq(
		String(view.get("attempt", "")), attempt_id, "the read model names the attempt in flight"
	)
	var outcome: Dictionary = view.get("attempt_outcome", {})
	assert_eq(
		String(outcome.get("status", "")),
		String(BodyAttempt.STATUS_COMMITTED),
		"and the record is committed, not resolved"
	)
	assert_eq(
		String(outcome.get("reason", "")),
		"",
		"so there is no verdict to report: nothing has been rolled yet"
	)
	# The lockout a screen offers resolve against must be the module's own named clause,
	# not something the screen re-derives (ADR 0150).
	var refused: Array = (view.get("unavailable", {}) as Dictionary).get("breakthrough", [])
	assert_eq(refused.size(), 1, "one clause refuses a second attempt")
	assert_eq(
		String((refused[0] as Dictionary).get("kind", "")),
		BodyRefusal.KIND_ATTEMPT_IN_FLIGHT,
		"and it is named as the lockout"
	)


## **Acceptance criterion 3.** The single-call verb still works for a player who never
## quits: one press, one terminal record, at most one realm gained, exactly one pill
## spent. Asserted on the invariants that hold whichever way the roll fell, because the
## facade takes no generator and a test that assumed a victory would be testing seed 0.
func test_the_single_call_verb_still_ends_its_attempt() -> void:
	var hero := _prepared()
	var seed := _play.seed_for(hero)
	var pills := _pill_count(hero, seed.breakthrough_item)
	var rank := String(hero.path(BodyPath.PATH_ID).rank_id)
	var advanced := BodyCultivationApi.attempt_breakthrough(hero)
	var stored := BodyAdvancement.attempt(hero)
	assert_ne(stored == null, true, "a prepared hero's press wrote an attempt record")
	if stored == null:
		return
	assert_eq(stored.is_active(), false, "and it is terminal the moment the call returns")
	assert_eq(stored.is_resolved(), true, "so it reached a verdict, not a cancellation-by-omission")
	assert_eq(_pill_count(hero, seed.breakthrough_item), pills - 1, "for exactly one pill")
	# The report and the world agree, whichever way the roll fell. Written as a pairing
	# rather than two assertions so neither half can pass while the other fails.
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id) != rank,
		advanced,
		"the hero moved a realm exactly when the press reported an advance"
	)


## A refusal while an attempt is committed must cost NOTHING, which is a promise
## `BodyRefusal` publishes in prose. `face_tribulation` descends a wave and
## `Tribulation.fight_wave` charges `WAVE_TOLL` — 1.0 COMPREHENSION, which is this path's
## own entry gate — so if the lockout is read after it, a refused press pays for a fight.
##
## **MEASURED WHERE A WAVE IS ACTUALLY CHARGED, which is the whole difficulty.** Two
## easier shapes of this case prove nothing and would have shipped as green:
##   - at R1 the tribulation gate is trivially open, so `face_tribulation` is a no-op and
##     comprehension cannot move whatever the order is;
##   - with the gate shut and no attempt committed, `can_breakthrough` refuses on the
##     tribulation clause, so the actor looks identical either way.
## The state that separates the two orders is an attempt committed WITH the gate won — the
## only way `_start` gets that far — and the gate abandoned afterwards. That is a player's
## journey: commit the pill, walk away from the fight, come back and press again.
func test_a_refused_press_while_an_attempt_is_committed_costs_no_comprehension() -> void:
	# The last rung whose NEXT realm still sits inside the mortal run, so nothing here has
	# to open an inside world or walk an ascent before the pill can be committed.
	var below := Breakthrough.IMMORTAL_REALM_THRESHOLD - 1
	var ladder := RealmDefaults.ladder()
	if ladder.size() <= below:
		return
	var standing := ladder.realm(below)
	var hero := _play.climb_to(&"qi_refining", standing.id)
	_born.append(hero)
	assert_eq(
		String(hero.path(BodyPath.PATH_ID).rank_id),
		String(standing.id),
		"climbed to %s, whose next realm owes a tribulation" % standing.id
	)
	assert_ne(_play.prepare(hero) == null, false, "and prepared for it, winning the fight it owes")
	assert_eq(
		BodyCultivationApi.begin_breakthrough(hero).is_empty(),
		false,
		"so the attempt commits with the gate open, which is the only way one commits"
	)
	# Now the player abandons the fight. The gate shuts UNDER a committed attempt — the
	# only state in which `face_tribulation` would descend a wave for a press that is
	# going to be refused anyway.
	Breakthrough.cancel_tribulation(hero)
	assert_eq(Breakthrough.tribulation_ok(hero, below + 1), false, "and the gate is shut")
	var comprehension := hero.stats.get_base(Stat.COMPREHENSION)

	assert_eq(BodyCultivationApi.attempt_breakthrough(hero), false, "a second attempt cannot start")
	assert_eq(
		hero.stats.get_base(Stat.COMPREHENSION),
		comprehension,
		"and refusing it cost no comprehension: the lockout is read before the toll"
	)
	assert_eq(
		BodyAdvancement.active_attempt(hero) != null,
		true,
		"and the committed attempt is untouched by the refused press"
	)


# --- Source helpers ------------------------------------------------------------


## A hero at the brink of its next realm, brought there by play.
func _prepared() -> Actor:
	var hero := _play.actor()
	_born.append(hero)
	assert_ne(_play.prepare(hero), null, "prepared for the next realm through public actions")
	return hero


## `persist`, then read the envelope back and rebuild the body the way a boot does —
## `Actor.from_dict` FIRST, then the module attaches, because that order is the one
## `tests/modules/save/test_cultivation_boot_round_trip.gd` exists to police: an attach
## that re-enrols overwrites what the save restored.
##
## The raw `module_data` slots (`acupoints`, `body_progress`, `item_state`) are consumed
## by those attaches, so the rebuilt body is the only comparable thing — which is the
## point, since a boot produces exactly this actor and nothing finer-grained survives it.
func _reload_through_the_save(hero: Actor) -> Actor:
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")
	var restored := SaveStore.restore()
	assert_eq(bool(restored.get("ok", false)), true, "and the slot reads back")
	var envelope := restored.get("envelope", {}) as Dictionary
	if envelope.is_empty():
		return null
	var reloaded := Actor.from_dict(envelope.get("actor", {}) as Dictionary)
	_born.append(reloaded)
	BodyCultivationApi.attach(reloaded)
	BodyCultivationApi.attach_acupoints(reloaded)
	ItemsApi.attach(reloaded)
	BodyTraining.synchronize(reloaded)
	return reloaded


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The smallest seed whose first draw beats `chance`. Bounded by the 255 candidates this
## sweep tries, and it RETURNS rather than growing anything, so the loop cannot be the
## thing that does not terminate.
func _seed_beating(chance: float) -> int:
	for candidate in range(1, 256):
		if _rng(candidate).randf() < chance:
			return candidate
	return 0


func _pill_count(actor: Actor, def_id: StringName) -> int:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return 0
	return inventory.count(def_id)


## Asserted through a helper so the case reads as one sentence: the reloaded resolve
## either granted (a realm on, a flag set) or deviated (a wound, no realm), and in both
## cases it left a TERMINAL record rather than a stranded one. A stranded attempt is the
## failure this whole feature exists to remove, so it is the one thing asserted here.
func _assert_resolved(reloaded: Actor) -> void:
	var stored := BodyAdvancement.attempt(reloaded)
	assert_ne(stored == null, true, "a record is on the actor after the resolve")
	if stored == null:
		return
	assert_eq(stored.is_active(), false, "and it is terminal: no attempt left in flight")
	assert_eq(
		BodyAdvancement.active_attempt(reloaded), null, "so the read model offers resolve to nobody"
	)
	assert_eq(
		stored.trial_complete or stored.status == BodyAttempt.STATUS_CANCELLED,
		true,
		"and the record says which of the two endings it was (status=%s)" % stored.status
	)


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
