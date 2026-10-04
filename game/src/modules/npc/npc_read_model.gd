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
static func summary(
	key: StringName, entry: NpcRosterEntry, def: NpcDef, is_live: bool, live_presence: StringName
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
			"location_id": "",
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
		"location_id": String(entry.location_id),
	}


## Who is here right now, tracked and untracked in one read. `summaries` is the already
## built list, so this owns only the envelope, the location filter and the truncation flag.
##
## **A non-empty `location_id` FILTERS.** It used to be echoed straight into the result, so
## the read model labelled its answer with a place it had never checked — a caller asking
## "who is in `spirit_peaks`" was handed everyone, captioned as spirit_peaks. An empty id
## means "everywhere", which is what a boot-time settlement wants.
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
