extends TestCase

## ADR 0071's three erosion KINDS, and the one line of production that decided all
## three were `DISRUPT`.
##
## ## Why this file exists at all
##
## `CombatBoot.ctx_builder_for` hardcoded `MindDamage.builder(MindDamage.Kind.DISRUPT, ...)`
## on a literal. A hardcoded kind is not a conservative default — it is a switch held at
## one position, and two of the three settings cannot be reached from anywhere in
## `game/src`:
##
##   - `_illusion_resistance_of` returns `0.0` for anything but `OBSCURE`, so the
##     illusion branch of `_mitigation_of` never ran and `ILLUSION_RESISTANCE` was a
##     stat no attack in the game ever read;
##   - `_awareness_delta_of` returns `0.0` for anything but `ATTEND`, so the AWARENESS
##     reserve ADR 0152 gave a writer was never spent by an attack — the reserve existed,
##     a drain existed, and nothing connected them.
##
## `mind_illusion_lattice.tres` is authored as an illusion (its own `tags` include
## `&"illusion"`) and resolved as a plain disrupt.
##
## ## Every case here goes through the PRODUCTION builder
##
## Nothing in this file calls `MindDamage.builder` or builds an `AttackContext` by hand.
## A suite that drove `breakdown` on a hand-staged context would still be green on the
## day the hardcoded literal came back, because the context would carry the kind the
## test staged rather than the kind production resolves. The subject under test is
## `CombatBoot.ctx_builder_for`, so it is the thing every assertion below exercises.
##
## ## The actors are built the way PRODUCTION builds them
##
## `ActorFactory.with_mind_cultivation`, not a fixture that hand-attaches a sea — the
## same argument `test_combat_boot.gd` opens with. A fixture that supplies what
## production withholds hides the hole instead of closing it.

## The three kinds as the authored `.tres` spells them. The field is a `StringName`
## precisely so `app/` never has to name `MindDamage.Kind` to carry one, and these are
## the spellings a designer types into a `.tres`.
const DISRUPT := &"disrupt"
const OBSCURE := &"obscure"
const ATTEND := &"attend"
## A technique authored before `TechniqueDef.mind_kind` existed: the field reads `&""`,
## which is what all 46 non-mind `.tres` files carry.
const UNAUTHORED := &""

## The base attributes a CREATED hero carries, handed to `ActorFactory.build` exactly as
## `CharacterCreationFlow._body` does (`build(race_id, base_stats)`).
##
## ## Why a fixture has to supply these at all
##
## `ActorFactory.build(&"seer")` with no base stats produces an actor whose
## `perception`, `mental_clarity` and `will` are all `0.0`, and every figure the two
## kinds under test read is DERIVED from exactly those:
##
##   - `illusion_resistance = minf(0.8, mental_clarity * 0.004 + will * 0.002)`, which
##     is `0.0` on a blank actor -- so an `OBSCURE` strike would read `0.0` for the same
##     reason a `DISRUPT` one does, and the pair of assertions below could not tell the
##     two kinds apart at all;
##   - the erosion is `0.0` for a sea with no `structural_capacity` (hole 2), and the
##     `ATTEND` drain is `awareness_ratio * erosion`, so it is `0.0` too.
##
## That is not a fixture papering over a defect: a hero with no allocated attributes has
## no mind attack and no illusion resistance in the real game either, and the honest
## reading for one is exactly `0.0`. The property under test is "the KIND selects which
## branch runs", and a blank actor cannot exhibit a difference between branches because
## both of them read zero. So the attributes go in, through the factory's own parameter,
## and everything after that is production.
const HERO_BASE := {
	MindStats.PERCEPTION: 20.0,
	MindStats.MENTAL_CLARITY: 30.0,
	Stat.WILL: 25.0,
	Stat.PHYSIQUE: 10.0,
}

## The same pair with the DEFENDER's `mental_defense` driven to `0.0`, which is the only
## way to make `_mitigation_of`'s `maxf` observable.
##
## ## Why a fixture has to do this at all
##
## `illusion_resistance` and `mental_defense` are BOTH derived from `mental_clarity` and
## `will`, and `mental_defense` grows roughly four times faster, so on any actor this
## `HERO_BASE` describes the saturating term `d/(d+base)` is already above
## `ILLUSION_RESISTANCE`. The `maxf` then cannot move — which is correct engine
## behaviour, and precisely why ADR 0071's "an illusion-resistance build and a clarity
## build are DIFFERENT defenders" needs a build that actually specialises.
##
## Zeroing `mental_defense` is the mechanical way to reach one. It is a DERIVED stat, so
## it cannot be set through a base attribute, and `ActorStats` applies a `FLAT` modifier
## as an OFFSET on the provider's contribution — so the modifier's value is measured, not
## restated, exactly as `mind_damage_fixture.gd:_pin_defense` documents. `FLAT` because a
## `PERCENT` on a derived rate would evaluate against its own baseline (BRIEF 1.8).
const LOW_DEFENSE_SOURCE := &"mind_kind_probe_defense"

# --- the actors production builds -----------------------------------------------


## An attacker who can actually produce a mind hit, and a defender whose sea is the
## denominator of it. Both enrolled through the factory verb `CombatBoot` gates on.
func _pair() -> Dictionary:
	var attacker := ActorFactory.with_mind_cultivation(ActorFactory.build(&"seer", HERO_BASE))
	var defender := ActorFactory.with_mind_cultivation(ActorFactory.build(&"ward", HERO_BASE))
	# `MindTraining.synchronize` seeds the sea's `structural_capacity` from the R1 seed,
	# so the denominator ADR 0071 divides by is present. Asserted rather than assumed:
	# every erosion figure below is `0.0` without it, and a suite that passed for that
	# reason would be measuring nothing.
	var sea := MindCultivationApi.sea(defender)
	assert_ne(sea, null, "the enrolled defender carries a sea")
	if sea != null:
		assert_eq(
			sea.structural_capacity > 0.0,
			true,
			"with the capacity that is the erosion's denominator"
		)
	return {"attacker": attacker, "defender": defender}


## The pair whose saturating term sits BELOW the defender's illusion resistance, so the
## `maxf` in `_mitigation_of` is the thing that decides the answer.
func _pair_low_defense() -> Dictionary:
	var pair := _pair()
	var defender: Actor = pair["defender"]
	var derived_before := defender.stats.derived(MindStats.MENTAL_DEFENSE)
	defender.stats.add_modifier(
		StatModifier.new(
			MindStats.MENTAL_DEFENSE, Stat.Op.FLAT, -derived_before, LOW_DEFENSE_SOURCE
		)
	)
	defender.mark_stats_dirty()
	return pair


## A mind technique carrying `kind`, built the way an authored `.tres` is: a
## `TechniqueDef` on the mind path, which is the whole of what
## `CombatBoot.mechanism_for_hit` reads to pick the mind builder.
func _technique(kind: StringName, def_id: StringName) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = def_id
	def.path = PathState.MIND
	def.mind_kind = kind
	return def


## The one `breakdown` row production produces for this attacker, this defender and
## this technique — built by `CombatBoot.ctx_builder_for` and run over a real
## `AttackContext` shaped the way `CombatSpine._context` shapes one.
##
## `pair` is a parameter rather than always [method _pair] so a row that needs a
## SPECIALISED defender — one whose saturating defence does not already dominate its
## illusion resistance — can build it through the same production path. Everything after
## the pair is identical either way.
func _production_parts(kind: StringName, def_id: StringName, pair: Dictionary = {}) -> Dictionary:
	var actors: Dictionary = pair if not pair.is_empty() else _pair()
	var attacker: Actor = actors["attacker"]
	var defender: Actor = actors["defender"]
	var technique := _technique(kind, def_id)
	var ctx := AttackContext.new(attacker, defender, technique, CombatEngineApi.tuning(), 100.0)
	var builder := CombatBoot.ctx_builder_for(attacker, defender, technique)
	var staged: Variant = builder.call(ctx)
	assert_ne(staged, null, "the production builder staged a context")
	return MindDamage.new().breakdown(staged as AttackContext)


# --- the illusion kind, and the stat that was dead ---------------------------


## An `OBSCURE` technique READS the defender's `ILLUSION_RESISTANCE`, through the
## production builder. This is the assertion the hardcoded literal made impossible:
## the row is `> 0.0` only because `ctx_builder_for` carried the authored kind, and
## `_illusion_resistance_of` reached its `OBSCURE` arm at all.
func test_an_obscure_technique_reads_illusion_resistance_in_production() -> void:
	var parts := _production_parts(OBSCURE, &"obscure_probe")
	assert_eq(String(parts["kind"]), "obscure", "the authored kind survived the builder")
	assert_eq(
		float(parts["illusion_resistance"]) > 0.0,
		true,
		"an OBSCURE strike reads ILLUSION_RESISTANCE, which the mechanism zeroes otherwise"
	)


## A `DISRUPT` technique does NOT, and the assertion is the mirror image rather than
## the absence of one: the same defender, the same production path, one authored word
## different. Two rows that both said "> 0.0" would prove the branch fires; only the
## pair proves it fires FOR `OBSCURE`.
func test_a_disrupt_technique_never_reads_illusion_resistance() -> void:
	var parts := _production_parts(DISRUPT, &"disrupt_probe")
	assert_eq(String(parts["kind"]), "disrupt", "the authored kind survived the builder")
	assert_almost_eq(
		float(parts["illusion_resistance"]),
		0.0,
		"a DISRUPT strike is answered by mental_clarity alone"
	)


## ## The two rows must be read on ONE non-saturating defender to differ
##
## ADR 0071 claims `OBSCURE` and `DISRUPT` are "different defenders of the same skill",
## and that claim is a claim about `_mitigation_of`'s `maxf(rate, ILLUSION_RESISTANCE)`
## against the saturating `d/(d+base)`. It is NOT a claim that `OBSCURE` always loses
## more: `rate` is already `saturating` on any ordinary hero, and a `maxf` against a
## SMALLER number cannot move it.
##
## So this row builds the specialised defender the file already documents and measures
## the engine's EXACT arithmetic rather than asserting a direction. The condition below
## is still stated rather than assumed, because which case the fixture lands in is a
## fact about its numbers and not a contract -- but the fixture is chosen so the first
## arm is the one taken, and the second arm remains reachable if a retune to
## `combat_damage.tres` ever removes the gap.
func test_the_obscuring_branch_is_exactly_a_maxf_against_the_saturating_term() -> void:
	var tuning := CombatEngineApi.tuning()
	# ONE defender for BOTH rows, and a SPECIALISED one. `_pair_low_defense` pins the
	# defender's `mental_defense` at `0.0`, which drops the saturating term to `0.0`
	# and leaves `ILLUSION_RESISTANCE` as the only thing `maxf` can raise. Two rows on
	# one defender differ by exactly one authored word, which is what makes the
	# comparison below a fact about the KIND and not about two actors' numbers.
	var pair := _pair_low_defense()
	var defend := _production_parts(DISRUPT, &"cap_probe", pair)
	var obscure := _production_parts(OBSCURE, &"cap_probe_obscure", pair)
	var defense := float(defend["mental_defense"])
	var base := float(defend["base"])
	var saturating := defense / (defense + base) if (defense + base) > 0.0 else 0.0
	var cap := _share(tuning.mental_defense_cap)
	# What the saturating term alone already refuses, before the branch runs.
	var rate := minf(saturating, cap)
	# `OBSCURE` is `maxf(minf(saturating, cap), ILLUSION_RESISTANCE)`, re-clamped to
	# `ILLUSION_RESISTANCE_CAP`. That is hole 1 through hole 3 of `mind_damage.gd` and
	# nothing else, so this row is the whole of what the branch does.
	assert_almost_eq(
		float(obscure["mitigation"]),
		minf(
			maxf(minf(saturating, cap), float(obscure["illusion_resistance"])),
			_share(tuning.illusion_resistance_cap)
		),
		"OBSCURE mitigation is exactly maxf(saturating, ILLUSION_RESISTANCE)"
	)
	assert_almost_eq(
		float(defend["mitigation"]),
		minf(saturating, cap),
		"and DISRUPT is exactly the saturating term alone"
	)
	# The read that DOES differ is the one the branch is for, and it is the stat the
	# engine now consults for exactly one of the three kinds. This is the assertion that
	# would have failed before `ctx_builder_for` stopped hardcoding DISRUPT.
	assert_eq(
		float(obscure["illusion_resistance"]) > float(defend["illusion_resistance"]),
		true,
		"while the ILLUSION_RESISTANCE the branch READS is strictly higher"
	)
	# ## What decides observability is NOT `saturating < cap`
	#
	# `rate` is `minf(saturating, cap)` -- the value the saturating term ALONE produces.
	# `maxf` can only raise it, so the branch is strictly observable exactly when
	# `ILLUSION_RESISTANCE > rate`. Asking instead whether `saturating` is below the cap
	# asks a different question: it holds on this hero (0.4603 < 0.6) and the `maxf` still
	# could not move, because 0.4603 was already ABOVE the 0.17 the branch read. That
	# guard was asserting a fact about the fixture's numbers while claiming to assert a
	# fact about the engine, and it failed the moment the fixture specialised the
	# defender it had always been given.
	if float(obscure["illusion_resistance"]) > rate:
		assert_eq(
			float(obscure["mitigation"]) > float(defend["mitigation"]),
			true,
			"this defender does not saturate, so the branch is strictly observable"
		)
	else:
		assert_almost_eq(
			float(obscure["mitigation"]),
			float(defend["mitigation"]),
			"this defender saturates, so maxf cannot move it -- the honest reading"
		)


## Internals


## A rate read out of the shipped tuning and clamped into `[0, 1]`, so the cap above is
## quoted from data rather than restated as a `0.6` a retune could invalidate.
func _share(value: Variant) -> float:
	return clampf(float(value), 0.0, 1.0) if (value is float or value is int) else 0.0


# --- the attend kind, and the reserve nothing was spending ---------------------


## An `ATTEND` technique DRAINS the AWARENESS reserve, through the production builder.
## `awareness_delta` is negative for `ATTEND` and `0.0` for everything else, so a
## non-zero reading here is the drain and nothing else is.
##
## The defender is held at a FULL reserve so the drain is at its largest: ADR 0071
## computes it as `awareness_ratio * erosion`, and an empty reserve would make the
## assertion pass for the wrong reason (a target with no awareness at all answers
## `0.0`, which is the same degradation every absent read on the file gives).
func test_an_attend_technique_drains_the_awareness_pool_in_production() -> void:
	var pair := _pair()
	var attacker: Actor = pair["attacker"]
	var defender: Actor = pair["defender"]
	var pool := _full_awareness(defender)
	var technique := _technique(ATTEND, &"attend_probe")
	var ctx := AttackContext.new(attacker, defender, technique, CombatEngineApi.tuning(), 100.0)
	var staged: Variant = CombatBoot.ctx_builder_for(attacker, defender, technique).call(ctx)
	var parts := MindDamage.new().breakdown(staged as AttackContext)
	assert_eq(String(parts["kind"]), "attend", "the authored kind survived the builder")
	assert_eq(
		float(parts["awareness_delta"]) < 0.0,
		true,
		"an ATTEND strike spends the reserve coherence is computed from"
	)
	# The effect the SPINE applies, not just the row: `awareness_delta` only becomes
	# health-adjacent state if the proposal carries it, and a panel reads the payload.
	var proposal := MindDamage.new().resolve(staged as AttackContext)
	assert_eq(
		float(proposal.effect_of(MindDamage.EFFECT_KIND)[MindDamage.KEY_AWARENESS]) < 0.0,
		true,
		"and the erosion effect carries the drain the applier will spend"
	)
	assert_ne(pool, null, "the defender really carried the reserve that was spent")


## A `DISRUPT` technique spends nothing from it. The mirror of the row above on the
## same defender at the same reserve, so the pair says ATTEND costs the reserve and
## nothing else does — which is what makes ATTEND a CHOICE the player makes rather
## than a name on a `.tres`.
func test_a_disrupt_technique_never_drains_the_awareness_pool() -> void:
	var pair := _pair()
	var attacker: Actor = pair["attacker"]
	var defender: Actor = pair["defender"]
	_full_awareness(defender)
	var technique := _technique(DISRUPT, &"disrupt_probe_3")
	var ctx := AttackContext.new(attacker, defender, technique, CombatEngineApi.tuning(), 100.0)
	var staged: Variant = CombatBoot.ctx_builder_for(attacker, defender, technique).call(ctx)
	var parts := MindDamage.new().breakdown(staged as AttackContext)
	assert_almost_eq(
		float(parts["awareness_delta"]), 0.0, "a DISRUPT strike leaves the AWARENESS reserve alone"
	)


# --- the default, and what production actually ships -------------------------


## An unauthored `.tres` resolves to `DISRUPT`, which is the contract the field's
## default has to keep: 46 of the 52 authored techniques carry no `mind_kind` at all,
## and none of them is a mind technique, so `&""` must not become a fourth meaning.
func test_a_technique_that_authored_no_kind_resolves_to_disrupt() -> void:
	var parts := _production_parts(UNAUTHORED, &"unauthored_probe")
	assert_eq(
		String(parts["kind"]),
		"disrupt",
		"an unauthored def is the plain strike, exactly as it was before the field"
	)


## A null or non-object technique degrades to the same plain strike. `mechanism_for_hit`
## already treats a technique as untrusted (`technique is Object` before it asks it
## anything), and a combat tick must not be the place that assumption is first tested.
func test_a_missing_technique_degrades_to_disrupt_rather_than_crashing() -> void:
	var pair := _pair()
	var attacker: Actor = pair["attacker"]
	var defender: Actor = pair["defender"]
	var ctx := AttackContext.new(attacker, defender, null, CombatEngineApi.tuning(), 100.0)
	var staged: Variant = CombatBoot.ctx_builder_for(attacker, defender, null).call(ctx)
	assert_ne(staged, null, "the builder still staged a context")
	assert_eq(
		String(MindDamage.new().breakdown(staged as AttackContext)["kind"]),
		"disrupt",
		"and the plain strike is what it staged"
	)


## The shipped `.tres` files, read through production, carry the kinds their own
## descriptions claim. This is the authored-content half of the gap: `illusion_lattice`
## tags itself `illusion`, and if the file were edited back to no `mind_kind` this
## fails — which no fixture built in a test could ever catch, because a fixture authors
## the field it is asserting about.
func test_the_shipped_mind_techniques_carry_their_kinds_in_production() -> void:
	for entry in [
		{"path": "res://data/techniques/mind_illusion_lattice.tres", "kind": "obscure"},
		{"path": "res://data/techniques/mind_abyssal_drown.tres", "kind": "obscure"},
		{"path": "res://data/techniques/mind_glare_of_warding.tres", "kind": "attend"},
		{"path": "res://data/techniques/mind_prime_autopsy.tres", "kind": "attend"},
	]:
		var def := load(String((entry as Dictionary)["path"])) as TechniqueDef
		assert_ne(def, null, "%s loads as a TechniqueDef" % String((entry as Dictionary)["path"]))
		if def == null:
			continue
		var parts := _production_parts(def.mind_kind, def.id)
		assert_eq(
			String(parts["kind"]),
			String((entry as Dictionary)["kind"]),
			(
				"%s resolves to the kind its own description claims"
				% String((entry as Dictionary)["path"]).get_file()
			)
		)


## Internals


## The defender's AWARENESS reserve held FULL, read back off the pool so an assertion
## states the ratio it measured. ADR 0071's drain is `awareness_ratio * erosion`, so a
## partly-spent reserve would weaken every row above for reasons that are not under
## test.
func _full_awareness(defender: Actor) -> ResourcePool:
	var pool := defender.resource(MindStats.AWARENESS) as ResourcePool
	if pool != null and pool.maximum > 0.0:
		pool.current = pool.maximum
	return pool
