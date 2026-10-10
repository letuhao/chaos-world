extends TestCase

## The two READ-MODEL cases for a manual's margin: what `TechniquesApi.inspect`
## publishes — the inscribed sheet and the margin as SEPARATE columns — and what the
## codex summary marks: an `annotated` flag, so a row does not have to project every
## technique's effects to say whether one is worth opening.
##
## Split out of `test_technique_marginalia.gd` when that file passed gdlint's
## `max-file-lines` ceiling. The fixtures are shared: `TechniqueMarginaliaFixture` holds
## the hero, the manual, the seeded study and the constants, and nothing here asserts
## anything the suite beside it does not also hold to.


func test_the_read_model_reports_the_sheet_and_the_margin_as_two_columns() -> void:
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var learned := TechniqueMarginaliaFixture.study(hero, def, 55)
	var margin: Dictionary = learned.get("margin", {})
	var view := TechniquesApi.inspect(hero, def)
	var authored: Array = view.get("authored_effects", [])
	var marginal: Array = view.get("marginal", [])
	var effective: Array = view.get("effects", [])
	assert_eq(authored.size(), 2, "the sheet reports both inscribed options")
	assert_eq(marginal.size(), 2, "and so does the margin")
	assert_eq(effective.size(), 2, "and the effective column is the margin, not both")
	for row in marginal:
		assert_almost_eq(
			float(row["value"]),
			float(margin[String(row["option_id"])]),
			"'%s' reads at what the copy said" % String(row["option_id"]),
			0.0001
		)
	# The sheet is unchanged, because a copy annotates a book and never rewrites it.
	for row in authored:
		var option_id := String(row["option_id"])
		if option_id == String(TechniqueMarginaliaFixture.CAPACITY_OPTION):
			assert_almost_eq(
				float(row["value"]),
				TechniqueMarginaliaFixture.CAPACITY_VALUE,
				"the sheet is untouched",
				0.0001
			)
		else:
			assert_almost_eq(
				float(row["value"]),
				TechniqueMarginaliaFixture.STAT_VALUE,
				"the sheet is untouched",
				0.0001
			)


func test_the_codex_list_marks_which_rows_are_annotated() -> void:
	# A summary row must not have to project every technique's effects to say
	# whether one is worth opening, so `annotated` is published as its own flag.
	var hero := TechniqueMarginaliaFixture.hero()
	var def := TechniqueMarginaliaFixture.manual()
	var plain := TechniqueMarginaliaFixture.manual()
	TechniquesApi.codex(hero).learn(def.id)
	TechniquesApi.codex(hero).learn(plain.id)
	TechniquesApi.attach(hero)
	var rows: Array = TechniquesApi.summary(hero).get("entries", [])
	var seen := {}
	for row in rows:
		seen[String(row["id"])] = row
	assert_eq(bool(seen[def.id].get("annotated", false)), false, "an unstudied row is plain")
	assert_eq(bool(seen[plain.id].get("annotated", false)), false, "and so is a direct learn")
	TechniqueMarginaliaFixture.study(hero, def, 13)
	rows = TechniquesApi.summary(hero).get("entries", [])
	for row in rows:
		if String(row["id"]) == String(def.id):
			assert_eq(bool(row.get("annotated", false)), true, "a studied copy is marked")
