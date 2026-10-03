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
##
## It deliberately asserts NOTHING about the three being "balanced" or within any
## ratio. No ADR claims they are, and a tolerance invented in this file would be
## this file DECIDING balance rather than measuring it. The printed spread IS the
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
## are named in prose: qi's attack carries the shipped default elemental share
## (no technique authored one, so `CombatTuning.default_element_share` decides),
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

## ADR 0069's realm invariance is asserted to this epsilon because
## `test_qi_damage_realm.gd` already asserts the SAME claim to the SAME epsilon
## over two realms. Quoting the repo's own tolerance for the repo's own claim is
## not inventing one; widening it would be.
const FRACTION_EPSILON := 0.000001

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


## A qi hit: one element against a defender whose authored resistance is HALF the
## shipped `resist_cap`, so the elemental term survives and the fraction is a
## real number rather than a tautological zero.
func _qi_hit(realm_id: StringName) -> Dictionary:
	var resistance := _tuning.resist_cap * 0.5
	var attacker: Actor = _qi._attacker(ATTACKING_ELEMENT)
	var target: Actor = _qi._defender(ATTACKING_ELEMENT, resistance)
	_stand_at(attacker, PathState.QI, realm_id)
	_stand_at(target, PathState.QI, realm_id)
	var ctx: AttackContext = _qi._context(
		attacker, target, ATTACKING_ELEMENT, _tuning.default_element_share, 100.0, DEFENDER_ELEMENT
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
		"resistance": float(parts["resistance"]),
		"pool": _pool_of(target),
	}


## A body hit: one named meridian, `lung`, at `OPEN` so the channel carries
## exactly one step of armour — the smallest non-zero location multiplier, where
## a sign or an off-by-one-step shows up undivided by twenty.
func _body_hit(realm_id: StringName) -> Dictionary:
	var attacker: Actor = _body._attacker()
	var target: Actor = _body._defender([String(AIM_MERIDIAN)], {AIM_MERIDIAN: MeridianState.OPEN})
	_stand_at(attacker, PathState.BODY, realm_id)
	_stand_at(target, PathState.BODY, realm_id)
	var ctx: AttackContext = _body._context(
		attacker, target, _body._technique(100.0, AIM_MERIDIAN), BodyLocation.MODE_NAMED
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
		var ratio := float(row["qi"]["s5"]) / float(row["body"]["s5"])
		print(
			(
				"%-24s %12.4f %12.4f %14.4f %12.4f"
				% [row["realm"], qi_hits, body_hits, float(row["mind"]["sea_hits"]), ratio]
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
	print(
		(
			"qi elem fraction spread       : %10.9f   (constant to %g => %s)"
			% [
				spread,
				FRACTION_EPSILON,
				(
					"REALM-INVARIANT"
					if spread <= FRACTION_EPSILON
					else "NOT CONSTANT -- FINDING, ADR 0069 does not hold"
				)
			]
		)
	)
	print(
		(
			"qi/body ratio    R1 -> R30     : %10.2f -> %.2f"
			% [
				float(first["qi"]["s5"]) / float(first["body"]["s5"]),
				float(last["qi"]["s5"]) / float(last["body"]["s5"])
			]
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


## Hits-to-kill, or a marked absence rather than an infinity.
func _hits(value: float) -> float:
	return -1.0 if not is_finite(value) or value <= 0.0 else value
