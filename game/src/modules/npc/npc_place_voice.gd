class_name NpcPlaceVoice
extends Resource

## What ONE PLACE sounds like — the authored rows a minor npc standing there inherits
## (ADR 0253).
##
## ## This is the answer to "compose, don't roll"
##
## One `.tres` per location, named after the location id. It carries the names its
## residents answer to, how they carry themselves, what they are doing, **and what they
## believe** — so a composed minor's opinion is TRUE OF THE ROOM rather than drawn from
## a global list. That is the whole difference between a person and a cutout with a
## random name, and it costs **one file per place** rather than one per npc.

## The place these rows belong to. Matches the authored location id, so the composer
## finds them by name and the file name is the key (ADR 0050).
@export var location_id: StringName = &""

## Names its residents answer to. An authored list, chosen by the caller's ordinal — never
## rolled, so a room met twice reads the same way.
@export var names: Array[String] = []

## How they carry themselves. One short authored clause each.
@export var manners: Array[String] = []

## What they are doing while they stand here. Printed by a panel as-is.
@export var activities: Array[String] = []

## What they BELIEVE, about this place and about whoever is in it. **Each row names the
## tiers it is a plausible view FOR**, which is how the composer satisfies "one opinion
## consistent with the place they are in AND their tier" without a mechanism ever
## comparing a tier (ADR 0067): the composer asks the CONTENT which rows fit, rather
## than branching on `tier` itself.
@export var opinions: Array[NpcOpinionDef] = []

## The bodies available in this place. Read through the tier filter exactly as
## `opinions` is, for the same reason.
@export var tells: Array[NpcTellDef] = []

## The tuned magnitude a composed persona from this place is built at, 0..100. An
## override of the def's own `minor_power_scale`, because a PLACE knows its people
## better than a species def does.
@export_range(0.0, 100.0, 0.1) var power_scale: float = 0.0


func has_names() -> bool:
	return not names.is_empty()


func has_manners() -> bool:
	return not manners.is_empty()


func has_activities() -> bool:
	return not activities.is_empty()


func has_opinions() -> bool:
	return not opinions.is_empty()


func has_tells() -> bool:
	return not tells.is_empty()
