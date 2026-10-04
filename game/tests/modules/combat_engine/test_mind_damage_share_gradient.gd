extends TestCase

## ADR 0071's denominator, and the realm gradient it does NOT remove.
##
## ## What is pinned, and what is deliberately NOT
##
## `MindDamage` divides by the defender sea's `structural_capacity`, so the erosion is a
## SHARE of that sea rather than an absolute. That is ADR 0071's decision and it is pinned
## here as the identity it is: `erosion == mental_attack * share / capacity`.
##
## What this file exists for is the CONSEQUENCE nobody ruled on. ADR 0071 justified that
## denominator by claiming "one full strike" is "the same SHARE of that sea at every
## realm". It is not. Measured over the 30 shipped `MindRealmSeed` `.tres`, with
## `MENTAL_ATTACK` carrying only `RealmRate` (`1.02^29 = 1.775845`) against an authored
## capacity ladder of `100.0 -> 825.0` (linear, step 25), the share runs `0.625` at R1 to
## `0.1345` at R30 and falls strictly at every realm: a `4.6457x` decay, exactly
## `cap_span / rate_span`.
##
## ## The `1.775845` here is MIND'S RATE, and NOT the technique ladder
##
## That figure is `RealmRate`, the TRAINING rate, and it reaches `MENTAL_ATTACK` through
## `MindProvider` alone. This file reads `MindDamage.breakdown`, which never touches
## `CombatSpine.base_damage`, so the technique path is not in it at all: techniques are
## gated by `TechniqueMagnitudeTable.factor` (ADR 0055, ADR 0182), a SEPARATE ladder that
## reaches `2.7667x` at R30 and replaced the rate at S1. Nothing here should be read as
## pricing a technique, and nothing here changes if that table is retuned — the gradient is
## a ratio of two mind-owned ladders and cancels any third factor.
##
## ## The ruling this file encodes
##
## **The decay is NOT intended, and nothing may quietly ratify it.** The only document that
## justifies the denominator claims the opposite of what the numbers do, so the gradient is
## unowned rather than designed. Fixing it is a `sea_capacity` re-author — a balance
## decision this suite may not make — and explicitly NOT a `RATE_STEP` edit, because the
## rate is bounded by the authored work budget (`core/realm_rate.gd`) and raising it would
## invert qi's deepest breakthrough.
##
## So this file pins the decay's SHAPE and its DERIVATION, never its magnitude:
## - the share falls strictly at every one of the 30 realms (the refutation of the removed
##   invariant claim, and a trip-wire: re-authoring `sea_capacity` to flatten the gradient
##   turns this RED and forces the ruling to be written down);
## - the gradient is EXACTLY `cap_span / rate_span`, which proves no third factor rides in
##   either the numerator or the denominator.
##
## Both endpoints are printed rather than asserted, and no `4.6457` literal appears in the
## body: a test that pins a number nobody has ruled on is how a defect becomes permanent.
## An owner who rules the gradient intended should re-point
## `test_the_share_falls_strictly_at_every_realm` at an invariance assertion and say so in
## a superseding ADR.

## The ladder ends, read off `RealmDefaults.ladder()` so no realm name is a literal here.
const FIRST_INDEX := 0
const LAST_INDEX := 29
## The fixture's authored `share`, so `erosion` reduces to `mental_attack / capacity`.
const SHARE := 1.0
## Relative tolerance. The identity is exact arithmetic on authored floats, so anything
## looser would hide a second factor arriving through one of the two terms.
const REL_EPSILON := 0.000001

var _mind: Variant = preload("res://tests/modules/combat_engine/mind_damage_fixture.gd").new()


func setup() -> void:
	_mind.setup()


## One realm's share, as `MindDamage`'s OWN published primitives: `MENTAL_ATTACK` and the
## `structural_capacity` it divided by, both read off `breakdown()` rather than recomputed,
## so this measures the mechanism's arithmetic and not a restatement of it.
func _share_at(realm_index: int) -> Dictionary:
	var realms := RealmDefaults.ladder().realms()
	var realm_id: StringName = realms[realm_index].id
	var attacker: Actor = _mind._attacker()
	attacker.set_path(PathState.new(PathState.MIND, realm_id))
	var target: Actor = _mind._defender(0.0, 0.0)
	# The AUTHORED capacity for this realm, not the fixture's pinned `SEA_CAPACITY`: the
	# denominator is the thing under test, so measuring a ladder against a constant would
	# measure the fixture. Same shape as `test_cross_mechanism_balance.gd`'s mind row.
	var seed: MindRealmSeed = MindRealmSeed.for_realm(realm_id)
	assert_ne(seed, null, "a MindRealmSeed exists for %s" % String(realm_id))
	var sea: SeaOfConsciousness = _mind._sea_of(target)
	sea.set_structural_capacity(seed.sea_capacity)
	var ctx: AttackContext = _mind._context(MindDamage.Kind.DISRUPT, attacker, target, SHARE)
	var parts: Dictionary = MindDamage.new().breakdown(ctx)
	var attack := float(parts["mental_attack"])
	var capacity := float(parts["structural_capacity"])
	return {
		"realm": String(realm_id),
		"attack": attack,
		"capacity": capacity,
		"share": 0.0 if capacity <= 0.0 else attack / capacity,
		"erosion": float(parts["erosion"]),
		"coherence": float(parts["coherence"]),
		"focused": bool(parts["focused"]),
	}


## The ladder, materialised ONCE. The bound is `realms.size()`, a fixed count read from the
## ladder, and the loop only READS it -- nothing is appended, so this cannot run away.
func _ladder() -> Array[Dictionary]:
	var realms := RealmDefaults.ladder().realms()
	var rows: Array[Dictionary] = []
	for index in range(realms.size()):
		rows.append(_share_at(index))
	return rows


func _span(rows: Array[Dictionary]) -> float:
	return float(rows[LAST_INDEX]["share"]) / float(rows[0]["share"])


func _report(rows: Array[Dictionary]) -> String:
	return (
		"R1 share %s, R30 share %s, decay %sx"
		% [rows[0]["share"], rows[LAST_INDEX]["share"], _span(rows)]
	)


# --- ADR 0071's decision: the erosion is a SHARE -----------------------------


## The pinned decision. `erosion` is exactly `MENTAL_ATTACK * share * coherence * focus /
## structural_capacity`, with an empty AWARENESS reserve and no rng making both the coherence
## and the focus the neutral `1.0`. If the denominator is ever anything else this goes red.
##
## `focused` is asserted as the BOOL the breakdown publishes, not as a multiplier: `focused`
## is `focused > 1.0`, so reading it as a factor would compare `true` against `1.0`. The
## effective focus being `1.0` is what the erosion identity below proves, which is the only
## place worth proving it.
func test_the_erosion_is_the_strike_over_the_seas_own_capacity() -> void:
	var rows := _ladder()
	for row in rows:
		var label: String = "erosion is attack/capacity at %s" % row["realm"]
		assert_almost_eq(
			float(row["coherence"]),
			1.0,
			"an empty awareness reserve reads the neutral coherence at %s" % row["realm"],
			REL_EPSILON
		)
		assert_eq(
			bool(row["focused"]),
			false,
			"a null rng spends no draw and never focuses at %s" % row["realm"]
		)
		assert_almost_eq(
			float(row["erosion"]),
			float(row["attack"]) * SHARE / float(row["capacity"]),
			label,
			REL_EPSILON
		)


## The denominator is the SEA, so a defender's realm moves the erosion and a defender's
## authored capacity is what moves it. Two capacities at one realm, one ratio: this is the
## claim that makes the gradient below a property of the AUTHORED LADDERS rather than of
## this mechanism.
func test_the_denominator_is_the_defenders_own_sea_not_a_constant() -> void:
	var realms := RealmDefaults.ladder().realms()
	var realm_id: StringName = realms[0].id
	var attacker: Actor = _mind._attacker()
	attacker.set_path(PathState.new(PathState.MIND, realm_id))
	var target: Actor = _mind._defender(0.0, 0.0)
	var sea: SeaOfConsciousness = _mind._sea_of(target)
	var ctx: AttackContext = _mind._context(MindDamage.Kind.DISRUPT, attacker, target, SHARE)
	var mechanism := MindDamage.new()
	sea.set_structural_capacity(200.0)
	var wide: float = mechanism.breakdown(ctx)["erosion"]
	sea.set_structural_capacity(100.0)
	var narrow: float = mechanism.breakdown(ctx)["erosion"]
	assert_almost_eq(
		wide * 2.0, narrow, "doubling the sea halves the share a full strike erodes", REL_EPSILON
	)


# --- The gradient, and that it is UNRULED --------------------------------------


## The refutation of the claim this file's docblock used to make. `MENTAL_ATTACK /
## sea_capacity` falls STRICTLY at every one of the 30 realms, so "one full strike" is NOT
## the same share of the sea at every realm — the deep realms take ~4.6x more strikes to
## reach the same turbulence.
##
## The assertion is the DIRECTION, not the magnitude, and that is deliberate. The decay is
## unruled: ADR 0071 claims the share is invariant, these numbers refute it, and nobody has
## said which is right. Pinning `4.6457x` here would make an unowned gradient permanent;
## pinning the direction is a trip-wire in BOTH directions — an owner who re-authors
## `sea_capacity` to flatten the gradient turns this red and has to write the ruling down,
## and an owner who rules the decay intended keeps it green without touching a number.
func test_the_share_falls_strictly_at_every_realm() -> void:
	var rows := _ladder()
	# The bound is the materialised row count, read BEFORE the loop; the loop appends
	# nothing, so this terminates on the ladder's own length.
	for index in range(1, rows.size()):
		var here := float(rows[index]["share"])
		var below := float(rows[index - 1]["share"])
		assert_eq(
			here < below,
			true,
			(
				"the share fell into %s (%s < %s) -- %s"
				% [rows[index]["realm"], here, below, _report(rows)]
			)
		)
	print("mind share gradient: %s" % _report(rows))


## The gradient is EXACTLY `cap_span / rate_span`, which is the whole content of the
## correction: a bounded RATE in the numerator against an authored MAGNITUDE in the
## denominator, and NOTHING ELSE. A hidden third factor -- a realm term on the sea, a second
## multiplier on `MENTAL_ATTACK` -- moves this off `rate_span / cap_span` while leaving every
## monotonicity assertion above still green.
##
## It is also build-independent: it is a relationship between the two authored ladders, so
## it survives any retune of either. What it does NOT say is whether the resulting `4.6457x`
## is wanted. Only an owner can say that.
func test_the_gradient_is_the_rate_over_the_capacity_and_nothing_else() -> void:
	var rows := _ladder()
	var realms := RealmDefaults.ladder().realms()
	var rate_span := (
		RealmRate.factor(realms[LAST_INDEX].id) / RealmRate.factor(realms[FIRST_INDEX].id)
	)
	var cap_span := float(rows[LAST_INDEX]["capacity"]) / float(rows[0]["capacity"])
	assert_almost_eq(
		1.0 / _span(rows),
		cap_span / rate_span,
		(
			"the decay is cap_span/rate_span only (%s; cap_span %s, rate_span %s)"
			% [_report(rows), cap_span, rate_span]
		),
		REL_EPSILON
	)
	# Stated so a retune of either ladder cannot quietly pass by holding the ratio fixed.
	assert_eq(rate_span < 2.0, true, "the rate really is the bounded gain (%s)" % rate_span)
	assert_eq(
		cap_span > rate_span, true, "the capacity really is the steeper ladder (%s)" % cap_span
	)
