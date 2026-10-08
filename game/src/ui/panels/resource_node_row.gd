class_name ResourceNodeRow
extends PanelContainer

## One resource node as a gather screen shows it, from [method ForageApi.view].
##
## ## The three custody states are THREE rows, never two greys
##
## A node the hero HOLDS, a node nobody holds, and a node somebody else holds while
## a standoff is open are three different facts about the world, and they are the
## same three ADR 0083 states a nation's board renders. So this row takes the SAME
## card and label variations a filled seat and a vacant seat take — `FilledSeatCard`
## against `VacantSeatCard`, and `ContestedClaimCard` for the open standoff — rather
## than inventing a second visual vocabulary for a second institution.
##
## ## It owns EVERY number on the row
##
## `yield_per_period`, `upkeep_per_period`, `condition`, `depletion`, `claim_floor`,
## `meets_floor` and `accrued` all arrive raw and are printed HERE, as AGENTS.md's UI
## standard requires: "no number formatting in a screen — the panel owns `%d/%d`, decimals
## and widths." The screen hands this row a primitives dictionary and formats nothing.
##
## ## `{}` is the FIRST state, not a blank row
##
## `show_node({})` is a spare row in the pool that no authored node occupies: it
## clears, hides and reports `{}`. A node that EXISTS but is unheld arrives with
## `vacant: true` and renders as a visible card — the distinction a widget pool
## makes for free and one a collapsed row would throw away.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` when unfilled.

## Stands in for a node the hero holds. A word, never the id and never a dash: an
## absent holder is a value that is ABSENT, and "-" would read as an authored value.
const VACANT_TEXT := "LOC_UI_PANELS_1966F9678D"
const UNKNOWN_TEXT := "LOC_UI_PANELS_70CA95AB53"
const HELD_PREFIX := "LOC_UI_PANELS_755844BC39"
const CONTESTED_SUFFIX := "LOC_UI_PANELS_AB9302DA1F"
## A node the catalog does not author and the yield table does not name, so the
## row is asked about something this build does not ship. Said in words rather than
## rendered as an empty card.
const UNKNOWN_KIND := "LOC_UI_PANELS_E0D21B1EA6"
## "yields 5 a period · keeps 5 more". `periods` is the module's word (DEF-0111), so
## the row uses it rather than inventing a unit.
const META_SEP := "·"

var _view: Dictionary = {}
var _head: String = ""
var _custody: String = ""
var _rates: String = ""
var _meta: String = ""
var _head_label: Label = null
var _custody_label: Label = null
var _rates_label: Label = null
var _meta_label: Label = null


func _ready() -> void:
	_bind_nodes()
	_render()


## Render one node as [method ForageApi.view] publishes it.
##
## An EMPTY dictionary is ADR 0083's FIRST state — no node is on this row — so the
## row clears itself and hides. That is the whole difference between a spare row in
## a pool and an authored node nobody holds, and it is why the two are not the same
## call.
func show_node(view: Dictionary) -> void:
	_bind_nodes()
	if view.is_empty():
		_view = {}
		_head = ""
		_custody = ""
		_rates = ""
		_meta = ""
		_render()
		return
	_view = view.duplicate(true)
	_head = String(_view.get("display_name", ""))
	if _head == "":
		_head = String(_view.get("node_id", ""))
	if _head == "":
		_head = UNKNOWN_TEXT
	_custody = _custody_text()
	_rates = _rates_text()
	_meta = _meta_text()
	_render()


func clear() -> void:
	show_node({})


## Everything the row shows, primitives only. `{}` when no node is on this row —
## never a shaped row with empty fields, which is what would make a spare pool row
## and an authored-but-unheld node read alike.
func summary() -> Dictionary:
	_bind_nodes()
	if not is_filled():
		return {}
	return {
		"node_id": node_id(),
		"display_name": String(_view.get("display_name", "")),
		"kind": String(_view.get("kind", "")),
		"realm": String(_view.get("realm", "")),
		# ADR 0083's custody states, carried into the testable surface as THREE
		# distinct facts so a reader never has to infer one from the absence of
		# another. `held` is about THIS hero; `vacant` is about the node existing with
		# no holder; `contested` is about an open standoff on ground somebody holds.
		"known": bool(_view.get("known", false)),
		"held": is_held(),
		"vacant": is_vacant(),
		"contested": is_contested(),
		"permits": bool(_view.get("permits", false)),
		"workable": bool(_view.get("workable", false)),
		"item_id": String(_view.get("item_id", "")),
		"yield_per_period": int(_view.get("yield_per_period", 0)),
		"upkeep_per_period": int(_view.get("upkeep_per_period", 0)),
		"condition": int(_view.get("condition", 0)),
		"depletion": int(_view.get("depletion", 0)),
		"claim_floor": int(_view.get("claim_floor", 0)),
		# ADR 0248: the gate the floor imposes, already evaluated against THIS hero's
		# holding count. Published beside the floor it is read against so a row can say
		# "not yet" rather than leaving a panel to re-derive the rule.
		"meets_floor": bool(_view.get("meets_floor", false)),
		"accrued": int(_view.get("accrued", 0)),
		# The row's OWN sentences, so a test reads the rendered figure and not only
		# the raw number behind it — which is the half of "the panel owns the format"
		# that a number-only assertion cannot see.
		"head": _head,
		"custody_line": _custody,
		"rates_line": _rates,
		"meta": _meta,
		"card_tone": String(_card_tone()),
		"head_tone": String(_head_tone()),
		"focus_target": "ResourceNodeRow",
	}


## Whether a node is ON this row. An authored node nobody holds answers true and
## renders; a spare row in the pool answers false and does not.
func is_filled() -> bool:
	return not _view.is_empty()


## Whether the bound hero holds this node — the one custody state that makes the
## harvest reachable at all.
func is_held() -> bool:
	return is_filled() and bool(_view.get("held", false))


## Whether the node exists with no holder. Never rendered as a held node in quieter
## ink: that is the state `claim` acts on, and it has to look available.
func is_vacant() -> bool:
	return is_filled() and bool(_view.get("vacant", false))


## Whether an open standoff stands on this node. ADR 0085: a claim on held ground
## moves nothing, so this row is showing somebody else's ground with a challenger
## written against it — not a node waiting to be taken.
func is_contested() -> bool:
	return is_filled() and bool(_view.get("contested", false))


func node_id() -> String:
	return String(_view.get("node_id", ""))


## Give the keyboard and pad a landing spot. The target is recorded first, because a
## node outside a viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if is_inside_tree():
		grab_focus()


# --- Plumbing ---------------------------------------------------------------


## Resolve the scene's widgets on first use rather than in `@onready`: the headless
## suite runner drives this row before a scene tree exists, so `_ready()` is not a
## dependable place to bind them. Idempotent.
func _bind_nodes() -> void:
	L.localize_tree(self)
	if _head_label != null:
		return
	_head_label = get_node_or_null("%HeadLabel") as Label
	_custody_label = get_node_or_null("%CustodyLabel") as Label
	_rates_label = get_node_or_null("%RatesLabel") as Label
	_meta_label = get_node_or_null("%MetaLabel") as Label


func _render() -> void:
	if _head_label == null:
		return
	visible = is_filled()
	theme_type_variation = _card_tone()
	if not visible:
		return
	_head_label.text = L.t(_head)
	_head_label.theme_type_variation = _head_tone()
	_custody_label.text = L.t(_custody)
	_custody_label.theme_type_variation = _custody_tone()
	_rates_label.text = L.t(_rates)
	_meta_label.text = L.t(_meta)


## The card this node paints itself with. A standoff is its OWN card rather than a
## tint of the vacant one: ADR 0085's whole claim is that a challenge moves no
## ground, and a player who cannot see that distinction reads it as a takeover.
func _card_tone() -> StringName:
	if is_contested():
		return &"ContestedClaimCard"
	return &"VacantSeatCard" if is_vacant() else &"FilledSeatCard"


## A vacant node's name is still its name — the node exists — but it is printed in
## the vacancy tone so the eye finds the gap without reading the line under it.
func _head_tone() -> StringName:
	if is_contested():
		return &"ContestedClaimLabel"
	return &"VacantSeatLabel" if is_vacant() else &"SeatLabel"


## "Yours" is the quiet tone, because holding ground is the expected state. "Vacant"
## is the loud one, because it is the state a claim acts on and a contested row is
## louder still.
func _custody_tone() -> StringName:
	if is_contested():
		return &"ContestedClaimLabel"
	return &"VacantSeatLabel" if is_vacant() else &"SeatHolderLabel"


## "Yours" / "Vacant" / "Vacant · contested". A held node the hero may not yet work
## says so on this line rather than pretending the hold is enough — ADR 0097's realm
## gate is a gate, and a row that said only "Yours" would read as "press and get
## goods".
func _custody_text() -> String:
	if is_contested():
		return (
			L.t("LOC_UI_PANELS_D342B2A250")
			% [L.t(VACANT_TEXT), L.t(META_SEP), L.t(CONTESTED_SUFFIX.strip_edges())]
		)
	if is_vacant():
		return L.t(VACANT_TEXT)
	if not bool(_view.get("permits", false)):
		return L.t("LOC_UI_PANELS_D342B2A250") % [L.t(HELD_PREFIX), L.t(META_SEP), _realm_line()]
	return L.t(HELD_PREFIX)


## The yield and the upkeep, both raw figures, both this row's. Upkeep is printed
## whenever the node declares one even if nothing has been charged yet, because
## upkeep is what makes a claim a decision rather than a free grab (ADR 0097) and a
## player should read the price before taking the ground.
func _rates_text() -> String:
	var line := L.t("LOC_UI_PANELS_A1ADBE4E4C") % int(_view.get("yield_per_period", 0))
	if String(_view.get("item_id", "")) == "":
		line = "%s %s %s" % [line, META_SEP, UNKNOWN_KIND]
	var upkeep := int(_view.get("upkeep_per_period", 0))
	if upkeep > 0:
		line = "%s %s keeps %d a period" % [line, META_SEP, upkeep]
	return line


## "foundation · 12 of 24 left · 0 accrued". The first pair is the node's band and
## what is left of it, which is what tells a player whether a second press is worth
## anything; `depletion = 0` is inexhaustible by the node's own documentation, so it
## prints "inexhaustible" rather than "0 of 0", which would read as a spent vein.
func _meta_text() -> String:
	var parts: Array[String] = []
	var realm := String(_view.get("realm", ""))
	if realm != "":
		parts.append(realm)
	var depletion := int(_view.get("depletion", 0))
	if depletion > 0:
		parts.append("%d of %d left" % [int(_view.get("condition", 0)), depletion])
	else:
		parts.append("inexhaustible")
	var accrued := int(_view.get("accrued", 0))
	if accrued > 0:
		parts.append("%d accrued" % accrued)
	return META_SEP.join(parts)


## The band the hero has not reached, named rather than numbered. The ladder is the
## module's; a screen that printed an index would be restating a rule it cannot read.
func _realm_line() -> String:
	var realm := String(_view.get("realm", ""))
	return (
		L.t("LOC_UI_PANELS_F5541C0CA4") % realm if realm != "" else L.t("LOC_UI_PANELS_3321009C6D")
	)
