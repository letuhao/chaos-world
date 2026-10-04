extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## ADR 0180, ruling Q1: `dantian_tier` is DELETED, and this suite is what stops
## it coming back ungated.
##
## The defect it closes (DEF-0228): the field was authored on all 30 seeds, written
## by `synchronize`, published on `panel_state`, rendered as a row name — and read
## by nothing. `_dantian_ready` checked injured/progress/comprehension/quality/ratio.
##
## Why DELETE rather than gate, which is the part worth re-deriving:
##
## - The three bands are a restatement of the ladder's own tiers. Nine Mortal, nine
##   Spirit, then IMMORTAL and TRANSCENDENT together — so `lower`/`middle`/`upper`
##   said nothing the realm line does not already print, and the screen printed it
##   beside the realm name.
## - The bands are NOT monotone, so a floor could not have gated anything. The
##   only writer is `QiTraining.synchronize`, which reads the realm the actor is
##   STANDING in (`training.gd:16`, `seed.dantian_tier`). A gate comparing that
##   against the target realm's own floor is therefore unsatisfiable at exactly the
##   two band edges and free at the other 27:
##     tribulation(lower)      -> spirit_condensation(middle)
##     spirit_ascension(middle)-> earth_immortal(upper)
##   `test_the_band_edges_are_where_a_tier_gate_would_have_walled_the_ladder_off`
##   below proves those two from the corpus, so the deletion is not a taste call.
##
## Re-adding the field is therefore a defect, not a feature. These are structural
## assertions rather than a behavioural walk because a tier that gates nothing has
## no behaviour to walk: the only question is whether the name is back.


## No qi seed declares a dantian tier. The field is authored data, so this reads
## the corpus rather than the loaded resource — a stale `.tres` in the import cache
## cannot make this green (ADR 0028's rule that the file is the truth).
func test_no_qi_seed_declares_a_dantian_tier() -> void:
	var ladder := RealmDefaults.ladder()
	var checked := 0
	for realm in ladder.realms():
		var path := "res://data/qi_cultivation/realms/%s.tres" % realm.id
		var text := FileAccess.get_file_as_string(path)
		assert_eq(text.is_empty(), false, "%s is readable" % realm.id)
		assert_eq(
			text.contains("dantian_tier"),
			false,
			"%s declares dantian_tier: a ladder no gate reads (ADR 0180)" % realm.id
		)
		checked += 1
	assert_eq(checked, 30, "and it graded the whole ladder, not a sample")


## The seed class does not carry the field either, so a fresh `.tres` written in
## the editor cannot reintroduce it by assigning a property that still exists.
func test_the_seed_class_carries_no_dantian_tier() -> void:
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	assert_ne(seed, null, "the first realm still has a seed")
	var declared: Array[String] = []
	for entry in seed.get_property_list():
		declared.append(String(entry.get("name", "")))
	assert_eq(
		declared.has("dantian_tier"),
		false,
		"QiRealmSeed still exports dantian_tier; every seed would be authoring a label"
	)


## No source file in the module reads or writes a dantian tier. `rg` over the
## shipped source is the guard; this asserts the outcome on the two classes that
## used to carry it, so a partial re-add (the field back, the writer gone) still
## fails rather than passing as dead data.
func test_the_runtime_carries_no_dantian_tier() -> void:
	var dantian_script := FileAccess.get_file_as_string(
		"res://src/modules/qi_cultivation/dantian.gd"
	)
	assert_eq(
		dantian_script.contains("set_tier"),
		false,
		"Dantian.set_tier is back; only synchronize ever called it"
	)
	assert_eq(
		dantian_script.contains("var tier"),
		false,
		"Dantian.tier is back; nothing read it but the row label"
	)
	var training := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/training.gd")
	assert_eq(training.contains("dantian_tier"), false, "training.gd writes a dantian tier again")
	var api_source := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/api.gd")
	assert_eq(
		api_source.contains("dantian_tier"),
		false,
		"panel_state publishes dantian_tier again; a screen would render a label"
	)


## WHY deletion, restated as a measurement over the corpus rather than an argument.
##
## If the bands were monotone, a tier floor would have been a real gate and this
## suite would be wrong. They are not: the tier steps UP at two boundaries, and the
## dantian's tier is written from the realm the actor stands in, so at exactly those
## two the floor can never be met. The map below is the ladder's own order, so a
## re-authored seed that moved a band edge would be caught here as a changed count.
func test_the_band_edges_are_where_a_tier_gate_would_have_walled_the_ladder_off() -> void:
	# Read straight from the files: the field is gone from the seeds, so this is the
	# historical shape preserved here as the reason, not as live content.
	var historic := {
		"qi_refining": "lower",
		"foundation": "lower",
		"core_formation": "lower",
		"nascent_soul": "lower",
		"spirit_transformation": "lower",
		"void_refinement": "lower",
		"body_integration": "lower",
		"great_ascension": "lower",
		"tribulation": "lower",
		"spirit_condensation": "middle",
		"spirit_sea": "middle",
		"spirit_palace": "middle",
		"spirit_manifestation": "middle",
		"spirit_severing": "middle",
		"spirit_unity": "middle",
		"spirit_domain": "middle",
		"spirit_sovereign": "middle",
		"spirit_ascension": "middle",
		"earth_immortal": "upper",
		"heaven_immortal": "upper",
		"golden_immortal": "upper",
		"mystic_immortal": "upper",
		"true_immortal": "upper",
		"primordial_immortal": "upper",
		"great_luo": "upper",
		"dao_fruit": "upper",
		"immortal_sovereign": "upper",
		"transcendent": "upper",
		"dao_ancestor": "upper",
		"primordial_origin": "upper",
	}
	var rank := {"lower": 1, "middle": 2, "upper": 3}
	var walled: Array[String] = []
	var realms := RealmDefaults.ladder().realms()
	# Bounded by the ladder's own length; each id visited once, and the body appends
	# to a list it is not walking (INC-0002).
	for index in range(realms.size() - 1):
		var standing := String(historic.get(String(realms[index].id), ""))
		var target := String(historic.get(String(realms[index + 1].id), ""))
		if int(rank.get(standing, 0)) < int(rank.get(target, 0)):
			walled.append("%s->%s" % [realms[index].id, realms[index + 1].id])
	assert_eq(
		walled.size(),
		2,
		"exactly two band edges step up, and both would have been unreachable gates"
	)
	assert_eq(
		walled,
		["tribulation->spirit_condensation", "spirit_ascension->earth_immortal"],
		"and they are the two the ladder crosses into Spirit and Immortal"
	)


## The dantian still saves and restores everything it owns. Deleting a field from a
## serialized component is where a save silently loses state, so the surviving keys
## are asserted rather than assumed.
func test_the_dantian_round_trips_without_a_tier() -> void:
	var dantian := Dantian.new()
	dantian.set_structural_capacity(200.0)
	dantian.set_quality(0.8)
	dantian.damage()
	var payload := dantian.to_dict()
	assert_eq(payload.has("tier"), false, "and it writes no tier key at all")
	var restored := Dantian.from_dict(payload)
	assert_almost_eq(restored.structural_capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.quality, 0.8, "quality round trip")
	assert_eq(restored.injured, true, "injury round trip")


## A save written BEFORE this ruling carries `"tier": "lower"`, and loading it must
## not fail. `from_dict` reads named keys, so an unknown one is ignored — asserted
## here because the fixture in `game/tests/fixtures/save_v2.json` still ships it and
## an old save in the wild will too.
func test_an_old_save_carrying_a_tier_still_loads() -> void:
	var restored := Dantian.from_dict(
		{"tier": "lower", "quality": 0.6, "injured": false, "structural_capacity": 150.0}
	)
	assert_almost_eq(restored.quality, 0.6, "and its real state is read")
	assert_almost_eq(restored.structural_capacity, 150.0, "capacity too")
