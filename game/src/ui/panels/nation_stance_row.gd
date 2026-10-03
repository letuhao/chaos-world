class_name NationStanceRow
extends PanelContainer

## One stance, as `NationApi.summary(actor)` publishes it under `stances`:
## `{pair_key, a_id, b_id, verb, other_id, sequence}`.
##
## ## ADR 0047's symmetry, made visible
##
## The facade stores ONE canonical row per UNORDERED pair, keyed by the two ids
## ordered lexicographically, so this panel never has to ask "which side is me?" to
## know who the other party is — `other_id` is on the row. What this panel does have
## to get right is that a swapped read produces the SAME row: it prints the verb and
## the two ids, never a directional sentence like "A regards B as", because a
## one-sided opinion is structurally impossible in the data and must not reappear
## in the prose.
##
## The verbs are a CLOSED set (`rival`, `neutral`, `allied`, `truce`, `embargo`,
## `war`) and `war` only ever appears here because a declaration wrote it. An
## unreadable verb is printed as itself rather than silently defaulting to neutral
## (ADR 0085).
##
## `summary()` is the testable surface.

const UNKNOWN_TEXT := "stance unread"
const PARTNER_PREFIX := "with"
const IDENTITY_TEXT := "against"

var _view: Dictionary = {}
var _head: String = ""
var _partner: String = ""
var _meta: String = ""
var _head_label: Label = null
var _partner_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one stance row. An empty dictionary clears and hides the row — a spare
## pool row is not a neutral stance, and printing it as one would put a `neutral`
## in front of a player that nobody ever declared.
func show_stance(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_partner = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	var verb := String(_view.get("verb", ""))
	_head = verb if verb != "" else UNKNOWN_TEXT
	_partner = _partner_text()
	_meta = _meta_text()
	_render()


func clear() -> void:
	show_stance({})


## Everything the row shows, primitives only. `{}` when the row carries nothing.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"pair_key": String(_view.get("pair_key", "")),
		"a_id": String(_view.get("a_id", "")),
		"b_id": String(_view.get("b_id", "")),
		"other_id": String(_view.get("other_id", "")),
		# Printed verbatim: the verb set is closed and an unread one is refused at
		# the facade, so a value here is one a player declared or a declaration wrote.
		"verb": String(_view.get("verb", "")),
		"known_verb": verb_is_known(),
		"sequence": int(_view.get("sequence", 0)),
		"head": _head,
		"partner_line": _partner,
		"meta": _meta,
		"head_tone": String(_head_tone()),
		"card_tone": String(_card_tone()),
		"focus_target": "NationStanceRow",
	}


## Whether this stance EXISTS. A pair nobody has ever taken a position with is not
## a neutral pair — it is a pair this row says nothing about, and the two are
## different claims.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether the printed verb is one of the closed set. A row whose verb is not in the
## set is a ledger this build could not read, and it is rendered in the warning tone
## rather than dressed up as something it is not.
func verb_is_known() -> bool:
	var verb := String(_view.get("verb", ""))
	return verb in ["rival", "neutral", "allied", "truce", "embargo", "war"]


func pair_key() -> String:
	return String(_view.get("pair_key", ""))


func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_partner_label = get_node_or_null("%PartnerLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_head_label.text = _head
	_head_label.theme_type_variation = _head_tone()
	_partner_label.text = _partner
	_meta_label.text = _meta


## War is the only stance with a standoff attached, so it is the only one that gets
## its own card. Every other verb shares the quiet card.
func _card_tone() -> StringName:
	return &"WarStanceCard" if String(_view.get("verb", "")) == "war" else &"StanceCard"


func _head_tone() -> StringName:
	if not verb_is_known():
		return &"WarnLabel"
	return &"WarStanceLabel" if String(_view.get("verb", "")) == "war" else &"SeatLabel"


## Both ids of the pair, in the order the canonical key stores them. Printing the
## pair rather than "you vs them" is what keeps this row symmetric under a swapped
## read.
func _partner_text() -> String:
	return (
		"%s %s and %s"
		% [PARTNER_PREFIX, String(_view.get("a_id", "")), String(_view.get("b_id", ""))]
	)


func _meta_text() -> String:
	return (
		"%s · %s · set at %d"
		% [
			String(_view.get("pair_key", "")),
			IDENTITY_TEXT if String(_view.get("verb", "")) == "war" else "in force",
			int(_view.get("sequence", 0)),
		]
	)
