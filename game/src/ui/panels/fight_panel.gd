class_name FightPanel
extends PanelContainer

## The fight's own figures: two bodies, their health, the blow counter and the rate.
##
## ## What it owns, and what it may not
##
## Every `%d`, every decimal and every verdict word on this surface — this panel, never
## the screen (AGENTS.md "No number formatting in a screen", ADR 0030, ADR 0038). It
## renders the primitives `FightLoop.summary()` published and re-derives NOTHING: the
## health ratios, the blow counts and the verdict are all read off the loop's own
## numbers, so a panel that decided a fight was over would be a second opinion about a
## module that already decided it.
##
## ## Why the fight gets its own surface rather than living on the readout
##
## `CombatReadoutPanel` answers "what did the spine do to ONE blow", and it renders a
## `CombatOutcome.to_dict()` — eleven stages of a single resolution. A fight is a
## different read model: two pools, a blow count, a rate and a verdict. Folding it into
## the readout would give one widget two unrelated payload shapes and a page that answers
## two different questions.
##
## Contract: `summary()` is the testable surface, primitives only, publishing the
## rendered strings beside the raw numbers.

## The panel's own lines for the states it must say out loud rather than print zeros
## for. `NO_FIGHT` and `FIGHT_OVER` are different words on purpose: "you have not
## started" and "you have finished" are the two answers a player acts on differently.
const NO_FIGHT := "No fight is under way."
const NO_HERO := "No hero bound."
const FIGHT_WON := "The fight is won."
const FIGHT_LOST := "The fight is lost."

## One bar: a name, its health and the share of it that is left. A local shape rather
## than a class because a row is a figure, not a behaviour.
const HEALTH_BAR := 24

var _fight: Dictionary = {}
var _header_label: Label = null
var _hero_label: Label = null
var _opponent_label: Label = null
var _blows_label: Label = null
var _verdict_label: Label = null
var _wounds_label: Label = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Show one fight. `fight` is `FightLoop.summary()` VERBATIM, or `{}` for no fight.
## Duplicated on the way in so a fight that ends mid-frame cannot repaint a panel from a
## dictionary the loop has already moved on from.
func show_fight(fight: Dictionary) -> void:
	_bind_nodes()
	_fight = (fight if fight != null else {}).duplicate(true)
	_render()


## Everything this panel shows, primitives only, with the rendered sentences beside the
## raw numbers so a headless test asserts what a player reads.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"has_fight": not _fight.is_empty(),
		"fighting": bool(_fight.get("fighting", false)),
		"outcome": String(_fight.get("outcome", "")),
		"hero_id": String(_fight.get("hero_id", "")),
		"opponent_id": String(_fight.get("opponent_id", "")),
		"hero_health": float(_fight.get("hero_health", 0.0)),
		"hero_health_max": float(_fight.get("hero_health_max", 0.0)),
		"opponent_health": float(_fight.get("opponent_health", 0.0)),
		"opponent_health_max": float(_fight.get("opponent_health_max", 0.0)),
		"hero_blows": int(_fight.get("hero_blows", 0)),
		"opponent_blows": int(_fight.get("opponent_blows", 0)),
		"blows_remaining": float(_fight.get("blows_remaining", 0.0)),
		"attack_speed": float(_fight.get("attack_speed", 1.0)),
		"blow_interval": float(_fight.get("blow_interval", 0.0)),
		"elapsed": float(_fight.get("elapsed", 0.0)),
		"wound_count": int(_fight.get("wound_count", 0)),
		"header_line": header_text(),
		"hero_line":
		_pool_text("You", _fight.get("hero_health", 0.0), _fight.get("hero_health_max", 0.0)),
		"opponent_line":
		_pool_text(
			"Foe", _fight.get("opponent_health", 0.0), _fight.get("opponent_health_max", 0.0)
		),
		"blows_line": blows_text(),
		"verdict_line": verdict_text(),
		"wounds_line": wounds_text(),
	}


## The header, and why a fight with no hero is not the same as a fight with no rival.
##
## `FightLoop.summary()` answers `{}` when there is no hero at all, and that empty
## payload IS the "no hero" answer rather than a fabricated fight — the same rule
## `CombatReadoutPanel.NO_DATA` states for a blow that was never struck.
func header_text() -> String:
	if _fight.is_empty():
		return NO_HERO if _fight.get("hero_id", "") == "" else NO_FIGHT
	if String(_fight.get("opponent_id", "")).is_empty():
		return NO_FIGHT
	return "Fighting %s" % String(_fight.get("opponent_id", ""))


## The blow tally and the rate that produced it, which is the pair a player builds
## against. `attack_speed` is printed as a multiple of the neutral rate because that is
## what it IS — the stat divides the anchor's own interval — so a build that raised it
## reads as "1.8x blows" rather than as an unexplained decimal.
func blows_text() -> String:
	if _fight.is_empty():
		return ""
	return (
		(
			"%d blows thrown · %d taken · %.1fs elapsed"
			% [
				int(_fight.get("hero_blows", 0)),
				int(_fight.get("opponent_blows", 0)),
				float(_fight.get("elapsed", 0.0)),
			]
		)
		+ (
			" · speed %.2fx (one blow every %.2fs, %.1fs ready)"
			% [
				float(_fight.get("attack_speed", 1.0)),
				float(_fight.get("blow_interval", 0.0)),
				float(_fight.get("blows_remaining", 0.0)),
			]
		)
	)


## The verdict, read off the loop's own `outcome` and never re-decided here. A decided
## fight keeps its opponent so this line can say WHO fell.
func verdict_text() -> String:
	if _fight.is_empty():
		return ""
	match String(_fight.get("outcome", "")):
		"":
			return "The fight is on." if bool(_fight.get("fighting", false)) else NO_FIGHT
		"hero_won":
			return (
				"%s You have %d blows and %s is down."
				% [
					FIGHT_WON,
					int(_fight.get("hero_blows", 0)),
					String(_fight.get("opponent_id", "the foe")),
				]
			)
		"hero_lost":
			return (
				"%s %s answered %d of your blows."
				% [
					FIGHT_LOST,
					String(_fight.get("opponent_id", "The foe")),
					int(_fight.get("opponent_blows", 0)),
				]
			)
		_:
			return String(_fight.get("outcome", "")).replace("_", " ")


## The wound ledger the fight has written, one row per struck channel. A NECROSED row is
## called out because necrosis is irreversible (ADR 0070) and is the one injury a player
## must never think will fade — the same wording rule `CombatReadoutPanel` follows.
func wounds_text() -> String:
	var wounds: Variant = _fight.get("wounds", {})
	if not (wounds is Dictionary) or (wounds as Dictionary).is_empty():
		return "No meridian carries a wound."
	var severity: Variant = (wounds as Dictionary).get("severity", {})
	if not (severity is Dictionary):
		return "No meridian carries a wound."
	var flags: Variant = (wounds as Dictionary).get("necrotic", {})
	var necrotic: Dictionary = flags if flags is Dictionary else {}
	var parts: Array[String] = []
	for key in (severity as Dictionary).keys():
		var tail := " NECROSED" if bool(necrotic.get(String(key), false)) else ""
		parts.append(
			(
				"%s %.3f%s"
				% [String(key).replace("_", " "), float((severity as Dictionary)[key]), tail]
			)
		)
	return " · ".join(parts) if not parts.is_empty() else "No meridian carries a wound."


# --- Plumbing ---------------------------------------------------------------


## One body's health as a filled bar and a pair of figures. The bar is `█`/`░` rather
## than a Godot `ProgressBar` because this panel owns its own presentation vocabulary and
## a headless drive reads the STRING — a test that can only read a widget's `value` cannot
## assert what a player was shown.
func _pool_text(label: String, current: Variant, maximum: Variant) -> String:
	var now := float(current)
	var top := float(maximum)
	if top <= 0.0:
		return "%s: no health pool" % label
	var filled := clampi(int(round((now / top) * float(HEALTH_BAR))), 0, HEALTH_BAR)
	return (
		"%s: %.1f / %.1f  %s%s"
		% [
			label,
			now,
			top,
			"█".repeat(filled),
			"░".repeat(HEALTH_BAR - filled),
		]
	)


## Resolved lazily, never in `@onready`: the headless driver runs this panel before a
## scene tree exists (ADR 0038). Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_header_label = get_node_or_null("%FightHeader") as Label
	_hero_label = get_node_or_null("%HeroHealth") as Label
	_opponent_label = get_node_or_null("%OpponentHealth") as Label
	_blows_label = get_node_or_null("%BlowsLabel") as Label
	_verdict_label = get_node_or_null("%VerdictLabel") as Label
	_wounds_label = get_node_or_null("%WoundsLabel") as Label
	_bound = _header_label != null


func _render() -> void:
	if _header_label == null:
		return
	_header_label.text = header_text()
	if _hero_label != null:
		_hero_label.text = _pool_text(
			"You", _fight.get("hero_health", 0.0), _fight.get("hero_health_max", 0.0)
		)
	if _opponent_label != null:
		_opponent_label.text = _pool_text(
			"Foe", _fight.get("opponent_health", 0.0), _fight.get("opponent_health_max", 0.0)
		)
	if _blows_label != null:
		_blows_label.text = blows_text()
		_blows_label.theme_type_variation = &"MetaLabel"
	if _verdict_label != null:
		_verdict_label.text = verdict_text()
		# Style by VARIATION only — `theme_override_*` is banned (AGENTS.md). A won
		# fight and a lost one must not read the same, because they are the two
		# answers a player acts on differently.
		_verdict_label.theme_type_variation = _verdict_variation()
	if _wounds_label != null:
		_wounds_label.text = wounds_text()
		_wounds_label.theme_type_variation = _wounds_variation()


## Ok while the fight runs, warn once it is decided. A live fight is not an "ok" state
## in the sense of a successful action, so it stays neutral and only the VERDICT is
## toned — which is the distinction a reader needs.
func _verdict_variation() -> StringName:
	match String(_fight.get("outcome", "")):
		"hero_won":
			return &"OkLabel"
		"hero_lost":
			return &"WarnLabel"
		_:
			return &"MetaLabel"


## A necrotic channel is a permanent loss, so its line is styled as one rather than as a
## number that happens to be large — the same reason `CombatReadoutPanel` does it.
func _wounds_variation() -> StringName:
	var wounds: Variant = _fight.get("wounds", {})
	if not (wounds is Dictionary):
		return &"MetaLabel"
	var flags: Variant = (wounds as Dictionary).get("necrotic", {})
	if not (flags is Dictionary):
		return &"MetaLabel"
	for key in (flags as Dictionary).keys():
		if bool((flags as Dictionary)[key]):
			return &"WarnLabel"
	return &"MetaLabel"
