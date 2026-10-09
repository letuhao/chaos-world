class_name CombatRequestStaging
extends RefCounted

## Staging the two authored claims a technique carries into the request the spine reads:
## the ADR 0105 status request, and the mind-kind the `mind_damage` builder takes.
##
## Extracted from `CombatBoot`, which had grown past the file budget. These four functions
## read AUTHORED content and write it into an `AttackContext`, so they touch neither the
## boot nor any seam the boot installs — which is what lets them live outside it, and why
## the two call sites that remain are one line each.
##
## **Every read here is a `Variant` read on purpose.** This is `app/` handing a
## `combat_engine` builder an authored content type it may not have a compile-time edge to,
## so a def that is null, is not an object, or predates the field must degrade rather than
## crash a combat tick. The NAME travels unresolved in the kind's case —
## `MindDamage._kind_of` is the only function that reads that vocabulary, so there is one
## place a kind can be added.

## Stage one ADR 0105 request onto `ctx.data`, or nothing when the blow carries
## no claimable element. Separated so the shape (one gate, element-carried) is
## asserted in one place rather than in every mechanism arm that builds a context.
static func stage_status_request(ctx: AttackContext, technique: Variant) -> void:
	if ctx == null:
		return
	var element := _element_of(technique)
	if element == &"":
		return
	var tuning := CombatEngineApi.tuning()
	var gate := float(tuning.status_gate_chance)
	var status_id := StatusApi.status_for_element(element, gate)
	if status_id == &"":
		return
	# ADR 0884: the status's own `kind` rides the request so S12 can read the
	# per-category channel without knowing a `status` module class.
	var def := StatusApi.definition(status_id)
	var request := {
		"id": status_id,
		"element": element,
		"kind": &"" if def == null else def.kind,
		"immunity_tags": [] if def == null else def.immunity_tags,
		"family": &"" if def == null else def.family,
		"categories": [] if def == null else def.categories,
		"potency": 0.0 if def == null else def.potency_base,
		"chance": gate,
		"scope": StatusApply.SCOPE_COMBAT,
	}
	if def != null and def.mechanic() == &"discord":
		request[StatusApply.KEY_DISCORD] = _discord_members(def, element)
	ctx.set_data(StatusApply.REQUEST_KEY, request)


## ADR 0925's discord: a chaos carrier lands ONE member of its authored table, drawn
## at landing time (S12 owns the rng). The draw is the ENGINE's and the TABLE is the
## app's, so every member's request is composed here and staged INSIDE the carrier's
## request — the same seam ADR 0105's request already uses, and the reason S12 can
## impose a member without a `status` edge.
##
## Members are staged as full requests with `chance: 1.0`: the carrier already passed
## the gate, so a member's own landing is the resist split and nothing else. A member
## def that does not resolve is skipped rather than staged as a guess.
static func _discord_members(carrier: StatusDef, element: StringName) -> Array:
	var members: Array = []
	for member_id in carrier.table():
		var member := StatusApi.definition(member_id)
		if member == null:
			continue
		(
			members
			. append(
				{
					"id": member_id,
					"element": element,
					"kind": member.kind,
					"immunity_tags": member.immunity_tags,
					"family": member.family,
					"categories": member.categories,
					"potency": member.potency_base,
					"chance": 1.0,
					"scope": StatusApply.SCOPE_COMBAT,
				}
			)
		)
	return members


## The element a technique carries, or `&""`. Variant-read exactly as
## [method mind_kind_of] reads `mind_kind`, so a def authored before the field
## existed degrades to elementless rather than throwing.
static func _element_of(technique: Variant) -> StringName:
	if technique is Object:
		var authored: Variant = (technique as Object).get(&"element")
		if authored is StringName or authored is String:
			return StringName(authored)
	return &""


## The erosion kind `technique` authors, or `DISRUPT` when it authors none.
##
## Returned as a `Variant`, not a `StringName`, because the two arms are different TYPES
## on purpose and GDScript will not let a declared `StringName` return hold either:
## `MindDamage.Kind.DISRUPT` is an enum ordinal — an `int` — not a name. Both arms are
## what `MindDamage.builder`'s `p_kind: Variant` already accepts and what
## [method MindDamage._kind_of] already resolves, a name and an ordinal through the same
## branch.
##
## The `Variant` read of the def is deliberate and is the same one `QiDamage.builder` and
## `BodyDamage.builder` already make: this is `app/` handing a `combat_engine` builder an
## authored content type it may not have a compile-time edge to, and a def that is null,
## is not an object, or predates the field must all degrade to the plain strike rather
## than crash a combat tick. The NAME travels unresolved — `_kind_of` is the only function
## that reads the vocabulary, so there is one place a kind can be added.
static func mind_kind_of(technique: Variant) -> Variant:
	if technique is Object:
		var authored: Variant = (technique as Object).get(&"mind_kind")
		if authored is StringName or authored is String:
			return StringName(authored)
	return MindDamage.Kind.DISRUPT
