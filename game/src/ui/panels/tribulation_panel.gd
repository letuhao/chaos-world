class_name TribulationPanel
extends PanelContainer

## Read-only row for one heavenly tribulation. Owns every number format on the
## screen: `wave/max`, the rating's decimals and the survival percentage live
## here, never in the screen.
##
## The panel holds no game rule and reads no module. It renders whatever state
## `HeavenlyTribulationApi.state()` produced and exposes `summary()` so a headless
## test asserts the fight rather than the pixels.
##
## Contract: `summary()` returns primitives only, and `{}` for an empty state.

## Shown when a fight was survived and paid nothing. A blank line would read as a row
## the panel forgot to fill, and "the absence is stated" is the same rule the loot
## readout's `NO_STATUSES` follows.
const NO_BLESSING := "No blessing earned"

var _target_label: Label = null
var _kind_label: Label = null
var _wave_label: Label = null
var _rating_label: Label = null
var _verdict_label: Label = null
var _blessing_label: Label = null
var _state: Dictionary = {}
## The permanent blessing the LAST decided fight paid, as the facade's own primitives.
## Held as fields and formatted only in `_render_blessing` so the dict a caller handed
## in is the dict `summary()` reports — a panel that rendered a string nobody can read
## back is a reward line a test cannot assert on.
var _blessing: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	_render()


## Render `state`, the view `HeavenlyTribulationApi.state()` produces. Unknown or
## missing keys leave the previous value alone.
func set_state(state: Dictionary) -> void:
	_bind_nodes()
	_state = state
	_render()


## Render the blessing a decided fight paid, `TribulationBlessing.award`'s own answer:
## `{ok, id, ...}` or a named refusal. Called only on a DECIDED result — the key is
## absent while a fight is still in the air, so a caller with nothing to report must pass
## nothing rather than invent an empty dict (which this would read as "paid nothing").
##
## ## Why this is a SEPARATE verb and not another `set_state` key
##
## The blessing is not part of `state()`: `TribulationFight.state` reads the record, and
## a record does not carry what was paid for it — the award is once-guarded per SESSION on the
## actor (`TribulationBlessing.REWARDED_KEY`, session-only per ADR 0186), so a second read of
## the same decided record within one session answers `already_rewarded` and a player who
## re-opens this screen would see their blessing replaced by a refusal. The action result is the
## one place the award is observable exactly once, and this panel renders it from there.
func show_blessing(blessing: Dictionary) -> void:
	_bind_nodes()
	_blessing = blessing if blessing != null else {}
	_render()


## The blessing this panel last rendered, as primitives. `{}` when nothing was handed in
## — which is NOT the same as a refusal, and `paid` tells the two apart.
func blessing_summary() -> Dictionary:
	_bind_nodes()
	if _blessing.is_empty():
		return {}
	return {
		"paid": bool(_blessing.get("ok", false)),
		"id": String(_blessing.get("id", "")),
		"reason": String(_blessing.get("reason", "")),
		"label": blessing_text(),
	}


## The fight this row shows, as primitives. This is the shape tests assert.
func summary() -> Dictionary:
	_bind_nodes()
	if _state.is_empty():
		return {}
	return {
		"bound": _target_label != null,
		"owed": bool(_state.get("owed", false)),
		"target": String(_state.get("target", "")),
		"target_name": String(_state.get("target_name", "")),
		"bound_realm": String(_state.get("bound", "")),
		"type": String(_state.get("type", "")),
		"phase": String(_state.get("phase", "")),
		"wave": int(_state.get("wave", 0)),
		"max_waves": int(_state.get("max_waves", 0)),
		"difficulty": float(_state.get("difficulty", 0.0)),
		"outcome": String(_state.get("outcome", "")),
		"chance": float(_state.get("chance", 0.0)),
		"gate_open": bool(_state.get("gate_open", false)),
		"active": bool(_state.get("active", false)),
		"decided": bool(_state.get("decided", false)),
		"blessing": blessing_summary(),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _target_label != null:
		return
	_target_label = get_node_or_null("%TargetLabel") as Label
	_kind_label = get_node_or_null("%KindLabel") as Label
	_wave_label = get_node_or_null("%WaveLabel") as Label
	_rating_label = get_node_or_null("%RatingLabel") as Label
	_verdict_label = get_node_or_null("%VerdictLabel") as Label
	_blessing_label = get_node_or_null("%BlessingLabel") as Label


func _render() -> void:
	if _target_label == null:
		return
	if _state.is_empty():
		_target_label.text = "No tribulation"
		_target_label.theme_type_variation = &"MetaLabel"
		_kind_label.text = ""
		_wave_label.text = ""
		_rating_label.text = ""
		_verdict_label.text = ""
		_blessing_label.text = ""
		return
	_target_label.theme_type_variation = &"SectionTitle"
	_target_label.text = (
		"Tribulation: %s" % String(_state.get("target_name", ""))
		if bool(_state.get("owed", false))
		else "Tribulation: none owed"
	)
	var kind := String(_state.get("type", ""))
	_kind_label.text = (
		"" if kind.is_empty() else "%s · %s" % [kind.capitalize(), String(_state.get("phase", ""))]
	)
	_wave_label.text = "Wave %d/%d" % [int(_state.get("wave", 0)), int(_state.get("max_waves", 0))]
	_rating_label.text = (
		"Rating %.2f · survival %d%%"
		% [float(_state.get("difficulty", 0.0)), int(float(_state.get("chance", 0.0)) * 100.0)]
	)
	_render_verdict()
	_render_blessing()


## The reward line: what the survived fight PAID, in words a player can act on.
##
## ## Why it exists at all (F-7)
##
## `TribulationFight.fight_wave` returns a `blessing` key on every decided result and the
## screen branched only on `ok` / `decided` / `survived`, so the player read "Survived the
## tribulation" and never learned which permanent status they had just earned. A permanent
## blessing is the fight's reward — the one thing the whole ladder was for — and a reward
## the player cannot name is a reward they cannot notice they are carrying.
##
## ## Why the name is turned into words rather than looked up
##
## `ui/` may not name `StatusDef` (the facade rule), so the authored `text` is unreachable
## from here; the id is turned into words by replacing its underscores, exactly as the
## loot panel's `_status_name` does. Showing the id beats hiding an effect the panel
## cannot name, and `blessing_summary()` publishes the raw id so a test can assert on it
## without parsing the sentence.
##
## A refusal is rendered as its REASON rather than as an absence: the named refusals are
## ordinary answers (`no_cultivation_blessing_for_element` — metal and water ship no
## blessing today), and a silent line would read as "the game forgot to pay me" rather
## than "this trial type pays nothing".
func _render_blessing() -> void:
	if _blessing_label == null:
		return
	if _blessing.is_empty():
		_blessing_label.theme_type_variation = &"MetaLabel"
		_blessing_label.text = ""
		return
	_blessing_label.theme_type_variation = (
		&"OkLabel" if bool(_blessing.get("ok", false)) else &"WarnLabel"
	)
	_blessing_label.text = blessing_text()


## The blessing line as the player reads it. Safe to call before `_render()`.
func blessing_text() -> String:
	if _blessing.is_empty():
		return ""
	var status_id := String(_blessing.get("id", ""))
	if bool(_blessing.get("ok", false)) and not status_id.is_empty():
		return "Blessing earned: %s" % status_id.replace("_", " ")
	var reason := String(_blessing.get("reason", ""))
	return NO_BLESSING if reason.is_empty() else "No blessing · %s" % reason


func _render_verdict() -> void:
	var outcome := String(_state.get("outcome", ""))
	match outcome:
		"survived":
			_verdict_label.theme_type_variation = &"OkLabel"
			_verdict_label.text = "Survived · the gate for this realm is open"
		"failed":
			_verdict_label.theme_type_variation = &"WarnLabel"
			_verdict_label.text = "Broken · repair the body and fight it again"
		_:
			_verdict_label.theme_type_variation = &"MetaLabel"
			_verdict_label.text = _pending_text()


func _pending_text() -> String:
	if not bool(_state.get("owed", false)):
		return "No tribulation is owed below the Immortal tier"
	if bool(_state.get("gate_open", false)):
		return "The gate is open; break through"
	if bool(_state.get("has_record", false)):
		return "A tribulation is in progress"
	return "A tribulation is owed · face it"
