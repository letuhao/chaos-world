class_name PortraitDef
extends Resource

## One authored portrait: an actor's visual identity as data, keyed by id (ADR 0131).
##
## ## Why this is authored data and not a file the game picks
##
## **Keyed by `id`, never by an array position.** `core/realm_power_table.tres` was built the
## same way and for the same reason: an inserted entry that shifts everything below it onto the
## wrong number is silent, and a portrait indexed by position would silently repaint every face
## after an author added one.
##
## ## Why the generator is not required for correctness
##
## **The resolver reads these `.tres` files and never the asset index.** The deferred generator
## writes a PNG and an index row, and a sync step turns index rows into these. Delete the whole
## index and every actor still resolves, because a missing face is the `PLACEHOLDER` row rather
## than a null. That is what keeps the generator optional rather than load-bearing.
##
## ## Why a portrait grants no stat
##
## Because appearance that changes numbers is a balance surface, which is exactly what ADR 0062
## forbids a race from being. This type has no stat field and must not grow one.

## The one face every actor gets. Resolution cannot return null, and this is what it returns.
const PLACEHOLDER := &"placeholder"

## Stable authored id. The only key anything resolves by.
@export var id: StringName = &""
@export var display_name: String = ""
## The body plan this face belongs to. Empty means "matches any race", which is what the
## placeholder is: a face that must never be missing, so it may not be tied to a race at all.
@export var race_id: StringName = &""
## Namespaced visual traits, `axis:value`, exactly as `tools/assets.py` validates them for item
## art. Shared vocabulary so one audit rule covers both.
@export var visual_traits: Array[StringName] = []
## The composable layers, back to front. More than one so a portrait can be assembled rather
## than baked, which is what lets the same body plan read differently per occasion.
@export var layer_paths: Array[String] = []
## A theme tint KEY, never a pixel value: styling belongs to the one theme, and a literal colour
## in content is a second place to retune it.
@export var palette_key: StringName = &""


## Whether this def names a portrait at all. A `.tres` deleted between two runs makes its
## portrait unreachable rather than granting one nothing defines.
func is_valid_def() -> bool:
	return id != &""


## Whether this face is the fallback every actor gets. Checked by `id` rather than by a flag,
## so a portrait cannot claim to be the fallback and also carry a race.
func is_placeholder() -> bool:
	return id == PLACEHOLDER


## One trait's value, or `""`. Read through this rather than by scanning `visual_traits`, so a
## caller never re-implements the `axis:value` split.
##
## ## Why the method is `trait_value` and not `trait`
##
## **`trait` is a reserved GDScript keyword**, the one that introduced traits before
## `@export` groups existed, and a member may not be named after it. Declaring `func trait(...)`
## fails the whole file with "Could not parse global class PortraitDef" — which reads as a
## corruption rather than as a name clash. The accessor carries the qualifier.
func trait_value(axis_name: String) -> String:
	var prefix := "%s:" % axis_name
	for trait_id in visual_traits:
		var trait_name := String(trait_id)
		if trait_name.begins_with(prefix):
			return trait_name.substr(prefix.length())
	return ""
