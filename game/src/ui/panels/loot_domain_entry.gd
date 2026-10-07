class_name LootDomainEntry
extends VBoxContainer

## What the selected domain asks of the player before they may enter it, and the
## bounded `loot_bonus` rate that shapes every drop they take.
##
## Presentation only. The screen hands raw numbers and this panel owns every
## `%d` and decimal it shows, so the gate reads the same wherever it appears and
## no screen has to restate a figure. It names no module and no item type.
##
## Contract: `summary()` is the testable surface.

## Wording for a domain that declares no key gate at all (ADR 0033).
const GATE_OPEN := "LOC_UI_PANELS_4708400A59"

var _required_reach: float = 0.0
var _carried_reach: float = 0.0
var _loot_bonus: float = 0.0
var _gate_label: Label = null
var _bonus_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Show the gate the selected domain declares against the reach the player
## carries, plus the rate that will shape the drops. A `required_reach` at or
## below zero means the domain declares no gate and is open to anyone.
func show_entry(required_reach: float, carried_reach: float, loot_bonus: float) -> void:
	_bind_nodes()
	_required_reach = maxf(0.0, required_reach)
	_carried_reach = maxf(0.0, carried_reach)
	_loot_bonus = loot_bonus
	_render()


## The gate line as the player reads it. Safe to call before `_render()`.
func gate_text() -> String:
	_bind_nodes()
	return _gate_label.text if _gate_label != null else _gate_text()


## The bonus line as the player reads it. Safe to call before `_render()`.
func bonus_text() -> String:
	_bind_nodes()
	return _bonus_label.text if _bonus_label != null else _bonus_text()


## Whether the player's carried reach opens the selected domain. A domain with no
## declared gate is always satisfied.
func satisfied() -> bool:
	return _required_reach <= 0.0 or _carried_reach >= _required_reach


func summary() -> Dictionary:
	_bind_nodes()
	return {
		"required_reach": _required_reach,
		"carried_reach": _carried_reach,
		"satisfied": satisfied(),
		"loot_bonus": _loot_bonus,
		"gate": _gate_text(),
		"bonus": _bonus_text(),
	}


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite drives this panel before a scene tree exists. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _gate_label != null:
		return
	_gate_label = get_node_or_null("%GateLabel") as Label
	_bonus_label = get_node_or_null("%BonusLabel") as Label


func _render() -> void:
	if _gate_label == null:
		return
	_gate_label.text = L.t(_gate_text())
	_bonus_label.text = L.t(_bonus_text())


func _gate_text() -> String:
	if satisfied():
		return L.t(GATE_OPEN)
	return L.t("LOC_UI_PANELS_B94EC87E2E") % [int(_required_reach), int(_carried_reach)]


func _bonus_text() -> String:
	return L.t("LOC_UI_PANELS_90D7240F83") % _loot_bonus
