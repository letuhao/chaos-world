extends TestCase

## ADR 0174's readout, part two: the effects and wound rows, and the SCREEN's verbs.
##
## Part one (`test_combat_readout.gd`) covers the verdict, the stage rows and the
## mechanism names. This file covers the two halves that turn a payload into rows —
## `effects_text` and `wounds_text` — plus every verb and refusal the screen exposes,
## which had no references anywhere in `game/tests`. It is a separate file only because
## one file covering both halves would run past the repo's 400-line cap.
##
## ## Why the refusals are asserted and not merely counted
##
## `act_strike` refuses four ways (no hero, no seam, no target, and the engine's own
## refusal), and `summary()` publishes `last_reason` so a probe can tell "the screen
## refused because nothing can strike" from "the module refused the blow". Those two
## read as the SAME EMPTY LINE on the panel, which is precisely why the reason is
## published — so `enabled.strike` and `last_reason` are asserted together, as the pair
## that decides whether the screen or the engine is at fault.

## One meridian with a real name, so `_replace("_", " ")` on the row labels is
## exercised rather than being a no-op that always passes.
const MERIDIAN := &"lung"
## A meridian id with an underscore in it, for the row-label spacing.
const NAMED_CHANNEL := &"heart_fire"
## An effect id nobody ships, for the unknown-kind fallback.
const UNKNOWN_KIND := &"shadow.echo"
const PANEL_SCENE := "res://src/ui/panels/combat_readout_panel.tscn"
const SCREEN_SCENE := "res://src/ui/screens/combat_readout.tscn"


func _panel() -> CombatReadoutPanel:
	var scene: PackedScene = load(PANEL_SCENE)
	assert_ne(scene, null, "the panel scene loads")
	return scene.instantiate() as CombatReadoutPanel


## The screen, wired with a strike seam over `hero` against `target`. The seam is a
## `Callable` because `ui/` may not mint an `Actor` or name `CombatBoot` — the same
## ADR 0143 door the quest screen's accept verb uses — so the test drives the seam
## rather than the engine unless it says otherwise.
func _screen(hero: Actor, target: Actor, strike: Callable = Callable()) -> CombatReadoutScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	assert_ne(scene, null, "the readout screen scene loads")
	var screen := scene.instantiate() as CombatReadoutScreen
	# No `_ready` here: `UiScreen` binds lazily in `refresh()`, which `setup` and
	# `bind_strike` both call, so a screen driven headless never needs one.
	screen.call("setup", hero)
	screen.bind_strike(strike, target, Callable())
	return screen


## A hero with the core resources `summary()` reads, so the screen's own `actor()` is a
## real actor rather than a null that would short-circuit every verb.
func _hero() -> Actor:
	var hero := Actor.new(&"readout_hero", {Stat.PHYSIQUE: 20.0, Stat.COMPREHENSION: 10.0})
	hero.attach_core_resources()
	return hero


## A `to_dict()`-shaped landed blow carrying `effects` verbatim.
func _hit_with(effects: Array) -> Dictionary:
	return {
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
		"effects": effects,
	}


## `BodyWounds.to_dict()`'s exact shape: two parallel maps the panel flattens into
## rows. Written as the module publishes it, so a change to the ledger's shape fails
## here rather than making the row reader silently skip a channel.
func _ledger(severity: Dictionary, necrotic: Dictionary = {}) -> Dictionary:
	return {"severity": severity, "necrotic": necrotic}


## The deliberately-CORRUPT ledger of the untrusted-input case, built through `Variant`
## so the static checker cannot reject the bad payload that is the point of the test.
func _corrupt_ledger(severity: Variant, necrotic: Variant) -> Dictionary:
	return {"severity": severity, "necrotic": necrotic}


# --- 1. effects_text(): each kind and the unknown-kind fallback -----------------


## A wound row quotes the meridian and the mechanism's OWN S4 subtotal — NOT the
## post-crit amount, because the wound is a fact about the defender's ledger and not a
## second estimate of the damage.
func test_a_wound_effect_row_quotes_the_meridian_and_its_own_subtotal() -> void:
	var panel := _panel()
	panel.show_hit(
		_hit_with(
			[{"kind": CombatReadoutPanel.KIND_WOUND, "meridian": NAMED_CHANNEL, "severity": 2.5}]
		)
	)
	assert_eq(
		panel.effects_text(),
		"wound heart fire 2.50",
		"the wound row names the channel, spaces it, and quotes S4's subtotal"
	)


## `MindDamage` puts ALL THREE sea writes in ONE effect entry, so a panel that showed
## turbulence without the clarity it cost would be lying by omission (ADR 0071).
func test_an_erosion_row_shows_all_three_sea_writes_together_with_signs() -> void:
	var panel := _panel()
	(
		panel
		. show_hit(
			_hit_with(
				[
					{
						"kind": CombatReadoutPanel.KIND_EROSION,
						"strike_kind": &"attend",
						"turbulence": 1.5,
						"clarity": -0.25,
						"awareness": -0.125,
					}
				]
			)
		)
	)
	assert_eq(
		panel.effects_text(),
		"erosion (attend) turbulence +1.500 clarity -0.250 awareness -0.125",
		"the three deltas are one row, signed, so the cost of the turbulence is visible"
	)


## S12 is a balance question, so BOTH answers are printed by name: an applied status
## with its potency, and a REFUSED one with the reason. `resisted` and `already held`
## are deliberately not flattened into "nothing happened".
func test_a_status_row_states_applied_or_refused_by_name() -> void:
	var panel := _panel()
	(
		panel
		. show_hit(
			_hit_with(
				[
					{
						"kind": CombatReadoutPanel.KIND_STATUS,
						"applied": true,
						"status_id": &"fire_immolation",
						"potency": 3.5,
					},
					{
						"kind": CombatReadoutPanel.KIND_STATUS,
						"applied": false,
						"refused": &"no_rng"
					},
				]
			)
		)
	)
	var line := panel.effects_text()
	assert_eq(
		line.contains("status fire immolation potency 3.50"),
		true,
		"an applied status is named with its potency, underscores spaced"
	)
	assert_eq(
		line.contains("status withheld: no rng"),
		true,
		"and a refusal is printed by name rather than as nothing happening"
	)


## An effect id the panel does not know is SHOWN, never hidden — the same rule as the
## mechanism fallback. An id that arrived with no `kind` at all gets the spelled
## fallback, because an empty row teaches the reader nothing.
func test_an_unknown_effect_kind_is_shown_raw_and_a_kindless_one_is_named() -> void:
	var panel := _panel()
	panel.show_hit(_hit_with([{"kind": UNKNOWN_KIND}, {"severity": 1.0}, {"kind": ""}]))
	var line := panel.effects_text()
	assert_eq(line.contains("shadow.echo"), true, "an unknown id is shown, not dropped")
	assert_eq(line.contains("unnamed effect"), true, "and an effect with no kind is named")
	# And `effect_kinds` publishes what was carried, so a test can index by id rather
	# than by parsing the sentence.
	assert_eq(
		(panel.summary()["effect_kinds"] as Array).has(String(UNKNOWN_KIND)),
		true,
		"the raw id is published for a test to assert on"
	)


## The order is the PROPOSAL's order, not a sort: a wound then a status reads in the
## order the mechanism emitted them, and a row that reordered them would misreport the
## sequence the engine actually performed.
func test_effects_render_in_the_order_the_proposal_carried_them() -> void:
	var panel := _panel()
	(
		panel
		. show_hit(
			_hit_with(
				[
					{"kind": CombatReadoutPanel.KIND_WOUND, "meridian": MERIDIAN, "severity": 2.5},
					{
						"kind": CombatReadoutPanel.KIND_STATUS,
						"applied": false,
						"refused": &"no_rng"
					},
				]
			)
		)
	)
	assert_eq(
		panel.effects_text().find("status withheld") > panel.effects_text().find("wound lung"),
		true,
		"the status row follows the wound row, in the proposal's own order"
	)
	assert_eq(int(panel.summary()["effect_count"]), 2, "and both effects are counted")


## A payload whose `effects` key is missing or is not an Array must degrade to the
## "nothing beyond the damage" sentence. A typed read of a missing key is what turns a
## miss into a null dereference.
func test_a_missing_or_non_array_effects_field_degrades_rather_than_crashing() -> void:
	var panel := _panel()
	panel.show_hit(
		{"landed": true, "crit": false, "parried": false, "blocked": false, "clean": true}
	)
	assert_eq(panel.effects_text(), L.t(CombatReadoutPanel.NO_EFFECTS), "no effects key at all")
	panel.show_hit({"landed": true, "effects": "not an array"})
	assert_eq(
		panel.effects_text(),
		L.t(CombatReadoutPanel.NO_EFFECTS),
		"and an effects field that is not an Array reads as no effects"
	)


# --- 2. wounds_text(): the necrotic suffix and the rows ------------------------


## The suffix is the point of the whole row: necrosis is IRREVERSIBLE downward
## (ADR 0070), so it is the one wound a player must never think will fade.
func test_a_necrotic_channel_is_suffixed_and_a_healthy_one_is_not() -> void:
	var panel := _panel()
	panel.show_wounds(_ledger({"lung": 0.05}, {}))
	assert_eq(panel.wounds_text(), "lung 0.050", "a wounded channel reads as a severity")
	assert_eq(
		panel.wounds_text().contains("NECROSED"),
		false,
		"and carries no necrosis suffix before it has crossed"
	)

	panel.show_wounds(_ledger({"lung": 0.31}, {"lung": true}))
	assert_eq(
		panel.wounds_text(),
		"lung 0.310 NECROSED",
		"a necrotic channel says so, because decay will never take it below the floor"
	)


## Every channel gets its OWN row, so two injured meridians are never collapsed into
## one another — and the `necrotic` flag is read PER KEY rather than being a blanket
## "any channel is necrotic".
func test_each_channel_is_its_own_row_and_the_flag_is_per_channel() -> void:
	var panel := _panel()
	panel.show_wounds(_ledger({"lung": 0.05, "heart_fire": 0.2}, {"heart_fire": true}))
	var line := panel.wounds_text()
	assert_eq(int(panel.summary()["wound_count"]), 2, "both channels are counted")
	assert_eq(line.contains("lung 0.050"), true, "the healthy channel has its own row")
	assert_eq(line.contains("heart fire 0.200 NECROSED"), true, "and the necrotic one is named")


## Two parallel maps that must AGREE with each other are flattened here so a test
## indexes rows rather than walking both. A hand-edited save can carry a non-dictionary
## under either key, and the readout must degrade to "no wound" rather than fail to
## load — which is the untrusted-input contract `Actor.get_module_data` already states.
func test_a_ledger_with_a_non_dictionary_severity_map_degrades_to_no_wound() -> void:
	var panel := _panel()
	panel.show_wounds(_corrupt_ledger("not a dictionary", {}))
	assert_eq(
		panel.wounds_text(), L.t(CombatReadoutPanel.NO_WOUNDS), "severity must be a Dictionary"
	)
	panel.show_wounds(_corrupt_ledger({"lung": 0.05}, "not a dictionary"))
	assert_eq(
		panel.wounds_text(),
		"lung 0.050",
		"a bad necrotic map is treated as absent rather than failing the whole ledger"
	)


## The rows are published STRUCTURLED as well as rendered, so a test can assert the
## number without parsing the sentence — and so a future level of nesting cannot make a
## `wounds_line` assertion fail for a good change.
func test_the_wound_rows_are_published_beside_the_rendered_line() -> void:
	var panel := _panel()
	panel.show_wounds(_ledger({"lung": 0.31}, {"lung": true}))
	var rows := panel.summary()["wound_rows"] as Array
	assert_eq(rows.size(), 1, "one row is published")
	var row := rows[0] as Dictionary
	assert_eq(String(row["meridian"]), "lung", "the channel is named")
	assert_eq(float(row["severity"]), 0.31, "at its accumulated severity")
	assert_eq(bool(row["necrotic"]), true, "and flagged necrotic")


# --- 3. the screen's verbs and refusals ----------------------------------------


## Unwired, every verb refuses BY NAME and the screen says so on its own line. This is
## the case a player hits first, and it must not present as a broken strike.
func test_a_screen_with_no_seam_refuses_by_name_rather_than_silently() -> void:
	var screen := _screen(_hero(), null)
	assert_eq(screen.strike_wired(), false, "no strike seam was injected")
	assert_eq(screen.act_strike(), false, "so striking is refused")
	assert_eq(
		String(screen.summary()["last_reason"]), CombatReadoutScreen.REASON_NO_STRIKE, "by name"
	)
	assert_eq(bool(screen.summary()["enabled"]["strike"]), false, "and the button reads disabled")
	assert_eq(bool(screen.summary()["fired"]), false, "no blow is reported as fired")


## `enabled.strike` is the conjunction of the two facts the screen owns, and it is the
## one field a probe reads to decide whether a refusal is the SCREEN's or the ENGINE's.
func test_enabled_strike_is_the_conjunction_of_a_seam_and_a_target() -> void:
	var hero := _hero()
	var target := _hero()
	var seam := func(_a: Actor, _d: Actor) -> Dictionary: return {}
	# Seam but no target: the screen can strike nothing, so it must not offer to.
	var bare := _screen(hero, null, seam)
	assert_eq(bare.strike_wired(), true, "the seam is bound")
	assert_eq(bool(bare.summary()["enabled"]["strike"]), false, "but there is no target to hit")
	# Target but no seam: the refusal must not be drawn as a disabled strike either.
	var aimless := _screen(hero, target)
	assert_eq(bool(aimless.summary()["enabled"]["strike"]), false, "no seam means nothing to do")
	assert_eq(String(aimless.summary()["last_reason"]), "", "and nothing has been struck yet")
	# Both: the verb is offered.
	var live := _screen(hero, target, seam)
	assert_eq(bool(live.summary()["enabled"]["strike"]), true, "a seam and a target offer the verb")


## A strike seam answering `{}` — the engine's own empty-miss convention — is NOT a
## refusal: the blow was attempted and never arrived. The screen must report that as a
## miss, distinct from the named refusals above, because a whiff and a gut-punch are
## the same event to a player if both read as nothing.
func test_a_miss_is_reported_as_a_miss_and_not_as_a_refusal() -> void:
	var seam := func(_a: Actor, _d: Actor) -> Dictionary: return {}
	var screen := _screen(_hero(), _hero(), seam)
	assert_eq(screen.act_strike(), false, "an empty payload is not a landed blow")
	var view := screen.summary()
	assert_eq(int(view["hits"]), 1, "but the attempt is counted, so it is not a refusal")
	assert_eq(String(view["last_reason"]), "missed", "and the reason names the miss")
	assert_eq(bool(view["last_ok"]), false, "with no landed blow to report")


## The BAD seam of the untrusted-caller case, answering something that is not a
## Dictionary. Built through `Variant` so the static checker cannot reject the wrong
## return type that is the entire point of the test.
func _bad_seam() -> Callable:
	return func(_a: Actor, _d: Actor) -> Variant: return 42


## A strike seam answering something that is NOT a Dictionary must not be handed to the panel
## as a half-initialised payload: it degrades to `{}`, which is the panel's own
## "no blow" state, rather than crashing the readout on a caller's bad return.
func test_a_strike_seam_answering_a_non_dictionary_degrades_to_the_miss_state() -> void:
	var screen := _screen(_hero(), _hero(), _bad_seam())
	assert_eq(screen.act_strike(), false, "a non-dictionary is not a landed blow")
	assert_eq(String(screen.summary()["last_reason"]), "missed", "and reads as a miss")
	assert_eq(
		bool((screen.summary()["readout"] as Dictionary)["has_hit"]),
		false,
		"the panel is never handed a non-dictionary to decompose"
	)


## `act_clear` forgets the last blow, because a readout that keeps painting a stale
## blow after the player walked away from it teaches them the fight never ended.
func test_clearing_forgets_the_last_blow_and_the_hit_count() -> void:
	var seam := func(_a: Actor, _d: Actor) -> Dictionary:
		return {"landed": true, "crit": false, "parried": false, "blocked": false, "amount": 3.85}
	var screen := _screen(_hero(), _hero(), seam)
	assert_eq(screen.act_strike(), true, "a landed blow resolves")
	assert_eq(int(screen.summary()["hits"]), 1, "and is counted")
	assert_eq(screen.act_clear(), true, "clearing always succeeds")
	var view := screen.summary()
	assert_eq(int(view["hits"]), 0, "the hit count is reset")
	assert_eq(bool(view["fired"]), false, "no blow is reported as fired")
	assert_eq(bool(view["last_ok"]), false, "and the outcome is forgotten")
	assert_eq(
		String((view["readout"] as Dictionary)["verdict_line"]),
		L.t(CombatReadoutPanel.NO_DATA),
		"the panel falls back to saying nothing has been struck"
	)


## A screen with NO actor reports `{}` — not a readout of nothing — so a test never
## reads a half-initialised screen as a real view, and the UI's own screen contract is
## pinned rather than assumed.
func test_a_screen_with_no_actor_reports_nothing_at_all() -> void:
	# The same `SCREEN_SCENE` `_screen` loads, rather than a second literal — one scene
	# string means one thing to change when the screen is renamed.
	var bare := (load(SCREEN_SCENE) as PackedScene).instantiate() as CombatReadoutScreen
	assert_eq(bare.summary(), {}, "no hero means no view — not a readout of nothing")
