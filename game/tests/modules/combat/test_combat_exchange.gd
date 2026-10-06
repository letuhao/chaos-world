extends TestCase

## One encounter exchange, end to end against the shipped content (ADR 0076).
##
## This is the suite the completion bar's failure branch rests on. Before ADR 0076 a
## boss fight could not be lost: the only thing reducing boss vitality was a caller's
## flat constant, and nothing ever touched the player. Every assertion here is about the
## *exchange*, and the headline one is that a player can lose.
##
## The two bands are chosen, not arbitrary: `EMBER` tier 1 is a shallow keyless band and
## `DEEP` (`elemental_transcendent_domain`) the deepest one an actor with no key can enter
## at all (`key_reach = 0`). Both were RE-PRICED by the realm-scaled loot wave of
## 2026-10-05 — `EMBER` authors `12843.8` vitality in `spirit_severing`, `DEEP`
## `491793.8` in `transcendent` — so the control cases below assert WINNABILITY with the
## actor a band is priced for, and a bare actor losing is the expected reading rather than
## a forced one. The gated `loot_storm_crypt_domain` is deliberately not used — its
## `key_reach = 6` is ADR 0033's entry gate, and a test that carried a key would be
## testing the gate.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
const DEEP_DOMAIN := &"elemental_transcendent_domain"
const DEEP_TIER := 1
const SEED := 20260902

## Exchanges one fight may take before the test calls it a stall. A share is floored at
## `CombatDamage.MIN_SHARE`, so this cap cannot be reached by a working model — it names
## the condition that failed to converge (a fight that never ends), and it is small.
const EXCHANGE_CAP := 200


## A bare actor: no gear, no cultivation. This is the one that must be able to lose.
func _delver(physique: float = 10.0, spirit: float = 8.0) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: physique, Stat.SPIRIT: spirit})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	return actor


## The same actor wearing gear. Applied the way items apply gear — a source-tagged FLAT
## `StatModifier` on the same ids `master_option_pool.jsonl` grants — so the test does not
## depend on the items module's own verbs and cannot pass because of how a bag is filled.
func _equipped(physique: float = 10.0, spirit: float = 8.0) -> Actor:
	var actor := _delver(physique, spirit)
	for id in [
		Stat.ATTACK_PHYSICAL,
		Stat.ATTACK_SPIRITUAL,
		Stat.DEFENSE_PHYSICAL,
		Stat.DEFENSE_SPIRITUAL,
		Stat.PENETRATION,
	]:
		actor.stats.add_modifier(StatModifier.new(id, Stat.Op.FLAT, 60.0, &"gear"))
	return actor


## Fight until somebody wins. Returns `{outcome, exchanges, result}`. The cap names the
## condition that failed to converge.
func _fight(actor: Actor, seed_value: int = SEED) -> Dictionary:
	var exchanges := 0
	while exchanges < EXCHANGE_CAP:
		var result := CombatExchange.exchange(actor, seed_value)
		exchanges += 1
		if String(result.get("outcome", "")) != "":
			return {"outcome": String(result["outcome"]), "exchanges": exchanges, "result": result}
	return {"outcome": "unresolved", "exchanges": exchanges, "result": {}}


## Enter a band, refusing loudly if content ever gates or renames it: a test that silently
## fought nothing would report green for the wrong reason.
func _entered(actor: Actor, domain_id: StringName, tier: int) -> bool:
	var result := LootApi.enter_domain(actor, domain_id, tier, SEED)
	assert_eq(bool(result["ok"]), true, "entered %s" % String(domain_id))
	return bool(result["ok"])


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


func test_a_bare_actor_can_lose_a_fight_and_the_run_is_over() -> void:
	var actor := _delver()
	if not _entered(actor, DEEP_DOMAIN, DEEP_TIER):
		return
	var boss_id := String(_active(actor)["boss_id"])
	assert_eq(boss_id != "", true, "a boss is live")

	var fight := _fight(actor)
	assert_eq(
		String(fight["outcome"]),
		CombatExchange.OUTCOME_PLAYER_LOST,
		"a bare actor loses the deepest authored band rather than winning it"
	)
	assert_eq(bool(_active(actor).get("in_domain", false)), false, "the run is over")
	assert_eq(
		int((LootApi.summary(actor)["runs"] as Dictionary).size()),
		1,
		"and the domain's run ledger still remembers the run it granted"
	)
	assert_eq(int(CombatExchange.duel(actor)["defeats"]), 1, "the loss is recorded and readable")
	assert_eq(
		String((CombatExchange.duel(actor)["last_defeat"] as Dictionary)["boss_id"]),
		boss_id,
		"and it names the boss that beat them"
	)


## The control: a loss is not a forced outcome — the shallow band IS winnable.
##
## ## The bands are realm-scaled, and the control moved with them
##
## The 2026-10-05 loot wave re-priced every authored band off its own realm: `EMBER`
## tier 1 authors `12843.8` vitality in `spirit_severing`, so the warden attacks for
## `vitality * ATTACK_PER_VITALITY = 3210.95` — pinned at `CombatDamage.POWER_CEILING`
## and, with its authored `penetration 2.0`, able to spend a bare pool in one exchange.
## The actor a band clears for is the actor it is priced for, so the control uses the
## same `_equipped` set the deep-band case uses, and the assertion is that the fight is
## WINNABLE rather than free.
func test_the_shallow_band_is_winnable_so_a_loss_is_not_a_forced_outcome() -> void:
	var actor := _equipped()
	if not _entered(actor, EMBER_DOMAIN, EMBER_TIER):
		return
	var fight := _fight(actor)
	assert_eq(
		String(fight["outcome"]),
		CombatExchange.OUTCOME_BOSS_DEFEATED,
		"the shallowest authored band is winnable, with the numbers it is priced for"
	)
	assert_eq(int(CombatExchange.duel(actor)["defeats"]), 0, "and nothing was lost doing it")


func test_a_loss_mints_no_reward_because_the_boss_was_never_defeated() -> void:
	var actor := _delver()
	if not _entered(actor, DEEP_DOMAIN, DEEP_TIER):
		return
	var fight := _fight(actor)
	assert_eq(
		String(fight["outcome"]), CombatExchange.OUTCOME_PLAYER_LOST, "and the fight was lost"
	)
	var summary := LootApi.summary(actor)
	assert_eq(int(summary["reward_count"]), 0, "nothing fell from a boss that lived")
	assert_eq(
		int(summary["claimed_encounters"]),
		0,
		"and no claim was spent, so the same reward is still winnable"
	)


func test_a_player_is_carried_out_rather_than_left_dead_on_the_floor() -> void:
	var actor := _delver()
	if not _entered(actor, DEEP_DOMAIN, DEEP_TIER):
		return
	_fight(actor)
	var player := CombatExchange.player(actor)
	assert_eq(bool(player["alive"]), true, "the player is alive again")
	assert_almost_eq(
		float(player["health"]),
		float(player["health_max"]),
		"and at full vitality: a boss fight is a stake on the run, not a wound"
	)


func test_a_lost_run_can_be_re_entered_and_fought_again() -> void:
	# The failure branch must be recoverable, or "fail recoverably" is not true of a boss.
	var actor := _delver(1.0, 1.0)
	if not _entered(actor, DEEP_DOMAIN, DEEP_TIER):
		return
	var lost := _fight(actor)
	assert_eq(
		String(lost["outcome"]), CombatExchange.OUTCOME_PLAYER_LOST, "a hopeless actor loses it"
	)
	var reentry := LootApi.enter_domain(actor, DEEP_DOMAIN, DEEP_TIER, SEED)
	assert_eq(bool(reentry["ok"]), true, "the run is re-granted rather than lost for good")
	var active := _active(actor)
	assert_eq(
		float(active["vitality"]),
		float(active["vitality_max"]),
		"and the boss is back at its full authored vitality"
	)
	assert_eq(int(CombatExchange.duel(actor)["defeats"]), 1, "while the loss stays on the record")


func test_gear_makes_the_same_fight_winnable_that_bare_fists_lose() -> void:
	# The whole point of the module: the actor's own numbers decide the fight.
	var bare_actor := _delver()
	if not _entered(bare_actor, DEEP_DOMAIN, DEEP_TIER):
		return
	var bare := _fight(bare_actor)
	assert_eq(
		String(bare["outcome"]),
		CombatExchange.OUTCOME_PLAYER_LOST,
		"bare fists lose the deepest band"
	)
	var geared := _equipped()
	if not _entered(geared, DEEP_DOMAIN, DEEP_TIER):
		return
	var won := _fight(geared)
	assert_eq(
		String(won["outcome"]),
		CombatExchange.OUTCOME_BOSS_DEFEATED,
		"the same actor wearing gear wins it"
	)


func test_the_players_own_stats_decide_the_exchange_not_a_caller_constant() -> void:
	# Two actors with different numbers, same boss, same seed: the exchange must differ,
	# and it must differ on the damage, not only on the outcome.
	# The weak side is the smallest actor that SURVIVES one answer from the band: the
	# warden's authored `penetration 2.0` shaves mitigation, and a `4.0/2.0` pool is spent
	# by the first exchange (`taken == health_max`), which would make the vitality compare
	# below read a missing boss. `12.0/10.0` lives through the answer and still spends far
	# less of the band than the strong actor.
	var weak := _delver(12.0, 10.0)
	if not _entered(weak, EMBER_DOMAIN, EMBER_TIER):
		return
	var weak_hit := CombatExchange.exchange(weak, SEED)
	var strong := _delver(40.0, 30.0)
	if not _entered(strong, EMBER_DOMAIN, EMBER_TIER):
		return
	var strong_hit := CombatExchange.exchange(strong, SEED)
	assert_eq(
		float(strong_hit["share"]) > float(weak_hit["share"]),
		true,
		"a stronger actor spends more of the same authored pool"
	)
	assert_eq(
		float(_active(strong)["vitality"]) < float(_active(weak)["vitality"]),
		true,
		"and so leaves less of it, on an identically authored boss"
	)


func test_a_boss_that_survives_the_blow_answers_it() -> void:
	var actor := _delver()
	if not _entered(actor, DEEP_DOMAIN, DEEP_TIER):
		return
	var result := CombatExchange.exchange(actor, SEED)
	assert_eq(String(result["outcome"]), "", "one blow is not a whole fight")
	assert_eq(float(result["taken"]) > 0.0, true, "so the boss answered")
	assert_eq(
		(
			float(CombatExchange.player(actor)["health"])
			< float(CombatExchange.player(actor)["health_max"])
		),
		true,
		"and the player is measurably hurt"
	)


func test_an_exchange_outside_a_domain_is_refused_with_loot_s_own_reason() -> void:
	var actor := _delver()
	var result := CombatExchange.exchange(actor, SEED)
	assert_eq(bool(result["ok"]), false, "there is nothing to fight")
	# The reason is `loot`'s vocabulary, read through its facade rather than restated here,
	# so a caller matches one string instead of two — and nothing was mutated on the way.
	assert_eq(
		String(result["reason"]),
		String(LootApi.strike(actor, 0.0, SEED)["reason"]),
		"the exchange refuses with exactly what the primitive refuses with"
	)
	assert_eq(String(result["reason"]), "not_in_domain", "which is the reason a reader shows")
	assert_eq(int(CombatExchange.duel(actor)["defeats"]), 0, "and no loss was invented")


func test_the_preview_quotes_the_exchange_without_spending_anything() -> void:
	var actor := _delver()
	if not _entered(actor, EMBER_DOMAIN, EMBER_TIER):
		return
	var before := float(_active(actor)["vitality"])
	var view := CombatExchange.preview(actor)
	assert_eq(float(view["health"]) > 0.0, true, "the player has health")
	assert_eq(float(view["offense"]["attack"]) > 0.0, true, "and offensive numbers")
	assert_eq(float(view["base_share"]), CombatDamage.BASE_SHARE, "and the share they resolve")
	assert_eq(float(_active(actor)["vitality"]), before, "a preview spends nothing")


func test_the_live_boss_reports_the_numbers_it_fights_with() -> void:
	var actor := _delver()
	if not _entered(actor, DEEP_DOMAIN, DEEP_TIER):
		return
	var active := _active(actor)
	var vitality := float(active["vitality_max"])
	assert_eq(vitality > 0.0, true, "the band authors a vitality")
	# Read through `LootApi`, never off `LootTier`: this module's only door into `loot` is
	# the facade, and the numbers a boss fights with have to arrive through it.
	assert_eq(float(active["attack"]) > 0.0, true, "and the boss arrives with an attack")
	assert_eq(float(active["defense"]) > 0.0, true, "and with a defense")
	assert_eq(
		float(active["attack"]) / vitality,
		float(active["defense"]) / vitality,
		"both priced off the same authored number, so the band has one dial, not two"
	)
