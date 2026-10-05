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


## Whether `def` is learnable, what it would cost, and what would stop both the
## learn and the equip. `{}` when either is missing, so a panel never renders a row
## it cannot fill.
static func learn_preview(
	actor: Actor, codex: TechniqueCodex, def: TechniqueDef, learn_unmet: Array, equip_unmet: Array
) -> Dictionary:
	if actor == null or def == null:
		return {}
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"grade": String(def.grade),
		"rarity": String(def.rarity),
		"active": def.active,
		"path": String(def.path),
		"shared": def.is_shared(),
		"known": codex.knows(def.id),
		"can_learn": learn_unmet.is_empty(),
		"price": TechniqueGate.learn_price_for(actor, def),
		"learn_unmet": learn_unmet,
		"equip_unmet": equip_unmet,
	}


## One technique in full: identity, grade, path, costs, the mastery ladder, the
## effects it would contribute and both gates.
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
		"effects": effect_view(def, entry),
		# The printed text against this copy's ANNOTATIONS (ADR 0196): what the
		# sheet says and what this copy says. `marginal` is empty for an active
		# technique and for a row carrying no margin, which is why a panel shows the
		# authored column alone rather than a difference nobody can compute.
		"authored_effects": effect_view(def, null),
		"marginal": effect_view(def, entry, true),
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
static func _short(_actor: Actor, _owed: Dictionary) -> Array:
	var out: Array = []
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
		effects = def.effects() if not marginal_only else []
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
