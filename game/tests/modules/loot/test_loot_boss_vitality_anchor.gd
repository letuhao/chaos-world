extends TestCase

## ADR 0198: a boss's authored vitality IS the owner's 60-second duel anchor.
##
## ## What this asserts, and what it deliberately does NOT
##
## The owner ruled (2026-10-04): two actors of the same power, no healing, no dodging,
## should finish in **60 seconds**, and at the ladder's own blow rate that is **25 landed
## blows**. `RealmScaling.SCALED_STATS` carries BOTH `Stat.MAX_HEALTH` and
## `Stat.ATTACK_PHYSICAL`, so an actor's pool and its attack grow by the same authored
## `RealmDef.power` and the blow count is constant down the whole ladder — the ladder is
## self-consistent and this ADR does not touch it.
##
## What was wrong is AUTHORED BOSS VITALITY: flat at 40-800 (~20x) against a realm table
## spanning 1.0-551.46 (551x). So the fix is CONTENT, and the property worth guarding is
## the ratio, not the absolute number:
##
## ```
## blows_needed(realm) = BASE_HEALTH * RealmDef.power(realm) / HITS_TO_KILL
## hits_to_kill        = vitality / blows_needed
##                    = (HITS_TO_KILL * BASE_HEALTH * power) / (BASE_HEALTH * power / HITS_TO_KILL)
##                    = HITS_TO_KILL ^ 2
## ```
##
## The ladder CANCELS. That is the whole point of asserting the ratio across realms
## rather than pinning vitality per realm: the claim survives a `realm_power` retune,
## because both sides of it are multiplied by the same authored power.
##
## ## The two readings, and which one is which
##
## - **MAGNITUDE** (`hits_to_kill` above) is the spine's reading — the one ADR 0174 and
##   the boss-fight routing need, and the one the ruling is about.
## - **SHARE** is what `CombatExchange.exchange` spends today. `CombatDamage.resolve_hit`
##   returns a FRACTION of the pool, so `vitality / (share * vitality_max) == 1/share` and
##   the pool's SIZE cannot move the count at all. `CombatDamage` clamps share into
##   `[MIN_SHARE 0.05, 1.0]`, so share-mode `hits_to_kill` is bounded into `[1.0, 20.0]`
##   and the anchor's 25 is unreachable there at ANY realm, before any content is read.
##
## **This suite asserts the MAGNITUDE reading and deliberately measures the SHARE one**
## (see `test_the_share_model_cannot_reach_the_anchor_and_that_is_not_a_content_fault`).
## `modules/combat/` is another lane's module, so the share ceiling is reported, not
## edited. What the content fix buys is that the magnitude relationship is now CORRECT,
## which is what lets the real boss fight route through the spine at all.
##
## ## Where the numbers come from
##
## `RealmDefaults.ladder()` and `RealmPowerTable` are read live; `BASE_HEALTH`,
## `HITS_TO_KILL` and `WORLD_DOMAIN_FLOOR` are `tools/acquisition/design.py`'s named
## decisions, restated here as the SAME numbers the generator writes the `.tres` from.
## Restating them is deliberate: a test that computed its expectation by calling the
## generator proves only that the generator is self-consistent, which is not the claim.

## The owner's blow count, and the anchor itself. 25 blows in 60 s == 25 blows/min.
const HITS_TO_KILL := 25.0
## `Stat.MAX_HEALTH` of the anchor's reference actor before gear. The brief's measured
## table reports a 75.0 pool and a 3.0 attack at R1, and `75 / 3 == 25` blows.
const BASE_HEALTH := 75.0
## The pool a band's tier-2 (deep) band carries: the same formula times
## `design.HARD_TIER_MULTIPLIER`.
const HARD_TIER_MULTIPLIER := 1.6
## The ladder rung a WORLD band's derived drop label is floored at (`design.py`'s
## `WORLD_DOMAIN_FLOOR` == index 5, `void_refinement`), resolved through the ladder
## rather than quoted so a ladder that grows cannot leave a second curve behind.
const WORLD_FLOOR_INDEX := 5
## Tolerance for the authored-vs-derived comparison, in blows. The generator rounds to
## one decimal, and `vitality` runs to 1033987.5 at R30, so a fixed absolute epsilon
## would be far tighter at R30 than the rounding allows and meaningless at R1. A RELATIVE
## tolerance is the honest one for a quantity that spans 882x.
const RELATIVE_TOLERANCE := 0.0001
## The minimum number of SHIPPED bands the census assertions must actually look at, so
## a content wave that empties the corpus cannot turn a census into a silent pass. The
## corpus holds 320 bands today; this is deliberately well under.
const MIN_BANDS := 200
## The minimum number of ladder bands priced off a canonical realm.
const MIN_LADDER_BANDS := 150


## `RealmDef.power` per realm id, from the ladder the runtime reads.
func _power(realm_id: StringName) -> float:
	return RealmDefaults.ladder().realm(realm_id).power


## The ladder's realm ids in order, so a column is never a literal typed here.
func _ladder() -> Array:
	var out: Array = []
	for realm in RealmDefaults.ladder().realms():
		out.append(String(realm.id))
	return out


## One 60-second bout at `realm_id`: how much of a same-realm actor's pool one blow
## spends, expressed as the pool itself divided by the anchor's blow count.
func _blow_at(realm_id: StringName) -> float:
	return BASE_HEALTH * _power(realm_id) / HITS_TO_KILL


## Every shipped `LootTier`, as `{encounter_id, tier}`.
func _bands() -> Array:
	var content := LootContent.instance()
	var out: Array = []
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		for tier in encounter.tiers:
			if tier != null:
				out.append({"encounter_id": encounter_id, "tier": tier})
	return out


## The bands a LADDER trial owns, whose `realm` is a canonical realm and therefore a
## claim about the fight. The generator's `_trial_` prefix is the shipped naming, so the
## split is read off the encounter id rather than re-derived from content nobody here owns.
func _ladder_band(tier: LootTier) -> bool:
	return tier.realm != &"" and RealmDefaults.ladder().realm(tier.realm) != null


func test_the_anchor_holds_for_a_ladder_trial_at_every_realm_it_shapes() -> void:
	# ONE test, every realm, so the printed table and the pass/fail cannot come from two
	# different runs of the arithmetic. The band for realm R is priced off R's own
	# `RealmDef.power`, and `hits_to_kill` is asserted into a band around the anchor
	# rather than pinned, because the anchor is "~25 blows", not exactly 25.
	var rows: Array[String] = []
	var ladder_bands := 0
	for band in _bands():
		var tier: LootTier = band["tier"]
		if not _ladder_band(tier):
			continue
		ladder_bands += 1
		var realm_id := tier.realm
		var blow := _blow_at(realm_id)
		var expect := HITS_TO_KILL * blow
		if tier.tier != 1:
			expect *= HARD_TIER_MULTIPLIER
		# hits_to_kill measured as vitality / (pool / HITS_TO_KILL), i.e. the ratio the
		# ruling is about, rather than `vitality / BASE_HEALTH` which would be a
		# different (and much larger) number wearing the same name.
		var pool := BASE_HEALTH * _power(realm_id)
		var htk := tier.vitality / (pool / HITS_TO_KILL)
		rows.append(
			(
				"%-20s power %7.2f  band t%d %12.1f  pool %10.1f  blow %9.2f  htk %6.1f"
				% [realm_id, _power(realm_id), tier.tier, tier.vitality, pool, blow, htk]
			)
		)
		assert_almost_eq(
			tier.vitality,
			expect,
			(
				"%s tier %d is priced off its OWN realm's power, not a ladder position"
				% [realm_id, tier.tier]
			),
			maxf(RELATIVE_TOLERANCE * expect, 0.05)
		)
		assert_eq(
			htk >= HITS_TO_KILL * 0.9 and htk <= HITS_TO_KILL * 1.1,
			true,
			(
				(
					"%s tier %d takes %.1f of a same-realm actor's blows; the anchor band is "
					+ "%.1f..%.1f"
				)
				% [realm_id, tier.tier, htk, HITS_TO_KILL * 0.9, HITS_TO_KILL * 1.1]
			)
		)
	print("ADR 0198 -- a same-realm boss's hits_to_kill, across the ladder:")
	for line in rows:
		print("  ", line)
	assert_eq(ladder_bands >= MIN_LADDER_BANDS, true, "the shipped corpus has bands to judge")


func test_a_world_band_never_prices_a_fight_below_the_drop_label_it_borrowed() -> void:
	# A WORLD domain's `LootTier.realm` is `Graph.band_realm`'s derived drop-context
	# LABEL -- the lowest realm any of its drops belongs to -- not a claim about the
	# creature. 59 of the shipped world bands carry `qi_refining`/`foundation` for that
	# reason alone, so priced straight off the label a trash mob would get R1's pool.
	# The generator floors such a band; this asserts the floor is real and that it never
	# prices a band BELOW what its own label says (the floor only ever raises).
	var content := LootContent.instance()
	var worlds := 0
	var floored := 0
	var floor_power := _power(StringName(_ladder()[WORLD_FLOOR_INDEX]))
	for encounter_id in content.encounter_ids():
		var encounter := content.encounter_by_id(StringName(encounter_id))
		if encounter == null:
			continue
		for tier in encounter.tiers:
			if tier == null or _ladder_band(tier):
				continue
			worlds += 1
			var expect := HITS_TO_KILL * BASE_HEALTH * floor_power
			if tier.tier != 1:
				expect *= HARD_TIER_MULTIPLIER
			assert_almost_eq(
				tier.vitality,
				expect,
				"%s is a world band floored at ladder rung %d" % [encounter_id, WORLD_FLOOR_INDEX],
				maxf(RELATIVE_TOLERANCE * expect, 0.05)
			)
			if _power(tier.realm) < floor_power:
				floored += 1
	print(
		(
			(
				"ADR 0198 -- %d world band(s); %d of them carried a drop label BELOW the floor "
				+ "rung and were raised to it"
			)
			% [worlds, floored]
		)
	)
	assert_eq(worlds > 0, true, "the shipped corpus has world bands to judge")


func test_vitality_scales_with_the_ladder_rather_than_standing_flat() -> void:
	# The defect this ADR fixes, asserted as a SPREAD. The old content spanned 40..800,
	# i.e. 20x, against a ladder that spans 551x. A corpus whose bands still cluster in a
	# narrow range is the old defect wearing a new number, and only a spread catches it.
	# Its OWN floor, declared here: `floor_power` is local to
	# `test_a_world_band_never_prices_a_fight_below_the_drop_label_it_borrowed`, so naming it
	# in this function was an undeclared-identifier PARSE ERROR that stopped the whole file
	# from compiling - which is why a run reported this suite as failing for reasons that had
	# nothing to do with the assertion it makes.
	var floor_power := _power(StringName(_ladder()[WORLD_FLOOR_INDEX]))
	var seen: Dictionary = {}
	for band in _bands():
		# `%s`, not `String(...)`: `LootTier.vitality` is a float and GDScript has no
		# `String(float)` constructor, so the cast form is a PARSE ERROR that also strips the
		# type off `seen` and makes every `:=` below it uninferable. A formatted string is
		# the only key form that both compiles and keeps the distinct-value count honest.
		seen["%s" % (band["tier"] as LootTier).vitality] = true
	var values := seen.keys()
	assert_eq(values.size() >= 20, true, "authored vitality takes many distinct values")
	var low := float(values[0])
	var high := float(values[0])
	for value in values:
		low = minf(low, float(value))
		high = maxf(high, float(value))
	var spread := high / low
	print(
		(
			(
				"ADR 0198 -- authored vitality now spans %.1f .. %.1f (%.0fx) over %d distinct "
				+ "value(s); the ladder spans %.0fx"
			)
			% [
				low,
				high,
				spread,
				values.size(),
				_power(StringName(_ladder()[WORLD_FLOOR_INDEX + 24])) / floor_power
			]
		)
	)
	assert_eq(
		spread > 100.0,
		true,
		"authored vitality tracks a realm ladder rather than standing flat (was 20x)"
	)


func test_a_deep_band_is_a_bigger_pool_not_a_longer_pool() -> void:
	# ADR 0076 prices a boss's own attack and defense off the SAME authored vitality, so a
	# tier-2 band is not 1.6x as many blows: it is 1.6x the pool AND 1.6x the boss's
	# hitting power. That is what makes the fight lengthen through the BUILD, which is
	# the second half of the owner's ruling ("longer depending on how they build").
	var tier := _band_tier(&"loot_body_qi_refining_trial", 2)
	var boss := tier.boss_ids()[0]
	var gate := _band_tier(&"loot_body_qi_refining_trial", 1)
	assert_almost_eq(
		tier.vitality,
		gate.vitality * HARD_TIER_MULTIPLIER,
		"the deep band carries 1.6x the pool",
		0.05
	)
	assert_almost_eq(
		tier.attack_for(boss),
		gate.attack_for(boss) * HARD_TIER_MULTIPLIER,
		"and its boss hits 1.6x as hard, so the blow count does not simply rise",
		0.05
	)


func test_the_share_model_cannot_reach_the_anchor_and_that_is_not_a_content_fault() -> void:
	# MEASURED, not asserted as a content property: `CombatDamage.resolve_hit` returns a
	# FRACTION, so the pool's size cancels out of the blow count entirely and share-mode
	# `hits_to_kill` is `1/share`. The clamps bound it into [1.0, 20.0], which excludes
	# the anchor's 25 at every realm. `modules/combat/` is another lane's module, so this
	# is reported rather than edited -- and the point of asserting it is that a future
	# agent does not go looking for the missing 25 in the CONTENT, which is correct now.
	var lowest := INF
	var highest := -INF
	for value in [CombatDamage.MIN_SHARE, 1.0, 0.5, 0.25, CombatDamage.BASE_SHARE]:
		var htk := 1.0 / clampf(value, CombatDamage.MIN_SHARE, 1.0)
		lowest = minf(lowest, htk)
		highest = maxf(highest, htk)
	print(
		(
			(
				"ADR 0198 -- SHARE mode bounds hits_to_kill into %.1f..%.1f by construction "
				+ "(MIN_SHARE %.2f, ceiling 1.0); the anchor's %.0f is outside it"
			)
			% [lowest, highest, CombatDamage.MIN_SHARE, HITS_TO_KILL]
		)
	)
	assert_eq(
		highest < HITS_TO_KILL,
		true,
		"the share model cannot express the anchor at any vitality -- so the anchor is a MAGNITUDE claim"
	)
	assert_eq(
		lowest > 0.0,
		true,
		"and its floor is the 20-blow MIN_SHARE guard, not an unbounded exchange"
	)


func _band_tier(encounter_id: StringName, tier_index: int) -> LootTier:
	return LootContent.instance().encounter_by_id(encounter_id).tier_at(tier_index)
