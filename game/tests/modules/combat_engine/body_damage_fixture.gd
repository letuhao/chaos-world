extends TestCase

## Shared fixture for the body-damage suites. Not a suite itself: the runner
## discovers `test_*.gd` only, so this file is never executed on its own.
##
## It exists for exactly the reason `qi_damage_fixture.gd` does — the pinned actor
## arithmetic and the `_attacker()` / `_defender()` builders are ONE copy, because a
## second copy drifts and a drift here is invisible: every suite would still be green
## against its own copy of a number that no longer describes the mechanism.
##
## ## What is pinned, and why these particular numbers
##
## Only the BASE attributes are pinned. The DERIVED stats are READ OFF THE ACTOR, and
## that is the whole discipline of this fixture.
##
## An earlier version of this file restated core's formulas in prose and let every
## suite's arithmetic hang off the resulting literals: `ATTACK_PHYSICAL = physique * 2.0`
## and `DEFENSE_PHYSICAL = physique * 1.5`, so physique `10.0` meant `20.0` and `15.0`.
## Both derivations were TRUE of `actor_stats.gd` and BOTH were wrong about the actors
## these builders produce, because the defender runs `BodyCultivationApi.attach` and
## therefore carries a `BodyProvider`. `ActorStats._ensure_providers` makes a provider's
## contribution the BASELINE for whatever id it emits (ADR 0026), and `BodyProvider`
## emits `BodyStats.PHYSICAL_DEFENSE`, which is an ALIAS of `Stat.DEFENSE_PHYSICAL` —
## so a body-path defender reads core's `15.0` **plus** `(bone * 1.5 + vitality * 1.0)
## x shaped`, not `15.0`. Every armour assertion that quoted the hand-copied baseline was
## therefore asserting about an actor that does not exist, and it went red the moment the
## provider's shape moved.
##
## So nothing here derives a number. `attack_of()` / `defence_of()` ask the actor, and a
## suite that wants to say "the armour term moved and only the armour term moved" reads
## the two rows `breakdown` already publishes (`defense_physical`, `tissue`, `channel_rank`)
## instead of recomputing the sum from a formula it would then have to maintain.
##
## `DEFENSE_PHYSICAL` is FLAT and `0.0`-baselined (ADR 0022), so a FLAT modifier is the
## only form that can raise it — the same trap `ADR 0022` names and `qi_damage.gd` guards.
##
## Tissue is a weighting of `bone_density` / `muscle_fiber` / `organ_vitality`
## (`CombatTuning.tissue_stat_ids`), and `BodyProvider` contributes those ids only when
## the actor was enrolled on the body path, so a defender that wants tissue must have
## `BodyCultivationApi.attach` run. `_defender` does that; the fixture never invents a
## number the actor's own derived read would not produce.

## The attacker's pinned BASE physique. What `ATTACK_PHYSICAL` is FOLLOWS from it.
const PHYSIQUE := 10.0
## The defender's pinned BASE physique. See the docblock: `DEFENSE_PHYSICAL` is NOT this
## number, because a body-path defender also carries `BodyProvider`'s additive bonus.
const DEFENDER_PHYSIQUE := 10.0
## `body_integrity`'s maximum. A wound's severity is `damage / maximum`, so this is the
## divisor every wound assertion divides by — and it is read off the pool the fixture
## really created, never a literal.
const INTEGRITY_MAXIMUM := 100.0

## The defender's three base body attributes. Non-zero so `BodyProvider` contributes
## tissue defence, and deliberately EQUAL, so the four archetypes' weightings are
## compared against one number rather than three.
const BONE := 10.0
const MUSCLE := 10.0
const VITALITY := 10.0

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTuning.shipped()


## The shipped tuning, for the handful of assertions that quote a bound (BRIEF 1.7:
## the number lives in the `.tres`, and a suite that restated it would pin a rebalance).
func tuning() -> CombatTuning:
	return _tuning


## An attacker whose numbers are pinned: `ATTACK_PHYSICAL = 20.0`.
##
## `quiet_actor` is the combat kit's own no-crit builder and is the base here so a
## suite that is not about S3 cannot be surprised by one — `Stat.CRIT_CHANCE` has a
## constant `0.05` term, so an actor with no fortune and no agility still crits 5% of
## the time.
func _attacker() -> Actor:
	var actor := CombatTestKit.quiet_actor(&"striker", 1000.0)
	actor.stats.set_base(Stat.PHYSIQUE, PHYSIQUE)
	return actor


## A defender with a REAL location axis: twenty unlocked meridians through
## `unlock_for_realm`, a real `AcupointSet` of authored acupoint, and the
## `body_integrity` pool a wound is measured against.
##
## `qi_refining` is the realm index the shipped meridian defs unlock at tier 0, so every
## one of the twenty channels exists — a body the `random` aim has something to choose
## between. Enrolling through `BodyCultivationApi.attach` (rather than reaching for
## `AcupointDefaults` directly) is what makes the acupoint set and the integrity pool the
## SHIPPED ones, which is the whole point of building from real actors and real seeds.
##
## `attach_acupoints` is a SECOND call and is NOT reached by `attach`: `attach` builds the
## integrity pool, the provider, the progress tracker and the meridian channels, while the
## acupoint SET — the `AcupointSet` component the location axis reads — is attached
## separately, exactly as `actor_factory.gd` does for a real actor. Calling only `attach`
## left every body with twenty meridians and NO acupoint, so `_points_of` answered `[]`, every
## site came back `locked` at the neutral `1.0`, and the whole location vocabulary the
## suite exists to assert never ran.
func _defender(meridians: Array = ["lung"], states: Dictionary = {}) -> Actor:
	var actor := CombatTestKit.quiet_actor(&"ward", 5000.0)
	actor.stats.set_base(Stat.PHYSIQUE, DEFENDER_PHYSIQUE)
	actor.stats.set_base(BodyStats.BONE_DENSITY, BONE)
	actor.stats.set_base(BodyStats.MUSCLE_FIBER, MUSCLE)
	actor.stats.set_base(BodyStats.ORGAN_VITALITY, VITALITY)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	actor.meridians.unlock_for_realm(&"qi_refining")
	for entry in meridians:
		_open_to(actor, StringName(entry), StringName(states.get(entry, &"")))
	return actor


## ## The one place a suite reads an actor's strength from
##
## Both go through `ActorStats.derived`, which is the LIVE cache the mechanism's
## `AttackContext.target_value` / `attacker_value` resolve to (`_stat_of` prefers a live
## `derived` over the context's own table). A suite that quoted `physique * 1.5` here
## instead was asserting against a body with no `BodyProvider` on it — an actor
## `_defender` never builds.
##
## Read these, never a formula. They are what makes a rebalance of `actor_stats.gd` or
## of `BodyProvider`'s shape invisible to the suites, which is the property a hand-copied
## formula destroys: it keeps passing while describing an actor that does not exist, and
## goes red for a reason that has nothing to do with the mechanism under test.
func attack_of(actor: Actor) -> float:
	return actor.stats.derived(Stat.ATTACK_PHYSICAL)


## The defender's live `DEFENSE_PHYSICAL` — core's baseline PLUS whatever `BodyProvider`
## contributed, because a body-path actor carries both.
func defence_of(actor: Actor) -> float:
	return actor.stats.derived(Stat.DEFENSE_PHYSICAL)


## Walk one channel to `state` through the network's own ladder, because the ladder is
## ordered and `expand_meridian` refuses a channel that has not been opened.
func _open_to(actor: Actor, meridian_id: StringName, state: StringName) -> void:
	var network: MeridianNetwork = actor.meridians
	if state == MeridianState.CLOSED or state == &"":
		return
	network.open_meridian(meridian_id)
	if state == MeridianState.EXPANDED:
		network.expand_meridian(meridian_id)
	elif state == MeridianState.STRENGTHENED:
		network.expand_meridian(meridian_id)
		network.strengthen_meridian(meridian_id)


## Raise the defender's `DEFENSE_PHYSICAL` by `points`. FLAT on purpose: ADR 0022 makes
## this channel `0.0`-baselined, so a PERCENT modifier would evaluate `(0.0 + 0.0) * 1.5`
## and silently do nothing — a modifier on the actor that never applied.
func _armour(actor: Actor, points: float) -> void:
	actor.stats.add_modifier(
		StatModifier.new(Stat.DEFENSE_PHYSICAL, Stat.Op.FLAT, points, &"body_damage_fixture")
	)


## The fixture's flat `DAMAGE_REDUCTION`, which S5 reads. Also FLAT, same reason.
func _reduction(actor: Actor, value: float) -> void:
	actor.stats.add_modifier(
		StatModifier.new(Stat.DAMAGE_REDUCTION, Stat.Op.FLAT, value, &"body_damage_fixture")
	)


## A technique of a chosen authored magnitude, with no authored aim by default — so
## the aim mode under test is whatever this suite says it is and not whatever the
## `.tres` happened to carry.
func _technique(magnitude: float = 100.0, aim_meridian: StringName = &"") -> TechniqueDef:
	var def := CombatTestKit.technique(magnitude)
	def.id = &"body_test"
	def.aim_meridian = aim_meridian
	return def


## A context shaped as `CombatSpine._context` shapes one, carrying this mechanism's own
## three inputs through the seam's extension point.
##
## `p_magnitude` is S1's OUTPUT and the spine's `base` / `magnitude` pair, passed in as
## the ALREADY rate-gated figure so this helper never re-derives a rate — `RealmRate` is
## the spine's stage and a fixture that multiplied by it would be a second S1 the suite
## could not tell from the real one. It is NOT defaulted to `0.0`: an omitted magnitude
## left every body suite measuring a mechanism whose gross was `0.0 x ATTACK_PHYSICAL`,
## which is why the gross identity assertions below were written against the bare stat.
## Pass the RATE-GATED magnitude and the context is indistinguishable from the spine's.
##
## `mode` is the per-HIT aim choice (`BodyDamage.AIM_MODE_KEY`), which is deliberately
## not `TechniqueDef.aim_meridian`: one authored id means `named` and its absence means
## `random`, while `broad` is a per-hit choice the author cannot make.
##
## There is deliberately NO wounds parameter, and it was removed with the channel it fed:
## `ctx.data[BodyDamage.WOUNDS_KEY]` was written and never read (ADR 0195), and the
## ledger a fixture actually wants is the one BOUND on the target — `CombatEngineApi
## .attach_wounds` is the only writer, and `BodyDamage.apply_wounds` /
## `CombatEffectApply._wound` read that. A `ctx` channel could only ever have been a
## second answer about the same state.
func _context(
	attacker: Actor,
	target: Actor,
	technique: TechniqueDef,
	mode: StringName = &"",
	tuning: CombatTuning = null,
	p_magnitude: float = NAN
) -> AttackContext:
	var magnitude := p_magnitude
	if not is_finite(magnitude):
		magnitude = CombatSpine.base_damage(attacker, technique)
	var ctx := AttackContext.new(
		attacker, target, technique, tuning if tuning != null else _tuning, magnitude
	)
	if technique != null and technique.aim_meridian != &"":
		ctx.set_data(BodyDamage.AIM_MERIDIAN_KEY, technique.aim_meridian)
	if mode != &"":
		ctx.set_data(BodyDamage.AIM_MODE_KEY, mode)
	if tuning != null:
		ctx.set_data(BodyDamage.TUNING_KEY, tuning)
	return ctx


## The parts for one case, through a mechanism that has the shipped tuning bound — so a
## suite that is about the formula never has to remember to bind one.
func _parts(
	attacker: Actor, target: Actor, mode: StringName = &"", aim_meridian: StringName = &""
) -> Dictionary:
	var mechanism := BodyDamage.new()
	mechanism.tuning = _tuning
	return mechanism.breakdown(_context(attacker, target, _technique(100.0, aim_meridian), mode))


## One `breakdown` row's own `sites[]` entry, or an empty dictionary when the row was
## not struck there. Tests assert on a SPECIFIC meridian's site rather than indexing
## `sites[0]`, so a `broad` sweep that gained or lost a row cannot silently re-point an
## assertion at a different channel.
func _site_of(parts: Dictionary, meridian_id: StringName) -> Dictionary:
	for row in parts["sites"]:
		var site: Dictionary = row
		if StringName(site.get("meridian_id", "")) == meridian_id:
			return site
	return {}


## The meridian ids the fixture's defender actually carries, as `StringName`s, in the
## order `BodyLocation.broad_sites` emits them: **sorted**, which is that implementation's
## documented contract ("one row per UNLOCKED meridian, in sorted id order so two
## identical sweeps produce identical payloads").
##
## Read off the network rather than restated, so the 20-bucket claim is measured. The
## sort here is what makes the two agree, and it is done on the `String` form on purpose:
## `MeridianNetwork.get_all_meridians` returns a `Dictionary`'s insertion order, which is
## the order the defs were AUTHORED in (lung, large_intestine, stomach, spleen), while
## `broad_sites` sorts its own `Array[StringName]`. The two orders agree here only
## because these twenty ids share a prefix and differ in a single digit, and
## `StringName`'s comparison — which falls back to the handle when the pointers differ —
## is NOT the text order that `String` gives. Sorting `String` values is the form whose
## order a reader can check by eye.
##
## Previously this returned the network's authored order, so the sweep loop was
## comparing an implementation against itself, twice unsorted: "the sweep really is in
## sorted id order" was never actually being checked.
func _meridian_ids(actor: Actor) -> Array[StringName]:
	var sorted: Array[String] = []
	for state in actor.meridians.get_all_meridians():
		sorted.append(String(state.id))
	sorted.sort()
	var out: Array[StringName] = []
	for id in sorted:
		out.append(StringName(id))
	return out


## The acupoint bound to one meridian on this actor, read through the authored map the
## mechanism itself uses (`BodyLocation.meridian_of_point`), so a test asserting on a
## point is asserting on the same partition the location axis saw.
func _points_on(actor: Actor, meridian_id: StringName) -> Array[Acupoint]:
	var out: Array[Acupoint] = []
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null:
		return out
	for point in points.points:
		if BodyLocation.meridian_of_point(point.id) == meridian_id:
			out.append(point)
	return out


## The `body_integrity` pool's maximum, read off the actor. 0.0 when there is none.
func _integrity_maximum(actor: Actor) -> float:
	var pool: ResourcePool = actor.resource(BodyStats.BODY_INTEGRITY)
	return 0.0 if pool == null else pool.maximum


## A defender on one open `lung` with `points` of extra `DEFENSE_PHYSICAL` — the case
## almost every floor and armour assertion needs, and the one place the two parameters
## are named. Shared rather than copied into the floor and formula suites for the reason
## `PHYSIQUE` is: a second copy of "a walled body" is a second chance for the two files
## to disagree about what a wall IS.
func _walled(points: float, state: StringName = MeridianState.OPEN) -> Actor:
	var target := _defender(["lung"], {"lung": state})
	_armour(target, points)
	return target


## One wound's worth of severity, expressed the way `BodyWounds.add` measures it, so a
## suite can hand the ledger an exact fraction of a threshold and land on it.
func _severity_for(actor: Actor, share: float) -> float:
	return share * _integrity_maximum(actor)


## The tissue weighting ADR 0070's formula adds to `D` exactly once:
## `tissue = tissue_scale * (sum of stat x archetype weight) / divisor`, for the HEAVIEST
## archetype weight in `CombatTuning.tissue_weights` — found the same way
## `BodyDamage._weights_of` ranks, so the two cannot disagree about which archetype a body
## is described by, and a balance pass that re-weights the archetypes moves this with it
## rather than stranding a literal here.
##
## It lives on the FIXTURE rather than in `test_body_damage.gd` because ADR 0200 turned
## "the ladder's own contribution to `D`" into something two suites have to subtract: this
## file measures the ladder (`D - tissue`) and `test_body_damage.gd` measures the whole of
## `D`. Two copies of the weighting would be two chances for them to disagree, and a
## disagreement there is a disagreement about what armour IS.
func _tissue_expectation(target: Actor) -> float:
	var heaviest := 0.0
	var heaviest_total := 0.0
	for key in _tuning.tissue_weights.keys():
		var row: Array = _tuning.tissue_weights[key]
		var sum := 0.0
		for value in row:
			sum += absf(float(value))
		if sum > heaviest_total:
			heaviest_total = sum
			heaviest = sum / maxf(1.0, float(row.size()))
	var total := 0.0
	for index in _tuning.tissue_stat_ids.size():
		total += target.stats.derived(StringName(_tuning.tissue_stat_ids[index])) * heaviest
	return _tuning.tissue_scale * total / _tuning.tissue_stat_divisor


## The penetration ADR 0200's ratio produces, re-derived from the mechanism's OWN
## published primitives rather than pasted as a literal.
##
## ## Why this helper exists at all
##
## Before ADR 0200 the identity every body suite asserted was
## `maxf(gross - resistance, gross * min_penetration_ratio)` — a subtraction of hit points
## off a blow. `body_damage.gd` replaced it with
## `maxf(gross * (1 - mitigation_ceiling * D_eff / (K + D_eff)), gross * min_penetration_ratio)`
## and a FOUR-TERM identity replaced the two-term one, so every suite that re-derived the
## old shape had to be rewritten. One shared derivation is the same discipline this file
## already applies to the actor arithmetic: the alternative is four copies of the ratio in
## four files, which drift and which a reader then has to reconcile against
## `body_damage.gd`'s own docblock.
##
## It reads `defense_effective`, `divisor_k`, `mitigation_rate` and `floor` off the row
## under test rather than off the tuning, so a copy of the tuning with one field replaced
## (which several suites build) is priced by ITS OWN numbers and not by the shipped ones.
func _expected_penetration(parts: Dictionary) -> float:
	var gross := float(parts["gross"])
	return maxf(gross * (1.0 - float(parts["mitigation_rate"])), float(parts["floor"]))


## The mitigation rate ADR 0200's ratio produces for one armour figure and one gross,
## recomputed from the tuning rather than from the row. Used where a suite has to DERIVE an
## expectation instead of reading one — the whole point of the derivation is that it does
## not trust the number it is checking.
func _expected_mitigation_rate(defence: float, gross: float, tuning: CombatTuning) -> float:
	var ceiling := clampf(tuning.mitigation_ceiling, 0.0, 1.0)
	if ceiling <= 0.0:
		return 0.0
	var k := maxf(0.0, tuning.defense_divisor_k * gross)
	var denominator := k + absf(defence)
	if denominator <= 0.0:
		return 0.0
	var share := absf(defence) / denominator if defence >= 0.0 else 2.0 - k / denominator
	return ceiling * share
