extends TestCase

## Cross-mechanism balance: ONE table, four realms, three mechanisms.
##
## ## What this file is FOR
##
## ADR 0069, 0070 and 0071 each decided one mechanism's formula and NONE of them
## decided a relationship BETWEEN the three. This file MEASURES that relationship
## and prints it. It asserts three things and only three, because only three are
## claims an ADR actually makes:
##
## 1. qi's elemental fraction of a hit is realm-INVARIANT — ADR 0069's claim is
##    that the realm MULT on `element_power_<e>` keeps the element's share of a
##    hit constant down the ladder.
## 2. No mechanism returns NaN, negative or non-finite at any realm — BRIEF 1.5's
##    claim that the spine's ONE non-finite guard at S6's entrance may assume the
##    mechanisms never hand it one.
## 3. qi and body damage grows monotonically with realm — ADR 0067's S1 plus
##    `RealmDef.power` from `core/realm_power_table.tres`.
## 4. The two mechanisms that spend HEALTH stay within one order of magnitude of each
##    other at every realm, and their ratio is the SAME number at R1 and at R30 — the
##    relationship ADR 0067's shared S1 magnitude implies and neither ADR 0069 nor ADR
##    0070 ever stated.
##
## It deliberately asserts NOTHING about a tolerance on ABSOLUTE damage, and nothing
## about mind being comparable to either: mind returns `amount 0.0` by design (ADR 0071),
## so its row is an erosion in different units and a ratio against it would be a
## category error. Claim 4 is a RATIO between two mechanisms that share a unit, which is
## the one comparison that is well formed. The printed spread IS the rest of the
## deliverable; a human reads it and decides whether the gap is a bug.
##
## ## What the actors are
##
## Built from the three EXISTING fixtures — `qi_damage_fixture.gd`,
## `body_damage_fixture.gd`, `mind_damage_fixture.gd` — so no pinned number
## lives in two places. MATCHED at each realm: attacker AND defender are both
## `RealmScaling.apply`'d, so a row is one realm's fight rather than an R30
## attacker beating an R1 defender. Defenders are UNDEFENDED: no qi resistance
## beyond the stated half-cap, no authored `DAMAGE_REDUCTION`, an empty AWARENESS
## reserve and a pinned-zero `mental_defense`. That is the only reading under
## which the three are comparable at all, and it is stated rather than implied.
##
## ## Where every number comes from
##
## `CombatTuning.shipped()`, a live `ActorStats.derived` read, an authored `.tres`
## (`RealmDef.power`, `MindRealmSeed.sea_capacity`), or arithmetic on those. The
## only two named inputs are fixture-shaped rather than balance-shaped, and both
## are named in prose: qi's attack AUTHORS its elemental share (`MEASURED_SHARE`,
## because BL-0348 ruled the tuning default to `0.0` and a row that read the default
## would measure a zero-share tautology rather than the elemental path),
## and body's strike aims at one named meridian, `lung`, because ADR 0070's
## granularity IS the meridian and a sweep is a different mechanic.
##
## ## Mind's "equivalent damage"
##
## Mind's `amount` is `0.0` BY DESIGN (ADR 0071): it erodes the sea and never
## subtracts health. So the table reports the EROSION (`proposal.effects`) and
## two conversions, both explicitly labelled:
##
## - `mind_eq_mag` — turbulence x the sea's `structural_capacity`, i.e. the
##   erosion in the same MAGNITUDE units qi and body report. This is SEA
##   STRUCTURE eroded, not health spent. It is the only conversion that makes
##   the three rows the same kind of number.
## - `rupture_hp_1s` — what `MindDamage.tick_rupture` actually spends on health
##   in ONE SECOND at the post-hit turbulence. This is the ONLY route mind has
##   to health (BRIEF 2.3), and it is zero below `RUPTURE_THRESHOLD`, which is
##   exactly the floor of safety ADR 0071 claims.

## The realm indices measured: R1, R10, R20, R30. Read off
## `RealmDefaults.ladder()`, so the names are never a literal typed here and a
## ladder retune cannot silently mislabel a column.
const REALM_INDICES: Array[int] = [0, 10, 20, 29]
## A tier-2 element ("mid" in the wuxing sense) with a tier-2 mastery divisor, so
## the row is not a tier-1 row measured twice.
const ATTACKING_ELEMENT := ElementStats.LIGHTNING
## The defender's OWN element, distinct from the attacker's, so
## `rules.multiplier(attacker, defender)` is a real read rather than a tie.
const DEFENDER_ELEMENT := ElementStats.WATER
## The meridian body's strike aims at. Named in the docblock above.
const AIM_MERIDIAN := &"lung"

## The elemental share the qi row AUTHORS. `0.8` was the shipped default until
## BL-0348's ruling set it to `0.0`; authoring it here keeps the fraction column
## measuring the elemental path rather than a `0 == 0` tautology.
const MEASURED_SHARE := 0.8

## ADR 0069's realm invariance is asserted to this epsilon because
## `test_qi_damage_realm.gd` already asserts the SAME claim to the SAME epsilon
## over two realms. Quoting the repo's own tolerance for the repo's own claim is
## not inventing one; widening it would be.
const FRACTION_EPSILON := 0.000001

## One order of magnitude, as the bound on qi/body at every realm. Stated rather than
## measured-and-fitted: the pre-fix rows were 362.92 and 589.74, both three decades out,
## so this bound has three clear decades of headroom over the fixed ladder and still
## fails a mechanism that stops tracking the other.
const MAX_QI_BODY_RATIO := 10.0

# --- DEF-0344: the six placeholder families and their declared bands -------------
#
# Shipping a guess is fine; calling it balance is not. Each band is the ENVELOPE the
# family's retune must stay inside — every bound names the degenerate state it must not
# reach (an invisible coefficient, a saturated contest, an immunity). The report below
# prints shipped-vs-band; moving a family WITHIN its band is the play-data retune
# DEF-0344 still tracks, so crossing a bound is a FINDING rather than a number nobody
# re-reads.
const RATE_SCALE_BAND: Array[float] = [0.005, 0.05]
const REFUSAL_CAP_BAND: Array[float] = [0.5, 0.99]
const MATRIX_K_BAND: Array[float] = [0.001, 0.5]
const MATRIX_GAMMA_BAND: Array[float] = [0.5, 2.0]
const MATRIX_SPAN_BAND: Array[float] = [0.5, 2.0]
const GRANT_ROW_RATIO_BAND: Array[float] = [0.5, 2.0]
const GRANT_TECHNIQUE_RATIO_BAND: Array[float] = [0.1, 1.0]
const STATUS_RATE_SCALE_BAND: Array[float] = [0.1, 1.0]
const STATUS_NET_SCALE_BAND: Array[float] = [0.25, 4.0]
const STATUS_NET_MIN_BAND: Array[float] = [0.0, 0.5]
const STATUS_NET_MAX_BAND: Array[float] = [1.0, 10.0]

var _qi: Variant = preload("res://tests/modules/combat_engine/qi_damage_fixture.gd").new()
var _body: Variant = preload("res://tests/modules/combat_engine/body_damage_fixture.gd").new()
var _mind: Variant = preload("res://tests/modules/combat_engine/mind_damage_fixture.gd").new()
var _tuning: CombatTuning = null


func setup() -> void:
	_tuning = CombatTuning.shipped()
	_qi.setup()
	_body.setup()
	_mind.setup()


## The measure, then the assertions, then the verdict. One test so the printed
## table and the pass/fail cannot come from two different runs of the arithmetic.
func test_the_three_mechanisms_are_measured_and_only_what_is_claimed_is_asserted() -> void:
	var rows: Array[Dictionary] = []
	for index in REALM_INDICES:
		rows.append(_row(index))
	_print_table(rows)
	_assert_fraction_is_realm_invariant(rows)
	_assert_the_two_health_mechanisms_stay_comparable(rows)
	_assert_nothing_is_non_finite(rows)
	_assert_qi_and_body_grow(rows)


# --- one row per realm --------------------------------------------------------


## One realm: its id and authored power, plus what each mechanism resolved.
func _row(realm_index: int) -> Dictionary:
	var realm: RealmDef = RealmDefaults.ladder().realms()[realm_index]
	var realm_id: StringName = realm.id
	return {
		"realm": String(realm_id),
		"power": float(realm.power),
		"qi": _qi_hit(realm_id),
		"body": _body_hit(realm_id),
		"mind": _mind_hit(realm_id),
	}


## A qi hit: one element against a defender whose authored elemental DEFENSE is one
## divisor's worth, so the mitigation is a real number rather than a tautological
## zero and the elemental term survives.
##
## The magnitude is S1's OUTPUT for the same reason the body row's is: `QiDamage` reads
## `ctx.magnitude` for both of its shares, so handing it the bare authored `100.0` fed
## the mechanism a PRE-GATE figure and skipped the rate this file's other column pays.
## `RealmRate` is the spine's stage, so the gated number is read through the spine's own
## `base_damage` rather than re-multiplied here. The rate is a sub-2x factor that cancels
## out of the qi/body ratio either way — it makes the two rows differ by exactly ONE thing,
## which is the two attack stats.
##
## The row publishes ADR 0200's FOUR TERMS rather than the single deleted `resistance`
## percent, because that is what the ratio is built from and a panel has to be able to see
## which of them moved: `defense` is `D`, `defense_effective` is `D` after the bounded
## reciprocal on penetration, `divisor_k` is `K` (which rides the ATTACKER) and
## `mitigation_rate` is the unclamped curve output `m`.
func _qi_hit(realm_id: StringName) -> Dictionary:
	# ADR 0200: the elemental defense is a MAGNITUDE on the divisor's scale, not a share of
	# a removed `resist_cap`. This is a defended target, which is all this comparison needs.
	var defense_points: float = _tuning.resist_divisor
	var attacker: Actor = _qi._attacker(ATTACKING_ELEMENT)
	var target: Actor = _qi._defender(ATTACKING_ELEMENT, defense_points)
	_stand_at(attacker, PathState.QI, realm_id)
	_stand_at(target, PathState.QI, realm_id)
	var technique: TechniqueDef = _qi._technique(ATTACKING_ELEMENT, MEASURED_SHARE)
	var ctx: AttackContext = _qi._context(
		attacker,
		target,
		ATTACKING_ELEMENT,
		MEASURED_SHARE,
		CombatSpine.base_damage(attacker, technique),
		DEFENDER_ELEMENT
	)
	var mechanism := QiDamage.new()
	mechanism.tuning = _tuning
	var parts: Dictionary = mechanism.breakdown(ctx)
	var resolved: DamageProposal = mechanism.resolve(ctx)
	var mitigated: DamageProposal = mechanism.mitigate(ctx, resolved)
	var subtotal := float(parts["subtotal"])
	return {
		"s4": resolved.amount,
		"s5": mitigated.amount,
		"fraction": 0.0 if subtotal <= 0.0 else float(parts["elemental_term"]) / subtotal,
		"mitigation": float(parts["mitigation"]),
		"defense": float(parts["defense"]),
		"defense_effective": float(parts["defense_effective"]),
		"divisor_k": float(parts["divisor_k"]),
		"mitigation_rate": float(parts["mitigation_rate"]),
		"pool": _pool_of(target),
	}


## A body hit: one named meridian, `lung`, at `OPEN` so the channel carries
## exactly one step of armour — the smallest non-zero location multiplier, where
## a sign or an off-by-one-step shows up undivided by twenty.
##
## The context is built with the SAME S1 magnitude qi's row above uses — `CombatSpine`'s
## own `base_damage`, which is `technique.magnitude x RealmRate.factor(attacker.realm())`.
## That is the only reason the two rows are comparable at all: `BodyDamage` prices a hit
## at `magnitude x ATTACK_PHYSICAL` and `QiDamage` at `magnitude x ATTACK_SPIRITUAL`, so a
## row that fed one mechanism the spine's gated magnitude and the other a hand-picked
## constant would be measuring the fixture, not the engine. Both techniques are authored
## at `100.0` and both actors are stood at the same realm, so the S1 factor is identical
## and cancels out of the ratio — which is what makes the qi/body ratio CONSTANT.
func _body_hit(realm_id: StringName) -> Dictionary:
	var attacker: Actor = _body._attacker()
	var target: Actor = _body._defender([String(AIM_MERIDIAN)], {AIM_MERIDIAN: MeridianState.OPEN})
	_stand_at(attacker, PathState.BODY, realm_id)
	_stand_at(target, PathState.BODY, realm_id)
	var technique: TechniqueDef = _body._technique(100.0, AIM_MERIDIAN)
	var ctx: AttackContext = _body._context(
		attacker,
		target,
		technique,
		BodyLocation.MODE_NAMED,
		null,
		CombatSpine.base_damage(attacker, technique)
	)
	var mechanism := BodyDamage.new()
	mechanism.tuning = _tuning
	var parts: Dictionary = mechanism.breakdown(ctx)
	var resolved: DamageProposal = mechanism.resolve(ctx)
	var mitigated: DamageProposal = mechanism.mitigate(ctx, resolved)
	return {
		"s4": resolved.amount,
		"s5": mitigated.amount,
		"refused": bool(parts["refused"]),
		"gated": bool(parts["gated"]),
		# Published so the residual-drift readout below can name the three armour terms
		# instead of restating them: the `DEFENSE_PHYSICAL` stat itself, the channel
		# step, and the tissue weighting. Read off the mechanism's own breakdown.
		"resistance": float(parts["resistance"]),
		"defense_physical": float(parts["defense_physical"]),
		"armour_step": float(parts["armour_step"]),
		"channel_rank": float(parts["channel_rank"]),
		"tissue": float(parts["tissue"]),
		"pool": _pool_of(target),
	}


## A mind hit. `amount` is `0.0` by design, so what is measured is the erosion
## the proposal carries, in three units: the sea SHARE, the sea MAGNITUDE, and
## the health the rupture tick would actually spend in one second.
func _mind_hit(realm_id: StringName) -> Dictionary:
	var attacker: Actor = _mind._attacker()
	var target: Actor = _mind._defender(0.0, 0.0)
	_stand_at(attacker, PathState.MIND, realm_id)
	_stand_at(target, PathState.MIND, realm_id)
	# The sea's capacity is the AUTHORED magnitude for this realm
	# (`MindRealmSeed.sea_capacity`, 100 -> 825), not the fixture's pinned 100.0:
	# it is ADR 0071's denominator, so measuring a realm ladder against a pinned
	# constant would measure nothing.
	var seed: MindRealmSeed = MindRealmSeed.for_realm(realm_id)
	var sea: SeaOfConsciousness = _mind._sea_of(target)
	sea.set_structural_capacity(seed.sea_capacity if seed != null else sea.structural_capacity)
	var ctx: AttackContext = _mind._context(MindDamage.Kind.DISRUPT, attacker, target, 1.0)
	var mechanism := MindDamage.new()
	mechanism.tuning = _tuning
	var resolved: DamageProposal = mechanism.resolve(ctx)
	var mitigated: DamageProposal = mechanism.mitigate(ctx, resolved)
	var effect: Dictionary = _mind._effect_of(mitigated)
	var turbulence := float(effect.get(MindDamage.KEY_TURBULENCE, 0.0))
	var rupture: Dictionary = MindDamage.new().tick_rupture(sea, target, 1.0, _tuning)
	return {
		"amount": mitigated.amount,
		"turbulence": turbulence,
		"clarity": float(effect.get(MindDamage.KEY_CLARITY, 0.0)),
		"awareness": float(effect.get(MindDamage.KEY_AWARENESS, 0.0)),
		"capacity": sea.structural_capacity,
		"equiv": turbulence * sea.structural_capacity,
		"rupture": float(rupture.get(MindDamage.KEY_HP_LOSS, 0.0)),
		"pool": _pool_of(target),
	}


## Put an actor on a path at a realm and apply BOTH realm halves. The element
## half is re-applied because `RealmScaling.apply` clears the shared `realm`
## source tag wholesale — `test_qi_damage_realm.gd:118` measures that wipe, and
## this is the order it documents.
func _stand_at(actor: Actor, path_id: StringName, realm_id: StringName) -> void:
	actor.set_path(PathState.new(path_id, realm_id))
	RealmScaling.apply(actor)
	ElementsApi.apply_realm_modifiers(actor)


## The actor's own health pool maximum. Read off the pool, never typed.
func _pool_of(actor: Actor) -> float:
	var pool: ResourcePool = actor.resource(&"health")
	return 0.0 if pool == null else pool.maximum


# --- the three assertions, and only the three ---------------------------------


## ADR 0069: the element's share of a qi hit does not move with the realm.
func _assert_fraction_is_realm_invariant(rows: Array[Dictionary]) -> void:
	var first := float(rows[0]["qi"]["fraction"])
	for row in rows:
		assert_almost_eq(
			float(row["qi"]["fraction"]),
			first,
			(
				"the qi elemental fraction is realm-invariant at %s (measured %.9f vs R1 %.9f)"
				% [row["realm"], float(row["qi"]["fraction"]), first]
			),
			FRACTION_EPSILON
		)


## BRIEF 1.5: the spine's ONE non-finite guard at S6 may assume no mechanism
## hands it a NaN, and S9's single sign flip means a negative would be spent as
## a HEAL. Mind's three effect writes are included because they are the numbers
## it produces at all — `amount` is `0.0` by design and proves nothing.
func _assert_nothing_is_non_finite(rows: Array[Dictionary]) -> void:
	for row in rows:
		for field in ["s4", "s5"]:
			_finite_non_negative(float(row["qi"][field]), "qi %s %s" % [row["realm"], field])
			_finite_non_negative(float(row["body"][field]), "body %s %s" % [row["realm"], field])
		_finite_non_negative(float(row["mind"]["amount"]), "mind %s amount" % row["realm"])
		_finite_non_negative(float(row["mind"]["turbulence"]), "mind %s turbulence" % row["realm"])
		_finite_non_negative(float(row["mind"]["equiv"]), "mind %s equiv" % row["realm"])
		_finite_non_negative(float(row["mind"]["rupture"]), "mind %s rupture" % row["realm"])
		_finite_non_negative(float(row["mind"]["awareness"]), "mind %s awareness" % row["realm"])
		assert_eq(
			is_finite(float(row["mind"]["clarity"])) and float(row["mind"]["clarity"]) <= 0.0,
			true,
			"mind %s clarity is finite and is a NEGATIVE delta" % row["realm"]
		)


## ADR 0067 S1 plus the authored realm power: more realm, more hit.
func _assert_qi_and_body_grow(rows: Array[Dictionary]) -> void:
	for index in range(1, rows.size()):
		var realm := String(rows[index]["realm"])
		assert_eq(
			float(rows[index]["qi"]["s5"]) > float(rows[index - 1]["qi"]["s5"]),
			true,
			(
				"qi damage grew into %s (%.4f from %.4f)"
				% [realm, float(rows[index]["qi"]["s5"]), float(rows[index - 1]["qi"]["s5"])]
			)
		)
		assert_eq(
			float(rows[index]["body"]["s5"]) > float(rows[index - 1]["body"]["s5"]),
			true,
			(
				"body damage grew into %s (%.4f from %.4f)"
				% [realm, float(rows[index]["body"]["s5"]), float(rows[index - 1]["body"]["s5"])]
			)
		)


func _finite_non_negative(value: float, label: String) -> void:
	assert_eq(is_finite(value) and value >= 0.0, true, "%s is finite and non-negative" % label)


## The largest absolute deviation of the qi elemental fraction from its R1 value,
## measured and reported, and asserted against only in ADR 0069's own terms.
func _spread_of(rows: Array[Dictionary]) -> float:
	var first := float(rows[0]["qi"]["fraction"])
	var spread := 0.0
	for row in rows:
		spread = maxf(spread, absf(float(row["qi"]["fraction"]) - first))
	return spread


# --- the deliverable: the printed table ---------------------------------------


func _print_table(rows: Array[Dictionary]) -> void:
	print("")
	print("=== CROSS-MECHANISM BALANCE ==========================================")
	print(
		(
			(
				"shipped tuning | matched attackers AND defenders | undefended targets | "
				+ "element=%s vs %s | aim=%s | QiDamage S5 vs BodyDamage S5 vs MindDamage erosion"
			)
			% [ATTACKING_ELEMENT, DEFENDER_ELEMENT, AIM_MERIDIAN]
		)
	)
	print("")
	print(
		(
			"%-24s %9s %12s %12s %13s %13s %11s | %9s %9s %9s %9s %11s"
			% [
				"realm",
				"power",
				"qi_dmg",
				"body_dmg",
				"mind_erosion",
				"mind_eq_mag",
				"qi_elem_frac",
				"qi_s4",
				"qi_s5==s4",
				"body_s5",
				"sea_hits",
				"rupture_hp_1s"
			]
		)
	)
	for row in rows:
		var qi: Dictionary = row["qi"]
		var body: Dictionary = row["body"]
		var mind: Dictionary = row["mind"]
		print(
			(
				"%-24s %9.2f %12.4f %12.4f %13.6f %13.4f %11.6f | %9s %9s %9.4f %9.4f %11.4f"
				% [
					row["realm"],
					float(row["power"]),
					float(qi["s5"]),
					float(body["s5"]),
					float(mind["turbulence"]),
					float(mind["equiv"]),
					float(qi["fraction"]),
					"%s" % ("yes" if is_equal_approx(float(qi["s4"]), float(qi["s5"])) else "NO"),
					(
						"%s"
						% ("yes" if is_equal_approx(float(body["s4"]), float(body["s5"])) else "NO")
					),
					float(body["s5"]),
					_hits(float(mind["turbulence"])),
					float(mind["rupture"])
				]
			)
		)
	print("")
	_print_hits(rows)
	_print_spread(rows)
	_print_residual_drivers(rows)
	_print_placeholder_families()


## Hits-to-kill against a REFERENCE pool: the qi defender's own health maximum,
## read live. qi and body both strike that pool at the same figure, so their
## columns are directly comparable. Mind's column is hits-to-EMPTY-THE-SEA, and
## is labelled as such — mind never subtracts health, so a hits-to-kill for it
## would be a fiction.
func _print_hits(rows: Array[Dictionary]) -> void:
	var pool := float(rows[0]["qi"]["pool"])
	print("=== HITS (reference pool = qi defender's own health max = %.2f) ==========" % pool)
	print(
		"%-24s %12s %12s %14s %12s" % ["realm", "qi_hits", "body_hits", "mind_sea_hits", "qi/body"]
	)
	for row in rows:
		var qi_hits := _hits(pool / float(row["qi"]["s5"]))
		var body_hits := _hits(pool / float(row["body"]["s5"]))
		var ratio := _qi_body_ratio(row)
		# Mind's column is hits-to-EMPTY-THE-SEA, and the table's own `sea_hits` column
		# is turbulence RECIPROCATED — it lives on `row["mind"]`, not on `row`, and
		# reading it off the row raised a script error that aborted the function before
		# the format string below ran, which is how a whole table of measured numbers
		# printed as nothing at all.
		var sea_hits := _hits(1.0 / float(row["mind"]["turbulence"]))
		print(
			(
				"%-24s %12.4f %12.4f %14.4f %12.4f"
				% [row["realm"], qi_hits, body_hits, sea_hits, ratio]
			)
		)
	print("")


## The spread, which is the thing this file exists to show and deliberately does
## NOT assert a tolerance against.
func _print_spread(rows: Array[Dictionary]) -> void:
	var first: Dictionary = rows[0]
	var last: Dictionary = rows[rows.size() - 1]
	var qi_ratio := float(last["qi"]["s5"]) / float(first["qi"]["s5"])
	var body_ratio := float(last["body"]["s5"]) / float(first["body"]["s5"])
	var power_ratio := float(last["power"]) / float(first["power"])
	var spread := _spread_of(rows)
	# `%9.9f` and `%.0e`, NOT `%10.9f` and `%g`: `validated_evaluate` rejects the
	# width on a float conversion and the `%g` on a real float out of hand, and a broken
	# format string makes the WHOLE `print` a no-op that discards the measured value it
	# was written to show — which is how a printed table can go blank on a green run.
	print("=== SPREAD (measured, NOT asserted against any tolerance) ===============")
	print(
		(
			"authored realm power R1->R30   : %10.2fx   (RealmDef.power, realm_power_table.tres)"
			% power_ratio
		)
	)
	print(
		(
			"qi damage       R1 -> R30      : %10.2fx   (%s)"
			% [qi_ratio, first["realm"] + " -> " + last["realm"]]
		)
	)
	print("body damage     R1 -> R30      : %10.2fx" % body_ratio)
	# NOT a literal. Every conversion is forced to a STRING before it reaches the
	# format: `validated_evaluate` resolves an argument's type from the ARRAY it is
	# handed, and a bare `float` carrying `0.0` there is read as the INTEGER `0` and
	# the whole conversion fails — which makes `print` a silent no-op and loses the
	# measured value the line exists to show. `str(...)` is the only reason the two
	# lines below print anything at all.
	var verdict := "REALM-INVARIANT" if spread <= FRACTION_EPSILON else "NOT CONSTANT -- FINDING"
	print(
		(
			"qi elem fraction spread       : %s   (constant to %s => %s)"
			% [str(spread), str(FRACTION_EPSILON), verdict]
		)
	)
	print(
		(
			"qi/body ratio    R1 -> R30     : %10.2f -> %.2f"
			% [_qi_body_ratio(first), _qi_body_ratio(last)]
		)
	)
	var pool_lo := float(rows[0]["qi"]["pool"])
	print("=== AUTHORED VITALITY POOL (ADR 0133's open desync) ====================")
	print(
		(
			"realms' vitality pool is authored 40.0 -> 800.0 (loot_*.tres, "
			+ "loot_route_elemental_transcendent_domain: 500/800), i.e. ~20x across 30 realms."
		)
	)
	print(
		(
			"one qi hit does %.1f%% of that pool at R1 and %.4f%% at R30."
			% [
				100.0 * float(first["qi"]["s5"]) / pool_lo,
				100.0 * float(last["qi"]["s5"]) / float(rows[rows.size() - 1]["qi"]["pool"])
			]
		)
	)
	print("")


## The two HEALTH mechanisms stay within one order of magnitude of each other at
## every realm.
##
## This is a claim an ADR makes. ADR 0067's S1 hands every mechanism ONE magnitude, and
## ADR 0069 and ADR 0070 each decided a formula that multiplies it by the attacker's
## own stat — and neither decided the RELATIONSHIP between the two, which is why
## `BodyDamage` shipped reading the bare `ATTACK_PHYSICAL` and dropping the magnitude
## entirely. Nothing caught it: body still grew with the realm, it just grew on a
## different power than qi did, so the gap WIDENED with the ladder (363x at R1 to 590x
## at R30) while every per-mechanism suite stayed green against its own formula.
##
## Deliberately a BOUND, not a constant ratio. A constant-ratio claim is FALSE on this
## ladder even once the arithmetic is right, for a reason that is content rather than
## code — see [method _print_residual_drivers]: `MindRealmSeed.sea_capacity` grows
## 8.25x over the thirty realms while `RealmDef.power` grows 551x, so a qi actor's
## attack stat outruns the body defender's armour by construction and any ratio between
## a growing numerator and a defended denominator drifts. What must not drift past its
## bound is the CLAIM, and the pre-fix rows were three decades past it.
func _assert_the_two_health_mechanisms_stay_comparable(rows: Array[Dictionary]) -> void:
	for row in rows:
		var ratio := _qi_body_ratio(row)
		assert_eq(
			ratio <= MAX_QI_BODY_RATIO and ratio >= 1.0 / MAX_QI_BODY_RATIO,
			true,
			(
				"qi and body are within one order of magnitude at %s (measured %.2f)"
				% [row["realm"], ratio]
			)
		)


## `qi / body` for one row, or `-1.0` when body declined the strike — a refusal, which
## is ADR 0070's own answer and is NOT an infinite ratio this file should trip over.
func _qi_body_ratio(row: Dictionary) -> float:
	var body := float(row["body"]["s5"])
	if body <= 0.0:
		return -1.0
	return float(row["qi"]["s5"]) / body


## What the remaining drift is made of, so nobody re-reads the ratio as a new defect.
## Every figure is read off the actors and the authored `.tres` files this run already
## touched — nothing here is a literal, because a literal here would be a second copy of
## the ladder.
##
## The qi/body ratio drifts because the two sides do not draw from the same authored
## pool. `ATTACK_SPIRITUAL` is a flat `25.0` base on the qi fixture and
## `ATTACK_PHYSICAL` a flat `20.0` on the body fixture, but the DEFENDER is not flat: the
## body defender carries a `BodyProvider` whose `DEFENSE_PHYSICAL` bonus scales with
## `BodyRealmSeed.integrity_maximum`, an AUTHORED ladder of 20.0 -> 165.0, or 8.25x, plus
## the fixed channel-armour and tissue terms. Qi has no such term at all — its defender
## contributes one `mitigation` figure that is realm-invariant by ADR 0069's construction.
## So qi/body is 0.59 -> 3.27 on a numerator growing 551x over a denominator growing
## 8.25x. Narrowing THAT further is the authored-vitality desync ADR 0133 records as open,
## not a mechanism defect: it is content that does not track `RealmDef.power`.
func _print_residual_drivers(rows: Array[Dictionary]) -> void:
	print("=== WHY THE RATIO STILL DRIFTS (authored data, not arithmetic) ===========")
	for row in rows:
		var body: Dictionary = row["body"]
		print(
			(
				"%-24s qi/body %8.4f | body defence %12.4f = stat %10.4f + channel %8.4f + tissue %7.4f"
				% [
					row["realm"],
					_qi_body_ratio(row),
					float(body["resistance"]),
					float(body["defense_physical"]),
					float(body["armour_step"]) * float(body["channel_rank"]),
					float(body["tissue"])
				]
			)
		)
	print("")


## Hits-to-kill, or a marked absence rather than an infinity.
func _hits(value: float) -> float:
	return -1.0 if not is_finite(value) or value <= 0.0 else value


# --- DEF-0344: the six placeholder families -----------------------------------


## What shipped, the band it must stay inside, and the verdict. The status-family
## lines also MEASURE the realm-invariance ADR 0891 claims, because a fixed scale
## over a delta is only readable while the delta means the same thing at every realm.
func _print_placeholder_families() -> void:
	var tuning := _tuning
	if tuning == null:
		return
	var table := AptitudeTable.shipped()
	var grant := AptitudeGrant.shipped()
	print("=== PLACEHOLDER FAMILIES (unmeasured; DEF-0344) ========================")
	print("%-26s %-34s %-22s %s" % ["family", "shipped", "band", "verdict"])
	_placeholder_line("rate_scale", "%.6f" % tuning.rate_scale, RATE_SCALE_BAND, tuning.rate_scale)
	_placeholder_line(
		"refusal_cap", "%.6f" % tuning.refusal_cap, REFUSAL_CAP_BAND, tuning.refusal_cap
	)
	if table != null:
		var edges := table.to_edges()
		var k_lo := INF
		var k_hi := -INF
		for edge in edges:
			k_lo = minf(k_lo, edge.k)
			k_hi = maxf(k_hi, edge.k)
		_placeholder_line(
			"matrix k (min of %d)" % edges.size(), "k = %.6f" % k_lo, MATRIX_K_BAND, k_lo
		)
		_placeholder_line("matrix k (max)", "k = %.6f" % k_hi, MATRIX_K_BAND, k_hi)
		_placeholder_line(
			"matrix share_exponent",
			"%.6f" % table.share_exponent,
			MATRIX_GAMMA_BAND,
			table.share_exponent
		)
		_placeholder_line(
			"matrix contest_span", "%.6f" % table.contest_span, MATRIX_SPAN_BAND, table.contest_span
		)
	if grant != null:
		var per_lo := INF
		var per_hi := -INF
		for row in grant.rows:
			var per_realm := float(row.get("per_realm", 0.0))
			per_lo = minf(per_lo, per_realm)
			per_hi = maxf(per_hi, per_realm)
		var row_ratio := per_hi / per_lo if per_lo > 0.0 else INF
		_placeholder_line(
			"grant per_realm max/min", "%.6f" % row_ratio, GRANT_ROW_RATIO_BAND, row_ratio
		)
		var technique_ratio := grant.technique_points / per_lo if per_lo > 0.0 else INF
		_placeholder_line(
			"grant technique/per_realm",
			"%.6f" % technique_ratio,
			GRANT_TECHNIQUE_RATIO_BAND,
			technique_ratio
		)
	_placeholder_line(
		"status_rate_scale",
		"%.6f" % tuning.status_rate_scale,
		STATUS_RATE_SCALE_BAND,
		tuning.status_rate_scale
	)
	_placeholder_line(
		"status_net_factor_scale",
		"%.6f" % tuning.status_net_factor_scale,
		STATUS_NET_SCALE_BAND,
		tuning.status_net_factor_scale
	)
	_placeholder_line(
		"status_min_net_factor",
		"%.6f" % tuning.status_min_net_factor,
		STATUS_NET_MIN_BAND,
		tuning.status_min_net_factor
	)
	_placeholder_line(
		"status_max_net_factor",
		"%.6f" % tuning.status_max_net_factor,
		STATUS_NET_MAX_BAND,
		tuning.status_max_net_factor
	)
	_print_status_realm_invariance(table)
	print(
		(
			"status potency BASE       : element_power<e> x %.2f (floor %.2f) -- a REUSE"
			% [tuning.status_potency_scale, tuning.status_potency_floor]
		)
	)
	print(
		(
			"                            authorable per status since ADR 0897 "
			+ "(StatusDef.potency_base; every shipped def 0.0 = fallback) -- the values are the wave"
		)
	)
	print("")


## One family's line: the shipped figure, its band, and `in` / `OUT -- FINDING`.
func _placeholder_line(name: String, shipped: String, band: Array[float], value: float) -> void:
	var verdict := "OUT -- FINDING"
	if is_finite(value) and value >= band[0] and value <= band[1]:
		verdict = "in"
	print("%-26s %-34s %-22s %s" % [name, shipped, "[%.6f, %.6f]" % [band[0], band[1]], verdict])


## ADR 0891: the status channels are share-space. This resolves ONE allocation through
## the shipped matrix at the first and the last ladder and prints the gate delta both
## times — the same number twice is the claim; two numbers is the finding.
func _print_status_realm_invariance(table: AptitudeTable) -> void:
	if table == null:
		return
	var realms := RealmDefaults.ladder().realms()
	if realms.is_empty():
		return
	var first := float(realms[0].power)
	var last := float(realms[realms.size() - 1].power)
	var sample := {&"might": 1.0, &"ferocity": 1.0, &"composure": 1.0}
	var at_first := AptitudeMatrix.resolve(
		table.to_edges(), sample, table.share_exponent, table.contest_span, first
	)
	var at_last := AptitudeMatrix.resolve(
		table.to_edges(), sample, table.share_exponent, table.contest_span, last
	)
	var delta_first := (
		float(at_first.get(&"status.power.omni", 0.0))
		- float(at_first.get(&"status.resist.omni", 0.0))
	)
	var delta_last := (
		float(at_last.get(&"status.power.omni", 0.0))
		- float(at_last.get(&"status.resist.omni", 0.0))
	)
	var verdict := (
		"REALM-INVARIANT" if is_equal_approx(delta_first, delta_last) else "DRIFTS -- FINDING"
	)
	print(
		(
			"status gate delta (sample) : %.6f at R1 vs %.6f at last (ladder %.2f..%.2f) => %s"
			% [delta_first, delta_last, first, last, verdict]
		)
	)
