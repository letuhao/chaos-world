extends TestCase

## The heavenly tribulation as a GATE, proved per path (ADR 0020/0041/0061, 0103).
##
## Every claim is made three times, once per path id: a gate proved on the qi path and
## asserted for body and mind is a gate proved once. Nothing here writes a rank, a law
## or a success flag — the fights run through `Breakthrough.face_tribulation`, the
## verb a player uses.

## Ladder index of R19, the first realm the Immortal tier gates (0-based).
const IMMORTAL := Breakthrough.IMMORTAL_REALM_THRESHOLD

const PATHS := [BodyPath.PATH_ID, QiPath.PATH_ID, MindPath.PATH_ID]

## Bounds that name what they catch: a phase machine that stopped converging would spin
## the fight, and an undecided fight would spin the verdict search. `SEED_GUARD` is
## over SEEDS, never over game state.
const WAVE_GUARD := 16
const SEED_GUARD := 64

# --- Fixtures -----------------------------------------------------------------


func _hero_at_r18(path_id: StringName) -> Actor:
	var actor := Actor.new(&"gate_hero", {Stat.COMPREHENSION: 40.0})
	var rank := RealmDefaults.ladder().realms()[IMMORTAL - 1].id
	actor.set_path(PathState.new(path_id, rank))
	actor.meridians.unlock_for_realm(rank)
	return actor


## Whether the tribulation gate in front of this path's next realm is open. True at the
## top of the ladder, where no realm remains to owe one.
func _gate_open(actor: Actor, path_id: StringName) -> bool:
	var upcoming := RealmDefaults.ladder().next(actor.path(path_id).rank_id)
	if upcoming == null:
		return true
	return Breakthrough.tribulation_ok(actor, RealmDefaults.ladder().index_of(upcoming.id))


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## One draw per fight, and only the draw on the wave that completes the record: the
## phase machine consumes no randomness, so the deciding draw is the FIRST one, and a
## seed chosen against it decides its fight for certain.
func _seeded_past(threshold: float, want_below: bool) -> RandomNumberGenerator:
	for seed_value in range(1, SEED_GUARD):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		if (rng.randf() < threshold) == want_below:
			rng.seed = seed_value
			return rng
	return RandomNumberGenerator.new()


## Unambiguously below every possible endurance, so the fight is won whatever the
## rating works out at.
func _won_roll() -> RandomNumberGenerator:
	return _seeded_past(TribulationEndurance.MIN_ENDURANCE, true)


## Unambiguously at or above every possible endurance, so the fight is lost whatever
## the rating works out at.
func _lost_roll() -> RandomNumberGenerator:
	return _seeded_past(TribulationEndurance.MAX_ENDURANCE, false)


## Fight until the gate opens, trying seeds until one rolls the actor through. A lost
## fight leaves a decided record and the next attempt replaces it, so every attempt
## runs a whole new fight.
func _fight(actor: Actor, path_id: StringName) -> bool:
	if _gate_open(actor, path_id):
		return true
	for candidate in range(1, SEED_GUARD):
		var rng := _seeded(candidate)
		var guard := 0
		while guard < WAVE_GUARD and not _gate_open(actor, path_id):
			guard += 1
			Breakthrough.face_tribulation(actor, path_id, rng)
		if _gate_open(actor, path_id):
			return true
	return false


## Descend waves with one chosen roll, until the record is decided.
func _descend(actor: Actor, path_id: StringName, rng: RandomNumberGenerator) -> void:
	var guard := 0
	while guard < WAVE_GUARD and not _decided(actor):
		guard += 1
		Breakthrough.face_tribulation(actor, path_id, rng)


func _decided(actor: Actor) -> bool:
	return actor.tribulation != null and actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED


func _injured_channels(actor: Actor) -> int:
	var wounded := 0
	for channel in actor.meridians.get_all_meridians():
		if channel.is_injured():
			wounded += 1
	return wounded


# --- The threshold ------------------------------------------------------------


## Every path is stopped at R19 by an actor that has done nothing wrong. A gate a bare
## actor already passes is not a gate.
func test_r19_is_shut_on_every_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		assert_eq(
			Breakthrough.tribulation_ok(actor, IMMORTAL), false, "%s: R19 needs a fight" % path_id
		)
		assert_eq(
			Breakthrough.try_advance_gated(actor, path_id), false, "%s: advance refused" % path_id
		)
		assert_eq(
			actor.path(path_id).rank_id,
			RealmDefaults.ladder().realms()[IMMORTAL - 1].id,
			"%s: rank held" % path_id
		)


## Nothing stands in front of R18 on any path, so the tier boundary is a threshold and
## not a wall from the first realm.
func test_no_fight_is_owed_below_the_immortal_tier_on_any_path() -> void:
	for path_id in PATHS:
		assert_eq(
			Breakthrough.tribulation_ok(_hero_at_r18(path_id), IMMORTAL - 1),
			true,
			"%s: R18 needs none" % path_id
		)


## `face_tribulation` is the verb that opens R19, and it opens it on all three paths:
## the fight is owed by the shared ladder, not by the qi path.
func test_face_tribulation_opens_r19_on_every_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		assert_eq(_fight(actor, path_id), true, "%s: the fight was won" % path_id)
		assert_eq(
			Breakthrough.tribulation_ok(actor, IMMORTAL), true, "%s: and the gate earned" % path_id
		)


## The call that descends a wave never also reports the gate open, so a gate can never
## be opened by the same call that produces the artifact it reads. The fight is
## `max_waves + 2` calls long, and the survivor is opened by the call after that.
func test_the_call_that_fights_never_opens_the_gate_on_any_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		var waves := int(Breakthrough.begin_tribulation(actor, IMMORTAL).max_waves) + 2
		var rng := _won_roll()
		for call_index in waves:
			assert_eq(
				Breakthrough.face_tribulation(actor, path_id, rng),
				false,
				"%s: call %d fought, so the gate reads shut" % [path_id, call_index + 1]
			)
		assert_eq(
			Breakthrough.face_tribulation(actor, path_id, rng),
			true,
			"%s: a decided win is opened by the next attempt" % path_id
		)


## A fight that has not reached its verdict opens nothing, however many waves it has
## survived. A tribulation that ran to its last phase has survived nothing.
func test_an_unfinished_fight_opens_nothing_on_any_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		assert_ne(Breakthrough.begin_tribulation(actor, IMMORTAL), null, "%s: began" % path_id)
		Breakthrough.face_tribulation(actor, path_id, _won_roll())
		assert_eq(_decided(actor), false, "%s: still running" % path_id)
		assert_eq(
			Breakthrough.tribulation_ok(actor, IMMORTAL), false, "%s: and opens nothing" % path_id
		)


# --- Failure is consequential and recoverable ----------------------------------


## A lost tribulation costs the actor something real — broken channels and a damaged
## dao heart — grants nothing, and takes no realm away.
func test_a_lost_fight_costs_something_on_any_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		var comprehension := actor.stats.get_base(Stat.COMPREHENSION)
		_descend(actor, path_id, _lost_roll())
		assert_eq(
			actor.tribulation.outcome, String(Tribulation.OUTCOME_FAILED), "%s: lost" % path_id
		)
		assert_eq(
			Breakthrough.tribulation_ok(actor, IMMORTAL), false, "%s: the gate stays shut" % path_id
		)
		assert_eq(
			actor.path(path_id).rank_id,
			RealmDefaults.ladder().realms()[IMMORTAL - 1].id,
			"%s: the rank is kept" % path_id
		)
		assert_eq(
			actor.stats.get_base(Stat.COMPREHENSION) < comprehension,
			true,
			"%s: the dao heart took damage" % path_id
		)
		assert_eq(_injured_channels(actor) > 0, true, "%s: the lightning broke channels" % path_id)
		assert_eq(actor.has_status(&"heavenly_blessing"), false, "%s: and paid nothing" % path_id)


## ... and the cost is recoverable. The channels are repairable at the same realm,
## repairing them decides nothing, and the refight opens the gate. A loss that were
## fatal, or that left no way back, would close R19-R30 for good.
##
## Nothing here is strandable: the loss jams no acupoint, so it cannot inherit a
## recovery rule the actor cannot currently reach.
func test_a_lost_fight_is_recoverable_on_any_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		_descend(actor, path_id, _lost_roll())
		assert_eq(actor.tribulation.survived(), false, "%s: lost first" % path_id)
		for channel in actor.meridians.get_all_meridians():
			if channel.is_injured():
				actor.meridians.repair_meridian(channel.id)
		assert_eq(_injured_channels(actor), 0, "%s: every channel repaired" % path_id)
		assert_eq(
			Breakthrough.tribulation_ok(actor, IMMORTAL),
			false,
			"%s: repairing the body does not decide the fight" % path_id
		)
		assert_eq(_fight(actor, path_id), true, "%s: the retry is won" % path_id)
		assert_eq(
			Breakthrough.tribulation_ok(actor, IMMORTAL), true, "%s: and the gate opens" % path_id
		)
		assert_eq(
			Breakthrough.try_advance_gated(actor, path_id), true, "%s: R19 is taken" % path_id
		)


# --- The save boundary --------------------------------------------------------


## A save mid-fight resumes the SAME fight: the waves already fought, the rating they
## were fought at, and the realm the record is bound to. A re-roll on reload makes the
## gate a coin flip on every load; a restart makes the waves fought worth nothing.
func test_a_save_mid_fight_resumes_the_same_fight_on_any_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		var rng := _won_roll()
		Breakthrough.face_tribulation(actor, path_id, rng)
		Breakthrough.face_tribulation(actor, path_id, rng)
		var restored := Actor.from_dict(actor.to_dict())
		assert_ne(restored.tribulation, null, "%s: the fight is on the save" % path_id)
		assert_eq(restored.tribulation.wave, actor.tribulation.wave, "%s: same wave" % path_id)
		assert_eq(restored.tribulation.phase, actor.tribulation.phase, "%s: same phase" % path_id)
		assert_eq(
			restored.tribulation.realm_id, actor.tribulation.realm_id, "%s: same realm" % path_id
		)
		assert_eq(
			restored.tribulation.difficulty,
			actor.tribulation.difficulty,
			"%s: same rating" % path_id
		)
		assert_eq(restored.tribulation.survived(), false, "%s: undecided on the save" % path_id)
		assert_eq(
			Breakthrough.tribulation_ok(restored, IMMORTAL),
			false,
			"%s: an unfinished fight opens nothing after a load" % path_id
		)


## A decided win is durable: the survivor that opens the gate survives the save, so a
## reload cannot silently re-close a gate the player already earned.
func test_a_won_fight_survives_a_save_on_any_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at_r18(path_id)
		assert_eq(_fight(actor, path_id), true, "%s: won" % path_id)
		var restored := Actor.from_dict(actor.to_dict())
		assert_eq(restored.tribulation.survived(), true, "%s: still a survivor" % path_id)
		assert_eq(
			Breakthrough.tribulation_ok(restored, IMMORTAL),
			true,
			"%s: the gate stays open" % path_id
		)


# --- The share of fights survived ---------------------------------------------


## Bounded at both ends and never reaching either: a certainty makes the fight a
## formality, a coin flip makes the gate unopenable, which is the same defect as no
## gate at all.
func test_the_share_of_fights_survived_is_bounded_at_both_ends() -> void:
	for path_id in PATHS:
		for realm in RealmDefaults.ladder().realms():
			var actor := _hero_at_r18(path_id)
			var record := Tribulation.new()
			record.start(actor, realm.id)
			var share := TribulationEndurance.endurance(actor, record)
			assert_eq(
				share >= TribulationEndurance.MIN_ENDURANCE,
				true,
				"%s %s: a floor" % [path_id, realm.id]
			)
			assert_eq(
				share <= TribulationEndurance.MAX_ENDURANCE,
				true,
				"%s %s: a ceiling" % [path_id, realm.id]
			)
			assert_eq(share < 1.0, true, "%s %s: can still be lost" % [path_id, realm.id])


## A harder fight is endured less often, and a deeper dao heart is endured more. If
## either term were dead the rating would be priced and never read.
##
## The dao heart is placed so BOTH shares land strictly inside the bounds. Clamped, the
## comparison is vacuous: at this rating an unprepared actor sits on the floor at either
## end, so a harder fight would read as endured exactly as often.
func test_the_share_of_fights_survived_reads_both_ends_of_the_trade() -> void:
	var actor := _hero_at_r18(QiPath.PATH_ID)
	actor.stats.set_base(Stat.COMPREHENSION, 80.0)
	var soft := Tribulation.new()
	soft.start(actor, &"earth_immortal")
	var hard := Tribulation.new()
	hard.start(actor, &"primordial_origin")
	assert_eq(hard.difficulty > soft.difficulty, true, "the harder fight is rated higher")
	var soft_share := TribulationEndurance.endurance(actor, soft)
	var hard_share := TribulationEndurance.endurance(actor, hard)
	assert_eq(soft_share < TribulationEndurance.MAX_ENDURANCE, true, "the softer share is interior")
	assert_eq(hard_share > TribulationEndurance.MIN_ENDURANCE, true, "the harder share is interior")
	assert_eq(hard_share < soft_share, true, "the harder fight is endured less")
	var before := TribulationEndurance.endurance(actor, soft)
	actor.stats.set_base(Stat.COMPREHENSION, 120.0)
	assert_eq(
		TribulationEndurance.endurance(actor, soft) > before,
		true,
		"a deeper dao heart is endured more"
	)
