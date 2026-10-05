extends TestCase

## ADR 0174's readout PANEL, part one: every rendering branch, asserted on CONTENT.
##
## ## Why this file exists at all
##
## `CombatReadoutPanel` and `CombatReadoutScreen` had ZERO references in `game/tests`
## for a whole session. The only coverage was `test_route_screen_contract.gd`, which
## asserts the scene loads and `summary()` is non-empty — and that guard is satisfied
## by the panel's `summary()` returning a dictionary of DEFAULTED FIGURES whether or
## not one rendering path ever works. So an `Array[String]` type error in
## `stages_text()` (the band row was once concatenated into a typed literal, which
## throws AT RUNTIME and only on a landed blow) passed that guard for the whole
## session, because no assertion ever reached the string the panel builds.
##
## The branch inventory below is taken from the panel's own `match`/early-return
## arms, not from what happens to be reachable: a branch nothing reaches is a branch
## nothing exercises, which is the failure mode this file exists to close.
##
## The payloads are HAND-BUILT `to_dict()`-shaped dictionaries on purpose. Driving the
## real spine cannot reach every arm — a `parried` outcome needs a parry roll, a
## `chain_dropped` one needs a reflect chain at depth — and a branch that is only
## reachable through a lucky roll is a branch that is effectively untested. The
## ENGINE's own contract is that the panel renders primitives verbatim and re-derives
## nothing, so a hand-built payload is exactly the input the panel was designed for.
## `test_a_real_blow_renders_through_the_same_branches` closes the loop by driving an
## actual `CombatSpine` blow so the shapes cannot drift apart.

const PANEL_SCRIPT := "res://src/ui/panels/combat_readout_panel.gd"

## One landed blow, with every figure distinct so a field wired to the wrong number is
## visible rather than coincidentally right. `proposed`/`amount`/`overflow`/`health`
## are deliberately 2.50/3.85/3.85/3.85 so S6's crit multiplier is readable too.
const BAND := {"draw": 0.125}
const ACTOR := {
	"attack_spiritual": 31.0,
	"attack_physical": 40.0,
	"defense_spiritual": 12.0,
	"defense_physical": 30.0,
	"crit_chance": 0.05,
	"damage_reduction": 0.0,
	"realm_id": "qi_refining",
	"realm_rate": 1.0,
}


## A panel with no scene tree behind it — the headless shape ADR 0038 requires, and the
## reason `_bind_nodes` is lazy. Every case below drives the panel exactly as the suite
## would in CI.
func _panel() -> CombatReadoutPanel:
	var scene: PackedScene = load("res://src/ui/panels/combat_readout_panel.tscn")
	assert_ne(scene, null, "the panel scene loads")
	return scene.instantiate() as CombatReadoutPanel


## A `to_dict()`-shaped landed blow. `over` sets the engine's own booleans one at a
## time, so a case names the single thing it is about instead of building a fixture
## whose every field is significant.
func _hit(over: Dictionary = {}) -> Dictionary:
	var base := {
		"base": 0.05,
		"amount": 3.85,
		"proposed": 2.5,
		"absorbed": 0.0,
		"overflow": 3.85,
		"health_delta": -3.85,
		"reflected": 0.0,
		"lifesteal": 0.0,
		"crit": false,
		"parried": false,
		"blocked": false,
		"landed": true,
		"clean": true,
		"neutral": false,
		"chain_dropped": false,
		"effects": [],
	}
	for key in over:
		base[key] = over[key]
	return base


# --- 1. verdict_text(): every arm the panel implements -------------------------


## Nothing struck yet. A panel that printed `0` here would teach the reader that a
## whiff and a gut-punch are the same event, which is the entire reason `to_dict()`
## returns `{}` for a miss.
func test_no_blow_reads_as_no_blow_and_not_as_zeroes() -> void:
	var panel := _panel()
	assert_eq(panel.verdict_text(), CombatReadoutPanel.NO_DATA, "an empty payload says so")
	# `NO_DATA` is the NOTHING-STRUCK state. A blow that was struck and never arrived is
	# a DIFFERENT payload — a non-empty `to_dict()` whose `landed` is false — and it must
	# read as the whiff, because a whiff and a gut-punch are the same event to a player
	# if both read as nothing.
	panel.show_hit({"landed": false, "crit": false})
	assert_eq(panel.verdict_text(), CombatReadoutPanel.MISS_TEXT, "a landed-false blow is a whiff")
	assert_eq(panel.stages_text(), "", "and no stage row is decomposed out of it")
	assert_eq(bool(panel.summary()["has_hit"]), true, "but it WAS struck, so it is not nothing")
	assert_eq(bool(panel.summary()["missed"]), true, "and summary() reports it as a miss")


## The clean baseline, with every mechanism-named half switched off. `hit` with nothing
## appended is the floor every other verdict is built on.
func test_a_clean_landed_blow_reads_as_a_plain_hit() -> void:
	var panel := _panel()
	panel.show_hit(_hit(), {}, {}, &"")
	assert_eq(panel.verdict_text(), "hit", "a clean blow with no mechanism named")
	assert_eq(panel.mechanism_text(), "", "and an unnamed mechanism prints nothing")


## The verdict LINE, not just the tokens: "critical hit" replaces "hit" rather than
## being appended to it, so a critic reading the row sees one leading word.
func test_a_crit_leads_the_verdict_rather_than_being_appended() -> void:
	var panel := _panel()
	panel.show_hit(_hit({"crit": true}), {}, {}, CombatReadoutPanel.MECHANISM_QI)
	assert_eq(
		panel.verdict_text(),
		"critical hit · answered by elemental share (qi)",
		"the crit OWNS the leading word and the mechanism answers it"
	)


## A parry is a DEFENSIVE RESPONSE (ADR 0068), so it is a word the blow was ANSWED
## with — never an exemption that hides the fact the blow landed.
func test_a_parried_blow_reads_as_answered_and_not_as_exempt() -> void:
	var panel := _panel()
	panel.show_hit(_hit({"parried": true}), {}, {}, CombatReadoutPanel.MECHANISM_BODY)
	var line := panel.verdict_text()
	assert_eq(line.contains("parried"), true, "the parry is named")
	assert_eq(
		line.contains("answered by flat subtraction at a meridian (body)"),
		true,
		"and the blow still names who answered it"
	)


func test_a_blocked_blow_reads_as_blocked() -> void:
	var panel := _panel()
	panel.show_hit(_hit({"blocked": true}), {}, {}, CombatReadoutPanel.MECHANISM_MIND)
	var line := panel.verdict_text()
	assert_eq(line.contains("blocked"), true, "the block is named")
	assert_eq(line.contains("sea erosion (mind)"), true, "over the mechanism that answered")


## A dropped reflect chain is VISIBLE TRUNCATION. Silence here reads as a rounding
## rather than as a chain that hit ADR 0068's depth limit.
func test_a_dropped_reflect_chain_is_called_out_rather_than_silently_truncated() -> void:
	var panel := _panel()
	panel.show_hit(_hit({"chain_dropped": true}), {}, {}, CombatReadoutPanel.MECHANISM_BODY)
	assert_eq(
		panel.verdict_text().contains("reflect chain dropped"),
		true,
		"the dropped chain is stated, not swallowed"
	)


## `neutral` is the ONE legal refusal that costs nothing at all (ADR 0067's
## invariant), and it is the fact a player most needs: the blow arrived and answered.
func test_a_neutral_blow_reads_as_answered_without_cost() -> void:
	var panel := _panel()
	panel.show_hit(_hit({"neutral": true}), {}, {}, CombatReadoutPanel.MECHANISM_BODY)
	assert_eq(
		panel.verdict_text().contains("answered without cost"),
		true,
		"a refusal that costs nothing still says it arrived"
	)


## All the flags at once, so the JOIN is pinned rather than each arm in isolation: the
## panel's own separator (` · `) and its fixed order are the contract a reader parses.
func test_every_flag_at_once_joins_in_the_panels_own_order() -> void:
	var panel := _panel()
	panel.show_hit(
		_hit({"crit": true, "parried": true, "blocked": true, "chain_dropped": true}),
		{},
		{},
		CombatReadoutPanel.MECHANISM_BODY
	)
	assert_eq(
		panel.verdict_text(),
		(
			"critical hit · answered by flat subtraction at a meridian (body)"
			+ " · parried · blocked · reflect chain dropped"
		),
		"crit leads, the mechanism answers, then the defensive words in the panel's order"
	)


# --- 2. stages_text(): the S1..S11 rows and the band row -----------------------


## The stage row is a LIST of figures so a reader compares two rows by NUMBER. Each
## row is asserted individually against a distinct payload figure, so a row wired to
## the wrong field fails here rather than agreeing by coincidence.
func test_the_stage_rows_quote_every_figure_the_engine_published() -> void:
	var panel := _panel()
	(
		panel
		. show_hit(
			_hit(
				{
					"base": 0.05,
					"proposed": 2.5,
					"amount": 3.85,
					"absorbed": 1.25,
					"overflow": 2.6,
					"health_delta": -2.6,
					"reflected": 0.75,
					"lifesteal": 0.5,
				}
			)
		)
	)
	var line := panel.stages_text()
	for row in [
		"S1 base 0.05",
		"S4 proposed 2.50",
		"S6 amount 3.85",
		"S9 absorbed 1.25",
		"S9 overflow 2.60",
		"S9 health 2.60",
		"S10 reflected 0.75",
		"S11 leech 0.50",
	]:
		assert_eq(line.contains(row), true, "the stage row quotes '%s'" % row)
	# `health_delta` is printed ABSOLUTE: a reader must never be shown that healing the
	# defender would make the blow's own row read as a positive loss.
	assert_eq(line.contains("S9 health -2.60"), false, "health is printed as a loss")


## The band draw is APPENDED to the typed `Array[String]`, never concatenated into it.
## This is the arm whose bug cost a whole session: assigning an untyped `[]` where
## `Array[String]` is declared throws AT RUNTIME, and only on a landed blow, so the
## stage row printed `""` on every real hit while `summary()` stayed non-empty.
func test_the_band_row_is_appended_to_a_typed_list_and_three_digit_drawn() -> void:
	var panel := _panel()
	panel.show_hit(_hit(), BAND, {}, CombatReadoutPanel.MECHANISM_BODY)
	var line := panel.stages_text()
	assert_eq(line.contains("band draw 0.125"), true, "the band draw is drawn at %.3f")
	# It is appended LAST, after S11, because it is not a stage of the blow — it is the
	# roll the blow did not consume.
	assert_eq(
		line.ends_with("band draw 0.125"),
		true,
		"and appended after the last stage rather than folded into one of them"
	)


## With no band supplied the row is OMITTED, not drawn as 0.000: a fabricated draw is a
## claim about a roll that never happened.
func test_a_blow_with_no_band_roll_prints_no_band_row_at_all() -> void:
	var panel := _panel()
	panel.show_hit(_hit(), {}, {}, CombatReadoutPanel.MECHANISM_BODY)
	assert_eq(
		panel.stages_text().contains("band draw"),
		false,
		"an absent roll is omitted rather than drawn as 0.000"
	)
	assert_eq(bool(panel.summary()["has_band"]), false, "and summary() publishes that too")


# --- 3. mechanism_text(): the three names and the raw fallback -----------------


## The panel's whole claim is that a player can SEE which of the three mechanisms
## answered a blow. All three are asserted by their own published class name, so a
## rename in `CombatBoot` fails here instead of silently changing what is shown.
func test_the_three_mechanisms_are_named_in_the_readers_own_words() -> void:
	var panel := _panel()
	for pair in [
		[CombatReadoutPanel.MECHANISM_QI, "elemental share (qi)"],
		[CombatReadoutPanel.MECHANISM_BODY, "flat subtraction at a meridian (body)"],
		[CombatReadoutPanel.MECHANISM_MIND, "sea erosion (mind)"],
	]:
		panel.show_hit(_hit(), {}, {}, pair[0] as StringName)
		assert_eq(
			panel.mechanism_text(), String(pair[1]), "the mechanism %s is named" % String(pair[0])
		)


## An unnamed mechanism prints NOTHING rather than a placeholder — `""` is what keeps
## `verdict_text` from appending "answered by " to a mechanism nobody named.
func test_no_mechanism_named_prints_no_mechanism_half() -> void:
	var panel := _panel()
	panel.show_hit(_hit(), {}, {}, &"")
	assert_eq(panel.mechanism_text(), "", "an unnamed mechanism is blank")
	assert_eq(
		panel.verdict_text(), "hit", "and the verdict does not append an empty answer to itself"
	)


## A mechanism this panel has never heard of is shown RAW rather than dropped: a fourth
## mechanism must be able to be VISIBLE before it can be readable. Underscores become
## spaces, so an unspaced engine id still reads as words.
func test_an_unknown_mechanism_falls_back_to_its_raw_underscored_name() -> void:
	var panel := _panel()
	panel.show_hit(_hit(), {}, {}, &"ShadowDamage")
	assert_eq(panel.mechanism_text(), "ShadowDamage", "an id with no space stays as it is")
	panel.show_hit(_hit(), {}, {}, &"shadow_damage")
	assert_eq(
		panel.mechanism_text(),
		"shadow damage",
		"an underscored id is shown raw with underscores spaced"
	)
	assert_eq(
		panel.verdict_text().contains("answered by shadow damage"),
		true,
		"and the verdict still answers with it rather than going silent"
	)


# --- 4. the panel's own empty-state sentences ----------------------------------


## Each `NO_*` string is a sentence a PLAYER reads, quoted from the panel's constant so
## a rename fails here rather than making the test assert a string nobody ships.
func test_the_empty_states_are_the_panels_own_sentences() -> void:
	var panel := _panel()
	assert_eq(panel.wounds_text(), CombatReadoutPanel.NO_WOUNDS, "no ledger reads as such")
	assert_eq(panel.effects_text(), CombatReadoutPanel.NO_EFFECTS, "no effects read as such")
	assert_eq(panel.actor_text(), "", "and no attacker line invents a stat line")


# --- Plumbing ------------------------------------------------------------------


## Comments and docblocks stripped, so a source scan reads CODE and not prose. Same
## shape `test_status_readout.gd` and `test_ui_conventions.gd` use.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		if raw.strip_edges().begins_with("#"):
			continue
		var hash := raw.find("#")
		out.append(raw.substr(0, hash) if hash >= 0 else raw)
	return "\n".join(out)


## The two rules a panel half could break silently: `@onready` cannot be used (the
## headless suite drives this panel before a scene tree exists) and style belongs to the
## theme, never a `theme_override_*` baked into the panel.
func test_the_panel_binds_lazily_and_owns_no_theme_override() -> void:
	var source := FileAccess.get_file_as_string(PANEL_SCRIPT)
	assert_eq(_code_only(PANEL_SCRIPT).contains("@onready"), false, "no @onready in ui/")
	assert_eq(source.contains("func _bind_nodes()"), true, "nodes resolve in _bind_nodes()")
	# Scanned code-only: the panel's own docblock NAMES the ban, and a doc comment
	# discussing `theme_override` is not a violation of it.
	assert_eq(
		_code_only(PANEL_SCRIPT).contains("theme_override"), false, "style belongs to the theme"
	)


## The panel formats figures and the SCREEN must not. A `%` format inside the screen
## would give one number two places to change, which is the defect AGENTS.md names.
func test_the_screen_formats_no_figure_of_the_outcome_itself() -> void:
	var code := _code_only("res://src/ui/screens/combat_readout.gd")
	for field in ["proposed", "amount", "overflow", "health_delta", "reflected", "lifesteal"]:
		assert_eq(
			code.contains(field), false, "the screen never reads the outcome field '%s'" % field
		)
