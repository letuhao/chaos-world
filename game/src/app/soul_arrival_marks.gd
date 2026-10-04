class_name SoulArrivalMarks
extends RefCounted

## Grants a re-embodied soul the fates its ARRIVAL authored, on the death that mints it
## (ADR 0190). `SoulDef.marks` was authored on all three shipped arrivals and read by NOTHING
## in `game/src`; this is the earn path it was always the hook for.
##
## ## What a mark IS, and the one thing it may never be
##
## A mark is a plain fate id in destiny's OWN catalog, named on the arrival the soul earned by
## dying. Never `soul:<id>`: an id the catalog cannot resolve "reads as a working reference and
## silently grants nothing" (ADR 0135), so a namespaced one would leave every mark authored and
## none earned, with no error anywhere.
##
## ## `earn_fate` and NOTHING else
##
## No destiny, no group, no picker (ADR 0181 guard 4, ADR 0159): an arrival is a receipt
## recorded in `SoulState.origins`, not a claim. `earn_destiny` would put a rebirth into the
## `origin` exclusivity set and hand the player the destination picker ADR 0065 forbids.
##
## ## ## Why this is in `app/` and not in `soul/`
##
## Three reasons, all load-bearing. `LAYER_DEPS["app"] == {"*"}` exempts this layer, so the
## grant creates NO `soul -> destiny` edge and `soul` keeps declaring exactly
## `[contracts, core, items]`. `soul_death.gd` is already past `LINE_BUDGET = 400` and a fourth
## carry would push it further. And NEITHER FACADE CAN GROW: `SoulApi` is at 12/12 and
## `DestinyApi` is at 12/12, so there is no legal home for a `grant_marks` verb at all.
##
## ## Everything is injected
##
## The exact shape `SoulDeath` already uses at `:104-106`: `app/` code takes its collaborators
## through its own constructor or reaches them through a facade, never by loading them itself,
## which is what keeps this a plain `RefCounted` a headless test can drive without a scene tree.
##
## ## The marks are PURE NARRATIVE
##
## All four ship with zero `flat_modifiers` and zero `percent_modifiers`. A modifier on a mark
## would move `DestinyProjection.modifier_count`, and
## `test_soul_fate_across_rebirth.gd` asserts that count is UNCHANGED across a death — a
## modifier turns that shipped guard red and reopens DEF-0241's balance scope.

## The `source` string every arrival grant carries. It names the SYSTEM, never the fate id
## (ADR 0065), so a consumer asking "how was this earned" reads `soul_arrival:<arrival_id>`
## and cannot mistake one mark's grant for another's. The ARRIVAL, not the mark, so the history
## discriminator stays unique per grant rather than colliding across a ladder that names the
## same fate twice.
const SOURCE_PREFIX := "soul_arrival:"


## The fates `arrival_id` is owed, resolved through `SoulCatalog` exactly as
## `CharacterCreationFlow.build_forced` resolves `SoulDef.race_id` — an authored arrival read
## off its own `SoulDef`, never a table restated in code.
##
## `[]` for an unknown arrival or one naming no mark. Empty rather than an invented
## definition: an unknown arrival is a content bug and guessing would hide it.
static func marks_for(arrival_id: StringName) -> Array[StringName]:
	var def := SoulCatalog.instance().arrival_definition(arrival_id)
	if def == null:
		return []
	return def.marks


## Earn every mark of `arrival_id` onto `body`. Returns `{ok, marks, ungranted}`: `marks` is
## what the arrival authored, `ungranted` is what is NOT held afterwards.
##
## ## Why `ungranted` exists rather than a silent no-op
##
## `earn_fate` refuses an unknown id and an ALREADY-HELD one IDENTICALLY — same empty return,
## no error (ADR 0134 §1a). So "granted" and "already held" and "named a fate the catalog does
## not define" are indistinguishable from the call. `ungranted` names itself: it is the only
## way the caller learns a mark is missing, and the typo it catches is the one the whole
## design exists to make impossible.
##
## ## The read-after-write is the `has_fate` idiom from `character_creation_flow.gd:292`
##
## `DestinyApi.earn_fate` is exactly-once, so the answer has to be READ, not inferred from the
## earn. Verbatim shape, deliberately: this is the one call in the repo that already asks
## "did that land" the honest way.
static func grant(body: Actor, arrival_id: StringName) -> Dictionary:
	var marks := marks_for(arrival_id)
	var ungranted: Array[StringName] = []
	for mark_id in marks:
		DestinyApi.earn_fate(body, mark_id, "%s%s" % [SOURCE_PREFIX, arrival_id])
		if not DestinyApi.has_fate(body, mark_id):
			ungranted.append(mark_id)
	return {"ok": ungranted.is_empty(), "marks": marks, "ungranted": ungranted}
