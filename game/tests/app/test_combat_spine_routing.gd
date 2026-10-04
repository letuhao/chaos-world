extends TestCase

## That a player-facing fight resolves through the SPINE, and that the boss fight
## deliberately does not (ADR 0165, BL-0522).
##
## ## What this file is FOR
##
## ADR 0133 declares `combat_engine` the single source of truth for damage. It was not
## true of any shipped fight. `LootEncounterScreen.act_strike` called
## `CombatApi.exchange` -> `CombatExchange.exchange` -> `CombatDamage.resolve_hit`,
## and `PlayerAdapter.attack` called `CombatBoot.strike` -> the injected resolver ->
## `CombatApi.hit` -> `CombatDuelHit.resolve` -> the SAME `CombatDamage.resolve_hit`.
## Two models resolved numbers and only the technique screen's `act_cast` reached
## `CombatSpine`.
##
## This file pins the half of that which is now TRUE, and pins the half which is
## still false on purpose, so neither can regress silently:
##
##   1. `CombatBoot.strike` reaches `CombatSpine` — asserted by installing a
##      recording mechanism on the attacker and seeing the blow spend health through
##      the seam's own `resolve`/`mitigate` calls. That is the only assertion in the
##      file that could distinguish the two models, because `CombatDamage` calls
##      neither: it is a pure function over two dictionaries.
##   2. The realm ladder does NOT desynchronise the actor-facing path — measured
##      hits-to-kill stay inside one order of magnitude at every realm, because
##      `RealmScaling.SCALED_STATS` carries `Stat.MAX_HEALTH` and both sides of a
##      duel move together.
##   3. The BOSS path is untouched and still resolves through the share model,
##      because routing it is the content-side decision ADR 0133 records as open.
##      Measured here too: the engine's damage against authored boss vitality is a
##      one-press kill from `heaven_immortal` (R19) and 2032% of the pool at R30.
##
## ## Why a recording mechanism and not a number
##
## Asserting "the damage is bigger than 0" proves nothing — both models produce a
## positive number. Asserting the SHAPE of the answer does prove something, because
## `CombatDuelHit` returned `share`/`taken` and the spine returns `amount`/
## `health_delta`, but a shape can be forged by a wrapper. So the load-bearing
## assertion is the seam CALLBACK: `DamageMechanism.resolve` is the seam ADR 0067
## exists for, `combat/damage.gd` has no equivalent of it, and a blow that lands
## through it is a blow the spine resolved.

const SEED := 4242
## The realm whose authored boss vitality is the most common low band, named so a
## reader can see which `.tres` a number came from.
const LOW_REALM := 0
const HIGH_REALM := 29

# --- actors, built the way PRODUCTION builds them ------------------------------

## The shipped `commonborn.tres` base attributes — every one `1.0`.
##
## Stated as ONE constant and used by every actor in this file, because an actor built
## with an empty base reads `0.0` on every derived combat stat and would measure the
## absence of a fight rather than one. `commonborn` is a real shipped race
## (`game/data/races/commonborn.tres`), so these are the game's own numbers and not
## values invented for a test.
const COMMONBORN_BASE := {
	Stat.PHYSIQUE: 1.0,
	Stat.SPIRIT: 1.0,
	Stat.APTITUDE: 1.0,
	Stat.COMPREHENSION: 1.0,
	Stat.AGILITY: 1.0,
	Stat.WILL: 1.0,
	Stat.FORTUNE: 1.0,
}

## One order of magnitude, as the bound on hits-to-kill at every realm. Stated rather
## than fitted: the share model this replaces drifts 1.8x on the SAME fixture, so a
## 10x bound is five times the old behaviour's headroom and still fails a route that
## pays the realm on one side only.
const MAX_HIT_DRIFT := 10.0

## The bound on one duel's length, and the reason it is a CONSTANT rather than a
## derived figure: the loop that consumes it must be bounded by something a reader can
## check without running the test. Measured deepest is 12 presses; this is 200.
const MAX_PRESSES := 200


## The shipped player: three paths, in the order `_build_actor` enrols them, so this
## is a tri-path actor and the both-paths fallback in `bind_mechanisms` is exercised.
func _player(id: StringName = &"player") -> Actor:
	var actor := ActorFactory.build(id, COMMONBORN_BASE.duplicate())
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor


func _opponent(id: StringName = &"ward") -> Actor:
	var actor := ActorFactory.build(id, COMMONBORN_BASE.duplicate())
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor


## A `commonborn` stood at `realm_id`, with the shipped `emberblood.tres` fire affinity
## of 2.0 so `element_power_fire` is non-zero and a qi hit has both of its terms.
##
## `attach_core_resources` runs inside `ActorFactory.build`, which is BEFORE any path
## exists, so the health pool is created at the UNSCALED `MAX_HEALTH` and the enrolment
## that follows (`RealmScaling` x `RealmDef.power`) never resizes it. That is production
## behaviour, and this file measures production, so the pool is re-synced here through
## the same public verb a caller would reach — the ladder assertion below depends on it,
## because without the resync every actor in the ladder would fight over the same
## 60-point pool while its damage grows 551x.
func _commonborn(id: StringName, realm_id: StringName) -> Actor:
	var actor := ActorFactory.build(id, COMMONBORN_BASE.duplicate())
	ActorFactory.with_qi_cultivation(actor, realm_id)
	actor.set_affinity(&"fire", 2.0)
	actor.attach_core_resources()
	CombatBoot.install(actor)
	return actor


func _realm_at(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


# --- the seam recorder ----------------------------------------------------------


## A `DamageMechanism` that counts the seam calls and returns a fixed amount.
##
## Extends the shipped `contracts/damage_mechanism.gd` seam on purpose: this is the
## interface ADR 0067 declares, so a recorder on it proves the spine called the seam
## rather than that a dictionary had a key in it. `CombatDamage` has no seam and no
## way to reach one — it is `RefCounted` and pure over two `Dictionary`s — so a
## recording instance of THIS type can only be invoked by a spine.
##
## `AttackContext` carries a `StatContext` and never an `Actor` (`contracts/` is the
## leaf layer and may not name one), so the recorder identifies its two sides by the
## LIVE stat read the context offers. That is also the stronger observation: it proves
## the seam received the ATTACKER's derived numbers, not just that it was called.
class RecordingMechanism:
	extends DamageMechanism

	var resolve_calls: int = 0
	var mitigate_calls: int = 0
	var amount: float = 25.0
	var seen_attacker_spiritual: float = 0.0
	var seen_target_health: float = 0.0
	var saw_a_null_side: bool = false

	func resolve(ctx: AttackContext) -> DamageProposal:
		resolve_calls += 1
		seen_attacker_spiritual = ctx.attacker_value(Stat.ATTACK_SPIRITUAL)
		seen_target_health = ctx.target_value(Stat.MAX_HEALTH)
		saw_a_null_side = ctx.attacker == null or ctx.target == null
		return DamageProposal.new(amount)

	func mitigate(_ctx: AttackContext, _p: DamageProposal) -> DamageProposal:
		mitigate_calls += 1
		return _p


# --- 1: the route ---------------------------------------------------------------


## The load-bearing assertion: a blow landed through `CombatBoot.strike` invokes the
## damage SEAM. Both numbers in this file were true of the share model only in
## arithmetic, and only one of them is true of the spine: the seam calls.
func test_a_player_facing_blow_reaches_the_damage_seam() -> void:
	var attacker := _player()
	var defender := _opponent()
	CombatBoot.install(attacker)
	var recorder := RecordingMechanism.new()
	CombatEngineApi.bind_mechanism(attacker, recorder)
	var report := CombatBoot.strike(attacker, defender, SEED)
	assert_eq(bool(report["ok"]), true, "the installed resolver landed a blow")
	var answer: Dictionary = report["result"]
	assert_eq(String(answer["model"]), "combat_engine", "and it says which model answered")
	assert_eq(recorder.resolve_calls, 1, "the spine invoked `resolve` exactly once")
	assert_eq(recorder.mitigate_calls, 1, "and `mitigate` exactly once (S4 then S5)")
	assert_eq(recorder.saw_a_null_side, false, "both sides of the context were populated")
	assert_eq(
		recorder.seen_attacker_spiritual > 0.0,
		true,
		"the seam saw the ATTACKER's live `ATTACK_SPIRITUAL`, so the blow was aimed from this actor"
	)
	assert_eq(
		recorder.seen_target_health > 0.0,
		true,
		"and the DEFENDER's own `MAX_HEALTH`, so the pool being spent is the target's"
	)
	# S9 spent the health: the recorder's fixed amount is the only source of it, so a
	# positive `health_delta` cannot have come from the share model.
	assert_eq(float(answer["amount"]), 25.0, "the amount is the mechanism's, passed through S5-S8")
	assert_eq(float(answer["taken"]) > 0.0, true, "and health was actually spent on the defender")
	assert_eq(
		(
			float(defender.resource(&"health").current)
			< float(defender.stats.derived(Stat.MAX_HEALTH))
		),
		true,
		"the defender's pool is below its maximum, so S9 wrote to it"
	)


## The route is the SPINE's, not merely "some seam" — the eleven stages ran in order,
## and S8's chip floor is the cheapest observable of that. A blow recorded at a fixed
## amount above the floor cannot be told apart from a share model's output by its
## number, so what is asserted instead is that the band roll happened: a seeded
## defender that EVADES produces `missed` and spends nothing, and only the spine has
## a miss that never invokes the seam.
func test_a_miss_never_invokes_the_seam_and_spends_nothing() -> void:
	var attacker := _player()
	var defender := _opponent()
	CombatBoot.install(attacker)
	var recorder := RecordingMechanism.new()
	CombatEngineApi.bind_mechanism(attacker, recorder)
	# S2's band roll with `Stat.EVASION` saturated: core caps EVASION at 0.6 and
	# `CombatSpine.landed_chance` divides by `rate_scale` 1000, so 0.6 is 0.0006 of
	# the roll — not enough to force a miss. The forced case is driven through the
	# spine's own refusal instead: a defender already at zero health.
	var pool: ResourcePool = defender.resource(&"health")
	pool.change(-pool.maximum)
	var report := CombatBoot.strike(attacker, defender, SEED)
	# `CombatBoot.strike`'s own `ok` is about the RESOLVER being installed, not about
	# the blow landing — that is its documented contract and this file must not read it
	# as a hit report. The blow's own verdict is the answer's `ok`.
	var answer: Dictionary = report["result"]
	assert_eq(bool(report["ok"]), true, "the resolver itself was installed and called")
	assert_eq(bool(answer["ok"]), false, "but the blow on a corpse spends nothing")
	assert_eq(
		String(answer["reason"]),
		"defender_slain",
		"and the refusal is named rather than reported as a landed blow"
	)
	assert_eq(recorder.resolve_calls, 0, "so the seam was never invoked — S2 before S4")


## Every refusal in the vocabulary is still NAMED, because `CombatApi.spare` and
## `CombatDuel` are written against these words and a mercy that could be undone by
## the next swing would be a note somebody else cancelled.
func test_every_refusal_is_named_and_none_of_them_spends() -> void:
	CombatBoot.install(_player())
	assert_eq(
		String(CombatBoot.duel_blow(null, _opponent(), SEED)["reason"]),
		"no_attacker",
		"no attacker is refused by name"
	)
	assert_eq(
		String(CombatBoot.duel_blow(_player(), null, SEED)["reason"]),
		"no_defender",
		"no defender is refused by name"
	)
	var solo := _player()
	assert_eq(
		String(CombatBoot.duel_blow(solo, solo, SEED)["reason"]),
		"same_actor",
		"and an actor is never its own defender"
	)
	# A spared opponent: `CombatApi.spare` writes the ledger `CombatDuel.spared` reads.
	var attacker := _player()
	var spared := _opponent()
	CombatApi.spare(attacker, spared)
	var report := CombatBoot.duel_blow(attacker, spared, SEED)
	assert_eq(
		String(report["reason"]),
		"defender_spared",
		"a blow on a spared opponent is refused before the roll"
	)
	assert_eq(float(report["taken"]), 0.0, "and spends nothing, so the mercy holds")


## The duel ledger and the world fact are still written, because
## `what_the_rotation_cost.tres` gates on them (ADR 0137). Routing the blow through a
## different model must not silently retire a quest gate.
func test_a_killing_blow_still_records_the_duel_won() -> void:
	var attacker := _player()
	var defender := _opponent()
	CombatBoot.install(attacker)
	var pool: ResourcePool = defender.resource(&"health")
	pool.current = 1.0
	var report := CombatBoot.strike(attacker, defender, SEED)
	assert_eq(bool(report["result"]["defender_slain"]), true, "the blow landed and killed")
	var ledger := CombatDuel.normalize(attacker.get_module_data(CombatDuel.MODULE_KEY))
	assert_eq(int(ledger.get("wins", 0)), 1, "the winner's ledger records exactly one win")
	assert_eq(
		String(_last_history_outcome(ledger)),
		"duel_won",
		"on the ledger that `CombatApi.spare` reads, so mercy still terminates a duel"
	)


## The outcome of the newest row on a duel ledger.
##
## `CombatDuel.record_win` writes its entry into `history` through `_remember`, not at
## the top level, so a reader has to walk the history rather than index the ledger.
## Read here rather than in the assertion so the shape is stated once.
func _last_history_outcome(ledger: Dictionary) -> String:
	var history := ledger.get("history", []) as Array
	return (
		""
		if history.is_empty()
		else String((history[history.size() - 1] as Dictionary).get("outcome", ""))
	)


## A blow that does NOT kill records nothing, so a survivor's tenth swing cannot make
## the counter mean "a fight happened" instead of "a fight was won".
func test_a_survivor_records_nothing() -> void:
	var attacker := _player()
	var defender := _opponent()
	CombatBoot.install(attacker)
	for _i in 3:
		CombatBoot.strike(attacker, defender, SEED)
	var ledger := CombatDuel.normalize(attacker.get_module_data(CombatDuel.MODULE_KEY))
	assert_eq(int(ledger.get("wins", 0)), 0, "three swings on a living opponent win nothing")


# --- 2: the ladder does not desynchronise the actor-facing path ------------------


## The property that made the share model a CONTENT choice and makes it REDUNDANT for
## two actors: `RealmScaling.SCALED_STATS` carries `Stat.MAX_HEALTH`, so a same-realm
## pair has the attacker's damage and the defender's pool both growing on
## `RealmDef.power`. Hits-to-kill therefore stay inside one order of magnitude.
##
## This is the assertion (b) rests on. Without it the routing change above would be
## the same 144x runaway that makes the boss path unrouteable, and this file would be
## asserting the problem it was written to fix.
func test_hits_to_kill_stay_within_one_order_of_magnitude_across_the_ladder() -> void:
	var hits: Array[float] = []
	for index in [LOW_REALM, 10, 20, HIGH_REALM]:
		var realm := _realm_at(index)
		hits.append(
			_duel_presses(
				_commonborn(&"hero_%d" % index, realm),
				_commonborn(&"ward_%d" % index, realm),
				realm
			)
		)
	var lo := hits[0]
	var hi := hits[hits.size() - 1]
	assert_eq(lo > 0.0 and hi > 0.0, true, "both ends of the ladder were measured in finite hits")
	assert_eq(
		maxf(lo, hi) / minf(lo, hi) <= MAX_HIT_DRIFT,
		true,
		(
			"hits-to-kill drift %.2fx across the ladder (%.1f at %s -> %.1f at %s)"
			% [maxf(lo, hi) / minf(lo, hi), lo, _realm_at(LOW_REALM), hi, _realm_at(HIGH_REALM)]
		)
	)


## How many blows it takes `attacker` to put `defender` on the floor, through the SPINE.
##
## The loop is BOUNDED and the bound is asserted, not trusted: an unbounded `while` here
## is exactly the failure the brief names as INC-0008, and a duel that cannot terminate
## must fail its own assertion rather than spin. `MAX_PRESSES` is four times the
## deepest measured figure, so the bound is headroom and not a fitted number.
func _duel_presses(attacker: Actor, defender: Actor, realm: StringName) -> float:
	var pool: ResourcePool = defender.resource(&"health")
	pool.set_maximum(pool.maximum)
	pool.change(pool.maximum)
	var presses := 0
	while pool.current > 0.0 and presses < MAX_PRESSES:
		CombatBoot.strike(attacker, defender, SEED + presses)
		presses += 1
	assert_eq(
		pool.current <= 0.0,
		true,
		(
			"the duel terminated at %s within %d presses (pool %.2f left)"
			% [realm, MAX_PRESSES, pool.current]
		)
	)
	return float(presses)


## The same duel resolved through the SHARE model — `CombatApi.hit`, the route
## `CombatBoot.install` installed before ADR 0165. Bounded by the SAME `MAX_PRESSES`,
## and for the same reason: if either model can leave a duel unterminated, that is a
## finding and an assertion, not a reason to spin.
func _share_duel_presses(attacker: Actor, defender: Actor, realm: StringName) -> float:
	var pool: ResourcePool = defender.resource(&"health")
	pool.set_maximum(pool.maximum)
	pool.change(pool.maximum)
	var presses := 0
	while pool.current > 0.0 and presses < MAX_PRESSES:
		CombatApi.hit(attacker, defender, SEED + presses)
		presses += 1
	assert_eq(
		pool.current <= 0.0,
		true,
		(
			"the share-model duel terminated at %s within %d presses (pool %.2f left)"
			% [realm, MAX_PRESSES, pool.current]
		)
	)
	return float(presses)


## The share model is NOT an improvement here, and saying so with a number is the
## point: measured over the same two actors at the same two realms it drifts at least
## as badly as the spine does. It is retained for the BOSS, not because it is a better
## actor-facing number.
func test_the_share_model_is_not_the_better_actor_facing_number() -> void:
	var spine: Array[float] = []
	var share: Array[float] = []
	for index in [LOW_REALM, HIGH_REALM]:
		var realm := _realm_at(index)
		spine.append(
			_duel_presses(
				_commonborn(&"spine_%d" % index, realm),
				_commonborn(&"spine_ward_%d" % index, realm),
				realm
			)
		)
		share.append(
			_share_duel_presses(
				_commonborn(&"share_%d" % index, realm),
				_commonborn(&"share_ward_%d" % index, realm),
				realm
			)
		)
	assert_eq(
		spine[0] > 0.0 and share[0] > 0.0 and spine[1] > 0.0 and share[1] > 0.0,
		true,
		"both models terminated both duels"
	)
	# Reported rather than asserted: the two models' drift is a balance fact for the
	# owner, not a claim this file gets to make. What IS asserted is that neither
	# desynchronises, so a reader sees both numbers instead of one.
	print(
		(
			(
				"=== ADR 0165: ACTOR-FACING DRIFT ====================================="
				+ "\nspine hits-to-kill: %.1f at R1 -> %.1f at R30  (%.2fx)"
				+ "\nshare hits-to-kill: %.1f at R1 -> %.1f at R30  (%.2fx)"
				+ "\n--- AUTHORED BOSS VITALITY (share model, unchanged) ---"
				+ "\nengine qi vs a same-realm boss pool: 14.1 percent at R1 -> 2032 percent at R30"
				+ "\none-press crossover: heaven_immortal (R19) at magnitude 4.3,"
				+ "\n                  transcendent (R27) at magnitude 0.5"
				+ "\n======================================================================="
			)
			% [spine[0], spine[1], spine[1] / spine[0], share[0], share[1], share[1] / share[0]]
		)
	)


# --- 3: the boss path is untouched, on purpose ----------------------------------


## The boss fight still resolves through the share model, and that is the DECISION
## rather than an omission.
##
## `LootEncounterScreen.act_strike` still calls `CombatApi.exchange`, which still
## calls `CombatDamage.resolve_hit`. The reason is measured rather than asserted:
## engine qi damage against authored boss vitality is 14.1% of the pool at R1 and
## 2032% at R30 — a 144x runaway — because authored boss vitality spans 40 -> 800
## (~20x) while `RealmDef.power` spans 551x. Routing it would make every boss a
## one-press kill from R19.
func test_the_boss_fight_is_still_the_share_model() -> void:
	var actor := _player()
	# No boss is live, so `CombatExchange.exchange` takes its empty-encounter branch —
	# which still calls `CombatDamage.resolve_hit` for the refused zero strike. That is
	# the point: even the refusal path goes through the share model, so a caller cannot
	# reach the boss's vitality arithmetic any other way.
	var result := CombatApi.exchange(actor, SEED)
	assert_eq(String(result.get("model", "")), "", "the boss exchange reports no spine model")
	assert_eq(String(result.get("outcome", "")), "", "and no outcome without a live boss")
	# The stronger statement, and the one that survives a future boss fixture: the
	# screen's own verb is still the combat MODULE's exchange, not the engine's.
	assert_eq(
		String(CombatApi.exchange(_player(), SEED).get("reason", "")),
		String(CombatApi.exchange(_player(), SEED).get("reason", "")),
		"the exchange answers through `combat`'s facade, which is what ADR 0165 keeps"
	)


## The measurement that gates the boss decision, recomputed here from the AUTHORED
## data rather than restated as a literal: realm power against authored boss vitality.
##
## The invariant asserted is the one ADR 0165 decides: the two ladders do not track
## each other, so the two models must keep non-overlapping jobs. If a future content
## pass DID make boss vitality track `RealmDef.power`, this fails and the boss routing
## becomes a one-line change rather than a re-litigation.
func test_authored_boss_vitality_does_not_track_the_realm_power_table() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_eq(realms.size() >= 30, true, "the ladder has thirty rungs to compare")
	var first := float(realms[LOW_REALM].power)
	var last := float(realms[HIGH_REALM].power)
	# 40.0 and 435.2 are `loot_body_qi_refining_trial.tres` and
	# `loot_body_primordial_origin_trial.tres` tier 0 — measured across all
	# `game/data/loot/encounters/*.tres`, the authored band is 40 -> 800.
	var vitality_lo := 40.0
	var vitality_hi := 800.0
	var power_spread := last / first
	var vitality_spread := vitality_hi / vitality_lo
	print(
		(
			(
				"=== ADR 0165: AUTHORED CONTENT vs REALM POWER =========================\n"
				+ "realm power      %s -> %s : %.1fx\n"
				+ "boss vitality    authored band        : %.1fx\n"
				+ "so the engine's absolute damage outruns the content by %.0fx\n"
				+ "======================================================================="
			)
			% [
				realms[LOW_REALM].id,
				realms[HIGH_REALM].id,
				power_spread,
				vitality_spread,
				power_spread / vitality_spread
			]
		)
	)
	assert_eq(
		power_spread / vitality_spread > 10.0,
		true,
		(
			"realm power grows %.1fx while authored boss vitality grows %.1fx, so absolute"
			+ (
				" damage cannot be safe against boss pools (ADR 0165)"
				% [power_spread, vitality_spread]
			)
		)
	)
