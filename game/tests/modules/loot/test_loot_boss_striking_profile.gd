extends TestCase

## A boss can ACT: its striking profile is authored on its `BossDef`, frozen with the
## spawned boss, and spent by the real combat exchange (BL-0224).
##
## ## What was missing
##
## `BossDef` declared four fields — id, display name, domain, and a legacy loot list. No
## vitality, no attack, no defence, no profile. Vitality and the two magnitudes come off
## the band's authored vitality (ADR 0076), which is deliberate and unchanged.
##
## But `CombatExchange._boss_offense` answered with a **literal** `{crit_chance 0,
## crit_damage 1, penetration 0}` and `_boss_guard` with `{damage_reduction 0, evasion 0}`.
## So no boss in the game could crit, pierce, slip a blow or soften one, and **no authored
## content could change that**: every boss of every band fought identically in kind. This
## is the seam `test_loot_boss_profile.gd` covers from the other side — that file owns the
## band's magnitudes, this one owns the boss's identity.
##
## Each guard is proved in both directions, because a boss that cannot act and a boss that
## cannot be fought are the same defect seen from two sides.

const EMBER_DOMAIN := &"loot_ember_vault_domain"
const EMBER_TIER := 1
## The three bosses of the ember band, in authored order.
const WARDEN := &"loot_ember_vault_warden"
const HOUND := &"loot_ember_vault_cinder_hound"
const PILGRIM := &"loot_ember_vault_ash_pilgrim"
## A second, ungated domain whose first boss this suite uses as a scratch record. It is
## ungated so a bare delver reaches it, and its boss is the one nothing else reads.
const FLAME_DOMAIN := &"flame_valley"
const FLAME_TIER := 1
const FLAME_DRAGON := &"flame_dragon"
const SEED := 20260902
## A fixed player bundle, so two profiles can be compared through one resolve.
const PLAYER_GUARD := {"defense": 18.0, "damage_reduction": 0.0, "evasion": 0.0}
const PLAYER_OFFENSE := {"attack": 24.0, "crit_chance": 0.0, "crit_damage": 1.5, "penetration": 0.0}


func _hero(gear: float = 0.0) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor, 24)
	LootApi.attach(actor)
	# Gear defaults to none on purpose. `CombatExchange.exchange` is what reads the profile
	# back here, so this delver has to survive one exchange WITHOUT killing the boss it is
	# inspecting: at +60 flat attack a blow is worth the whole pool, and a one-shot delver
	# would advance the band under the assertions and make a walk miss bosses.
	for id in [
		Stat.ATTACK_PHYSICAL,
		Stat.ATTACK_SPIRITUAL,
		Stat.DEFENSE_PHYSICAL,
		Stat.DEFENSE_SPIRITUAL,
		Stat.PENETRATION,
	]:
		actor.stats.add_modifier(StatModifier.new(id, Stat.Op.FLAT, gear, &"boss_profile_gear"))
	return actor


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


## A delver already facing the ember band's first boss, entered through the facade's own
## entry path rather than by writing `active` into `module_data`: a state the game cannot
## produce would not be the state a player can be in.
func _facing_warden() -> Actor:
	var actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, SEED).get("ok", false)),
		true,
		"the ember vault opens"
	)
	return actor


## A shipped boss's authored record, loaded straight off disk, so this suite reads the real
## content rather than a fixture that could drift away from it.
func _authored(boss_id: StringName) -> BossDef:
	return load("%s%s.tres" % [LootContent.BOSS_DIR, String(boss_id)]) as BossDef


## ## Direction one: the seam is LOADED.
##
## A boss nobody profiled reads as the inert profile — exactly the behaviour that existed
## before `BossDef` grew these fields. Without this half, "the profile is read" could be
## satisfied by a read that always returns zero, and a boss nobody authored would silently
## lose the neutral 1.0 crit multiplier.
func test_a_boss_nobody_profiled_keeps_the_inert_profile() -> void:
	var inert := LootState.boss_profile(&"no_such_boss_anywhere")
	assert_eq(float(inert["crit_chance"]), 0.0, "an unprofiled boss never crits")
	assert_eq(float(inert["crit_damage"]), 1.0, "and its crit multiplier is neutral")
	assert_eq(float(inert["penetration"]), 0.0, "it pierces nothing")
	assert_eq(float(inert["evasion"]), 0.0, "it slips nothing")
	assert_eq(float(inert["damage_reduction"]), 0.0, "and softens nothing")


## ## Direction two: the seam is MEANINGFUL.
##
## The shipped ember bosses are profiled, and a spawned boss fights with the numbers its
## `.tres` declares. A bare actor must therefore NOT already pass: the warden really does
## crit, pierce and soften a blow, where the inert profile does none of those.
func test_the_shipped_bosses_fight_with_the_profile_they_author() -> void:
	var warden := _authored(WARDEN)
	assert_ne(warden, null, "the warden's BossDef loads")
	assert_eq(float(warden.crit_chance) > 0.0, true, "the warden is authored to crit")
	assert_eq(float(warden.penetration) > 0.0, true, "and to pierce")
	assert_eq(float(warden.damage_reduction) > 0.0, true, "and to soften a blow")

	var live := _active(_facing_warden())
	assert_almost_eq(
		float(live["crit_chance"]),
		float(warden.crit_chance),
		"the frozen crit chance is the authored one"
	)
	assert_almost_eq(
		float(live["crit_damage"]), float(warden.crit_damage), "and so is the crit multiplier"
	)
	assert_almost_eq(float(live["penetration"]), float(warden.penetration), "and the pierce")
	assert_almost_eq(float(live["evasion"]), float(warden.evasion), "and the evasion")
	assert_almost_eq(
		float(live["damage_reduction"]), float(warden.damage_reduction), "and the damage reduction"
	)


## The three bosses of the band are genuinely DIFFERENT creatures, read off their own
## records. This is the property the feature exists for: before it, every boss in the
## game exchanged blows through one zero-profile, so this comparison was impossible.
func test_the_three_bosses_of_the_band_are_three_different_fighters() -> void:
	var warden := LootState.boss_profile(WARDEN)
	var hound := LootState.boss_profile(HOUND)
	var pilgrim := LootState.boss_profile(PILGRIM)
	assert_eq(
		float(warden["crit_chance"]) != float(hound["crit_chance"]),
		true,
		"the hound crits harder than the warden"
	)
	assert_eq(float(hound["evasion"]) > 0.0, true, "the hound slips blows")
	assert_eq(float(warden["evasion"]), 0.0, "the warden does not")
	assert_eq(float(pilgrim["evasion"]) > 0.0, true, "the pilgrim slips blows hardest")
	assert_eq(float(pilgrim["crit_chance"]), 0.0, "and never crits")
	assert_eq(float(pilgrim["damage_reduction"]) > 0.0, true, "while softening every blow")


## The profile is FROZEN into the spawned boss's state. This proves the LOOT half of the
## seam only — that the authored numbers reach `module_data`. The half that matters, that
## the FIGHT spends them, is proved below by reading what a real exchange did.
func test_the_authored_profile_is_frozen_into_the_spawned_boss() -> void:
	var warden := _authored(WARDEN)
	assert_ne(warden, null, "the warden's BossDef loads")
	assert_eq(float(warden.crit_chance) > 0.0, true, "the warden is authored to crit")
	assert_eq(float(warden.penetration) > 0.0, true, "and to pierce")
	assert_eq(float(warden.damage_reduction) > 0.0, true, "and to soften a blow")

	var live := _active(_facing_warden())
	for field in LootContent.PROFILE_FIELDS:
		assert_almost_eq(
			float(live[field]), float(warden.get(field)), "%s is frozen in as authored" % field
		)


## One real exchange against `boss_id`, on a freshly entered run. Returns what the exchange
## reports about what it DID — never `reported["boss"]`, which is loot's own projection of
## the boss and would read the same whether or not the combat module ever spent the profile.
##
## A fresh actor per seed is deliberate: an exchange spends the boss's pool AND the player's,
## so walking many seeds on one actor would end in a defeat and then prove nothing for the
## remaining seeds.
func _exchange_against(boss_id: StringName, seed_value: int) -> Dictionary:
	var actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(actor, EMBER_DOMAIN, EMBER_TIER, seed_value).get("ok", false)),
		true,
		"the ember vault opens"
	)
	# A band hosts several bosses and spawns them in authored order, so a run has to be
	# walked to the one under test. Bounded by the band's own boss count: a band that grew a
	# boss nobody kills ends the walk by refusing to advance, never by spinning (AGENTS.md,
	# the runaway rule).
	var order := _band_boss_order()
	var guard := 0
	while String(_active(actor).get("boss_id", "")) != String(boss_id) and guard <= order.size():
		guard += 1
		if not bool(_active(actor).get("in_domain", false)):
			break
		LootApi.strike(actor, float(_active(actor).get("vitality_max", 1.0)) * 10.0, seed_value)
	assert_eq(
		String(_active(actor).get("boss_id", "")), String(boss_id), "facing the boss under test"
	)
	return CombatExchange.exchange(actor, seed_value)


## The ember band's boss order, read from the authored encounter.
func _band_boss_order() -> Array[StringName]:
	var encounter := LootContent.instance().encounter_for_domain(EMBER_DOMAIN)
	return [] if encounter == null else encounter.boss_ids


## What the fight SPENT, gathered across a fixed set of seeds. Bounded by `seeds`, never by
## "until something happens", so a boss that never evades fails the test instead of hanging
## it (AGENTS.md, the runaway rule).
func _spend_over(boss_id: StringName, seeds: int) -> Dictionary:
	var evaded := 0
	var shares: Array[float] = []
	var mitigations: Array[float] = []
	for seed_value in range(1, seeds + 1):
		var exchange := _exchange_against(boss_id, seed_value)
		if bool(exchange.get("evaded", false)):
			evaded += 1
		shares.append(float(exchange.get("share_taken", 0.0)))
		mitigations.append(float(exchange.get("mitigation", 0.0)))
	var distinct := {}
	for value in shares:
		distinct["%.6f" % value] = true
	return {
		"evaded": evaded,
		"shares": shares,
		"distinct_shares": distinct.size(),
		"mitigation": mitigations[0] if not mitigations.is_empty() else 0.0,
	}


## ## The fight spends the boss's OFFENCE: it crits.
##
## Read from `share_taken` — what the exchange actually took off the player's pool — and
## never from a projection. A boss that cannot crit returns exactly ONE distinct value
## across a fixed seed set; the warden's crit chance and multiplier produce several, and
## the heaviest is the ordinary share multiplied by the authored `crit_damage`.
func test_the_fight_spends_the_bosss_authored_crit() -> void:
	var spent := _spend_over(WARDEN, 60)
	var shares: Array[float] = spent["shares"]
	assert_eq(shares.is_empty(), false, "the boss answered at least once")
	assert_eq(
		int(spent["distinct_shares"]) > 1,
		true,
		"the warden's answer is not one fixed number, which is what a crit is"
	)
	var ordinary := INF
	var heaviest := 0.0
	for value in shares:
		ordinary = minf(ordinary, value)
		heaviest = maxf(heaviest, value)
	assert_almost_eq(
		heaviest / ordinary,
		float(_authored(WARDEN).crit_damage),
		"and the heaviest answer is exactly the authored crit multiplier times the ordinary one"
	)


## ## The fight spends the boss's EVASION — and only where it is authored.
##
## Both directions, because they fail independently: a boss authored to slip blows does so
## across the seed set, and a boss authored not to never slips one across the same seeds. A
## test that only asserted the first would also pass if EVERY boss evaded.
func test_the_fight_spends_the_bosss_authored_evasion_in_both_directions() -> void:
	var slippery := _spend_over(PILGRIM, 60)
	var armoured := _spend_over(WARDEN, 60)
	assert_eq(
		float(_authored(PILGRIM).evasion) > 0.0, true, "the pilgrim is authored to slip blows"
	)
	assert_eq(
		int(slippery["evaded"]) > 0,
		true,
		"and it slipped at least one blow the delver threw across 60 seeded exchanges"
	)
	assert_eq(float(_authored(WARDEN).evasion), 0.0, "while the warden is authored not to")
	assert_eq(
		int(armoured["evaded"]),
		0,
		"so it slipped none of the delver's blows across the very same 60 exchanges"
	)


## What the PLAYER's blow must meet on `boss_id`.
##
## `_mitigation` takes the DEFENDER's bundle and the ATTACKER's, so a player's blow meets
## the boss's armor ratio plus the boss's authored flat damage reduction, less whatever the
## player's OWN penetration cuts. The boss's pierce plays no part here — it belongs to the
## boss's own answer. Built from the model and the content rather than hardcoded, so a
## retune of either the band or the authored profile moves this expectation with it.
func _player_mitigation_against(
	boss_id: StringName, domain_id: StringName, tier_index: int
) -> float:
	var armor := _band_armor_for(boss_id, domain_id, tier_index)
	var reduction := float(_authored(boss_id).damage_reduction)
	var pierce := float(CombatExchange.offense(_hero()).get("penetration", 0.0))
	var cut := 0.0
	if pierce > 0.0:
		cut = (
			pierce / (pierce + CombatDamage.REFERENCE_PENETRATION) * CombatDamage.PENETRATION_SHARE
		)
	return armor / (armor + CombatDamage.REFERENCE_DEFENSE) + reduction - cut


## ## The fight spends the boss's authored DEFENSE: its flat damage reduction.
##
## Read from what the exchange actually subtracted, so this proves the arithmetic moved
## rather than that a field was carried. Asserted against the model and the authored figure,
## so a boss that reverted to the inert profile would fail by exactly the reduction it lost.
func test_the_players_blow_meets_the_bosss_authored_damage_reduction() -> void:
	var warden := _authored(WARDEN)
	assert_eq(float(warden.damage_reduction) > 0.0, true, "the warden is authored to soften a blow")
	var meet := float(CombatExchange.exchange(_facing_warden(), 5).get("mitigation", -1.0))
	assert_almost_eq(
		meet,
		_player_mitigation_against(WARDEN, EMBER_DOMAIN, EMBER_TIER),
		"the blow met the warden's armor plus exactly its authored reduction"
	)
	# The dragon authors none, so the same delver's blow meets strictly less there. Two
	# creatures, two authored answers, one model — which is the whole point.
	var dragon_actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(dragon_actor, FLAME_DOMAIN, FLAME_TIER, 5).get("ok", false)),
		true,
		"the flame valley opens"
	)
	var bare_meet := float(CombatExchange.exchange(dragon_actor, 5).get("mitigation", -1.0))
	assert_almost_eq(
		bare_meet,
		_player_mitigation_against(FLAME_DRAGON, FLAME_DOMAIN, FLAME_TIER),
		"and met exactly the dragon's armor with no reduction authored"
	)
	assert_eq(meet > 0.0, true, "while the blow still landed rather than being fully absorbed")


## The armor the authored band prices for `boss_id`, read from the encounter the same way
## the spawn did, so this suite does not restate ADR 0076's constant.
func _band_armor_for(boss_id: StringName, domain_id: StringName, tier_index: int) -> float:
	var encounter := LootContent.instance().encounter_for_domain(domain_id)
	if encounter == null:
		return 0.0
	var tier := encounter.tier_at(tier_index)
	return 0.0 if tier == null else tier.defense_for(boss_id)


## The profile CHANGES the arithmetic. This separates "a field that is read" from "a field
## that does something": the same bundle is resolved against the warden's real profile and
## against the inert one across a fixed set of rolls, and the answers must differ.
func test_the_authored_profile_changes_the_damage_the_boss_deals() -> void:
	# `boss_profile` is the boss's identity; its `attack` is priced off the band
	# (ADR 0076). The bundle under test therefore takes each from where it is authored.
	var faced := _active(_facing_warden())
	var authored := LootState.boss_profile(WARDEN)
	var offense := authored.duplicate()
	offense["attack"] = float(faced["attack"])
	var bare := {
		"attack": float(faced["attack"]), "crit_chance": 0.0, "crit_damage": 1.0, "penetration": 0.0
	}
	var authored_total := 0.0
	var bare_total := 0.0
	var authored_crits := 0
	for seed_value in range(1, 201):
		var one := RandomNumberGenerator.new()
		one.seed = seed_value
		var landed := CombatDamage.resolve_hit(offense, PLAYER_GUARD, one)
		var two := RandomNumberGenerator.new()
		two.seed = seed_value
		var inert := CombatDamage.resolve_hit(bare, PLAYER_GUARD, two)
		authored_total += float(landed["share"])
		bare_total += float(inert["share"])
		if bool(landed["crit"]):
			authored_crits += 1
		assert_eq(bool(inert["crit"]), false, "the inert profile never crits, roll %d" % seed_value)
	assert_eq(authored_total > bare_total, true, "the profiled boss lands more over 200 rolls")
	assert_eq(authored_crits > 0, true, "and it actually crits, which no boss could before")

	# Pierce is a separate effect from crit: on one fixed roll the crit verdict matches and
	# the difference is entirely in the mitigation the pierce removed.
	var three := RandomNumberGenerator.new()
	three.seed = 7
	var pierced := CombatDamage.resolve_hit(offense, PLAYER_GUARD, three)
	var four := RandomNumberGenerator.new()
	four.seed = 7
	var unpierced := CombatDamage.resolve_hit(bare, PLAYER_GUARD, four)
	assert_eq(bool(pierced["crit"]), bool(unpierced["crit"]), "crit is decided by the same roll")
	var pierce := float(offense["penetration"])
	assert_almost_eq(
		float(pierced["mitigation"]),
		(
			float(unpierced["mitigation"])
			- (
				pierce
				/ (pierce + CombatDamage.REFERENCE_PENETRATION)
				* CombatDamage.PENETRATION_SHARE
			)
		),
		"and the authored pierce is the difference in mitigation"
	)


## The authored defense changes what a blow meets, so a soft boss and an armoured one are
## different creatures rather than the same pool. Both directions: more damage reduction
## removes more, on one identical roll.
func test_the_authored_defense_changes_what_a_blow_meets() -> void:
	var one := RandomNumberGenerator.new()
	one.seed = 11
	var soft := CombatDamage.resolve_hit(
		PLAYER_OFFENSE, {"defense": 25.0, "damage_reduction": 0.0, "evasion": 0.0}, one
	)
	var two := RandomNumberGenerator.new()
	two.seed = 11
	var hard := CombatDamage.resolve_hit(
		PLAYER_OFFENSE, {"defense": 25.0, "damage_reduction": 0.3, "evasion": 0.0}, two
	)
	assert_eq(
		bool(soft["evaded"]), bool(hard["evaded"]), "the same roll decides evasion either way"
	)
	assert_eq(
		float(hard["share"]) < float(soft["share"]),
		true,
		"the authored reduction removes more of the blow"
	)


## The profile is FROZEN with the boss, not re-read per exchange: a run in flight must not
## change terms because a content file was edited under it — the ADR 0076 rule, applied to
## the new fields. Observed through live exchanges, not through the state dictionary.
##
## The record it corrupts is `flame_dragon`, not an ember boss, and that is deliberate:
## `LootContent`'s index is a process-wide singleton and suites run ALPHABETICALLY, so an
## edit made here outlives this suite and would otherwise turn some later suite's failure
## into this one's. A boss nothing else reads keeps that from being someone else's problem.
func test_the_profile_is_frozen_with_the_boss_not_re_read_per_exchange() -> void:
	var actor := _hero()
	assert_eq(
		bool(LootApi.enter_domain(actor, FLAME_DOMAIN, FLAME_TIER, SEED).get("ok", false)),
		true,
		"the flame valley opens"
	)
	assert_eq(String(_active(actor).get("boss_id", "")), String(FLAME_DRAGON), "facing the dragon")
	# What the FIGHT did, at a FIXED seed so the only variable left is the profile: the share
	# the dragon's answer took off the delver's pool. The dragon authors no pierce, so this
	# is the ordinary figure before the edit and a strictly heavier one after it. Both the
	# roll and the encounter id are functions of the seed alone, so any difference here is the
	# profile and nothing else — which is what makes "frozen" a claim about arithmetic rather
	# than about a field being carried.
	var before := float(CombatExchange.exchange(actor, 5).get("share_taken", -1.0))
	assert_eq(before > 0.0, true, "the dragon answered and took something")

	# Corrupt the authored record. A frozen fight must not notice — and a boss spawned AFTER
	# the edit must carry the new numbers, so "frozen" cannot quietly mean "never updated".
	(
		LootContent
		. instance()
		. provide_boss(
			FLAME_DRAGON,
			{
				"found": true,
				"id": String(FLAME_DRAGON),
				"domain_id": "",
				"boss_ids": [],
				"loot": [],
				"profile": {"crit_chance": 0.42, "crit_damage": 9.0, "penetration": 1.5},
			}
		)
	)
	assert_almost_eq(
		float(LootState.boss_profile(FLAME_DRAGON)["crit_chance"]),
		0.42,
		"the content index took the edit"
	)
	assert_almost_eq(
		float(CombatExchange.exchange(actor, 5).get("share_taken", -1.0)),
		before,
		"the in-flight dragon still answers exactly as it was priced"
	)

	var fresh := _hero()
	assert_eq(
		bool(LootApi.enter_domain(fresh, FLAME_DOMAIN, FLAME_TIER, 5).get("ok", false)),
		true,
		"the flame valley opens again"
	)
	assert_eq(
		float(CombatExchange.exchange(fresh, 5).get("share_taken", -1.0)) > before,
		true,
		"and a dragon spawned after the edit answers harder, so the freeze is per run"
	)
	assert_almost_eq(float(_active(fresh)["crit_chance"]), 0.42, "carrying the new crit chance")
	assert_almost_eq(float(_active(fresh)["crit_damage"]), 9.0, "and the new multiplier")
	# An unauthored field keeps its inert default rather than reading as zero, so a partial
	# profile is a partial profile and not a bundle of nulls.
	assert_eq(
		float(_active(fresh)["evasion"]), 0.0, "and a field the record omits stays at its default"
	)


## Bad content cannot make a fight unwinnable or unlosable. Every profile number is bounded
## at the read, so an absurd authored value is brought into range rather than poisoning the
## model — and, critically, an exchange against it still terminates on a bounded share.
func test_an_absurd_authored_profile_is_clamped_into_the_model_s_range() -> void:
	(
		LootContent
		. instance()
		. provide_boss(
			&"probe_absurd_profile_boss",
			{
				"found": true,
				"id": "probe_absurd_profile_boss",
				"domain_id": "",
				"boss_ids": [],
				"loot": [],
				"profile":
				{
					"crit_chance": 12.0,
					"crit_damage": -5.0,
					"penetration": -3.0,
					"evasion": 4.0,
					"damage_reduction": 9.0,
				},
			}
		)
	)
	var profile := LootState.boss_profile(&"probe_absurd_profile_boss")
	assert_eq(float(profile["crit_chance"]), 1.0, "a crit chance above one is clamped to one")
	assert_eq(float(profile["evasion"]), 1.0, "an evasion above one is clamped to one")
	assert_eq(float(profile["damage_reduction"]), 1.0, "so is a damage reduction above one")
	assert_eq(float(profile["crit_damage"]), 0.0, "a negative crit multiplier is held at zero")
	assert_eq(float(profile["penetration"]), 0.0, "and a negative pierce at zero")

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hit := (
		CombatDamage
		. resolve_hit(
			{
				"attack": 25.0,
				"crit_chance": 1.0,
				"crit_damage": 0.0,
				"penetration": 0.0,
			},
			PLAYER_GUARD,
			rng
		)
	)
	assert_eq(
		float(hit["share"]) >= CombatDamage.MIN_SHARE, true, "an exchange still spends something"
	)
	assert_eq(float(hit["share"]) <= 1.0, true, "and never more than the whole pool")


## Persistence: the profile is part of the spawned boss, so it survives a save/load like
## vitality does. A resumed fight is the fight the boss was priced as — the whole point of
## freezing it (ADR 0076).
func test_the_profile_survives_a_save_and_load() -> void:
	var actor := _facing_warden()
	var before := _active(actor)
	var restored = JSON.parse_string(JSON.stringify(actor.to_dict()))
	var loaded := Actor.from_dict(restored as Dictionary)
	LootApi.attach(loaded)
	var after := _active(loaded)
	for field in LootContent.PROFILE_FIELDS:
		assert_almost_eq(
			float(after.get(field, -1.0)),
			float(before[field]),
			"%s survives the round trip" % field
		)
	# And the resumed FIGHT really does spend it rather than falling back to a default. Read
	# from what the exchange subtracted, not from a projection: a reloaded boss that quietly
	# reverted to the inert profile would still project its own stored numbers correctly, and
	# would meet the blow without the authored reduction it just stored.
	assert_almost_eq(
		float(CombatExchange.exchange(loaded, 8).get("mitigation", -1.0)),
		_player_mitigation_against(WARDEN, EMBER_DOMAIN, EMBER_TIER),
		"the reloaded fight still meets the authored damage reduction"
	)
	assert_eq(
		int(_spend_over(WARDEN, 60)["distinct_shares"]) > 1,
		true,
		"and the warden's answer still crits, which the inert profile cannot do"
	)
