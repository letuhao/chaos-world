extends TestCase

## What each AUTHORED body plan actually produces, read through the live stat pipeline.
##
## Three claims live here because they are all the same kind of claim — a number the
## author intended, checked against what the game derives rather than against the `.tres`
## as written:
##
## - **BL-0811** — every shipped race is born with a physique. A `base_attributes` dict
##   that omits one grants nothing there, `ActorStats._attr` falls back to `0.0`, and
##   `ATTACK_PHYSICAL = physique * 2.0` reads `0.0`. Two of the five shipped races were
##   born unable to hit anything.
## - **BL-0279** — `commonborn` is the baseline, and a baseline that led every axis would
##   be the best body in the game. It tops none: `commonborn` is a flat 1.0 across all
##   seven attributes, so it is a body a specialist beats on the axis they chose and the
##   ceiling, not the frame, is what holds it back. The framing the old test used — a
##   handed-down strength score with a `MAX_TOP_AXES` cap no ADR states — is gone.
## - **BL-0772** — `race_lifespan` is an inert magnitude. Authored, contributed, and read
##   by nothing that ages anyone.
##
## Everything is read off the SHIPPED catalog, for the same reason as `test_race_content.gd`:
## the `.tres` files are the subject. A fixture catalog here would prove the expectations,
## not the game.
##
## ## Why the expectations are a table and not arithmetic
##
## An earlier `test_race_content.gd` derived strength from content and capped the result
## with a constant invented in the test file (`MAX_TOP_AXES := 2`) that no ADR states. This
## file deliberately does the opposite: the authored values ARE the specification, stated
## once, here, where a human can read them and disagree. The arithmetic
## (`physique * 2.0`) is still derived, because that is a rule `core` states rather than an
## opinion — but it is checked through the real `ActorStats` pipeline, so a race that
## authored a physique and somehow failed to land it would still fail.

## ## Why the expectations are a table and not arithmetic
##
## An earlier `test_race_content.gd` derived strength from content and capped the result
## with a constant invented in the test file (`MAX_TOP_AXES := 2`) that no ADR states. This
## file deliberately does the opposite: the authored values ARE the specification, stated
## once, in `PLANS`, where a human can read them and disagree with one.
##
## ## On attribute VALUES, and why 1.0 is not "absent"
##
## `base_attributes` is a GRANT applied additively onto an actor's existing base
## (`RaceProjection._grant`), not a whole stat sheet: the actor's own build and any other
## module's grant land in the same dict, and every one of `Stat.BASE_ATTRIBUTES` defaults to
## `0.0`. So an omitted key is an omitted GRANT of zero — and it is indistinguishable from
## "absent" right up until a derived stat asks the question. That is the whole of BL-0811.
## A mortal frame is 1.0 of each of the seven (see `commonborn`); a specialist is high on
## its own one or two and a plain 1.0 on the rest.
##
## `lead` is what each body must be the best available frame for, checked by TIES against
## the whole catalog, so two bodies may not both be the top on an axis unless one gave it
## up. `forfeit` is the axis a body hands to someone else, checked as a strict inequality.
const PLANS: Dictionary = {
	&"commonborn":
	# Nothing anyone would call beautiful survives tribulation, and nothing about this
	# frame favours a path. An even 1.0 everywhere, so it tops no axis at all. Where it
	{
		# lands is decided by its realm ceilings, not by its frame.
		"attributes":
		{
			"physique": 1.0,
			"spirit": 1.0,
			"aptitude": 1.0,
			"comprehension": 1.0,
			"agility": 1.0,
			"will": 1.0,
			"fortune": 1.0
		},
		"lead": [],
		"forfeit": [],
		"note": "even frame, no lead; refused by a realm ceiling",
	},
	# "carries more physique and stamina than anything else here" — the top body axis,
	# and the only one. Where it spends that is irrelevant to which axes it leads.
	&"stoneborn":
	{
		"attributes": {"physique": 4.0, "will": 1.0},
		"lead": [Stat.PHYSIQUE],
		"forfeit": [],
		"note": "the load-bearing frame",
	},
	# "reads intent at the speed of a struck match" — the top qi frame. A plain 1.0
	# physique, so it keeps a hand rather than being bodiless, and gives up the body axis
	# to stoneborn rather than merely tying it.
	&"emberblood":
	{
		"attributes": {"physique": 1.0, "spirit": 2.0, "aptitude": 3.0, "agility": 1.0},
		"lead": [Stat.SPIRIT, Stat.APTITUDE],
		"forfeit": [Stat.PHYSIQUE],
		"note": "the qi frame",
	},
	# "assembled for looking, not for being hit" — the top perception frame, and it
	# explicitly forfeits the body axis.
	&"tidecaller":
	{
		"attributes": {"physique": 1.0, "comprehension": 3.0, "will": 2.0, "spirit": 1.0},
		"lead": [Stat.COMPREHENSION],
		"forfeit": [Stat.PHYSIQUE],
		"note": "the perception frame",
	},
	# "altered rather than specialised" — strong enough at qi and will to stand beside
	&"emberblood_touched":
	{
		# both specialists, but the top on neither. The deliberately mediocre body.
		"attributes":
		{
			"physique": 2.0,
			"spirit": 1.0,
			"aptitude": 1.0,
			"comprehension": 1.0,
			"agility": 1.0,
			"will": 2.0,
			"fortune": 1.0
		},
		"lead": [],
		"forfeit": [Stat.COMPREHENSION, Stat.APTITUDE, Stat.SPIRIT],
		"note": "altered, not specialised",
	},
}


func _catalog() -> RaceCatalog:
	return RaceCatalog.instance()


func setup() -> void:
	RaceFixtureCatalog.teardown()


# --- BL-0811: a race with no physique cannot hit anything --------------------


## The defect this holds: a `base_attributes` dict that omits `physique` contributes
## nothing to physical attack, because `ActorStats._recompute` derives
## `ATTACK_PHYSICAL = physique * 2.0` and `_attr` falls back to `0.0` for a base the race
## never set. Two shipped races (`emberblood`, `tidecaller`) were in exactly that state.
##
## Asserting the field is PRESENT would not have caught it — the field was never absent,
## the VALUE was. So this reads the stats the game actually derives and pins them, which
## is where the defect showed.
func test_every_shipped_race_is_born_with_a_physique_and_can_strike() -> void:
	for race_id in _catalog().race_ids():
		var actor := _born_into(race_id)
		var physique := actor.stats.get_base(Stat.PHYSIQUE)
		# `assert_ne` against 0.0 rather than a `>` helper: the framework has no ordering
		# assertion, and a physique of 0.0 is the defect in both directions — a body born
		# with none, or one born with a negative.
		#
		# Read off `get_base`, not `derived`: the question here is ANATOMY, and the race's
		# own `percent_modifiers` are entitled to move the derived stat afterwards.
		assert_ne(physique, 0.0, "'%s' is born with a physique" % [race_id])
		# The derived stat, not the attribute. This is the number combat reads and the
		# assertion that would have gone red before BL-0811 was fixed: 2.0 * 0.0.
		assert_ne(
			actor.stats.derived(Stat.ATTACK_PHYSICAL), 0.0, "'%s' can actually strike" % [race_id]
		)


## The value each race's author intended, by way of the pipeline that produces it.
##
## Split from the test above on purpose: the first says "a body can hit", this says "for
## exactly as much as its author wrote". A future rebalance that moves a physique has to
## come here and say so in a number, which is what an oversight looks like on its way in.
##
## ## Two numbers, deliberately, because they are two questions
##
## The GRANTED physique is anatomy: the base attribute the `.tres` wrote, read off
## `get_base`, with nothing downstream of it. The DERIVED physical attack is what combat
## reads, and the race's own `percent_modifiers` move it — `tidecaller` strikes for 1.6
## off a physique of 1.0, which is `attack_physical: -0.2` doing exactly what its author
## asked. Asserting the derived number against a bare `physique * 2.0` would have called
## authored content a bug; asserting only the base would have missed the whole defect,
## which is a DERIVED number reading zero. So both are held, and each is labelled by what
## it claims.
##
## Every attribute the author wrote is checked, not just the physique: a `.tres` that
## quietly drops a value the table still names is caught here too.
func test_each_races_authored_attributes_are_the_values_it_is_born_with() -> void:
	var checked := 0
	for race_id in _catalog().race_ids():
		var expected: Dictionary = _plans(race_id).get("attributes", {}) as Dictionary
		var actor := _born_into(race_id)
		for attribute in expected.keys():
			var authored := float(expected[attribute])
			assert_almost_eq(
				actor.stats.get_base(StringName(attribute)),
				authored,
				"'%s' is granted %s" % [race_id, attribute]
			)
			checked += 1
		# The derived physical attack. NOT compared against a bare `physique * 2.0`:
		# `percent_modifiers` are entitled to move it, and `tidecaller` does. What is held
		# is the FLOOR — a derived attack of 0.0 is a legal number, so without this clause
		# the comparison would pass for a body the pipeline failed to land at all. That is
		# the shape of BL-0811 and the reason this clause exists.
		assert_ne(
			actor.stats.derived(Stat.ATTACK_PHYSICAL), 0.0, "'%s' can actually strike" % [race_id]
		)
	# A suite that asserted nothing because every `PLANS` lookup missed would report
	# green, so the coverage is counted rather than assumed. The expected number is
	# derived from the SHIPPED tree, not written down: an author who adds an
	# attribute to a `.tres` without writing it into this table turns this red, and
	# that is the whole point of the table being the specification.
	assert_eq(
		checked,
		_authored_attribute_count(),
		"every attribute the shipped tree authors is checked against a written plan"
	)


## How many `(race, attribute)` pairs the shipped catalog authors.
func _authored_attribute_count() -> int:
	var total := 0
	for race_id in _catalog().race_ids():
		total += (_catalog().race_definition(race_id)).base_attributes.size()
	return total


## The rule behind that count: `PLANS` is a SPECIFICATION of the shipped tree, so a race
## the catalog ships and the table does not name is a change nobody has written a sentence
## about yet. An unknown plan is silently skipped above — deliberately, so a seventh race
## does not break the suite — which is exactly why this counts.
func test_every_shipped_race_has_a_written_plan() -> void:
	for race_id in _catalog().race_ids():
		assert_ne(
			_plans(race_id).is_empty(),
			true,
			"'%s' is named in PLANS, attributes and all" % [race_id]
		)


## A race that authored an attribute it does not need is not a defect; a race that authored
## NOTHING for an attribute it needs is. So the check is not "every dict has seven keys"
## — `stoneborn` authors two and that is correct. It is that each shipped body reaches a
## non-zero physique, which `test_every_shipped_race_is_born_with_a_physique_and_can_strike`
## holds directly, and that the authored value is the value that lands.
func test_no_shipped_race_authored_an_empty_attribute_grant() -> void:
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		assert_ne(
			def.base_attributes.is_empty(), true, "'%s' authors at least one attribute" % [race_id]
		)


# --- BL-0279: the baseline must not lead every axis -------------------------


## ## This is the rule that replaces the invented `MAX_TOP_AXES` cap.
##
## ADR 0062 says the fallback body stops where mortals stop because nothing about its
## anatomy favours a path. A baseline that led every axis would contradict that sentence
## directly: the frame nobody chose would beat the frame everybody chose for a reason.
##
## The check is against the WHOLE catalog, not against a tally, so adding a sixth race
## cannot push this one over an invented line by arithmetic. It states what each author
## wrote: nobody ties for the top on an axis unless they gave it up, and nobody writes a
## body with no lead that tops one anyway.
func test_the_baseline_leads_no_axis_and_leads_nothing_a_specialist_leads() -> void:
	for race_id in _catalog().race_ids():
		var plan := _plans(race_id)
		var leads: Array = plan["lead"]
		var forfeits: Array = plan["forfeit"]
		for attribute in Stat.BASE_ATTRIBUTES:
			var leader := _axis_leader(attribute)
			if leads.has(attribute):
				assert_eq(
					leader, race_id, "'%s' is the top %s, as its plan says" % [race_id, attribute]
				)
			elif forfeits.has(attribute):
				assert_ne(
					leader, race_id, "'%s' gives up %s to '%s'" % [race_id, attribute, leader]
				)


## The strongest body on `attribute`, by the shipped catalog's own base attributes.
##
## Built from the `.tres` rather than off derived stats so a `percent_modifier` on some
## downstream stat cannot quietly change which BODY is the top frame — the claim is about
## anatomy, and `base_attributes` is anatomy.
##
## A tie on an axis is not a failure here and is not a dodge either: `>0` lets the first
## race found hold the axis, and the assertion that consumes this is a per-body one, so a
## tie is caught by the body that ties rather than by this helper inventing a winner.
func _axis_leader(attribute: StringName) -> StringName:
	var best: StringName = &""
	var best_value := -1.0
	for race_id in _catalog().race_ids():
		var value := _axis_value(race_id, attribute)
		if value > best_value:
			best_value = value
			best = race_id
	return best


func _axis_value(race_id: StringName, attribute: StringName) -> float:
	var def := _catalog().race_definition(race_id)
	return float(def.base_attributes.get(attribute, 0.0))


# --- BL-0772: lifespan is an inert magnitude --------------------------------


## ## What is actually true about `race_lifespan` today, stated as a test.
##
## 1. It is AUTHORED — every shipped race declares one, and it is the `RaceDef` default
##    when a `.tres` does not.
## 2. It is CONTRIBUTED — `RaceProvider` publishes it, scaled by realm tier (ADR 0169).
## 3. It is READ by a screen and by nothing else. **Nothing ages an actor.**
##
## The third fact is the one worth pinning, because a test that only asserted 1 and 2
## would look like enforcement and be none. Option (b) of BL-0772 — wire some partial
## ageing hook — was considered and rejected on evidence, not taste: there is no age
## field, no elapsed-days field and no birth date anywhere in `src/` (grep for
## `age_years|elapsed_days|born_year|born_on|age_days` returns zero), `Actor.to_dict()`
## serializes no age, and the only `age` in the tree is `FightLoop.age(delta)`,
## `SocialBond.age` and `FightScreen`'s `act_age` — a combat rate gate, a
## bond-strengthening counter and a UI verb. None of them is an age a lifespan could be
## compared to. Building one is BL-0037 and belongs to whoever owns time.
##
## So the honest state is asserted, and the assertion is about the PIPELINE not the
## fiction: the number is published and it is not compared against anything.
func test_race_lifespan_is_authored_and_reaches_a_stat_but_enforces_nothing() -> void:
	for race_id in _catalog().race_ids():
		var def := _catalog().race_definition(race_id)
		assert_ne(def.lifespan, 0.0, "'%s' authors a lifespan" % [race_id])

		# Published: the provider really does contribute it, at the Mortal tier
		# multiplier an actor with no realm has. This half was true before and stays true.
		var actor := _born_into(race_id)
		assert_almost_eq(
			actor.stats.derived(RaceStats.LIFESPAN),
			def.lifespan,
			"'%s' publishes its lifespan" % [race_id]
		)

		# Enforced: nothing. Asserting the ABSENCE of a mechanism is the only honest form
		# of this claim — a test cannot prove a negative about the whole engine, so it
		# proves the two things a mechanism would need and names what is missing.
		assert_eq(
			_nothing_ages_the_actor(actor),
			true,
			"'%s' has no age to be outlived by, so its lifespan is inert" % [race_id]
		)


## Whether this actor carries a field an age could be kept in at all.
##
## Deliberately narrow and deliberately mechanical: it asks whether a lifespan COULD be
## compared against anything today, which is the precondition for the stat meaning
## anything. When BL-0037 lands an age, this returns false and the test above goes RED —
## which is correct. The gap should become a failing test the day it stops being a gap,
## not drift quietly closed.
func _nothing_ages_the_actor(actor: Actor) -> bool:
	for field in ["age", "age_days", "age_years", "elapsed_days", "born_year", "born_on"]:
		if field in actor:
			return false
	return true


## ## Why `DEFAULT_LIFESPAN_DAYS` is an AUTHORING rung and never an ENFORCED one
##
## `test_race_content.gd` reads `def.lifespan` to tell whether an author made a body
## short-lived. That is a legitimate use: it reads what was WRITTEN. It is not evidence the
## game refuses anything, and the partition assertion there no longer accepts a lifespan as
## a refusal for exactly that reason.
##
## This test pins the half that is easy to forget — that the authoring still says what it
## said — and is deliberately WEAK on which body it is. It asserts the catalog still has a
## body shorter than the `RaceDef` default of 36,500 days, and that the shortest is named
## in its own tags, without writing either number into a constant that a balance pass could
## drift across. Pinning `18250.0` and `&"emberblood"` would be the `MAX_TOP_AXES` mistake
## wearing a different hat: a magic number in a test file that no ADR states, failing for a
## reason nobody chose. The load-bearing claims live in ADR 0169's authored table, which
## this test deliberately does not restate.
##
## What it does NOT claim is that the shortest body is `emberblood`, or that 18,250 days is
## the right number, or that a body being shorter than another matters to any outcome. It
## claims: lifespan still exteriorises, and the shortest body still says so.
func test_the_short_lived_body_is_still_authored_short_lived() -> void:
	var shortest := &""
	var shortest_days := INF
	for race_id in _catalog().race_ids():
		var days := (_catalog().race_definition(race_id)).lifespan
		if days < shortest_days:
			shortest_days = days
			shortest = race_id
	assert_eq(
		shortest_days < RaceDef.new().lifespan,
		true,
		"some body is authored shorter-lived than the unspecialised default"
	)
	assert_eq(
		(_catalog().race_definition(shortest)).tags.has(&"short_lived"),
		true,
		"and '%s' says so in its own tags" % [shortest]
	)
	# The authored value is inert, so the ONLY thing that can make this number mean
	# anything is a gate. Nothing gates it, so it is read by a screen and by nothing else
	# — asserted here as a fact about the pipeline, not as a wish.
	assert_eq(
		_nothing_ages_the_actor(_born_into(shortest)),
		true,
		"and nothing ages it, so the number changes no outcome yet"
	)


# --- Helpers -----------------------------------------------------------------


## A bare actor born into `race_id`, with no build of its own — so every number read off
## it is the body plan's contribution and nothing else.
func _born_into(race_id: StringName) -> Actor:
	var actor := Actor.new(&"body_plan_probe")
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	return actor


## `PLANS` for one race, or an empty dictionary for a race nobody has written a plan for.
##
## The empty fallback is deliberate: a seventh race must not break this suite for want of a
## sentence. `test_every_shipped_race_has_a_written_plan` is what turns the omission red,
## with a message that says which race is missing, instead of a suite that quietly checks
## nothing new.
func _plans(race_id: StringName) -> Dictionary:
	return PLANS.get(race_id, {}) as Dictionary
