extends TestCase

## The shipped roster, measured: **race × path is a partition, not a tier list**
## (ADR 0062). Two numbers, and only two, because ADR 0062 states two claims:
##
## 1. **No race leads every axis.** Measured here, from the `.tres` files, with no cap
##    and no score.
## 2. **Every race is genuinely refused somewhere.** Not measured here — read through
##    the real gate in `test_race_content.gd::test_every_authored_race_is_genuinely_refused_somewhere`,
##    because a refusal is something the game does, not something a test infers.
##
## ## Why this exists even though `test_race_body_plan.gd` names the leaders
##
## It does not measure anything. `PLANS` is a SPECIFICATION: a table of the authored
## values, checked attribute by attribute against what the pipeline derives. It is the
## right place to say *`tidecaller` is granted exactly `comprehension: 3.0`* and it is
## the wrong place to answer *what does the whole roster add up to*.
##
## A mutation proved the difference rather than arguing it. Raising `commonborn` to
## `physique: 9.0, spirit: 9.0, aptitude: 9.0, comprehension: 9.0, will: 9.0` — a body
## that then leads qi, body AND mind, which is the exact defect BL-0279 was filed
## against — turned that suite red **9 times**, and every one of the 9 was a message
## about a *number*: "'commonborn' is granted physique: expected 1.0, got 9.0",
## "'tidecaller' is the top comprehension, as its plan says: expected tidecaller, got
## commonborn". A suite of restated authored values cannot distinguish a retune from a
## degenerate tree: both are "a number moved". What it can never do is say *the
## roster stopped being a partition*, because that is a statement about the relationship
## BETWEEN bodies, and no per-body assertion reads the relationship.
##
## So the claim ADR 0062 actually makes gets its own measurement here, derived from the
## shipped `.tres` and nothing else.
##
## ## Why there is no MAX_TOP_AXES, and why one will not come back
##
## The old guard was `MAX_TOP_AXES := 2` in `test_race_content.gd`: a constant
## invented inside a test file, with no ADR behind it, capping a tally the test itself
## computed. Two rules cannot both be invented — one of them is always wrong and
## nothing said which. The guard below therefore states NO COUNT. It states the
## sentence, which is unimprovable: the leader of an axis is whoever holds the highest
## authored value on it, and no race may hold the highest on all three.
##
## A cap could not be reintroduced as `MAX_TOP_AXES := 1` without re-creating the
## defect, because 1 would forbid the thing ADR 0062's own corpus does: `emberblood_touched`
## is authored to lead NOTHING precisely so that a fourth body can exist without
## strengthening the specialists. The real ceiling is not "a race may lead 2 axes" — it
## is "a race may not lead every axis", and that is the whole guard.

## The three axes and the base attributes that govern them.
##
## **The membership is read from the game, not typed here.** Each entry is the highest
## `base_attributes` value a shipped body authored on that axis, which is anatomy and
## nothing else — deliberately no `percent_modifiers` and no derived stats, so a
## downstream tuning number cannot quietly move which BODY is the top frame.
##
## `mind_cultivation`'s own breakthrough condition (`MindCultivationAdvancement`) reads
## `Stat.COMPREHENSION` and `core.ActorStats._recompute` derives `INSIGHT_GAIN` from it
## alone, so comprehension is the mind axis' governing attribute in shipped code rather
## than by a convention this file establishes. `qi_cultivation` is the only axis with
## two, because `ATTACK_SPIRITUAL`, `MAX_QI`, `QI_REGEN` and `CULTIVATION_RATE` all read
## `spirit` and `aptitude` together. `body_cultivation` reads `physique` alone
## (`ATTACK_PHYSICAL = physique * 2.0`, `DEFENSE_PHYSICAL = physique * 1.5`).
const AXIS_ATTRIBUTES: Dictionary = {
	&"qi_cultivation": [&"spirit", &"aptitude"],
	&"body_cultivation": [&"physique"],
	&"mind_cultivation": [&"comprehension"],
}


func _catalog() -> RaceCatalog:
	return RaceCatalog.instance()


func setup() -> void:
	RaceFixtureCatalog.teardown()


## ADR 0062's second claim, measured on the shipped tree: **no body is the best
## frame on all three axes at once.**
##
## Every axis's leader is collected from the whole catalog, then the intersection is
## required to be empty. A race that led all three would appear in all three leader
## lists and this goes red naming it.
##
## Three assertions minimum, not one: a suite that aborts on an empty catalog would
## otherwise report green having proved nothing, and the runner's `expect_assertions`
## floor is a per-suite opt-in this file declines to rely on.
func test_no_authored_race_leads_every_cultivation_axis() -> void:
	expect_assertions(4)
	var catalog := _catalog()
	var ids := catalog.race_ids()
	assert_eq(ids.size() >= 3, true, "a partition needs at least three bodies, found %d" % ids.size())

	var leads: Dictionary = {}
	for axis in AXIS_ATTRIBUTES.keys():
		leads[axis] = _axis_leaders(axis)
		assert_ne(
			(leads[axis] as Array).is_empty(), true, "'%s' has a body that leads it" % [axis]
		)

	# The intersection across the three axes, then the claim.
	var everywhere := _intersection(leads)
	assert_eq(
		everywhere.is_empty(),
		true,
		"no body leads qi AND body AND mind, found %s (leaders: qi %s, body %s, mind %s)"
		% [
			everywhere,
			leads[&"qi_cultivation"],
			leads[&"body_cultivation"],
			leads[&"mind_cultivation"],
		]
	)


## The bodies that hold the highest authored value on `axis`.
##
## **A tie yields every body at the top, not one winner.** `emberblood_touched` and
## `tidecaller` both author `will: 2.0`, and a helper that let the first race found keep
## the axis would report one of them as *the* leader and silently discard the tie — and
## a discarded tie is exactly how "nobody leads two axes" becomes unfalsifiable. An
## honest tie makes the claim in the test above strictly harder to pass, never easier.
func _axis_leaders(axis: StringName) -> Array[StringName]:
	var best := -1.0
	for race_id in _catalog().race_ids():
		best = maxf(best, _axis_value(race_id, axis))
	var out: Array[StringName] = []
	for race_id in _catalog().race_ids():
		if is_equal_approx(_axis_value(race_id, axis), best):
			out.append(race_id)
	out.sort()
	return out


## The strongest authored body on `axis`, by that axis' governing attributes only.
##
## An attribute the roster does not author reads `0.0`, which is the same fallback
## `core.ActorStats._attr` applies and the same one BL-0811 turned on. It is the right
## fallback here precisely because it is the game's: a body that grants no `comprehension`
## has no mind frame, and this reads that as the game does rather than inventing an
## optimistic default that would flatter a race for something it never authored.
func _axis_value(race_id: StringName, axis: StringName) -> float:
	var base := (_catalog().race_definition(race_id)).base_attributes
	var best := 0.0
	for attribute in AXIS_ATTRIBUTES[axis] as Array:
		best = maxf(best, float(base.get(attribute, 0.0)))
	return best


## Every race that appears in ALL the leader lists — the set that would be best at
## everything. A plain loop rather than a typed reduce, because GDScript has no
## `reduce` over dictionaries and an array-typed accumulator would be a second thing to
## keep correct.
func _intersection(leads: Dictionary) -> Array[StringName]:
	var axes := AXIS_ATTRIBUTES.keys()
	var out: Array[StringName] = []
	for race_id in (leads[axes[0]] as Array):
		var everywhere := true
		for axis in axes:
			if not (leads[axis] as Array).has(race_id):
				everywhere = false
				break
		if everywhere:
			out.append(race_id)
	return out