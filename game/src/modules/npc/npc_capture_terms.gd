class_name NpcCaptureTerms
extends RefCounted

## WHICH AUTHORED INDIVIDUALS MAY BE TAKEN (ADR 0247) — the read model behind a custody claim.
##
## ## Why this is a named type and not a `NpcApi` method
##
## `NpcApi` publishes exactly `MAX_FACADE_PUBLIC_METHODS` (12) methods, and the cap binds
## immediately — `TechniquesApi` records the same thing when it moved `activate` to
## `TechniqueCasting` behind a published `CASTING_COMPONENT`. So the question this answers is
## reached as a named type, which is what keeps the facade's surface an interface rather than a
## list of everything the module can do.
##
## **`custody` is at the cap too and gained NOTHING.** It already had a correct `capture`; what
## it lacked was a caller, and this file is that caller's question rather than a thirteenth verb
## on either module.
##
## ## What it publishes, and what it does not
##
## Primitives only: `{subject_id, subject_kind, term_id, periods}` for every def that authors a
## custody term. It is a READ model — it writes no row, holds no state, owns no clock and takes
## no `Actor` — and it decides nothing about whether a particular actor may be taken. ADR 0104
## leaves that condition to the caller, and a capture threshold belongs to `combat`; what was
## missing was the SUBJECT LIST, and this is it.
##
## ## No prose, ever
##
## A term is a term id and a count of periods. There is no `description`, no `flavor` and no
## `display_name` here or on the `NpcDef` behind it, because ADR 0104's rule that a custody
## record carries none holds on the AUTHORED side of the record too, and prose in content becomes
## the thing a panel ends up reading.

## The `subject_kind` every capturable individual is reported under. It is the one value
## `CustodyState.SUBJECT_KINDS` ships — the other, `player`, is closed and reserved for a
## `PlayerDef` that does not exist — and it is spelled HERE rather than read off `CustodyState`,
## because `npc` declares no `custody` edge and reaching a sibling module's interior would be an
## undeclared dependency `tools arch` fails on. One literal, one place, read only by the caller
## that is allowed to name both.
const SUBJECT_KIND := &"npc"


## Every authored individual in the catalog that may be TAKEN, as primitives only and in a
## stable order — `NpcCatalog.npc_ids()` is sorted, and a dictionary's iteration order is not an
## order a player can be shown twice.
##
## ## Every capturable individual, not only the ones the player has met
##
## `NpcPresence` is deliberately NOT a filter. A player has to be able to walk to a capturable
## subject and see it offered, and a "you must have met them first" gate would be a second,
## invisible condition layered on the one ADR 0104 already left to the caller — and it would be
## invisible precisely because presence is the `npc` module's read model and custody is a ledger
## row it may consult, never the reverse.
##
## **Bounded by the catalog**: one row per authored def, read once, never a walk over live bodies.
static func capturable() -> Array:
	var out: Array = []
	var catalog := NpcCatalog.instance()
	for npc_id in catalog.npc_ids():
		var def := catalog.definition(npc_id)
		if def == null:
			continue
		var term := def.capture_term_row()
		if term.is_empty():
			continue
		(
			out
			. append(
				{
					"subject_id": String(npc_id),
					"subject_kind": SUBJECT_KIND,
					"term_id": String(term["term_id"]),
					"periods": int(term["periods"]),
				}
			)
		)
	return out
