class_name NpcReadModel
extends RefCounted

## The `summary()` and `presence_here()` read models (ADR 0092). Split out of the facade
## so the facade stays the verbs a consumer calls and this stays the projection a panel
## renders — the same split `techniques` already makes with `TechniqueReadModel`.
##
## **Every value here is a primitive.** A panel tests this dictionary; nothing in it names
## an `NpcDef`, an `NpcRosterEntry` or an `Actor`.

## Bounded read size for `presence_here`. A busy settlement reports `truncated` rather
## than silently dropping an npc the player can see.
const MAX_PRESENCE_READ := 16


## The read model for one npc: tier, stage, presence and identity as primitives.
##
## Accepts either a stable `npc_id` or a live instance key (`drifter#3`), so
## `presence_here` can pass registry keys straight through without a second lookup.
##
## ## `live_location_id` is the place the LIVE body was minted for, not the place the
## ## roster last remembers it at (BL-0715)
##
## These are two different facts and the row has to answer the one it was asked. A live
## actor's place comes from `NpcRegistry`, because an untracked npc has no roster entry
## to remember it in at all; the roster entry's `location_id` is "where you LAST met
## them", which for someone standing in front of you may be a settlement you left an hour
## ago. A presence read filters on the live place, so reading the remembered one is what
## made a freshly stocked room filter itself to nothing. Empty when the caller has no
## live place to offer — a summary asked for somebody who is not here — which is the one
## case where the remembered value is the only value there is.
static func summary(
	key: StringName,
	entry: NpcRosterEntry,
	def: NpcDef,
	is_live: bool,
	live_presence: StringName,
	live_location_id: StringName = &""
) -> Dictionary:
	if entry == null:
		return {
			"npc_id": String(key),
			"instance": String(key),
			"known": false,
			"tracked": def.tracked() if def != null else false,
			"tier": NpcTier.label(def.normalized_tier()) if def != null else "",
			"presence": NpcPresence.label(NpcPresence.PRESENT if is_live else NpcPresence.UNKNOWN),
			"display_name": def.display_name if def != null else "",
			"faction": String(def.faction) if def != null else "",
			"stage_id": "",
			"stage_label": "",
			"stage_index": 0,
			"stage_count": def.stage_count() if def != null else 0,
			"location_id": String(live_location_id),
		}
	var stage_def := def.stage(entry.stage_id) if def != null else null
	return {
		"npc_id": String(entry.npc_id),
		"instance": String(key),
		"known": true,
		"tracked": entry.tracked(),
		"tier": NpcTier.label(entry.tier),
		"presence": NpcPresence.label(live_presence),
		"display_name": def.display_name if def != null else "",
		"faction": String(def.faction) if def != null else "",
		"stage_id": String(entry.stage_id),
		"stage_label": stage_def.display_name if stage_def != null else "",
		"stage_index": entry.stage_index(),
		"stage_count": def.stage_count() if def != null else 0,
		"location_id": String(live_location_id if is_live else entry.location_id),
	}


## Who is here right now, tracked and untracked in one read. `summaries` is the already
## built list, so this owns only the envelope, the location filter and the truncation flag.
##
## **A non-empty `location_id` FILTERS.** It used to be echoed straight into the result, so
## the read model labelled its answer with a place it had never checked — a caller asking
## "who is in `spirit_peaks`" was handed everyone, captioned as spirit_peaks. An empty id
## means "everywhere", which is what a boot-time settlement wants.
##
## ## The filter is now real, and that is why the write has to carry a place (BL-0715)
##
## It was already a real filter before that fix — it just had nothing to match. Every
## row was built with `location_id: ""`, so a room load that stocked four bodies and then
## asked "who is in `mortal_plains`" was handed nobody, and nothing in the read path
## could say so: `count` was a true answer to a question about the wrong table. A filter
## this sharp is only safe because the WRITE records where it put each body; the two
## halves are one invariant and this function is where it is paid.
static func presence(
	location_id: StringName, _keys: Array[StringName], summaries: Array
) -> Dictionary:
	var kept: Array = []
	for index in range(summaries.size()):
		if summaries[index].get("location_id", String(location_id)) != String(location_id):
			continue
		kept.append(summaries[index])
	var total := kept.size()
	if total > MAX_PRESENCE_READ:
		total = MAX_PRESENCE_READ
		kept = kept.slice(0, MAX_PRESENCE_READ)
	return {
		"location_id": String(location_id),
		"count": kept.size(),
		"truncated": kept.size() < summaries.size(),
		"npcs": kept,
	}
