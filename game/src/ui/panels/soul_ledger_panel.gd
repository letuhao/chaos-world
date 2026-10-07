class_name SoulLedgerPanel
extends PanelContainer

## The soul's own condition, and what the last death did.
##
## ## Why this is a panel and not a screen
##
## The soul, the difficulty dial, the anchor works and the save's status are four
## questions a player asks together and four verbs they reach through one page, so
## they belong on ONE routed surface. Four screens would mean four routes and four
## nav slots for one player's condition, and ADR 0128's save status has no verb at
## all — it could never justify a route of its own.
##
## ## What it owns
##
## Every `%d/%d`, every duration and every sentence on this surface (AGENTS.md, UI
## standard). The screen hands raw primitives down and formats none of it.
## `summary()` publishes the counts AND the rendered strings, so a headless test
## asserts the sentence a player reads rather than a pixel.
##
## ## The save half is a STATUS LINE, and it is the whole of ADR 0128
##
## It reports the generation, whether the live slot and a backup exist, and nothing
## else. **There is no control here at all, and there is deliberately no verb that
## reaches the backup** — the player cannot choose to load it, and
## `tests/modules/save/test_save_envelope.gd::test_no_shipped_caller_can_name_the_backup_slot`
## is the guard that makes that a rule rather than an intention. A panel that grew a
## "restore" button would not be a missing feature; it would be a removed invariant.
##
## Contract: `summary()` is the testable surface, primitives only.

## Wording for the last death. The module authored the `reason` constants; these are
## the player-facing sentences for them, kept here beside the rest of this panel's
## vocabulary rather than invented by the screen.
const DEATH_TEXT := {
	"": "This soul has never fallen.",
	"guardian_spent": "A guardian was spent, so the body was kept and the soul untouched.",
	"soul_spent": "The soul spent its last life, and no body was owed back.",
}

const UNWIRED_TEXT := "Nothing is wired to this panel, so it has nothing to report."
const NOT_WIRED_TEXT := "The soul is not reported here, and no save status is wired."
const GENERATION_UNITS := 1
const BACKUP_LINE := "A spare copy of an earlier generation is on disk."
const NO_BACKUP_LINE := "No spare copy exists yet: the first save leaves none behind."
const NO_SAVE_LINE := "Nothing has been written yet."

var _soul: Dictionary = {}
var _death: Dictionary = {}
var _save: Dictionary = {}
var _soul_wired: bool = false
var _save_wired: bool = false
var _integrity_line: String = ""
var _lives_line: String = ""
var _incarnation_line: String = ""
var _arrival_line: String = ""
var _death_line: String = ""
var _save_line: String = ""
var _backup_line: String = ""
var _soul_label: Label = null
var _lives_label: Label = null
var _incarnation_label: Label = null
var _arrival_label: Label = null
var _death_label: Label = null
var _save_label: Label = null
var _backup_label: Label = null
var _bound: bool = false


func _ready() -> void:
	_bind_nodes()
	_render()


## Render the soul and the last death. `soul` is `SoulApi.summary(actor)` verbatim;
## `death` is the composition root's own last-death verdict, passed through
## untouched so a panel reword of it is impossible. `{}` clears the half that is
## empty rather than leaving the last reading painted.
func show_soul(soul: Dictionary, death: Dictionary = {}) -> void:
	_bind_nodes()
	_soul = soul.duplicate(true)
	_death = death.duplicate(true)
	_soul_wired = not _soul.is_empty()
	_integrity_line = _integrity_text()
	_lives_line = _lives_text()
	_incarnation_line = _incarnation_text()
	_arrival_line = _arrival_text()
	_death_line = _death_text()
	_render()


## Render the save's condition. A STATUS LINE: the figures, and no control. The
## caller cannot ask this panel to restore anything, because it publishes no verb
## that could (ADR 0128).
func show_save(status: Dictionary) -> void:
	_bind_nodes()
	_save = status.duplicate(true)
	_save_wired = not _save.is_empty()
	_save_line = _save_text()
	_backup_line = _backup_text()
	_render()


## Everything this panel shows, primitives only, counts beside the rendered strings.
func summary() -> Dictionary:
	_bind_nodes()
	return {
		"soul_wired": _soul_wired,
		"save_wired": _save_wired,
		"integrity": int(_soul.get("integrity", 0)),
		"integrity_max": int(_soul.get("integrity_max", 0)),
		"lives": int(_soul.get("lives", 0)),
		"lives_max": int(_soul.get("lives_max", 0)),
		"incarnation": int(_soul.get("incarnation", 0)),
		"arrival": String(_soul.get("arrival", "")),
		"next_arrival": String(_soul.get("next_arrival", "")),
		"arrivals_left": int(_soul.get("arrivals_left", 0)),
		"can_rebody": bool(_soul.get("can_rebody", false)),
		"damage_count": int(_soul.get("damage_count", 0)),
		"repair_count": int(_soul.get("repair_count", 0)),
		"death_reason": String(_death.get("reason", "")),
		"death_died": bool(_death.get("died", false)),
		"death_guardian": String(_death.get("guardian", "")),
		"death_damage": int(_death.get("damage", 0)),
		"generation": int(_save.get("generation", 0)),
		"primary_present": bool(_save.get("primary_present", false)),
		"backup_present": bool(_save.get("backup_present", false)),
		# Reported so a caller can prove the invariant rather than trust it: this
		# surface publishes no verb at all, so "nothing can load the backup" is a
		# property of the panel and not only of the module.
		"restore_verbs": [],
		"integrity_line": _integrity_line,
		"lives_line": _lives_line,
		"incarnation_line": _incarnation_line,
		"arrival_line": _arrival_line,
		"death_line": _death_line,
		"save_line": _save_line,
		"backup_line": _backup_line,
	}


## Whether the soul half has anything to report. A screen reads this to decide
## whether the surface is a status page or an empty one, rather than inferring it
## from a count of zero.
func has_soul() -> bool:
	_bind_nodes()
	return _soul_wired


## Whether the save half is wired at all. `false` means the seam nobody filled, and
## the panel says so on the row rather than painting a zero generation.
func has_save() -> bool:
	_bind_nodes()
	return _save_wired


# --- Plumbing ---------------------------------------------------------------


## Resolved lazily, never in `@onready`: the headless runner drives this panel
## before a scene tree exists. Idempotent, and every connect guarded.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _bound:
		return
	_soul_label = get_node_or_null("%SoulLabel") as Label
	_lives_label = get_node_or_null("%LivesLabel") as Label
	_incarnation_label = get_node_or_null("%IncarnationLabel") as Label
	_arrival_label = get_node_or_null("%ArrivalLabel") as Label
	_death_label = get_node_or_null("%DeathLabel") as Label
	_save_label = get_node_or_null("%SaveLabel") as Label
	_backup_label = get_node_or_null("%BackupLabel") as Label
	_bound = _soul_label != null and _save_label != null


func _render() -> void:
	if _soul_label == null:
		return
	_soul_label.text = _integrity_line if _soul_wired else NOT_WIRED_TEXT
	_lives_label.text = _lives_line
	_incarnation_label.text = _incarnation_line
	_arrival_label.text = _arrival_line
	_death_label.text = _death_line
	_save_label.text = _save_line if _save_wired else UNWIRED_TEXT
	_backup_label.text = _backup_line
	_death_label.theme_type_variation = &"WarnLabel" if _soul_wired else &"MetaLabel"


## Integrity against its own ceiling. `0/0` never prints, because a soul that
## reported no ceiling at all would read as a soul with nothing left to lose.
func _integrity_text() -> String:
	if not _soul_wired:
		return ""
	if int(_soul.get("integrity_max", 0)) <= 0:
		return "Integrity is not measured."
	return (
		"Integrity %d/%d"
		% [
			int(_soul.get("integrity", 0)),
			int(_soul.get("integrity_max", 0)),
		]
	)


## Lives, and whether the body it is carrying can be lost again. `can_rebody` is the
## facade's own verdict, printed rather than re-derived from a count.
func _lives_text() -> String:
	if not _soul_wired:
		return ""
	var line := (
		"Lives %d/%d"
		% [
			int(_soul.get("lives", 0)),
			int(_soul.get("lives_max", 0)),
		]
	)
	if not bool(_soul.get("can_rebody", false)):
		return line + " - no body is owed back."
	return line + " - a body is owed back."


## The incarnation count, and how much the soul has been through. The two trails are
## counts the ledger already holds, never counters this panel keeps.
func _incarnation_text() -> String:
	if not _soul_wired:
		return ""
	return (
		"Incarnation %d - damaged %d time(s), repaired %d time(s)"
		% [
			int(_soul.get("incarnation", 0)),
			int(_soul.get("damage_count", 0)),
			int(_soul.get("repair_count", 0)),
		]
	)


## Where this soul currently is, and what it has left to arrive into. `arrival` is
## an AUTHORED id, so it is printed as one: the sentence names the arrival rather
## than describing it, because the meaning lives in the content that authored it.
func _arrival_text() -> String:
	if not _soul_wired:
		return ""
	var arrival := String(_soul.get("arrival", ""))
	var line := "Arrival: %s" % ("unnamed yet" if arrival.is_empty() else arrival)
	var next_arrival := String(_soul.get("next_arrival", ""))
	if next_arrival.is_empty():
		return line + " - and no further arrival is owed."
	return (
		"%s - owed next: %s (%d left)"
		% [
			line,
			next_arrival,
			int(_soul.get("arrivals_left", 0)),
		]
	)


## What the last resolved death did, in the module's own vocabulary. A guardian
## death is a death the player SURVIVED, and it is reported as one: integrity did
## not move and the incarnation did not advance, which is the whole difference ADR
## 0130 draws.
func _death_text() -> String:
	if _death.is_empty():
		return String(DEATH_TEXT.get("", "This soul has never fallen."))
	var reason := String(_death.get("reason", ""))
	var line := String(DEATH_TEXT.get(reason, "The last death is unresolved: %s" % reason))
	if not bool(_death.get("died", false)):
		return line
	return "%s Cost %d integrity." % [line, int(_death.get("damage", 0))]


## The save's condition: how many generations have been written, and whether the
## live slot is there. `envelope_version` is reported by the module and not printed
## here, because a player has no action for a schema number and printing it invites
## reading the file.
func _save_text() -> String:
	if not _save_wired:
		return ""
	if not bool(_save.get("primary_present", false)):
		return NO_SAVE_LINE
	return (
		"Saved - generation %d is the live slot."
		% [int(_save.get("generation", 0)) * GENERATION_UNITS]
	)


## Whether a spare copy exists. Reported, never offered: saying a backup is there
## is not a way to reach it, and ADR 0128's rule is that no control offers to.
func _backup_text() -> String:
	if not _save_wired or not bool(_save.get("primary_present", false)):
		return ""
	return BACKUP_LINE if bool(_save.get("backup_present", false)) else NO_BACKUP_LINE
