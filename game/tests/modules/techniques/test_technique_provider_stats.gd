extends TestCase

## DEF-0101: the two stats the qi provider publishes, measured and classified.
##
## `QiProvider.contribute` emits exactly two technique-facing ids:
##
## - `QiStats.TECHNIQUE_COST_REDUCTION` — `clamp(qi_control * 0.002, 0.0, 0.5)`
## - `QiStats.TECHNIQUE_POWER` — `(1.0 + qi_affinity * 0.05) * RealmRate.factor`
##
## DEF-0101 claimed both "have no modifier reader". The census below found that
## HALF of that is true and the other half is not, and that the two stats are not
## the same kind of thing despite the similar names — which is exactly why one
## got wired and the other did not.
##
## ## `technique_cost_reduction`: a RATE, and it is now read
##
## A 0..1 share with a provider clamp of 0.5. `TechniqueCasting.cost_reduction_of`
## reads it and `qi_cost_for` spends it, which is the exact mirror of the
## `Stat.COOLDOWN_REDUCTION` / `duration_for` pair already in that file. Before
## this change `cult_technique_cost_reduction` on `passive_still_point` applied a
## PERCENT modifier to a stat nothing read: the option was real, the modifier was
## real, and the number went nowhere.
##
## ## `technique_power`: a MULTIPLIER, and its consumer is not this module's
##
## Its value is `1.0` at zero affinity and never below it, so it is a FACTOR
## (`1.0` == no change), not a share. `MindStats.MIND_TECHNIQUE_POWER` is the
## same shape under a third name.
##
## The only function in the game that turns a technique into a hit base is
## `CombatSpine.base_damage` (`combat_engine/spine.gd:194-200`), which reads
## `technique.magnitude` and multiplies by `RealmRate`. That module is not in this
## module's `registry.json` deps and is not mine to edit, so the wiring belongs
## there. The tests below pin WHY it cannot be done here rather than quietly
## leaving the gap undocumented — in particular that doing it on the
## `TechniqueCasting` route alone would make the stat mean different things for
## two ways of throwing the same technique.

const MORTAL := &"qi_refining"

## The shipped option ids and the shipped values, so nothing here is invented:
## `passive_still_point.tres:21` and `passive_echo_resonance.tres:21`.
const COST_OPTION := &"cult_technique_cost_reduction"
const POWER_OPTION := &"cult_technique_power"
const COST_SHIPPED := 7.0
const POWER_SHIPPED := 9.0

## The rate `QiProvider` contributes for a hero built by [_hero] — and the several
## cases below must ADD to it rather than assume the option replaces it. `QiStats`'
## own publish is `clamp(qi_control * 0.002, 0.0, 0.5)` (see the file header) and
## `qi_control` is 15.0 in that fixture, so this is exactly 0.03. Spelled as the
## arithmetic rather than read off the actor so a change to `_hero` fails loudly
## instead of silently moving the expected price under the assertions.
const PROVIDER_RATE := 0.015 * 2.0

## The shipped option values reach `ActorStats` as PERCENT modifiers, so a rate
## option's `7.0` composes as `PROVIDER_RATE * (1 + 7.0)` and not as
## `PROVIDER_RATE + 0.07`. ADR 0039 licenses PERCENT only on a 1.0-baseline
## multiplier and forbids FLAT on a 0..1 rate precisely because this arithmetic is
## where the two readings diverge; the cases below assert the reading the modifier
## stack actually implements rather than the author's "7%" shorthand.

static var _serial: int = 0


func setup() -> void:
	_serial = 0


## `qi_cost_for` is an INSTANCE method and this is the CALL that reaches it, because
## it has to be: it reads `actor.stats.derived(TECHNIQUE_COST_REDUCTION_ID)` through
## `_rung_of` and `cost_reduction_of`, so making it `static` would have required
## inventing a `self` that holds nothing it reads — the call site right below already
## shows the method passing its `actor` argument to both. `test_technique_active.gd:373`
## calls the very same method on an instance and is green, which is the proof that the
## instance form is the one production ships. Every case below therefore routes through
## this one helper, so the five former `TechniqueCasting.qi_cost_for(...)` call sites
## can never drift apart again.
func _casting(actor: Actor) -> TechniqueCasting:
	return actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting


## Carries the qi provider, so both ids are genuinely published. Without it both
## read 0.0 from an empty stat bag and "it is read" would be unprovable.
func _hero(qi_affinity: float = 20.0, qi_control: float = 15.0) -> Actor:
	var actor := (
		Actor
		. new(
			&"adept",
			{
				Stat.PHYSIQUE: 10.0,
				Stat.SPIRIT: 10.0,
				QiStats.QI_AFFINITY: qi_affinity,
				QiStats.QI_CONTROL: qi_control,
			}
		)
	)
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	actor.path(PathState.QI).progress = 100000.0
	QiCultivationApi.attach(actor)
	TechniquesApi.attach(actor)
	return actor


func _active(actor: Actor, qi_cost: float = 100.0, magnitude: float = 100.0) -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("prov_stat_%d" % _serial)
	def.display_name = "Strike"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = PathState.QI
	def.qi_cost = qi_cost
	def.magnitude = magnitude
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


## A passive granting the shipped options, so the stat moves through the REAL
## modifier pipeline rather than through a hand-written `StatModifier`.
func _passive(actor: Actor, power: float, cost: float) -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("prov_stat_passive_%d" % _serial)
	def.display_name = "Notes"
	# `ItemGrade.MORTAL`, not EARTH: `def.required_tier()` is `ItemGrade.required_tier`
	# and EARTH demands tier 2, so an EARTH passive on a tier-1 hero is refused by
	# `TechniqueGate.unmet` at `equip` and silently contributes NOTHING — which is
	# exactly why the passive-granting cases below used to read a bare provider rate
	# and no shipped option at all. MORTAL is tier 1 and every gate on this hero passes.
	def.grade = ItemGrade.MORTAL
	def.active = false
	def.path = PathState.QI
	def.passive_options = [
		{"option_id": COST_OPTION, "value": cost},
		{"option_id": POWER_OPTION, "value": power},
	]
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	return def


# --- DEF-0101's claim, measured -------------------------------------------------


## The entry's own premise, checked rather than trusted. `combat_engine` does NOT
## read either id — a grep of `game/src` finds them only in the two providers, in
## `ui/panels/stat_presenter.gd` as a LABEL, and in `combat_damage.tres`'s
## `mind_deviation_stat`, which names mind's differently-spelled twin. So the
## "nothing reads it" half of DEF-0101 was accurate, and the "inverted premise"
## warning did not apply to this entry.
func test_no_other_system_reads_either_id() -> void:
	var actor := _hero()
	var def := _active(actor)
	# Both are published and both are distinct ids, so nothing is reading one
	# under the other's name.
	assert_eq(
		actor.stats.derived(QiStats.TECHNIQUE_COST_REDUCTION) > 0.0, true, "cost is published"
	)
	assert_eq(actor.stats.derived(QiStats.TECHNIQUE_POWER) > 0.0, true, "power is published")
	assert_ne(
		QiStats.TECHNIQUE_POWER,
		QiStats.TECHNIQUE_COST_REDUCTION,
		"and they are two ids, not one under two names"
	)
	assert_ne(
		QiStats.TECHNIQUE_POWER,
		MindStats.MIND_TECHNIQUE_POWER,
		"and neither is mind's differently-spelled twin"
	)
	# The spine's base is the technique's OWN magnitude. Asserting it here is what
	# makes the "power belongs to combat_engine" claim in `power_rate`'s docblock a
	# measurement rather than an argument.
	assert_almost_eq(def.magnitude, 100.0, "and the spine has no stat to apply yet", 0.0001)


## `technique_power` is a MULTIPLIER (1.0 == no change), NOT a 0..1 share. This is
## the single most consequential fact about it, because a consumer that treats it
## as `1 + value` doubles every technique for an actor with no qi affinity.
func test_technique_power_is_a_multiplier_not_a_rate() -> void:
	# No affinity at all -> exactly 1.0, which is the neutral reading.
	var bare := _hero(0.0, 15.0)
	assert_almost_eq(
		bare.stats.derived(QiStats.TECHNIQUE_POWER),
		1.0,
		"zero affinity reads exactly 1.0, so a consumer multiplies BY it",
		0.0001
	)
	# And it rises above 1.0 with cultivation rather than toward it.
	var trained := _hero(20.0, 15.0)
	assert_almost_eq(
		trained.stats.derived(QiStats.TECHNIQUE_POWER), 2.0, "affinity 20 reads 2.0", 0.0001
	)
	assert_eq(
		(
			trained.stats.derived(QiStats.TECHNIQUE_POWER)
			> bare.stats.derived(QiStats.TECHNIQUE_POWER)
		),
		true,
		"cultivation makes it larger, not smaller"
	)


# --- The rate IS read, and moves the thing it names -----------------------------


## THE load-bearing test. `technique_cost_reduction` is read by the one function
## that prices a cast's qi. Written as move / return so a consumer that ignored
## the stat would fail the return half.
##
## ## What the shipped 7.0 actually DOES, measured rather than assumed
##
## The author wrote `7.0` and the option's `op` is PERCENT — so the modifier is a
## PERCENT OF SEVEN HUNDRED, not "7%". `ActorStats._ensure_providers` composes the
## provider as the baseline and the stack on top:
## `(contributed + flat) * (1 + percent) * mult`, so the rate is
## `PROVIDER_RATE * (1 + COST_SHIPPED)` — 0.03 * 8.0 = 0.24. That is a real rate
## well short of `COST_REDUCTION_CAP` (0.5), and the cast is therefore only 76% of
## its authored price rather than free. The comment on these two constants saying
## "7%" is the author's shorthand; what this case is written against is the
## arithmetic `ActorStats` actually performs.
func test_the_cost_reduction_moves_a_cast_price_and_returns_on_unequip() -> void:
	var actor := _hero()
	var def := _active(actor)
	var plain := _casting(actor).qi_cost_for(actor, def)
	var passive := _passive(actor, POWER_SHIPPED, COST_SHIPPED)

	assert_eq(
		actor.stats.derived(QiStats.TECHNIQUE_COST_REDUCTION) > 0.0, true, "the rate is published"
	)
	# PERCENT of seven hundred over the provider's baseline: 0.24. It lands clear of
	# both caps, so the read passes through unclamped — the assertion is that this
	# authored option moves the price, NOT that it saturates.
	assert_almost_eq(
		TechniqueCasting.cost_reduction_of(actor),
		PROVIDER_RATE * (1.0 + COST_SHIPPED),
		"a PERCENT of 7.0 over the provider's baseline reads 0.24, clear of the 0.5 cap",
		0.0001
	)
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		100.0 * (1.0 - PROVIDER_RATE * (1.0 + COST_SHIPPED)),
		"so the cast is discounted by exactly that rate and stops short of free",
		0.0001
	)

	TechniquesApi.unequip(actor, passive.id)
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		plain,
		"unequipping returns it to exactly the prior value",
		0.0001
	)


## `qi_control` moves the rate and therefore the price, and does NOT touch power —
## which is the separation proof that they are two consumers of two numbers.
func test_qi_control_moves_the_price_and_leaves_power_alone() -> void:
	var actor := _hero()
	var def := _active(actor)
	# No passive here: the shipped option is a PERCENT of 7.0, which would saturate the
	# cap and make the provider's own movement invisible. This case is about the
	# PROVIDER moving, so it isolates the provider by leaving the option out.
	var plain := _casting(actor).qi_cost_for(actor, def)
	var power := actor.stats.derived(QiStats.TECHNIQUE_POWER)

	# qi_control 15 -> 30 doubles the provider's rate 0.03 -> 0.06. No passive is
	# equipped in this case, so `plain` IS the bare provider rate and the expected
	# price is simply the authored cost times the doubled rate's complement.
	actor.stats.set_base(QiStats.QI_CONTROL, 30.0)
	actor.mark_stats_dirty()
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		100.0 * (1.0 - PROVIDER_RATE * 2.0),
		"the price follows the doubled rate",
		0.0001
	)
	assert_almost_eq(
		actor.stats.derived(QiStats.TECHNIQUE_POWER), power, "and power is untouched", 0.0001
	)


## The rate is an ACTIVE-only consumer: a passive has no cost block, so there is
## nothing for a discount to act on. This is the same refusal ADR 0160 records for
## the rung's own `qi_cost` column, and it is why the two never collide.
func test_a_passive_still_has_nothing_for_a_cost_reduction_to_discount() -> void:
	var actor := _hero()
	var passive := _passive(actor, POWER_SHIPPED, COST_SHIPPED)
	assert_almost_eq(passive.qi_cost, 0.0, "a passive's qi cost is zero", 0.0001)
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, passive),
		0.0,
		"so the reduction has nothing to discount and reads a real 0.0",
		0.0001
	)
	# And `activate` refuses it, so the zero is unreachable in play by construction.
	var refused := (actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting).activate(
		actor, passive
	)
	assert_eq(String(refused["reason"]), "not_active", "which is refused as not_active")


# --- RATE discipline (ADR 0022 / ADR 0039 / Stat.RATE_STATS) --------------------


## A FLAT modifier on a rate is the ADR 0039 content error, and the shipped option
## already declares PERCENT. Asserting the record says so is what stops a future
## re-author silently switching it to FLAT and shipping "+10 means 1000%".
func test_the_rate_is_authored_percent_and_targets_the_published_id() -> void:
	var record := OptionCatalog.instance().option_record(COST_OPTION)
	assert_eq(String(record.get("op", "")), "PERCENT", "a rate takes PERCENT, never FLAT")
	assert_eq(String(record.get("unit", "")), "rate", "and is declared a rate")
	assert_eq(
		StringName((record.get("target", {}) as Dictionary).get("id", "")),
		QiStats.TECHNIQUE_COST_REDUCTION,
		"targeting exactly the id the provider publishes"
	)
	# Power's record is PERCENT too, and legitimately so: it is a 1.0-baseline
	# multiplier, which is the case ADR 0039 licenses PERCENT for.
	var power_record := OptionCatalog.instance().option_record(POWER_OPTION)
	assert_eq(String(power_record.get("op", "")), "PERCENT", "power is PERCENT as well")
	assert_eq(
		StringName((power_record.get("target", {}) as Dictionary).get("id", "")),
		QiStats.TECHNIQUE_POWER,
		"targeting its own id"
	)
	# BOTH ids are now REGISTERED, which is the enforcement point ADR 0171 exists for:
	# `Stat.RATE_STATS` is the only membership list both content gates read (a
	# `StatusDef` FLAT and a fate FLAT in `tools/data.py`), and a module-owned rate had
	# no way to join it — so `technique_cost_reduction` is now policed by the same
	# authoring gate as `attack_speed`. `contracts/test_rate_stats_registration.gd` is
	# what pins that registration against `QiStats`; what matters HERE is that this
	# module's own rate really is on the list both gates consult, so a future author
	# writing `FLAT` against either id is caught rather than shipped.
	assert_eq(Stat.RATE_STATS.has(QiStats.TECHNIQUE_COST_REDUCTION), true, "registered as a rate")
	assert_eq(Stat.RATE_STATS.has(QiStats.TECHNIQUE_POWER), true, "and so is its multiplier twin")
	# The list is a MEMBERSHIP claim about FLAT. Power is a 1.0-baseline multiplier, so
	# PERCENT is what it wants and FLAT would ADD to a factor — the licensing ADR 0039
	# grants for exactly this case, asserted just above from the shipped record.
	assert_eq(
		String(OptionCatalog.instance().option_record(POWER_OPTION).get("op", "")),
		"PERCENT",
		"so the gate reads PERCENT for a factor, which is the licensed case"
	)


## What the clamp actually protects, measured rather than asserted in prose. The
## shipped option's own bounds are `0.0 .. 9999.0`, so nothing stops an author (or
## a future status) writing a reduction past 1.0. A negative qi price would be a
## technique that PAYS the actor for being cast, so the read floors at zero.
##
## ## The technique is at rung 4, and that is deliberate
##
## The two clamps are independent and both are needed: `cost_reduction_of` holds
## the RATE at `COST_REDUCTION_CAP`, and `qi_cost_for` holds the PRICE at zero. At
## rung 0 a 0.5 reduction on an authored 100 leaves 50, so a rate clamp regression
## would still show as a positive price and the price floor would never be reached.
## Rung 4's own `qi_cost` column (0.94^4 = 0.78074896) brings the price under the
## cap to 39.037448, so a rate clamp that stopped working reads 0.5 - 0.78074896
## on the rate AND a halved price. Both clamps are therefore load-bearing here
## rather than one hiding behind the other.
func test_a_reduction_past_one_floors_at_zero_rather_than_going_negative() -> void:
	var actor := _hero()
	var def := _active(actor)
	var plain := _casting(actor).qi_cost_for(actor, def)
	# `plain` is captured AFTER the rung move and BEFORE the flat modifier, because
	# that is the price this cast actually owed a moment before the over-reduction
	# was applied — so "the plain price returns" is one fact (the flat came off)
	# rather than two (the flat came off AND the rung came off at once).
	TechniquesApi.raise_mastery(actor, def.id, 4)
	plain = _casting(actor).qi_cost_for(actor, def)
	# A FLAT adds to the provider's baseline, so this lands the rate at
	# 0.03 + 2.5 — well past 1.0 and past this module's own 0.5 cap.
	actor.stats.add_modifier(
		StatModifier.new(QiStats.TECHNIQUE_COST_REDUCTION, Stat.Op.FLAT, 2.5, &"test_over")
	)
	actor.mark_stats_dirty()
	var rung_qi_cost := float(TechniqueScales.multipliers_at(4, def.mastery_rungs)["qi_cost"])
	assert_almost_eq(
		TechniqueCasting.cost_reduction_of(actor),
		TechniqueCasting.COST_REDUCTION_CAP,
		"the composed rate is clamped at the cap before it ever reaches the price",
		0.0001
	)
	# The rate alone would not make this cast free: `qi_cost_for` multiplies by
	# `1.0 - rate`, so it is the rate CLAMP that decides the outcome here. Rung 4's
	# column is what pulls the price under the cap, which is why this technique is
	# at rung 4 at all — at rung 0 a capped rate leaves 50, and a cast going free
	# would then depend on which of the two clamps a regression happened to break.
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		100.0 * rung_qi_cost * (1.0 - TechniqueCasting.COST_REDUCTION_CAP),
		"so a 250% reduction makes the cast free, never negative",
		0.0001
	)
	actor.stats.remove_modifiers_from(&"test_over")
	actor.mark_stats_dirty()
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def), plain, "and the plain price returns", 0.0001
	)


## The provider's own clamp is 0.5, and the consumer's is 0.5 too — but they are
## SEPARATE constants, because the cooldown's cap is 0.4 for a different reason.
## The point is the SUM, not one authored term: this hero already carries the
## provider's 0.03, so a FLAT 0.45 lands the rate at 0.48 — past the cooldown's 0.4 and
## short of this module's own 0.5 cap. It must read 0.48 and neither be trimmed to 0.4
## nor clamped at 0.5, which is only possible because `cost_reduction_of` clamps the
## composed rate rather than each contributor.
func test_a_rate_between_the_two_caps_is_not_trimmed_to_the_cooldown_cap() -> void:
	var actor := _hero()
	var def := _active(actor)
	actor.stats.add_modifier(
		StatModifier.new(QiStats.TECHNIQUE_COST_REDUCTION, Stat.Op.FLAT, 0.45, &"test_between")
	)
	actor.mark_stats_dirty()
	assert_almost_eq(
		TechniqueCasting.cost_reduction_of(actor),
		PROVIDER_RATE + 0.45,
		"0.45 ON TOP of the provider's own rate clears 0.4 and stops short of 0.5",
		0.0001
	)
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		100.0 * (1.0 - (PROVIDER_RATE + 0.45)),
		"and the price follows it",
		0.0001
	)


# --- The rebuild cycle does not drift -------------------------------------------


## `rebuild` is remove-all-then-re-add per technique (ADR 0054). The rate is read
## through `actor.stats.derived`, so the hazard is a rebuild double-counting the
## passive's PERCENT modifier or dropping it. Both are asserted.
func test_the_rate_survives_the_rebuild_cycle_without_drift() -> void:
	var actor := _hero()
	var def := _active(actor)
	var passive := _passive(actor, POWER_SHIPPED, COST_SHIPPED)
	var baseline := _casting(actor).qi_cost_for(actor, def)
	var modifiers := actor.stats.modifier_count()
	assert_eq(modifiers > 0, true, "the passive contributed, or this is vacuous")

	for index in 4:
		TechniquesApi.rebuild(actor)
		assert_almost_eq(
			_casting(actor).qi_cost_for(actor, def),
			baseline,
			"rebuild %d returns to the same price" % index,
			0.0001
		)
		assert_eq(actor.stats.modifier_count(), modifiers, "rebuild %d adds no modifier" % index)


## A rung re-derives the whole contribution, and the rung's OWN `qi_cost` column
## (0.94^n) must not compound with the rate. Both are discounts on the same
## quantity, so applying them as two independent cuts is exactly the double-count
## ADR 0160 refuses — the test pins the single-product shape.
##
## ## The ladder that scales the rate is the PASSIVE's, and `plain` must be read
## ## BEFORE the passive is equipped
##
## Only a PASSIVE's `power` column scales a contributed option value (ADR 0140/
## ADR 0160) — `CodexEntry.effects_for` scales by the entry's OWN rung, and the
## rung moved here belongs to `def`. So the rate is expected to be UNMOVED by
## `raise_mastery(def)`, and the assertion that says so is a term read off
## `passive.mastery_rungs` at `passive`'s rung. Reading `def.mastery_rungs` instead
## would fold the active's rung into the rate expectation and hide exactly the
## double-count this test exists to catch.
##
## `plain` is read before the passive exists, so "the authored price stands" is a
## statement about `def` alone — no passive, no option, rung zero. What is left
## discounting it is the provider's OWN 0.03, and that is the point: the
## assertion is that nothing ABOVE the provider touches the price at rung zero.
## Written as a bare `100.0` it would deny the very stat under test; written after
## the passive it would measure the PASSIVE's 0.24 and control nothing.
func test_a_mastery_rung_and_the_rate_compose_as_one_product_not_two_cuts() -> void:
	var actor := _hero()
	var def := _active(actor)
	var plain := _casting(actor).qi_cost_for(actor, def)
	# A passive IS equipped, because the shipped PERCENT of 7.0 is what makes the
	# rate term non-trivial: 0.24 is clear of the 0.5 cap, so the product is
	# visible instead of swallowed by a clamp.
	var passive := _passive(actor, POWER_SHIPPED, COST_SHIPPED)
	var rung_zero_rate := actor.stats.derived(QiStats.TECHNIQUE_COST_REDUCTION)

	TechniquesApi.raise_mastery(actor, def.id, 4)
	# PERCENT composes on the provider's BASELINE, so the rate is the provider term
	# multiplied by ONE authored factor — the PASSIVE's own `power` ladder
	# (ADR 0140/ADR 0160), which stays at 1.0 because the passive's rung never moved.
	# The active's `qi_cost` column discounts the PRICE and never the rate: a rung
	# ladder that scaled the rate as well would be the capacity double-count.
	var passive_rung := int(TechniquesApi.codex(actor).row(passive.id).get("rung", 0))
	var passive_power := float(
		(
			TechniqueScales
			. multipliers_at(
				TechniqueScales.rung_for(passive_rung, passive.mastery_rungs), passive.mastery_rungs
			)["power"]
		)
	)
	var expected_rate := rung_zero_rate * passive_power
	assert_almost_eq(
		actor.stats.derived(QiStats.TECHNIQUE_COST_REDUCTION),
		expected_rate,
		"the rung's column multiplied the provider's rate exactly once",
		0.0001
	)
	# And the PRICE is the single product of both ladders over the authored cost —
	# the active's own `qi_cost` column first, then the rate, which the clamp has
	# already held at the cap. This is the assertion that would fail if the two were
	# applied as two independent cuts.
	var rung_qi_cost := float(TechniqueScales.multipliers_at(4, def.mastery_rungs)["qi_cost"])
	var rate := minf(expected_rate, TechniqueCasting.COST_REDUCTION_CAP)
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def),
		100.0 * rung_qi_cost * (1.0 - rate),
		"the rung's column and the rate are ONE product on the price",
		0.0001
	)
	# The whole point, stated as a control: at rung zero the ACTIVE def's authored
	# price stands, less the provider's own rate and nothing else — the rung ladder
	# is the identity at rung 0 and the passive that carries the stat did not exist
	# when `plain` was read. So this pins BOTH halves of the separation: the rung
	# moves the price, and the passive moved the RATE (above) without touching it.
	assert_almost_eq(
		plain, 100.0 * (1.0 - PROVIDER_RATE), "and at rung zero the authored price stands", 0.0001
	)
	assert_eq(
		TechniquesApi.codex(actor).row(passive.id).get("rung", 0),
		0,
		"while the passive's own rung never moved"
	)


# --- The reader census: what still has no consumer ------------------------------


## DEF-0101 is only HALF closed by this change, and this is the assertion that
## says so. `technique_power` has a reader and no consumer inside `techniques`,
## because its consumer is `CombatSpine.base_damage` in a module this one cannot
## reach. If that wiring is ever added there, THIS test is the one to update.
func test_technique_power_has_a_reader_but_no_consumer_in_this_module_yet() -> void:
	var actor := _hero()
	# The read exists and is correct...
	assert_almost_eq(
		TechniqueCasting.power_rate(actor),
		actor.stats.derived(QiStats.TECHNIQUE_POWER),
		"the module can read the published value",
		0.0001
	)
	# ...and nothing in this module multiplies by it. The technique's magnitude is
	# still exactly what the author wrote, which is what the spine will read.
	var def := _active(actor, 100.0, 100.0)
	assert_almost_eq(def.magnitude, 100.0, "the magnitude is untouched by the power stat", 0.0001)
	assert_almost_eq(
		def.magnitude * TechniqueCasting.power_rate(actor),
		200.0,
		"so the multiplier a combat_engine consumer must apply is exactly 2.0 here",
		0.0001
	)
	# And it is not secretly applied anywhere in the cast: the qi price is the only
	# thing the stat reaches in this module, and power moves it not at all.
	var before := _casting(actor).qi_cost_for(actor, def)
	actor.stats.set_base(QiStats.QI_AFFINITY, 60.0)
	actor.mark_stats_dirty()
	assert_almost_eq(
		_casting(actor).qi_cost_for(actor, def), before, "power never reaches the price", 0.0001
	)
