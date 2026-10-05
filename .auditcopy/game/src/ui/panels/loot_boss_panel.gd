class_name LootBossPanel
extends HBoxContainer

## The live encounter readout: which boss is up, how much of its authored vitality is
## left, and how much health the player has left to answer with.
##
## ## Both sides, because a fight has two sides (ADR 0076)
##
## A readout that showed only the boss's pool taught the player that a domain boss cannot
## hurt them — which was the defect ADR 0076 removed: nothing in the exchange ever touched
## the player, so no fight could be lost and every risk item was dead content. The player's
## health and the count of fights they have lost are therefore part of *this* panel, not an
## afterthought: a loss has to be visible on the same line as the blow that caused it.
##
## The bars' widths and every `%d / %d` and count beside them belong to this panel, so the
## screen hands over two primitive views (`LootApi`'s `active` and `CombatApi`'s `preview`)
## straight through and formats no figure of its own.
##
## Outside a domain the boss half says so plainly rather than showing an empty bar,
## because "no boss" and "a boss at zero vitality" are different states and the player must
## be able to tell them apart. The player's half is shown either way: their health is
## theirs, not the encounter's.
##
## ## The status line is this panel's, for the same reason
##
## ADR 0106: a burn the player cannot see is a health bar that falls for no stated
## reason. `StatusApi.summary(actor)` is already primitives-only, so the screen hands
## the dict straight through — ids, remaining seconds, magnitudes, pulse counts — and
## every `%d`, every "forever", every id-turned-word here. A screen formats nothing
## (AGENTS.md), so the panel is the only place a status becomes a sentence.
##
## Contract: `summary()` is the testable surface.

## Shown when nobody is inside a domain.
const OUTSIDE := "Outside a domain"
## Shown before the player has lost anything.
const NO_LOSSES := "No losses yet"
## Shown when the player is carrying nothing that is eating them. An empty line would
## read as a row the panel forgot to fill, so the absence is stated instead.
const NO_STATUSES := "No statuses"
## The gate line when nothing is shut. Also the wording for a domain that declares no
## gate at all -- "open" and "ungated" are the same thing to act on, and saying so is
## what stops a satisfied gate reading as a refusal.
const OPEN_DOMAIN := "Open domain"

var _in_domain: bool = false
var _boss_id: String = ""
var _tier_label: String = ""
var _vitality: float = 0.0
var _vitality_max: float = 0.0
var _health_ratio: float = 0.0
var _health: float = 0.0
var _health_max: float = 1.0
var _defeats: int = 0
var _last_boss: String = ""
## The live statuses, already reduced to primitives by the facade. Held as fields and
## formatted only in `_status_text()` so the same dict a caller passed is the dict
## `summary()` reports — a panel that rendered a string nobody can read back is a
## readout a test cannot assert on.
var _statuses: Array = []
var _boss_label: Label = null
var _vitality_bar: ProgressBar = null
var _vitality_label: Label = null
var _player_bar: ProgressBar = null
var _player_label: Label = null
var _defeat_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Show both sides of the encounter.
##
## `active` is `LootApi.summary(actor)["active"]`; an empty one means the player is not in
## a domain. `player` is `CombatApi.preview(actor)`, which carries the health pool and the
## duel record. Both are read for numbers only — this panel decides what any of them means
## to a player.
func show_fight(active: Dictionary, player: Dictionary) -> void:
	_bind_nodes()
	_in_domain = bool(active.get("in_domain", false))
	_boss_id = String(active.get("boss_id", ""))
	_tier_label = String(active.get("tier_label", ""))
	_vitality = maxf(0.0, float(active.get("vitality", 0.0)))
	_vitality_max = maxf(1.0, float(active.get("vitality_max", 1.0)))
	_health_ratio = clampf(float(active.get("health_ratio", 0.0)), 0.0, 1.0)
	_health = maxf(0.0, float(player.get("health", 0.0)))
	_health_max = maxf(1.0, float(player.get("health_max", 1.0)))
	var duel := player.get("duel", {}) as Dictionary
	_defeats = int(duel.get("defeats", 0))
	_last_boss = String((duel.get("last_defeat", {}) as Dictionary).get("boss_id", ""))
	_render()


## Show what is on the player right now (ADR 0106).
##
## `statuses` is `StatusApi.summary(actor)["active"]`: one primitives-only dict per
## live status. The panel reads the ids and the timers and decides what any of them
## means to a player — the same division every other readout here works by, and the
## reason the screen hands this over without formatting a character of it.
##
## Safe to call before `show_fight` and after it; the two are independent halves of
## the same line and neither one overwrites the other's words.
func show_statuses(statuses: Array) -> void:
	_bind_nodes()
	_statuses = statuses if statuses != null else []
	_render()


## The domain entry gate, in words.
##
## ## A satisfied gate must not read as a refusal
##
## This line used to be one branch: `Needs key reach %d, carrying %d`, whatever the
## player carried. At exactly the required reach it therefore printed "Needs key
## reach 6, carrying 6" -- the wording of a shut gate on an open one. That is the
## defect class the standard calls worst: a player cannot act on a permission, and
## cannot tell a permission from a prohibition. The gate's own `entry.satisfied` view
## used to carry this and died with the removed entry panel, so nothing replaced it.
##
## ## And it belongs here, not in the screen
##
## The screen hands over two raw floats and a required reach. Every `%d` in the
## result is this panel's, per AGENTS.md ("a screen formats no figure"). The label
## itself stays declared in `loot_encounter.tscn` because it belongs to the entry
## row's layout -- what a panel owns is the wording, not where a Label is declared.
func gate_text(required: float, carrying: float) -> String:
	if required <= 0.0:
		return OPEN_DOMAIN
	if carrying >= required:
		return OPEN_DOMAIN
	return "Needs key reach %d, carrying %d" % [int(required), int(carrying)]


## The player's own loot bonus, to two decimals.
##
## A percentage would be the obvious reading and would be wrong: `loot_bonus` is a
## multiplier on drop rolls (`fortune * 0.01`), so 0.10 is "a 10% better roll", not
## "10%". Printing it as a decimal keeps the number and its meaning the same thing.
func bonus_text(bonus: float) -> String:
	return "Loot bonus %.2f" % bonus


## The status line as the player reads it. Safe to call before `_render()`.
func status_text() -> String:
	_bind_nodes()
	return _status_label.text if _status_label != null else _status_text()


## The vitality line as the player reads it. Safe to call before `_render()`.
func vitality_text() -> String:
	_bind_nodes()
	return _vitality_label.text if _vitality_label != null else _vitality_text()


## The boss line as the player reads it.
func boss_text() -> String:
	_bind_nodes()
	return _boss_label.text if _boss_label != null else _boss_text()


## The player's own health line as the player reads it.
func player_text() -> String:
	_bind_nodes()
	return _player_label.text if _player_label != null else _player_text()


## The losses line as the player reads it.
func defeat_text() -> String:
	_bind_nodes()
	return _defeat_label.text if _defeat_label != null else _defeat_text()


func summary() -> Dictionary:
	_bind_nodes()
	return {
		"in_domain": _in_domain,
		"boss_id": _boss_id,
		"tier_label": _tier_label,
		"vitality": _vitality,
		"vitality_max": _vitality_max,
		"health_ratio": _health_ratio,
		"health": _health,
		"health_max": _health_max,
		"defeats": _defeats,
		"last_defeat_boss": _last_boss,
		"status_count": _statuses.size(),
		"status_ids": _status_ids(),
		"statuses": _statuses,
		"boss": _boss_text(),
		"vitality_label": _vitality_text(),
		"player_label": _player_text(),
		"defeat_label": _defeat_text(),
		"status_label": _status_text(),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	if _boss_label != null:
		return
	_boss_label = get_node_or_null("%BossLabel") as Label
	_vitality_bar = get_node_or_null("%VitalityBar") as ProgressBar
	_vitality_label = get_node_or_null("%VitalityLabel") as Label
	_player_bar = get_node_or_null("%PlayerBar") as ProgressBar
	_player_label = get_node_or_null("%PlayerLabel") as Label
	_defeat_label = get_node_or_null("%DefeatLabel") as Label
	_status_label = get_node_or_null("%StatusLabel") as Label


func _render() -> void:
	if _boss_label == null:
		return
	_boss_label.text = _boss_text()
	_vitality_bar.max_value = _vitality_max
	_vitality_bar.value = clampf(_vitality, 0.0, _vitality_max)
	_vitality_label.text = _vitality_text()
	_player_bar.max_value = _health_max
	_player_bar.value = clampf(_health, 0.0, _health_max)
	_player_label.text = _player_text()
	_defeat_label.text = _defeat_text()
	_status_label.text = _status_text()


func _boss_text() -> String:
	if not _in_domain:
		return OUTSIDE
	return _boss_id if _tier_label.is_empty() else "%s (%s)" % [_boss_id, _tier_label]


func _vitality_text() -> String:
	if not _in_domain:
		return ""
	return "%d / %d vitality" % [int(_vitality), int(_vitality_max)]


## The player's health is always shown: it is their own pool, and a run they are about to
## lose is exactly when they need to see it.
func _player_text() -> String:
	return "%d / %d health" % [int(_health), int(_health_max)]


## The loss count, and what beat them the last time. Empty until they have lost something,
## so "no losses" and "lost to nothing yet" are not the same sentence.
func _defeat_text() -> String:
	if _defeats <= 0:
		return NO_LOSSES
	var base := "Defeated %d time%s" % [_defeats, "" if _defeats == 1 else "s"]
	return base if _last_boss.is_empty() else "%s — last to %s" % [base, _last_boss]


## What is on the player, in the order the facade listed it.
##
## Every figure here is read straight off the dict the facade wrote: `remaining` is
## printed as authored rather than rounded by a panel-invented rule, `magnitude` is the
## POTENCY the caller applied and never a derived damage number, and `ticks_elapsed`
## is the pulse count the status module has actually spent — which is what makes a
## burning line visibly move while a DoT is paying out.
##
## The id is turned into words by replacing its underscores, not by a second lookup
## into the module's vocabulary: `ui/` may not reach `StatusDef`, and a name is the
## only thing the facade hands over that the player can read.
func _status_text() -> String:
	if _statuses.is_empty():
		return NO_STATUSES
	var parts: Array[String] = []
	for entry in _statuses:
		var status := entry as Dictionary
		parts.append(_status_line(status))
	return " · ".join(parts)


func _status_line(status: Dictionary) -> String:
	var name := _status_name(status)
	# `permanent` is the contract's own question (`remaining < 0.0`), not a re-derivation
	# of it here: a panel that compared the raw timer itself would print "forever" for
	# a status that had one second left and a number for one that had none.
	var timer := (
		"forever"
		if bool(status.get("permanent", false))
		else "%ds" % int(float(status.get("remaining", 0.0)))
	)
	var magnitude := float(status.get("magnitude", 0.0))
	var pulses := int(status.get("ticks_elapsed", 0))
	var text := "%s %s x%.1f" % [name, timer, magnitude]
	if pulses > 0:
		text += " (%d pulse%s)" % [pulses, "" if pulses == 1 else "s"]
	return text


## The authored id as words. A status the `status` module did not author still has an
## id, and showing it raw beats hiding a live effect the panel cannot name.
func _status_name(status: Dictionary) -> String:
	return String(status.get("id", "")).replace("_", " ")


## The live status ids, in the order the panel lists them, so a test can assert on the
## readout without parsing the sentence above it.
func _status_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in _statuses:
		out.append(String((entry as Dictionary).get("id", "")))
	return out
