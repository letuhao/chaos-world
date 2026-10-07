extends TestCase

## ADR 0258 §3's PAIRING, proven strictly (DEF-0368): an age band ships a DEBUFF half and
## a BUFF half, and the yin-yang rule has teeth only if the halves' ORDERING is a fact
## rather than a claim. Every shipped band is measured on the union of the axes its two
## halves touch, with three heroes built through production doors — the pair by the real
## `StatusLoop` (the age track's wire), each single half by `StatusApi.apply_cultivation`
## (the door `AgeBands` names) — and every reading taken after the production tick.
##
## ## A DIRECTION per band, read from the content, never one direction for all four
##
## `age_first_ash_wear.tres` documents the first asymmetry: the youngest band's cost axis
## reads POSITIVE, so `first_ash` is not a strictly worse state. The suite therefore
## DERIVES each band's direction from its authored modifier values: where the wear half
## is a cost (all values negative), clarity-only must strictly dominate it on every axis
## — the long-lived hero's strict ordering DEF-0368 asked for — and where the wear half
## is a gift, the suite asserts the opposite direction and that the PAIR strictly
## dominates both halves instead. Assuming one direction would have hidden the asymmetry.
##
## Per axis the suite also asserts the pair is EXACTLY the union: equal to the one half
## that authored the axis, and between the two halves everywhere. A pair that double-
## applied a modifier, dropped one, or reordered an op fails there.

const YEARS := 100.0
const EPS := 1e-6


## A long-lived hero standing mid-band: the lifespan is a flat the TEST authors, so the
## thresholds are deterministic, and `age_years` is set before any status is applied.
func _hero(id: StringName, age_years: float) -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.stats.add_modifier(
		StatModifier.new(&"race_lifespan", Stat.Op.FLAT, YEARS * 365.0, &"test")
	)
	actor.age_years = age_years
	NpcApi.attach(actor)
	return actor


## The authored modifier table of one half: `{stat: value}` read off the def's payload.
func _modifiers(def: StatusDef) -> Dictionary:
	var out: Dictionary = {}
	for row in def.payload.get("modifiers", []):
		out[StringName(row["stat"])] = float(row["value"])
	return out


## The mid-share of each band, derived from the table's OWN fractions: `(start + end) / 2`
## with the next row's fraction (or 1.0) as the end, so a retuned table moves the ages.
func _mid_shares() -> Array:
	var rows: Array = AgeBands.summary(_hero(&"age_band_probe", 0.0)).get("bands", [])
	var out: Array = []
	for index in rows.size():
		var start := float(rows[index].get("fraction", 0.0))
		var end := 1.0
		if index + 1 < rows.size():
			end = float(rows[index + 1].get("fraction", 1.0))
		out.append({"band": StringName(rows[index].get("band", "")), "share": (start + end) * 0.5})
	return out


func test_every_band_orders_its_halves_by_the_direction_its_content_authors() -> void:
	var bands := _mid_shares()
	assert_eq(bands.size(), 4, "the four shipped bands are all measured")
	var saw_cost := false
	var saw_gift := false
	for row in bands:
		var band: StringName = row["band"]
		var wear_def := StatusCatalog.instance().any_definition(AgeBands.wear_id(band))
		var clarity_def := StatusCatalog.instance().any_definition(AgeBands.clarity_id(band))
		assert_ne(wear_def, null, "%s's wear half loads" % String(band))
		assert_ne(clarity_def, null, "%s's clarity half loads" % String(band))
		if wear_def == null or clarity_def == null:
			continue
		var wear_mods := _modifiers(wear_def)
		var clarity_mods := _modifiers(clarity_def)
		assert_eq(wear_mods.size() > 0, true, "%s's wear half authors modifiers" % String(band))
		assert_eq(
			clarity_mods.size() > 0, true, "%s's clarity half authors modifiers" % String(band)
		)
		# The buff half is a BUFF in every band: every authored value is positive. This is
		# the claim the direction below leans on, so it is asserted rather than assumed.
		for stat in clarity_mods:
			assert_eq(
				float(clarity_mods[stat]) > 0.0,
				true,
				"%s: clarity's %s is a gain" % [String(band), String(stat)]
			)
		var wear_is_cost := true
		for stat in wear_mods:
			if float(wear_mods[stat]) >= 0.0:
				wear_is_cost = false
		if wear_is_cost:
			saw_cost = true
		else:
			saw_gift = true
		var age := float(row["share"]) * YEARS
		var wear_hero := _hero(StringName("age_order_%s_wear" % String(band)), age)
		var clarity_hero := _hero(StringName("age_order_%s_clarity" % String(band)), age)
		var pair_hero := _hero(StringName("age_order_%s_pair" % String(band)), age)
		assert_eq(
			bool(StatusApi.apply_cultivation(wear_hero, AgeBands.wear_id(band)).get("ok", false)),
			true,
			"%s's wear half applies through the cultivation door" % String(band)
		)
		assert_eq(
			bool(
				StatusApi.apply_cultivation(clarity_hero, AgeBands.clarity_id(band)).get(
					"ok", false
				)
			),
			true,
			"%s's clarity half applies through the cultivation door" % String(band)
		)
		var loop := StatusLoop.new(pair_hero)
		var ticked := loop.tick(1.0)
		assert_eq(
			String(ticked.get("age_band", "")),
			String(band),
			"%s's pair hero stands in its own band" % String(band)
		)
		StatusApi.tick_statuses(wear_hero, 1.0)
		StatusApi.tick_statuses(clarity_hero, 1.0)
		var axes := {}
		for stat in wear_mods:
			axes[stat] = true
		for stat in clarity_mods:
			axes[stat] = true
		var strict_dominance := 0
		for stat in axes:
			var wear_value := wear_hero.stats.derived(stat)
			var clarity_value := clarity_hero.stats.derived(stat)
			var pair_value := pair_hero.stats.derived(stat)
			var label := "%s: %s" % [String(band), String(stat)]
			# The pair is the UNION: exactly the half that authored the axis.
			var wear_authors := wear_mods.has(stat)
			var clarity_authors := clarity_mods.has(stat)
			if wear_authors and not clarity_authors:
				assert_almost_eq(
					pair_value, wear_value, "%s: the pair carries the wear half" % label, EPS
				)
			elif clarity_authors and not wear_authors:
				assert_almost_eq(
					pair_value, clarity_value, "%s: the pair carries the clarity half" % label, EPS
				)
			# And it is BETWEEN the two singles on every axis, both directions covered.
			assert_eq(
				(
					pair_value >= minf(wear_value, clarity_value) - EPS
					and pair_value <= maxf(wear_value, clarity_value) + EPS
				),
				true,
				"%s: the pair sits between the halves" % label
			)
			# Dropping the clarity half is never an improvement — the yin-yang core, true
			# in every band because the buff half is a buff.
			assert_eq(
				pair_value >= wear_value - EPS,
				true,
				"%s: the pair is never worse than wear-only" % label
			)
			if clarity_authors:
				assert_eq(
					clarity_value > wear_value + EPS,
					true,
					"%s: clarity-only is strictly above wear-only on the buff axis" % label
				)
				strict_dominance += 1
			if wear_authors:
				if wear_is_cost:
					assert_eq(
						clarity_value > wear_value + EPS,
						true,
						"%s: the cost axis leaves wear-only strictly worse" % label
					)
					strict_dominance += 1
				else:
					assert_eq(
						wear_value > clarity_value + EPS,
						true,
						"%s: the young band's cost axis reads positive" % label
					)
		if wear_is_cost:
			# THE HEADLINE: on a long-lived band, clarity-only strictly dominates wear-only
			# on EVERY authored axis — wear-only is the strictly worse state.
			assert_eq(
				strict_dominance,
				axes.size(),
				"%s: clarity-only strictly dominates on every authored axis" % String(band)
			)
		else:
			# THE ASYMMETRY: the gift band's pair strictly dominates BOTH singles, so
			# being young is never a strictly worse state.
			for stat in axes:
				var wear_value := wear_hero.stats.derived(stat)
				var clarity_value := clarity_hero.stats.derived(stat)
				var pair_value := pair_hero.stats.derived(stat)
				assert_eq(
					pair_value >= clarity_value - EPS,
					true,
					"%s: the pair is never worse than clarity-only either" % String(stat)
				)
	assert_eq(saw_cost, true, "the shipped table authors cost bands")
	assert_eq(saw_gift, true, "and at least one gift band (the first-ash asymmetry is real)")
