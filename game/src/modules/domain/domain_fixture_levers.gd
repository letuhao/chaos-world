class_name DomainFixtureLevers
extends RefCounted

## WHICH mitigation lever pushes back against an authored fixture, and by how much.
## Split out of `domain_fixtures.gd` for its thousand-line ceiling, and kept as ONE
## reader so "what counters a hazard" stays a single vocabulary in the game.
##
## Every table here is `EnvironmentField`'s, read rather than restated: the lever
## identity order (`EnvironmentZoneDef.LEVERS`), the substrate each lever moves
## (`LEVER_SUBSTRATES`), the share each removes at full strength (`LEVER_CAPS`), and the
## actor tag keys the four non-affinity levers publish and read
## (`environment_field.gd:250-254`). A second copy of any of them is a number that can
## disagree with the environment's.

const StatusApi := preload("res://src/modules/status/api.gd")

## The graded acute-damage substrate (`environment_field.gd:97`). A trap hurts
## IMMEDIATELY and lands once, which is exactly what that substrate is described as, and
## naming it is what makes the resolution below agree with the environment's by
## construction: `LEVER_SUBSTRATES` and `LEVER_CAPS` are read directly, so a `gear` ward
## that blunts a zone blunts a trap by the same number.
const SUBSTRATE := EnvironmentField.SUBSTRATE_GRADED_BODY


## Which lever actually reduces this fixture for this actor, or `""`. Read in identity
## order over `EnvironmentZoneDef.LEVERS` — the closed four, not a list restated here. A
## lever has to be PUBLISHED by the fixture, has to MOVE the trap's substrate, and has to
## be one this actor actually carries.
##
## **Returns on FIRST match, which is ADR 0212's rule made structural**: at most one lever
## is credited per hazard instance, so a hero holding all four gets the identity-first
## answer and never a summed 0.95. The loop is the enforcement — a version that collected
## every match and summed the caps is the "four magnitudes of one number" failure the ADR
## names, and there is no test that would be more specific than this structure.
static func lever_for(actor: Actor, fixture: Dictionary) -> String:
	var levers := published(fixture)
	for lever in EnvironmentZoneDef.LEVERS:
		if not levers.has(lever):
			continue
		# `LEVER_SUBSTRATES` is the same table `EnvironmentField.mitigates` consults,
		# read directly because `_moves` is private: a lever that does not act on the
		# graded substrate is structurally inert here, and crediting it anyway is the
		# invention `residual_amount`'s docblock refuses.
		if not (EnvironmentField.LEVER_SUBSTRATES.get(lever, []) as Array).has(SUBSTRATE):
			continue
		if holds(actor, lever, fixture):
			return String(lever)
	return ""


## The share `lever` removes at full strength, straight out of `EnvironmentField`'s
## table. 0.0 for a lever with no entry: an unrecognised lever must never quietly reduce
## a hazard.
static func cap_for(lever: String) -> float:
	for key in EnvironmentField.LEVER_CAPS:
		if String(key) == lever:
			return float(EnvironmentField.LEVER_CAPS[key])
	return 0.0


## The closed-set levers this fixture publishes, in authored order.
static func published(fixture: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var authored: Array = fixture.get("mitigation_tags", [])
	for lever in authored:
		if EnvironmentZoneDef.LEVERS.has(StringName(lever)):
			out.append(StringName(lever))
	return out


## [method published] as plain strings, for the telegraph payload a scene renders.
static func published_names(fixture: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for lever in published(fixture):
		out.append(String(lever))
	return out


## Whether this actor carries `lever`. The three non-affinity levers are read from the
## marker keys `EnvironmentField` itself publishes, so this file authors no fourth tag
## slot.
##
## ## `affinity` reads the LANDED STATUS's element, not the fixture's tags (ADR 0212)
##
## This branch used to `return false` unconditionally, justified by "a trap authors no
## element" — which is true of its `tags` (`ember`, `stone`, `ruined` belong to no
## `HOSTILE_ELEMENTS` row) and false of what it actually LANDS. Every shipped trap names a
## status that DOES ride an element: `ash_chamber_vein` -> `fire_immolation`
## (`element = &"fire"`), `storm_gallery_arc` -> `lightning_arc` (`&"lightning"`),
## `storm_gallery_vent` -> `wind_gust` (`&"wind"`). Two of those three even author
## `affinity` in their own `mitigation_tags`. So the read model was advertising counterplay
## the game could not deliver — precisely the defect ADR 0075's mandatory
## `mitigation_tags` exists to prevent. The strength test is
## `EnvironmentField.affinity_covers`, the SAME floor the field applies to a zone, so a
## root strong enough to answer a fire zone answers a fire trap and neither scale can
## drift from the other.
static func holds(actor: Actor, lever: StringName, fixture: Dictionary) -> bool:
	match lever:
		EnvironmentField.LEVER_AFFINITY:
			var element := status_element(StringName(fixture.get("status_id", "")))
			# An element-free status is hostile to no root, exactly as a kind with no
			# `HOSTILE_ELEMENTS` row is: a trap that lands `env_scourge` has no affinity
			# answer and is not credited one it did not earn.
			return element != &"" and EnvironmentField.affinity_covers(actor, element)
		EnvironmentField.LEVER_GEAR:
			return not _tags(actor, EnvironmentField.GEAR_TAGS_KEY).is_empty()
		EnvironmentField.LEVER_TECHNIQUE:
			return not _tags(actor, EnvironmentField.TECHNIQUE_TAGS_KEY).is_empty()
		EnvironmentField.LEVER_PILL:
			return not _tags(actor, EnvironmentField.PILL_TAGS_KEY).is_empty()
	return false


## The element `status_id` rides, or `&""` for a def that rides none (or names one this
## build does not ship). Read through the `status` FACADE — the edge
## `DomainFixtures` already preloads for `_settle` — so the answer is the SAME def the
## trap will actually land, resolved from the same catalogue. Parsing the `.tres` text
## here would be a second copy of the content tree, and a trap whose status moved would
## keep resolving against the old file.
static func status_element(status_id: StringName) -> StringName:
	if status_id == &"":
		return &""
	var def := StatusApi.definition(status_id) as StatusDef
	if def == null:
		return &""
	return StringName(def.element)


static func _tags(actor: Actor, key: StringName) -> Array:
	var out: Array = []
	if actor == null:
		return out
	# Bounded `for` over the published tag list, which is authored content and small.
	for entry in actor.get_module_data(key).get("tags", []):
		out.append(StringName(str(entry)))
	return out
