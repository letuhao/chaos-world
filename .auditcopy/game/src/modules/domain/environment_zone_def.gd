class_name EnvironmentZoneDef
extends Resource

## One severe environment as a LOCAL VOLUME inside a room or corridor (ADR 0075).
##
## A zone applies a `StatusEffect` through `Actor.add_status` / `tick_statuses`. It
## never subtracts damage directly — that is the bespoke damage channel ADR 0075
## forbids, and routing through a status is what makes every hazard obey the same
## duration, stacking and cleanse rules as every other status.
##
## **Every zone must publish `mitigation_tags`.** A zone with none is a flat damage
## tax with no counterplay, and `tools data audit` rejects it. The levers are the four
## that already exist: a gear affix, a technique, a consumable pill, or SPIRIT-ROOT
## AFFINITY. Affinity is the load-bearing one for identity — it is why `race` matters
## in traversal and not only at character creation.

## The catalogue is CLOSED. A closed set is what lets the audit hard-fail an unknown
## kind instead of accepting a typo that mitigates nothing.
const KINDS: Array[StringName] = [
	&"super_hot",
	&"super_cold",
	&"static",
	&"toxic",
	&"void",
	&"pressure",
	&"sorrow",
	&"verdant",
]

## The four levers, namespaced so a typo is caught rather than silently inert. Every
## kind's primary lever appears here, and the audit requires at least one NON-affinity
## lever per zone so a player with the wrong spirit root always has a counterplay.
const LEVER_AFFINITY := &"affinity"
const LEVER_GEAR := &"gear"
const LEVER_TECHNIQUE := &"technique"
const LEVER_PILL := &"pill"

const LEVERS: Array[StringName] = [
	LEVER_AFFINITY,
	LEVER_GEAR,
	LEVER_TECHNIQUE,
	LEVER_PILL,
]

## Intensity is an authored 3-point band, never a free float: a free float on a `.tres`
## is a number nobody can reason about at a glance.
const BAND_SCORCH := 1
const BAND_SEVERE := 2
const BAND_ANNIHILATING := 3
const BANDS: Array[int] = [BAND_SCORCH, BAND_SEVERE, BAND_ANNIHILATING]

## Per-kind authored magnitudes by band. Data, not a computed curve (ADR 0050): the
## audit asserts a def's band resolves here rather than trusting a hand-typed float.
const MAGNITUDES: Dictionary = {
	&"super_hot": [0.35, 0.70, 1.40],
	&"super_cold": [0.35, 0.70, 1.40],
	&"static": [0.40, 0.80, 1.60],
	&"toxic": [0.30, 0.60, 1.20],
	&"void": [0.50, 1.00, 2.00],
	&"pressure": [0.45, 0.90, 1.80],
	&"sorrow": [0.25, 0.50, 1.00],
	&"verdant": [0.20, 0.45, 0.90],
}

## The status this zone applies. The status id is shared across the three cultivation
## paths on purpose: what the status DOES is resolved per-path, because each path's
## power ladder reads a different substrate. One id, three different mechanisms —
## never one generic damage-over-time with three sets of numbers.
@export var zone_id: StringName = &""

## One of `KINDS`.
@export var kind: StringName = &"super_hot"

## One of `BANDS`.
@export var intensity: int = BAND_SCORCH

## The status applied to an actor standing in this zone.
@export var status_id: StringName = &"env_scourge"

## How long the status is renewed for, in seconds, per band. A zone re-applies on this
## budget so standing inside it stays harmful without a per-tick bespoke call.
@export var stay_budget: float = 8.0

## Authored tags, including the element(s) this zone is hostile to.
@export var tags: Array[StringName] = []

## The levers that reduce this zone. MANDATORY and non-empty; see the class docstring.
@export var mitigation_tags: Array[StringName] = []

## The zone's local bounds in TILES, relative to the owning room's origin. A zone is a
## volume you route around, never a whole-domain flag.
@export var bounds: Rect2i = Rect2i()


func resolved_intensity() -> int:
	return intensity if BANDS.has(intensity) else BAND_SCORCH


## The authored magnitude for this kind and band. Null rather than a guess: a kind that
## is not in the catalogue has no magnitude, and substituting one would be the flat tax
## ADR 0075 refuses.
func magnitude() -> float:
	var row: Array = MAGNITUDES.get(kind, [])
	if row.is_empty():
		return 0.0
	return float(row[resolved_intensity() - 1])


## True when at least one published lever is not spirit-root affinity, so a player with
## the wrong root still has an authored counterplay. The audit enforces this.
func has_non_affinity_mitigation() -> bool:
	for lever in mitigation_tags:
		if lever != LEVER_AFFINITY:
			return true
	return false


func mitigates(lever: StringName) -> bool:
	return mitigation_tags.has(lever)


func to_dict() -> Dictionary:
	var levers: Array = []
	for lever in mitigation_tags:
		levers.append(String(lever))
	var tag_out: Array = []
	for tag in tags:
		tag_out.append(String(tag))
	return {
		"zone_id": String(zone_id),
		"kind": String(kind),
		"intensity": resolved_intensity(),
		"status_id": String(status_id),
		"stay_budget": stay_budget,
		"tags": tag_out,
		"mitigation_tags": levers,
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
	}


static func from_dict(data: Dictionary) -> EnvironmentZoneDef:
	var zone := EnvironmentZoneDef.new()
	zone.zone_id = StringName(data.get("zone_id", ""))
	zone.kind = StringName(data.get("kind", "super_hot"))
	zone.intensity = int(data.get("intensity", BAND_SCORCH))
	zone.status_id = StringName(data.get("status_id", "env_scourge"))
	zone.stay_budget = float(data.get("stay_budget", 8.0))
	var levers: Array[StringName] = []
	for lever in data.get("mitigation_tags", []):
		levers.append(StringName(lever))
	zone.mitigation_tags = levers
	var tag_values: Array[StringName] = []
	for tag in data.get("tags", []):
		tag_values.append(StringName(tag))
	zone.tags = tag_values
	var box: Array = data.get("bounds", [0, 0, 0, 0])
	zone.bounds = (
		Rect2i(int(box[0]), int(box[1]), int(box[2]), int(box[3])) if box.size() == 4 else Rect2i()
	)
	return zone
