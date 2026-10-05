extends TestCase

## ADR 0174's readout, part three: the panel driven by a REAL engine blow.
##
## ## Why this file exists
##
## The other two readout suites (`test_combat_readout.gd` and
## `test_combat_readout_panel_rows.gd`) drive the panel with HAND-BUILT `to_dict()`
## payloads. That is deliberate and necessary: a `parried` arm needs a parry roll, a
## `chain_dropped` arm needs a reflect chain at depth, and no seeded generator reaches
## them on demand — so a branch reachable only through a lucky roll is a branch that is
## effectively untested.
##
## The cost of hand-built payloads is that they can DRIFT from the engine. Nothing in
## a fixture suite notices if `CombatOutcome.to_dict()` stops publishing a key, because
## the fixtures keep supplying it, and the panel keeps rendering a DEFAULTED FIGURE for
## it — a `0.00` that reads to a player as a measurement. That is the same failure as
## the one this whole file group exists to close, one layer down.
##
## So this file drives an ACTUAL `CombatSpine` blow and asserts the two facts the
## fixtures cannot: that the stage row survives a real landed blow (the `Array[String]`
## arm whose runtime throw cost a session), and that every key the panel reads is a key
## the engine really publishes.

const PANEL_SCRIPT := "res://src/ui/panels/combat_readout_panel.gd"
const OUTCOME_SCRIPT := "res://src/modules/combat_engine/outcome.gd"
const SCREEN_SCENE := "res://src/ui/screens/combat_readout.tscn"
## The meridian the synthetic blow aims at — a real authored channel, so the strike is
## a NAMED aim rather than a `random` one that may find nothing to subtract from.
const MERIDIAN := &"lung"
## Priced so one blow wounds without necrosing, matching the `ui_driver.gd` fixture.
## Fixture arithmetic, same as that harness's `DRILL_MAGNITUDE`.
const MAGNITUDE := 0.05

## Every key `CombatReadoutPanel` reads off the outcome payload. Held as one list so the
## "the panel reads it" and "the engine publishes it" halves of the contract case assert
## the SAME list rather than two lists that could drift apart.
const OUTCOME_KEYS: Array[String] = [
	"base",
	"proposed",
	"amount",
	"absorbed",
	"overflow",
	"health_delta",
	"reflected",
	"lifesteal",
	"crit",
	"parried",
	"blocked",
	"landed",
	"clean",
	"neutral",
	"chain_dropped",
	"effects",
]


## A hero/target pair with everything a body blow actually needs.
##
## The target carries the full body enrolment `ui_driver.gd:_build_drills` and
## `ItemWorkbenchApp._build_readout_target` both use, in the same order: `with_body_cultivation`
## builds the integrity pool, the provider and the meridian NETWORK, then
## `unlock_for_realm` OPENS the channels. The unlock is load-bearing, not decoration —
## ADR 0070 is explicit that a `named` aim at a meridian a body has never unlocked is
## NOT struck at all ("there is no channel there to subtract from"), so `sites[]` comes
## back empty and the blow carries no wound effect. The hero additionally carries the
## mechanism S4's loud read insists on, and the target the wound ledger ADR 0174 needs.
func _rig() -> Dictionary:
	var hero := Actor.new(&"readout_hero", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	hero.attach_core_resources()
	ActorFactory.with_body_cultivation(hero)
	CombatEngineApi.bind_mechanism(hero, BodyDamage.new())
	var target := Actor.new(&"readout_target", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	target.attach_core_resources()
	ActorFactory.with_body_cultivation(target)
	target.meridians.unlock_for_realm(&"qi_refining")
	CombatEngineApi.attach_wounds(target, CombatEngineApi.tuning())
	return {"hero": hero, "target": target}


## The screen, wired with a seam that resolves a REAL body blow through `CombatSpine`
## — the production entry point `CombatBoot.resolve_hit` calls. A `Callable` for the
## ADR 0143 reason the screen's own seam is one.
func _screen(hero: Actor, target: Actor) -> CombatReadoutScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	assert_ne(scene, null, "the readout screen scene loads")
	var screen := scene.instantiate() as CombatReadoutScreen
	screen.call("setup", hero)
	screen.bind_strike(Callable(self, "_real_blow"), target, Callable())
	return screen


## The screen with the composition root's OWN read injected — the `{band, actor,
## mechanism}` shape `ItemWorkbenchApp._readout_context` hands the screen in production,
## and the half that makes the band row appear.
func _banded_screen(hero: Actor, target: Actor) -> CombatReadoutScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	var screen := scene.instantiate() as CombatReadoutScreen
	screen.call("setup", hero)
	screen.bind_strike(Callable(self, "_real_blow"), target, _root_read(hero, target))
	return screen


## The composition root's one read, verbatim in shape.
func _root_read(hero: Actor, target: Actor) -> Callable:
	return func() -> Dictionary:
		return {
			"band": CombatEngineApi.band(hero, target, CombatEngineApi.tuning(), null),
			"actor": CombatEngineApi.summary(hero),
			"mechanism": CombatReadoutPanel.MECHANISM_BODY,
		}


## One REAL blow: a synthetic `TechniqueDef` aimed at a named meridian, resolved through
## the whole eleven stages with a seeded generator so the run reproduces exactly.
func _real_blow(attacker: Actor, defender: Actor) -> Dictionary:
	var def := TechniqueDef.new()
	def.path = PathState.BODY
	def.magnitude = MAGNITUDE
	def.aim_meridian = MERIDIAN
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260904
	return CombatSpine.resolve_hit(attacker, defender, def, CombatEngineApi.tuning(), rng).to_dict()


# --- 1. the stage row survives a REAL landed blow -----------------------------


## THE regression this whole file group exists for. The band row was once concatenated
## into a typed `Array[String]` literal, which throws AT RUNTIME and only on a landed
## blow — so the panel whose entire job is to print a landed blow printed `""` on every
## one of them, while `summary()` stayed non-empty and the generic route guard passed
## all session. This case fires a real blow so that throw would land HERE.
func test_a_real_blow_renders_a_stage_row_rather_than_throwing_on_the_band() -> void:
	var rig := _rig()
	var screen := _screen(rig["hero"] as Actor, rig["target"] as Actor)

	assert_eq(screen.act_strike(), true, "a real blow resolved and landed")

	var view := screen.summary()["readout"] as Dictionary
	var stages := String(view["stages_line"])
	assert_ne(stages.is_empty(), true, "a landed blow renders a stage row")
	# Every S-row the panel prints, from the engine's OWN figures rather than fixtures.
	for row in ["S1 base ", "S4 proposed ", "S6 amount ", "S9 absorbed ", "S9 overflow "]:
		assert_eq(stages.contains(row), true, "the real blow renders '%s': %s" % [row, stages])
	assert_eq(stages.contains("S10 reflected "), true, "S10 is rendered too")
	assert_eq(stages.contains("S11 leech "), true, "S11 is rendered too")
	# The append that used to throw. A seam with no `readout` callable is the harness
	# default here, so `has_band` is false and the band row is legitimately absent —
	# which is itself the omission branch, asserted rather than assumed.
	assert_eq(bool(view["has_band"]), false, "no band read was injected, so none is drawn")
	assert_eq(stages.contains("band draw"), false, "and the band row is omitted, not zeroed")


## The same row WITH a band read injected, which is the half that actually throws: the
## band row is APPENDED to the typed list, never concatenated into the literal.
func test_a_real_blow_renders_the_band_row_when_the_root_injects_the_read() -> void:
	var rig := _rig()
	var hero := rig["hero"] as Actor
	var target := rig["target"] as Actor
	var screen := _banded_screen(hero, target)

	assert_eq(screen.act_strike(), true, "a real blow resolved with a band read bound")

	var view := screen.summary()["readout"] as Dictionary
	var stages := String(view["stages_line"])
	assert_eq(bool(view["has_band"]), true, "the injected band read is published")
	assert_eq(
		stages.contains("band draw"),
		true,
		"and the band row APPENDED to the typed list instead of throwing: %s" % stages
	)
	assert_eq(
		stages.ends_with("band draw") or stages.contains("band draw "),
		true,
		"the band row is present and last"
	)
	# The mechanism the root named must reach the panel, not be dropped by the seam.
	assert_eq(
		String(view["mechanism_line"]),
		"flat subtraction at a meridian (body)",
		"and the injected mechanism name renders through the panel's own words"
	)


# --- 2. the effect and wound branches on a REAL blow ---------------------------


## A real body blow carries `body.wound`, so the effect branch and the wound-row branch
## are both exercised by the ENGINE here rather than only by a fixture. This is the ADR
## 0070 arc: one strike leaves a row that a second strike must RAISE.
func test_a_real_blow_writes_a_wound_row_and_the_second_blow_raises_it() -> void:
	var rig := _rig()
	var target := rig["target"] as Actor
	var screen := _screen(rig["hero"] as Actor, target)

	assert_eq(screen.act_strike(), true, "the first blow resolved")
	var first := screen.summary()["readout"] as Dictionary
	assert_eq(
		(first["effect_kinds"] as Array).has(String(CombatReadoutPanel.KIND_WOUND)),
		true,
		"the engine's own blow carried the wound effect: %s" % String(first["effects_line"])
	)
	var first_rows := first["wound_rows"] as Array
	assert_eq(
		first_rows.size(), 1, "the ledger rendered one row: %s" % String(first["wounds_line"])
	)
	var meridian := String((first_rows[0] as Dictionary)["meridian"])
	var first_severity := float((first_rows[0] as Dictionary)["severity"])
	assert_eq(first_severity > 0.0, true, "and it carries a real severity")

	assert_eq(screen.act_strike(), true, "the second blow resolved")

	var second := screen.summary()["readout"] as Dictionary
	var second_rows := second["wound_rows"] as Array
	assert_eq(second_rows.size(), 1, "the ledger still carries the one channel")
	var row := second_rows[0] as Dictionary
	assert_eq(String(row["meridian"]), meridian, "the SAME channel, because the body is the same")
	assert_eq(
		float(row["severity"]) > first_severity,
		true,
		(
			(
				"the second blow RAISED '%s' from %.4f to %.4f: a wound that never accumulates "
				+ "makes ADR 0070's whole decay/necrosis arc unobservable"
			)
			% [meridian, first_severity, float(row["severity"])]
		)
	)
	# Asserted as TEXT too, because the rendered line is what a player reads — a rise the
	# numbers show but the line does not print is a rise nobody can act on.
	assert_ne(
		String(second["wounds_line"]),
		String(first["wounds_line"]),
		"and the rendered wounds line CHANGED with it"
	)


# --- 3. the fixture/ENGINE contract, so the fixtures cannot drift ---------------


## EVERY key the panel reads is a key the engine really publishes. Both halves are
## checked against the SOURCE, not against a fixture, so this is the case that notices a
## rename in either place: the panel reading a key the engine dropped would render a
## DEFAULTED FIGURE for it, and the engine publishing a key the panel ignores is a
## readout that computes something and shows nothing.
func test_every_key_the_panel_reads_is_published_by_to_dict() -> void:
	var panel := _code_only(PANEL_SCRIPT)
	var engine := _code_only(OUTCOME_SCRIPT)
	for key in OUTCOME_KEYS:
		assert_eq(
			panel.contains('"%s"' % key),
			true,
			"the panel reads '%s', so the engine must publish it" % key
		)
		assert_eq(
			engine.contains('"%s"' % key), true, "`CombatOutcome.to_dict()` publishes '%s'" % key
		)


## The panel must not be reading a field the engine does NOT publish. A panel `.get` of
## a key the engine never writes is a figure that is always its `0.0` default, and a
## `0.00` on a readout reads to a player as a measurement. So the two key sets must be
## the SAME set, not merely overlapping.
func test_the_panel_reads_no_outcome_key_the_engine_never_publishes() -> void:
	var panel := _code_only(PANEL_SCRIPT)
	for key in ["missed", "stage", "stages", "seed", "chain", "index"]:
		assert_eq(
			panel.contains('_outcome.get("%s"' % key),
			false,
			"the panel must not read an outcome field the engine never publishes: '%s'" % key
		)


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


## The screen formats no figure of the OUTCOME. A `%` format inside the screen would give
## one number two places to change, which is the defect AGENTS.md names (ADR 0030).
func test_the_screen_formats_no_figure_of_the_outcome_itself() -> void:
	var code := _code_only("res://src/ui/screens/combat_readout.gd")
	for field in ["proposed", "amount", "overflow", "health_delta", "reflected", "lifesteal"]:
		assert_eq(
			code.contains(field), false, "the screen never reads the outcome field '%s'" % field
		)


# --- Plumbing ------------------------------------------------------------------


## Comments and docblocks stripped, so a source scan reads CODE and not prose.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		if raw.strip_edges().begins_with("#"):
			continue
		var hash := raw.find("#")
		out.append(raw.substr(0, hash) if hash >= 0 else raw)
	return "\n".join(out)
