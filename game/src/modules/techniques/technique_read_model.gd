class_name TechniqueReadModel
extends RefCounted

## Every primitive-only projection a screen renders, built for a UI program that
## owns all formatting (AGENTS.md's UI standard: a screen passes raw values to a
## panel, and the panel owns every `%d`, decimal and width).
##
## Nothing here mutates. A projection reads the codex, the slot table, the upkeep
## tracker and the catalog, and answers a question; it never writes state, so a
## panel can render as often as it likes without a preview costing anything.


## The whole codex and the whole loadout: counts, the tier's slot budget, every
## slot with what fills it, every entry with its rung, and what is suspended.
static func summary(
	actor: Actor,
	codex: TechniqueCodex,
	slot_table: TechniqueSlots,
	upkeep: TechniqueUpkeep,
	tier: int
) -> Dictionary:
	if actor == null:
		return {}
	var slots := slot_table.all()
	var equipped_ids := slot_table.equipped(tier)
	var rows: Array = []
	for slot_key in TechniqueSlots.slot_keys(tier):
		rows.append(slot_view(upkeep, slot_key, slots))
	var entries: Array = []
	for entry in codex.entries():
		entries.append(entry_view(slot_table, upkeep, entry, equipped_ids))
	return {
		"realm_tier": tier,
		"codex_count": codex.count(),
		"equipped_count": equipped_ids.size(),
		"slot_total": int(TechniquePolicy.slot_budget(tier)["total"]),
		"slot_free": free_total(slot_table, tier),
		"equipped_ids": _strings(equipped_ids),
		"slots": rows,
		"entries": entries,
		"suspended": _strings(upkeep.suspended()),
	}


## One technique in full: identity, grade, path, costs, the mastery ladder, the
## effects it would contribute and both gates.
##
## ## THE ONE DOOR to a learn preview (DEF-0300)
##
## This used to sit beside a second `learn_preview`, which published the same shape
## under different key names (`price` for `learn_price`, `can_learn` for
## `known && can_learn`). Nothing in the tree called it but one assertion in another
## program's suite, so it was not a second door anyone walked through — it was a
## second SHAPE of the same door, and the two had already drifted on the one key
## they both answered. A second reader of a learn's terms is the hazard ADR 0196
## names about margins and ADR 0053 names about learning: a preview is worth exactly
## what the learn it predicts is worth, and two predictions can only disagree.
##
## So the second one is deleted rather than wired, and this function is the whole
## preview — including `learn_price`, `learn_unmet`, `can_pay`, `learn_short` and
## `marginal_band`. The only caller it had read nothing this did not, and read it
## through the door a player would.
static func inspect(
	actor: Actor,
	codex: TechniqueCodex,
	slot_table: TechniqueSlots,
	upkeep: TechniqueUpkeep,
	def: TechniqueDef,
	learn_unmet: Array,
	equip_unmet: Array
) -> Dictionary:
	if actor == null or def == null:
		return {}
	var entry := codex.entry(def.id)
	var rung := 0 if entry == null else entry.mastery_rung
	# What a learn would cost this actor, and whether they can pay it BEFORE the
	# manual is consumed. ADR 0160 made `learn` charge the technique's own path's
	# `progress` all-or-nothing, so both the price and the shortfall are knowable in
	# advance. Publishing only `learn_price` left a player learning the cost by
	# spending the book and then being refused.
	#
	# The shortfall is the SAME list `TechniquesApi._short` produces on the learn path.
	# A screen computing its own affordability would restate the module's rule in
	# `ui/`, and the two would disagree the moment either moved. `can_pay_known` says
	# the answer is real: a SHARED technique is never charged, so "you can pay" is
	# true for a reason no price should be shown against.
	var owed := _owed(actor, def)
	var short := _short(actor, owed)
	var view := {
		"id": String(def.id),
		"display_name": def.display_name,
		"description": def.description,
		"grade": String(def.grade),
		"rarity": String(def.rarity),
		"element": String(def.element),
		"schools": _strings(def.schools),
		"tags": _strings(def.tags),
		"active": def.active,
		"path": String(def.path),
		"paths": _strings(def.path_ids()),
		"shared": def.is_shared(),
		"magnitude": def.magnitude,
		# ADR 0069: the qi path's elemental share, surfaced beside `element` so a
		# panel can say how much of this is elemental without opening the `.tres`.
		# A technique that authored none reads `0.0` -- "use the default" -- which
		# is a different statement from `element == ""`.
		"element_share": def.element_share,
		# The SAME call `CombatSpine.base_damage` prices a hit with, on the SAME realm id,
		# so the number on screen is the number the blow is built from. It read
		# `TechniqueGate.best_ordinal(actor)` -- the highest cultivation path -- which the hit
		# never did: the two disagreed for any actor whose paths diverged, and on top of that
		# they read two different ladders. Which realm a SHARED technique follows is owed its
		# own decision; this stops the two surfaces disagreeing in the meantime.
		"magnitude_now": def.magnitude * TechniqueMagnitudeTable.factor(actor.realm()),
		"qi_cost": def.qi_cost,
		"stamina_cost": def.stamina_cost,
		"cooldown": def.cooldown,
		"learn_price": TechniqueGate.learn_price_for(actor, def),
		"known": entry != null,
		"equipped": slot_table.is_equipped(def.id),
		"suspended": upkeep.is_suspended(def.id),
		"rung": rung,
		"rung_count": def.mastery_rungs,
		"mastery": mastery_view(def, rung),
		"mastery_ladder": ladder_view(def),
		# ## How THIS technique's ladder is climbed, and why it had to be published
		#
		# The player-visible half of DEF-0304 was not the missing input but the
		# ladder: `mastery_ladder` rendered five rungs of a passive with no verb
		# behind any of them, because an active climbs by firing and a passive had
		# nothing to fire. ADR 0247 gave it one — `worn`, a rung per settled upkeep
		# interval while equipped — and this is the key a panel prints next to the
		# ladder so the rows are not an aspiration.
		#
		# Read from `TechniqueUpkeep.MASTERY_BY` rather than spelled here, so the
		# projection and the settle loop cannot disagree about the verb: a screen
		# told `worn` while the settle loop earned it by casting would be the same
		# "one stat, two answers" hazard ADR 0160 refuses.
		"mastery_by":
		(
			String(TechniqueCasting.MASTERY_BY)
			if not def.is_passive()
			else String(TechniqueUpkeep.MASTERY_BY)
		),
		"effects": effect_view(def, entry),
		# The printed text against this copy's ANNOTATIONS (ADR 0196): what the
		# sheet says and what this copy says. `marginal` is empty for an active
		# technique and for a row carrying no margin, which is why a panel shows the
		# authored column alone rather than a difference nobody can compute.
		"authored_effects": effect_view(def, null),
		"marginal": effect_view(def, entry, true),
		# The RANGE a copy of this manual may read (ADR 0196/0204): the two edges
		# `TechniqueMarginalia.draw` rolls between, read through `band_for` so a
		# screen and the roll can never disagree about how wide the band is.
		# Published even when this row has no margin yet — a hero deciding whether
		# to spend a manual on it needs to know what the sheet is worth varying by.
		# `marginal_banded` says whether the edges bite at all: a COMMON copy spans
		# `1.0 .. 1.0`, and a player told "1.0-1.0" would read a precision nobody
		# authored. A capacity option is carried at its authored value and is not
		# banded, so a manual whose options are all capacity reads unbanded too.
		"marginal_band": _band(def),
		"marginal_banded": _band_bites(def, entry),
		"marginal_band_figures": _band_figures(def, entry),
		"learn_unmet": learn_unmet,
		"equip_unmet": equip_unmet,
		"claimable_slots":
		_strings(slot_table.claimable(TechniquePolicy.tier_of(actor.realm()), def)),
		"can_pay": short.is_empty(),
		"can_pay_known": not owed.is_empty() or def.is_shared(),
		"learn_short": short,
	}
	return view


## What `learn` would charge, as `{path_id: price}`. Empty for a SHARED technique
## (`shared` is not a `PathState` id) or a free one — which is exactly when
## affordability is not a question, so `can_pay_known` is what distinguishes
## "you can afford it" from "there is nothing to afford".
static func _owed(actor: Actor, def: TechniqueDef) -> Dictionary:
	if actor == null or def == null or def.is_shared():
		return {}
	var price := TechniqueGate.learn_price_for(actor, def)
	if price <= 0.0:
		return {}
	var paths: Array[StringName] = def.path_ids()
	if paths.is_empty() or not PathState.ALL.has(paths[0]):
		return {}
	return {paths[0]: price}


## Every pool this study cannot pay, with what it owed and what it held — the shape
## `TechniquesApi.learn` refuses on, published so a panel can say "you need 100,
## you have 40" rather than only "not affordable".
##
## The SAME loop `TechniquesApi._short` runs, in the same order and over the same
## `{path_id: price}` map, and the same epsilon it allows — so the shortfall a hero
## reads on the codex is by construction the shortfall the `learn` refuses on. This
## is the one place that sameness is asserted: `test_technique_study_preview.gd`
## drives a real short actor through both and compares the owed figure.
static func _short(actor: Actor, owed: Dictionary) -> Array:
	var out: Array = []
	if actor == null:
		return out
	for path_id in owed.keys():
		var state := actor.path(path_id)
		var held := 0.0 if state == null else state.progress
		var required := float(owed[path_id])
		if held + TechniquesApi.EPSILON >= required:
			continue
		out.append({"resource": String(path_id), "required": required, "current": held})
	return out


## One rung's multipliers, clamped to what the def actually authorises. `{rung,
## power, qi_cost, cooldown, qi_throughput}` — throughput is the ratio of the two,
## which is the number a player actually feels.
static func mastery_view(def: TechniqueDef, rung: int) -> Dictionary:
	var clamped := TechniqueScales.rung_for(rung, def.mastery_rungs)
	var multipliers := TechniqueScales.multipliers_at(clamped, def.mastery_rungs)
	return {
		"rung": clamped,
		"power": float(multipliers["power"]),
		"qi_cost": float(multipliers["qi_cost"]),
		"cooldown": float(multipliers["cooldown"]),
		"qi_throughput": float(multipliers["qi_throughput"]),
	}


## Every rung this def may reach, rung 0 through its authored count. A lower
## `mastery_rungs` is therefore a real, observable narrowing of the ladder.
static func ladder_view(def: TechniqueDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rung in range(maxi(0, def.mastery_rungs) + 1):
		out.append(mastery_view(def, rung))
	return out


## The band's two edges as primitives, `{floor, ceiling}` — a multiplier pair, not
## a `Vector2`, because every dictionary this file returns is primitives-only and a
## consumer must never have to reach back into the module to read it.
##
## Read through `TechniqueMarginalia.band_for`, which is the one place the width is
## declared. A caller that re-derived `1.0 ± rarity * reach` here would be a SECOND
## reader of a rule the roll owns, and the two would drift the first time a designer
## retuned the reach (DEF-0302).
static func _band(def: TechniqueDef) -> Dictionary:
	if def == null:
		return {"floor": 1.0, "ceiling": 1.0}
	var band := TechniqueMarginalia.band_for(def.rarity)
	return {"floor": float(band.x), "ceiling": float(band.y)}


## Whether the band is worth telling a player about for THIS row: the rarity's reach
## is non-zero AND at least one authored option may be moved.
##
## The second half is the honest answer for the three cases that would otherwise
## read as a promise the module cannot keep: an ACTIVE manual authors no options at
## all (so its margin is empty and nothing can vary), a capacity option is carried at
## its authored value by ADR 0160's refusal (`TechniqueMarginalia.draw`), and a
## COMMON manual's rarity reach is `0.0`, so its two edges are the same number.
##
## The ANSWER is `_band_figures`' — one reader, so the flag a row checks and the list
## a row prints cannot disagree about whether there was anything to print.
static func _band_bites(def: TechniqueDef, entry: CodexEntry) -> bool:
	if def == null:
		return false
	var band := _band(def)
	if float(band["ceiling"]) - float(band["floor"]) <= 0.0:
		return false
	return not _band_figures(def, entry).is_empty()


## The ACTUAL PRICE WIDTHS, not the multipliers — what a player can be told.
##
## `marginal_band` publishes the two multipliers a copy is rolled between. This
## publishes what they MEAN on this technique's own authored option values: the
## lowest and highest figure any copy of this manual may read. Both are read through
## `band_for` and applied to the module's own `authored_effects`, so a row shows a
## range in the same units as the sheet beside it — which is the claim ADR 0204 made
## and nothing made true.
##
## One entry per authored option that the band can actually move (ADR 0160 refuses
## the capacity channel), each carrying its `option_id`, `label` and the authored
## `authored`, `floor` and `ceiling` figures. Empty for a technique whose options
## cannot vary — which is why `marginal_banded` exists as the flag and this is the
## data behind it.
static func _band_figures(def: TechniqueDef, entry: CodexEntry) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	var band := _band(def)
	var floor_edge := float(band["floor"])
	var ceiling_edge := float(band["ceiling"])
	var authored := effect_view(def, null)
	# A drawn copy is the authority on what it moved: asking the catalog again would
	# answer about a DIFFERENT copy, and a capacity option was carried at its
	# authored value precisely because the band was refused on it.
	var rollable := 0
	if entry != null and not entry.realized.is_empty():
		# The SHEET figure comes from the authored options, never from the drawn
		# effect: `authored` is what the manual prints, and a copy that rolled to
		# 5.67 must still be reported against the 6.0 it was copied from. Passing the
		# realized effect here made the sheet column read 5.67 and the floor/ceiling
		# scale off the same wrong base, so the published window silently described
		# this copy rather than the band.
		var sheet := {}
		for option in authored:
			sheet[String(option.get("option_id", ""))] = option
		for effect in entry.realized:
			var rolled := effect as Dictionary
			var target_id := StringName(rolled.get("target_id", &""))
			if TechniqueMarginalia.is_capacity_effect(target_id):
				continue
			rollable += 1
			var option_id := String(rolled.get("option_id", ""))
			var printed: Dictionary = sheet.get(option_id, rolled)
			_append_band_figure(out, option_id, rolled, floor_edge, ceiling_edge, printed)
		return out
	for effect in authored:
		if TechniqueMarginalia.is_capacity_effect(StringName(effect.get("target_id", ""))):
			continue
		rollable += 1
		_append_band_figure(
			out, String(effect.get("option_id", "")), effect, floor_edge, ceiling_edge
		)
	if rollable > 0 and ceiling_edge - floor_edge <= 0.0:
		return []
	return out


static func _append_band_figure(
	out: Array[Dictionary],
	option_id: String,
	effect: Dictionary,
	floor_edge: float,
	ceiling_edge: float,
	printed: Dictionary = {}
) -> void:
	var resolved := (
		String(option_id) if not option_id.is_empty() else String(effect.get("option_id", ""))
	)
	if resolved.is_empty():
		return
	var authored := float(printed.get("value", effect.get("value", 0.0)))
	var low := authored * floor_edge
	var high := authored * ceiling_edge
	var label := String(printed.get("label", resolved))
	(
		out
		. append(
			{
				"option_id": resolved,
				"label": label,
				"authored": authored,
				"floor": low,
				"ceiling": high,
			}
		)
	)


## The normalized effects a technique contributes, as primitives, with the value the
## ACTOR has. `realized` says whether the row came from this copy's annotations or
## from the authored passive options.
##
## `marginal_only` asks for the ANNOTATIONS alone — the `true` arm of
## `CodexEntry.effects_for`, unscaled — so a panel can print the sheet and the
## margin as two columns instead of asking the reader to subtract one from the
## other. The values are deliberately NOT rung-scaled here: a rung is what the
## actor has done with the manual since, which is a different question from what
## this copy of it says.
static func effect_view(
	def: TechniqueDef, entry: CodexEntry, marginal_only: bool = false
) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	if entry == null or (marginal_only and entry.realized.is_empty()):
		# `marginal_only` with nothing realized IS the authored sheet, so the
		# authored read is the honest answer rather than an empty row nobody can
		# fill.
		#
		# Element-typed explicitly on the `else` arm rather than letting `:=`
		# infer it. `def.effects()` is declared `Array[Dictionary]` but `[]` is an
		# untyped `Array`, so the inferred local is untyped and the ternary
		# re-boxes an authored sheet as a plain `Array` — which throws "Trying to
		# assign an array of type Array to a variable of type Array[Dictionary]"
		# at RUNTIME, INSIDE `inspect`, before the dictionary is ever returned. The
		# whole read model was silently unreachable for every technique that
		# authored a passive option, and every key below this line — `can_pay`,
		# `learn_short`, and the band — was lost with it (DEF-0301/DEF-0302).
		if marginal_only:
			effects = [] as Array[Dictionary]
		else:
			effects = def.effects()
	elif marginal_only:
		for effect in entry.realized:
			effects.append(effect)
	else:
		effects = entry.effects_for(def)
	var out: Array[Dictionary] = []
	for effect in effects:
		(
			out
			. append(
				{
					"option_id": String(effect.get("option_id", "")),
					"label": String(effect.get("label", effect.get("option_id", ""))),
					"target_type": String(effect.get("target_type", "")),
					"target_id": String(effect.get("target_id", "")),
					"op": String(effect.get("op", "FLAT")),
					"unit": String(effect.get("unit", "magnitude")),
					"value": float(effect.get("value", 0.0)),
					"channel": String(effect.get("channel", "")),
				}
			)
		)
	return out


## One slot row: its key, its pool, and what fills it. Takes the already-resolved
## `slots` dict rather than the table, so a caller projecting N rows resolves the
## table ONCE instead of N times.
static func slot_view(
	upkeep: TechniqueUpkeep, slot_key: StringName, slots: Dictionary
) -> Dictionary:
	var technique_id: StringName = slots.get(slot_key, &"")
	var def := TechniqueCatalog.instance().definition(technique_id)
	return {
		"slot": String(slot_key),
		"kind": String(TechniqueSlots.kind_of(slot_key)),
		"technique_id": String(technique_id),
		"display_name": "" if def == null else def.display_name,
		"filled": technique_id != &"",
		"suspended": technique_id != &"" and upkeep.is_suspended(technique_id),
	}


## One codex row: what it is, where it sits, and how far it has been mastered.
## Takes the `entry` already read out of the codex, so a caller projecting N rows
## walks the codex ONCE instead of re-looking-up per row.
static func entry_view(
	slot_table: TechniqueSlots,
	upkeep: TechniqueUpkeep,
	entry: CodexEntry,
	equipped_ids: Array[StringName]
) -> Dictionary:
	var def := TechniqueCatalog.instance().definition(entry.technique_id)
	var slot_key := ""
	for key in slot_table.all().keys():
		if slot_table.all()[key] == entry.technique_id:
			slot_key = String(key)
	return {
		"id": String(entry.technique_id),
		"display_name": "" if def == null else def.display_name,
		"path": "" if def == null else String(def.path),
		"grade": "" if def == null else String(def.grade),
		"active": false if def == null else def.active,
		"equipped": equipped_ids.has(entry.technique_id),
		"suspended": upkeep.is_suspended(entry.technique_id),
		"rung": entry.mastery_rung,
		"rung_count": 0 if def == null else def.mastery_rungs,
		# Whether this copy carries annotations at all, so a codex LIST can mark the
		# rows worth opening without projecting every technique's effects.
		"annotated": not entry.realized.is_empty(),
		"slot": slot_key,
	}


## Free slots summed across every pool, from what is actually occupied.
static func free_total(slot_table: TechniqueSlots, tier: int) -> int:
	var free := 0
	free += slot_table.free_of(tier, TechniqueSlots.UNIVERSAL)
	for path_id in PathState.ALL:
		free += slot_table.free_of(tier, path_id)
	return free


## Flatten a list of ids to plain strings for a summary dictionary.
##
## The parameter is an UNTYPED `Array`, not `Array[StringName]`. `TechniqueDef.schools`
## is `Array[String]`, and GDScript refuses to pass a differently-typed array to a
## typed parameter at runtime — which made `inspect` throw on every real technique
## and return `{}`. Summaries only ever hold primitives, so accepting any array of
## stringish values and narrowing here is both correct and total.
static func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
