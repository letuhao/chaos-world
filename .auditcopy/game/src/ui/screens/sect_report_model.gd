class_name SectReportModel
extends RefCounted

## The sect screen's REPORTING: every read model [SectScreen] publishes that is
## computed from the facade's own snapshot rather than from the widget tree.
##
## ## Why this is not code in the screen
##
## Everything here answers "what does the facade say, as primitives" — the claim the
## row published, the promotion routes, the catalog for comparison, the ids the board
## is showing, and the authored price of founding. None of it paints, wires a signal,
## gates a button or calls a verb. The screen answers "what can this screen DO", and
## those are two reasons to change: a new field the sect facade publishes, a retuned
## `.tres`, or a new promoted row shape touches this file and not that one. That is the
## same split `domain_explore_model.gd` makes beside the world map.
##
## ## Why every read takes its input as an ARGUMENT
##
## Nothing is bound here, so there is no state that can go stale between a refresh and
## a `summary()`. A headless test drives the screen with no scene tree at all, and a
## cached row pool would then answer with rows the screen has not mounted. Passing the
## snapshot and the pools per call means every reader sees exactly the state the screen
## is holding RIGHT NOW, which is the property `summary()` is asserted on.
##
## ## The row pools are passed, never owned
##
## `claim_summary` and `office_ids` read rows the screen mounted; they do not build,
## grow, free or format one. A spare pool row renders `{}` and reads as `""`, which is
## what makes the reported count the sect's AUTHORED board rather than the size of the
## pool the scene happened to mount — the dead-content failure ADR 0063 shipped once.


## The member's own claim, nested under its own key. `{}` when nothing rendered, so
## a caller reads "no claim row" rather than a half-filled shape.
func claim_summary(claim_rows: Array) -> Dictionary:
	if claim_rows.is_empty():
		return {}
	return (claim_rows[0] as SectClaimRow).summary()


## Every promotion route the facade published, as primitives. The screen formats
## none of it: `reason` is the facade's named string, passed through untouched.
func promotion_summaries(codex: Dictionary) -> Array:
	var out: Array = []
	var promotion: Dictionary = codex.get("can_promote", {}) as Dictionary
	var ids := promotion.keys()
	ids.sort()
	for office_id in ids:
		var view: Dictionary = promotion[office_id]
		(
			out
			. append(
				{
					"office_id": String(view.get("id", "")),
					"display_name": String(view.get("display_name", "")),
					"standing_floor": int(view.get("standing_floor", 0)),
					"below_floor": bool(view.get("below_floor", false)),
					"held": int(view.get("held", 0)),
					"has_room": bool(view.get("has_room", false)),
					"reason": String(view.get("reason", "")),
				}
			)
		)
	return out


## Every authored sect the facade listed, as primitives, canonically ordered.
func sect_summaries(codex: Dictionary) -> Array:
	var out: Array = []
	var sects: Dictionary = codex.get("sects", {}) as Dictionary
	var ids := sects.keys()
	ids.sort()
	for sect_id in ids:
		var view: Dictionary = sects[sect_id]
		(
			out
			. append(
				{
					"sect_id": String(sect_id),
					"display_name": String(view.get("display_name", "")),
					"doctrine_id": String(view.get("doctrine_id", "")),
					"sworn": String(sect_id) == String(codex.get("sect_id", "")),
					"position_count": (view.get("positions", {}) as Dictionary).size(),
				}
			)
		)
	return out


## The office ids the board is showing, in display order.
##
## A SPARE pool row is not an office and is not reported: it renders `{}` and its id
## reads as `""`, so it is dropped here. That is what makes the reported count equal
## the sect's AUTHORED board rather than the size of the pool the scene happened to
## mount — a sect that authors four offices and a screen that reports twelve has
## invented eight offices, which is the dead-content failure ADR 0063 already
## shipped once.
func office_ids(office_rows: Array) -> Array:
	var out: Array = []
	for row in office_rows:
		var office_id := String((row as NationOfficeRow).office_id())
		if office_id != "":
			out.append(office_id)
	return out


## The sect ids the catalog offers, canonically ordered. A member is offered the whole
## catalog too — leaving is a `leave`, and re-swearing is the two in order — so this is
## the same list whatever the membership is.
func offered_ids(codex: Dictionary) -> Array:
	var out: Array = []
	var catalog: Dictionary = codex.get("sects", {}) as Dictionary
	var ids := catalog.keys()
	ids.sort()
	for sect_id in ids:
		out.append(String(sect_id))
	return out


## The authored price of founding `sect_id`, as primitives. Read off the facade's own
## `sect_view.founding_cost` — never re-derived — so the number a panel prints is the
## number `SectApi.found` charges.
func founding_cost_view(codex: Dictionary, sect_id: String) -> Dictionary:
	var catalog: Dictionary = codex.get("sects", {}) as Dictionary
	var view: Dictionary = catalog.get(sect_id, {}) as Dictionary
	var cost: Dictionary = view.get("founding_cost", {}) as Dictionary
	return {
		"sect_id": sect_id,
		"currency": String(cost.get("currency", "")),
		"amount": int(cost.get("amount", 0)),
		"found": int(cost.get("found", 0)),
		"outstanding": int(cost.get("outstanding", 0)),
	}


## `values` as an array of strings, or `[]` when it is not an array at all. Every
## string list the facade publishes (`duties`, `authorities`) passes through here, so
## `summary()` carries no engine type.
func string_list(values: Variant) -> Array:
	var out: Array = []
	if not (values is Array):
		return out
	for value in values as Array:
		out.append(String(value))
	return out
