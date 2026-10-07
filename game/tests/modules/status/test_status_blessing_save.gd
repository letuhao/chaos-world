extends TestCase

## ADR 0186: the tribulation blessing's once-guard is SESSION-ONLY, so a permanent reward
## a player earned is never silently deleted by a save and never unrecoverable.
##
## ## The defect this suite exists to pin shut (DEF-0235 / DEF-0150)
##
## `TribulationBlessing.award` pays one of three PERMANENT cultivation statuses
## (`earth_bulwark`, `light_halo`, `wood_bloom`, all `duration = -1.0`) and wrote its
## once-guard `REWARDED_KEY` into `actor.module_data`. `module_data` IS serialized
## (`core/actor.gd:344`) and restored (`core/actor.gd:397-398`), but `Actor.to_dict()`
## emits NO `statuses` key (ADR 0089) — so the GUARD survived the save and the REWARD it
## was guarding did not. Save & reload, and the restored actor answered `ALREADY_REWARDED`
## while `core/tribulation.gd:156,193` refused a re-fight on the restored `SURVIVED` outcome.
## **A permanent reward, deleted by an autosave, never re-earnable, silently** — the ADR 0140
## wound defect under a status's name.
##
## ## What each test asserts, and why none of them is the same claim
##
## 1. The guard does NOT ride `module_data` — it is absent from the serialized payload.
## 2. The DEFEAT: save -> reload -> the restored actor is RE-PAYABLE, and pays again. This is
##    the data-loss fix, and it fails against the old `module_data` guard.
## 3. ONCE-ONLY WITHIN A SESSION is intact — a second observation of the same decided record
##    in one session still refuses. The fix must not become a blessing farm.
## 4. A load does not resurrect the STATUS itself — the blessing is absent from the restored
##    actor until it is re-paid, which is what "session-only" means (ADR 0089).
##
## ## Why a SECOND observation is exercised directly rather than through a re-fight
##
## `TribulationFight.fight_to_verdict` refuses a re-fight on its own (`tribulation_fight.gd:81`),
## so it can never reach `award` a second time and would make the session guard look
## untestable. The guard that actually matters is the one inside `award` — "a caller that
## OBSERVED the same decided record twice" — so `award` is called twice directly here. That is
## the shape the ADR 0061 defect took, and it is the one ADR 0186 promises still cannot
## happen in a session.

const CULTIVATION_IDS: Array[StringName] = [
	&"earth_bulwark",
	&"light_halo",
	&"wood_bloom",
	&"metal_temper",
	&"water_wellspring",
	&"fire_forge",
	&"lightning_quicken",
	&"ice_stillness",
	&"wind_stride",
	&"dark_veil",
]


func setup() -> void:
	# A floor, so a body that aborts on its first line cannot report green.
	expect_assertions(6)


func _gate_index() -> int:
	# Read from core rather than pinned: the ladder is append-only, and a hardcoded
	# index broke the moment a realm was inserted (ADR 0050).
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


## The realm one BELOW the Immortal gate — the only position from which a tribulation is
## owed. `realm.index` is the ladder's own value, so an inserted realm moves the fixture.
func _owed_realm() -> RealmDef:
	return RealmDefaults.ladder().realms()[_gate_index() - 1]


func _hero(hero_id: StringName = &"save_guard_hero") -> Actor:
	var realm_id := _owed_realm().id
	var actor := ActorFactory.build(hero_id, {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## A generator whose first draw decides the whole fight by BOUND rather than by hope.
## `TribulationEndurance.endurance` CLAMPS into `[MIN_ENDURANCE, MAX_ENDURANCE]`, so a
## draw below the floor survives whatever the fight did and a draw at the ceiling always
## fails. The seed is REWOUND before it is returned, because the search has to draw to know
## a seed is decisive and that draw advances the generator (PCG state is seed-determined).
func _rng_for_survival() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if rng.randf() < TribulationEndurance.MIN_ENDURANCE:
			rng.seed = seed_value
			return rng
	rng.seed = 1
	return rng


## Begin the owed fight through the MODULE'S OWN verb, then set the trial type AFTER the
## record is rated — `start` takes `difficulty` from `rate(actor)`, which reads
## `TYPE_PRESSURE[type]`, so a type set before `start` would price the fight against a
## pressure it is not then fought at.
func _begin_and_survive(actor: Actor, trial_type: StringName = Tribulation.ELEMENTAL) -> Dictionary:
	var began := TribulationFight.begin(actor)
	if not bool(began.get("ok", false)):
		return began
	actor.tribulation.type = trial_type
	return TribulationFight.fight_to_verdict(actor, _rng_for_survival())


## A survived tribulation paid a blessing, through the production producer.
func _survivor_with_blessing(hero_id: StringName = &"save_guard_hero") -> Array:
	var actor := _hero(hero_id)
	var fought := _begin_and_survive(actor)
	assert_eq(
		bool(fought.get("ok", false)),
		true,
		"the fight resolved: %s" % String(fought.get("reason", ""))
	)
	assert_eq(bool(fought.get("survived", false)), true, "and was survived")
	var granted := fought.get("blessing", {}) as Dictionary
	assert_eq(bool(granted.get("ok", false)), true, "a blessing was paid: %s" % str(granted))
	var status_id := StringName(granted.get("id", ""))
	assert_eq(
		CULTIVATION_IDS.has(status_id),
		true,
		"and it is one of the permanent cultivation blessings, not %s" % String(status_id)
	)
	assert_eq(actor.has_status(status_id), true, "the status is on the actor")
	return [actor, status_id]


# --- the guard does not ride the persisted slot ----------------------------------


func test_the_once_guard_is_not_in_the_saved_payload() -> void:
	# The root cause, asserted on its own so a reader can see it without reading the
	# behavioural tests. `module_data` is serialized VERBATIM (`core/actor.gd:344`), so a
	# guard written there IS in every save — which is how the guard outlived the reward it
	# was guarding.
	var survivors := _survivor_with_blessing(&"guard_not_persisted")
	var actor := survivors[0] as Actor
	var payload: Variant = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_eq(typeof(payload), TYPE_DICTIONARY, "the actor payload is JSON-safe")
	var module_data: Variant = (payload as Dictionary).get("module_data", {})
	assert_eq(typeof(module_data), TYPE_DICTIONARY, "and carries a module_data slot")
	assert_eq(
		(module_data as Dictionary).has(String(TribulationBlessing.REWARDED_KEY)),
		false,
		(
			"the once-guard is NOT in module_data: a guard that is saved while the reward it "
			+ "guards is not turns a permanent blessing into one that can never be re-earned"
		)
	)
	# And nothing under any other spelling of it rode along either.
	assert_eq(
		JSON.stringify(module_data).contains("tribulation_blessing_paid"),
		false,
		"no spelling of the guard key reaches the save"
	)


# --- the data loss is closed ------------------------------------------------------


func test_a_survived_blessing_is_re_earnable_after_a_save_and_reload() -> void:
	# THE DEF-0235 fix, driven through the real payload path including a JSON hop.
	#
	# Save & reload, and the restored actor has the SURVIVED outcome and nothing else: no
	# blessing (ADR 0089 keeps statuses out of the payload) and no guard (ADR 0186). So the
	# next observation of that record must PAY again rather than answer `already_rewarded`
	# on a reward the actor does not have.
	var survivors := _survivor_with_blessing(&"reload_re_earnable")
	var actor := survivors[0] as Actor
	var status_id := survivors[1] as StringName
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored != null, true, "the actor was restored")
	assert_eq(
		restored.tribulation != null and restored.tribulation.survived(),
		true,
		"the restored record is still a SURVIVED fight — the gate's own proof it was won"
	)
	# The blessing did NOT ride the save, and the guard did not either.
	assert_eq(
		restored.has_status(status_id), false, "the blessing is session-only, not in the save"
	)
	assert_eq(
		restored.get_module_data(TribulationBlessing.REWARDED_KEY).is_empty(),
		true,
		"and the restored actor carries no once-guard to refuse against"
	)
	# THE CLAIM: the restored actor is re-payable, and pays.
	var re_paid := TribulationBlessing.award(restored)
	assert_eq(
		bool(re_paid.get("ok", false)),
		true,
		"a survived tribulation is re-earnable after a load: %s" % str(re_paid)
	)
	assert_eq(
		StringName(re_paid.get("id", "")),
		status_id,
		"and it pays the blessing this fight earned, not a different one"
	)
	assert_eq(
		restored.has_status(status_id), true, "so the player is not left without their reward"
	)


func test_a_json_hop_does_not_resurrect_the_guard_either() -> void:
	# The save is written through `JSON.stringify` (ADR 0128's envelope), so a payload that
	# only round-trips in memory is not the shape that ships. This is the same claim as the
	# test above through the wire format.
	var survivors := _survivor_with_blessing(&"reload_json_hop")
	var actor := survivors[0] as Actor
	var status_id := survivors[1] as StringName
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(actor.to_dict()))
	var restored := Actor.from_dict(round_tripped as Dictionary)
	assert_eq(restored != null, true, "the actor survived the JSON hop")
	assert_eq(restored.has_status(status_id), false, "still no blessing on the restored actor")
	var re_paid := TribulationBlessing.award(restored)
	assert_eq(
		bool(re_paid.get("ok", false)),
		true,
		"and it is still re-earnable through the real save format: %s" % str(re_paid)
	)


# --- the once-only guarantee survives inside a session ----------------------------


func test_a_second_observation_in_one_session_still_cannot_double_pay() -> void:
	# The guarantee ADR 0186 must not break. `award` is called directly rather than
	# through `TribulationFight`, because the module refuses a re-fight on its own decided
	# guard (`tribulation_fight.gd:81`) and would never reach `award` twice — which is
	# exactly why the guard INSIDE `award` needs its own test.
	var survivors := _survivor_with_blessing(&"session_once_only")
	var actor := survivors[0] as Actor
	var status_id := survivors[1] as StringName
	var second := TribulationBlessing.award(actor)
	assert_eq(
		bool(second.get("ok", false)),
		false,
		"a second observation of the same decided record in one session is refused"
	)
	assert_eq(
		String(second.get("reason", "")),
		String(TribulationBlessing.ALREADY_REWARDED),
		"and names ALREADY_REWARDED rather than silently doing nothing"
	)
	# And it did not pay a SECOND copy. `earth_bulwark` etc. are `refresh`-stacking, so a
	# double pay would not have produced two array entries — it would have silently
	# strengthened one. The status count is the observable that a single instance remains.
	assert_eq(actor.has_status(status_id), true, "the one blessing the actor earned is still there")
	var carriers := 0
	for status in actor.statuses:
		if status.id == status_id:
			carriers += 1
	assert_eq(carriers, 1, "and it is exactly one instance, not a second pay")


func test_the_decided_record_itself_still_refuses_a_re_fight() -> void:
	# The OTHER half of the same guarantee, and the one this ADR does not touch: the
	# record's own `outcome` guard (`core/tribulation.gd:156,193`) still refuses a re-fight
	# in the same session. A blessing farmable by re-fighting one trial is not a reward
	# (ADR 0061's shape).
	var survivors := _survivor_with_blessing(&"session_no_refight")
	var actor := survivors[0] as Actor
	var again := TribulationFight.fight_to_verdict(actor, _rng_for_survival())
	assert_eq(bool(again.get("ok", false)), false, "a decided fight cannot be re-fought")
	assert_eq(String(again.get("reason", "")), "the tribulation is already decided", "and says why")


func test_a_loss_pays_nothing_and_leaves_no_guard_behind() -> void:
	# The control that keeps the re-pay honest: if a fight was LOST, there is nothing to
	# re-earn, so a restored losing record must still refuse. Without this, "re-payable"
	# would be satisfied by an `award` that pays anything at all.
	var actor := _hero(&"session_loss")
	var began := TribulationFight.begin(actor)
	assert_eq(bool(began.get("ok", false)), true, "a fight was owed")
	actor.tribulation.type = Tribulation.ELEMENTAL
	# A draw at the MAX endurance ceiling always fails, whatever the fight did.
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if rng.randf() >= TribulationEndurance.MAX_ENDURANCE:
			rng.seed = seed_value
			break
	var lost := TribulationFight.fight_to_verdict(actor, rng)
	assert_eq(bool(lost.get("survived", false)), false, "the hero lost the fight")
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored != null, true, "the loser was saved and restored")
	assert_eq(restored.tribulation.survived(), false, "a restored loss is still a loss")
	var re_paid := TribulationBlessing.award(restored)
	assert_eq(bool(re_paid.get("ok", false)), false, "and it pays nothing after a load")
	assert_eq(
		String(re_paid.get("reason", "")),
		String(TribulationBlessing.NO_SURVIVOR),
		"naming NO_SURVIVOR — the record was never won"
	)


func test_a_different_actor_is_payable_independently() -> void:
	# The guard is keyed by actor, so one hero's blessing never refuses another's. This is
	# the shape that makes the store a per-actor session table rather than a module-wide
	# flag, which would have made the second tribulation in the game unpayable.
	var first := _hero(&"session_actor_a")
	_assert_survived_and_paid(first)
	var second := _hero(&"session_actor_b")
	assert_eq(
		bool(TribulationBlessing.award(second).get("ok", false)),
		false,
		"a second hero that has not fought pays nothing yet"
	)
	_assert_survived_and_paid(second)
	assert_eq(
		bool(TribulationBlessing.award(second).get("ok", false)),
		false,
		"and once it has, its own guard bites — independently of the first hero's"
	)


func _assert_survived_and_paid(actor: Actor) -> void:
	var fought := _begin_and_survive(actor)
	assert_eq(bool(fought.get("ok", false)), true, "the fight resolved")
	assert_eq(bool(fought.get("survived", false)), true, "and was survived")
	var granted := fought.get("blessing", {}) as Dictionary
	assert_eq(bool(granted.get("ok", false)), true, "and paid a blessing")
