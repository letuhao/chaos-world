extends TestCase

## Balance invariants for the body ladder's authored seed data.
##
## These are the properties a realm seed must hold for the ladder to be playable,
## asserted against the runtime rather than against the generator's recipe. `tools
## cultivation validate` asserts the same properties against the `.tres` text; this
## file asserts them against `BodyRealmSeed` as the game actually reads it, so a
## guard that passes on the file but not in play still fails.
##
## What is NOT here: any assertion about which formula produced a number. The ladder
## is authored data (ADR 0050), so a retune is legitimate and these must survive it.
## What IS here is the shape — a gate that can be failed, a floor that has to be
## earned, a band that training can move, and a budget that exists once.

# --- The quality gate is a gate ---------------------------------------------


## The acupoint quality floor must sit ABOVE what a fresh acupoint already carries.
## `AcupointDefaults.from_definition` builds every acupoint at 0.5, so a floor at or
## under that is passed by an actor that has done nothing at all. The shipped ladder
## ran 0.400-0.490 across R1-R8 and made the first eight breakthroughs a formality.
func test_quality_gate_is_above_the_quality_a_fresh_acupoint_carries() -> void:
	var fresh := AcupointDefaults.from_definition(AcupointDefaults.definitions()[0]).quality
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.quality_required > fresh,
			true,
			(
				"quality gate %.3f must exceed the fresh-acupoint quality %.3f at %s"
				% [seed.quality_required, fresh, realm.id]
			)
		)


## The gate must be reachable: `BodyTraining.cultivate` refines quality toward the
## CURRENT realm's `quality_target` and no further, so a floor above the realm below's
## ceiling is a realm no public action can enter. This is the check ADR 0028 was
## written for and it must never be traded away for the invariant above.
func test_quality_gate_is_reachable_from_the_realm_below() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in range(1, realms.size()):
		var target := BodyRealmSeed.for_realm(realms[index].id)
		var source := BodyRealmSeed.for_realm(realms[index - 1].id)
		if target == null or source == null:
			continue
		assert_eq(
			target.quality_required <= source.quality_target,
			true,
			(
				"gate %.3f for %s exceeds the ceiling %.3f training can reach in %s"
				% [
					target.quality_required,
					realms[index].id,
					source.quality_target,
					realms[index - 1].id
				]
			)
		)


## And there must be HEADROOM between them, not just reachability. The gap is the span
## of acupoint quality an actor can choose to hold at the moment of the attempt: the gate
## is what `_acupoints_ready` demands, the ceiling is what `cultivate` will not exceed,
## and everything between is what the breakthrough roll is pricing. Pinning the gate
## onto the ceiling pins that span to zero, so average acupoint quality at the moment of
## an attempt is one number and training the body cannot change the outcome.
func test_quality_gate_leaves_headroom_below_the_previous_ceiling() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in range(1, realms.size()):
		var target := BodyRealmSeed.for_realm(realms[index].id)
		var source := BodyRealmSeed.for_realm(realms[index - 1].id)
		if target == null or source == null:
			continue
		assert_eq(
			target.quality_required < source.quality_target,
			true,
			(
				"no acupoint quality span to price at %s: gate %.3f is not below the %.3f ceiling"
				% [realms[index].id, target.quality_required, source.quality_target]
			)
		)


## The ceiling itself must rise with depth and stay a RATIO inside (0, 1]. It is the
## cap `cultivate` refines toward, so a ceiling at or below the fresh 0.5 would pin
## quality there forever and make the whole acupoint axis inert.
func test_quality_ceiling_rises_and_stays_a_ratio() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(seed.quality_target > previous, true, "ceiling rises at %s" % realm.id)
		assert_eq(
			seed.quality_target > 0.0 and seed.quality_target <= 1.0,
			true,
			"ceiling %.3f stays inside (0, 1] at %s" % [seed.quality_target, realm.id]
		)
		assert_eq(
			seed.quality_target > seed.quality_required,
			true,
			"ceiling sits above its own gate at %s" % realm.id
		)
		previous = seed.quality_target


# --- The chance band is a band ----------------------------------------------


## Every realm must offer a range of outcomes that acupoint training can move within.
## `BodyAdvancement._chance` clamps to `chance_cap`, so a floor at or above the
## ceiling swallows the acupoint term entirely — the shipped ladder crossed at R26 and
## five realms had `chance_base >= chance_cap`.
func test_chance_floor_is_below_the_chance_ceiling() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.chance_base < seed.chance_cap,
			true,
			(
				"chance floor %.3f must sit below the ceiling %.3f at %s"
				% [seed.chance_base, seed.chance_cap, realm.id]
			)
		)


## The stronger form, and the one that actually matters: the band must be live across
## every acupoint quality an actor can HOLD while attempting this realm. That span is
## `quality_required` (what `_acupoints_ready` demands) to the previous realm's
## `quality_target` (what `cultivate` will not exceed). A zero-width span means the
## two authored numbers can each look reasonable and still price nothing.
func test_every_realm_leaves_a_chance_band_huyet_training_can_move() -> void:
	var realms := RealmDefaults.ladder().realms()
	for index in range(realms.size()):
		var seed := BodyRealmSeed.for_realm(realms[index].id)
		if seed == null:
			continue
		var ceiling := seed.quality_target
		if index > 0:
			var source := BodyRealmSeed.for_realm(realms[index - 1].id)
			if source != null:
				ceiling = source.quality_target
		var floor := minf(
			seed.chance_base + seed.quality_required * BodyAdvancement.QUALITY_TO_CHANCE,
			seed.chance_cap
		)
		var best := minf(
			seed.chance_base + ceiling * BodyAdvancement.QUALITY_TO_CHANCE, seed.chance_cap
		)
		assert_eq(
			best - floor > 0.001,
			true,
			(
				"%s offers a zero-width band %.4f-%.4f across quality %.3f-%.3f"
				% [realms[index].id, floor, best, seed.quality_required, ceiling]
			)
		)


## No realm may be a certain success, and risk must never fall to zero. A ceiling at
## or above 1.0 retires the deviation and recovery system at that realm.
func test_no_realm_is_a_guaranteed_success() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.chance_cap < 1.0,
			true,
			"ceiling %.3f is a certainty at %s" % [seed.chance_cap, realm.id]
		)
		assert_eq(
			seed.chance_base >= BodyAdvancement.MIN_CHANCE,
			true,
			"floor %.3f is under the clamp at %s" % [seed.chance_base, realm.id]
		)


# --- The budget exists once --------------------------------------------------


## `work_required` is derived from `progress_required`, not authored beside it. They
## were byte-identical in all 30 seeds, so the first edit to one silently desynced the
## gate `BodyBreakthroughCondition` enforces from the price the balance report reads.
func test_work_requirement_is_the_progress_requirement() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_almost_eq(seed.work_required, seed.progress_required, "one budget for %s" % realm.id)
		assert_eq(seed.progress_required > 0.0, true, "budget is positive at %s" % realm.id)


## The two sub-budgets cut the same budget against the acupoint and channel counts, so
## they can only be a share of it. They are derived for that reason; this asserts the
## derivation is the one the ladder expects rather than a stale authored number.
func test_sub_budgets_are_cuts_of_the_budget() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.acupoint_work <= seed.progress_required,
			true,
			"acupoint budget is a share of the budget at %s" % realm.id
		)
		assert_eq(
			seed.meridian_work <= seed.progress_required,
			true,
			"channel budget is a share of the budget at %s" % realm.id
		)
		assert_eq(
			seed.acupoint_work >= 1.0 and seed.meridian_work >= 1.0,
			true,
			"a share of the budget is still work at %s" % realm.id
		)


## The budget rises strictly with depth. Every later realm must cost more labour than
## the one before, or the deep realms become free.
func test_budget_rises_with_depth() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(seed.progress_required > previous, true, "budget rises at %s" % realm.id)
		previous = seed.progress_required


# --- The physique floor has to be earned ------------------------------------


## The physique floor must sit ABOVE what the ladder grants for itself. The only
## writers of base PHYSIQUE are `BodyProgress.grant` (the once-only milestone bonus,
## scaled by `BodyProgress.MILESTONE_PHYSIQUE_RATIO`) and the seed's own `rewards`, so
## arrival physique is fully determined by the ladder. A floor under that grant can
## never be unmet, which is how 26 of 30 shipped floors came to be dead.
func test_physique_floor_exceeds_what_the_ladder_grants_for_free() -> void:
	var granted := 0.0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.physique_required > granted,
			true,
			(
				"physique floor %.2f is not above the %.2f the ladder grants on arrival at %s"
				% [seed.physique_required, granted, realm.id]
			)
		)
		granted += float(seed.rewards.get("physique", 0.0))
		granted += seed.integrity_maximum * BodyProgress.MILESTONE_PHYSIQUE_RATIO


## The floor rises with depth, and the ladder's own grant rises faster than the rate
## could — so a constant floor would go dead further up. This asserts the floor tracks
## the grant rather than assuming the ladder's shape.
func test_physique_floor_rises_with_depth() -> void:
	var previous := 0.0
	for realm in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(seed.physique_required > previous, true, "physique floor rises at %s" % realm.id)
		previous = seed.physique_required


# --- Reachability of the whole ladder ----------------------------------------


## The reason the four invariants above exist in this order: each of them must be
## satisfiable at once. A gate above the ceiling is unreachable; a gate below the fresh
## quality is free; both at once would be a contradiction no data can satisfy, which is
## how a retune that satisfies one rule and breaks another gets caught.
func test_the_whole_ladder_is_reachable_and_no_gate_is_free() -> void:
	var fresh := AcupointDefaults.from_definition(AcupointDefaults.definitions()[0]).quality
	var granted := 0.0
	var realms := RealmDefaults.ladder().realms()
	for index in range(realms.size()):
		var seed := BodyRealmSeed.for_realm(realms[index].id)
		if seed == null:
			continue
		var ceiling := seed.quality_target
		if index > 0:
			var source := BodyRealmSeed.for_realm(realms[index - 1].id)
			if source != null:
				ceiling = source.quality_target
		assert_eq(
			fresh < seed.quality_required and seed.quality_required <= ceiling,
			true,
			(
				"%s is either free (%.3f vs fresh %.3f) or unreachable (above %.3f)"
				% [realms[index].id, seed.quality_required, fresh, ceiling]
			)
		)
		assert_eq(
			seed.physique_required > granted,
			true,
			(
				"%s physique floor %.2f is under the %.2f already granted"
				% [realms[index].id, seed.physique_required, granted]
			)
		)
		granted += float(seed.rewards.get("physique", 0.0))
		granted += seed.integrity_maximum * BodyProgress.MILESTONE_PHYSIQUE_RATIO
