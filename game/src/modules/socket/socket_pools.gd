class_name SocketPools
extends RefCounted

## The socket subsystem's own option pools, derived from the master catalog
## (ADR 0025). Nothing here defines an effect: option identity, eligibility,
## magnitude windows and realization all come from `OptionCatalog`.
##
## Each channel prefers the catalog's dedicated context (`socket_slot`,
## `socket_item`, `enchantment`) and falls back to the equipped affix contexts
## filtered down to options that can legally sit on an equipped item. The
## fallback keeps every socket roll legal today, and the preference means a
## socket pool authored in the catalog wins automatically once it exists.

const CHANNEL_SLOT := &"socket_slot"
const CHANNEL_ITEM := &"socket_item"
const CHANNEL_ENCHANT := &"enchantment"
## Every socket channel resolves while the parent is equipped, so they all share
## the equipped activation channel.
const ACTIVATION := &"equipped"
const CHANNELS: Array[StringName] = [CHANNEL_SLOT, CHANNEL_ITEM, CHANNEL_ENCHANT]
const FALLBACK_CONTEXTS := {
	CHANNEL_SLOT: [&"prefix"],
	CHANNEL_ITEM: [&"prefix", &"postfix"],
	CHANNEL_ENCHANT: [&"prefix"],
}
## Resource scopes that persist while equipped. A one-shot restoration has no
## consumer on a socket, so it is never a candidate.
const PERSISTENT_SCOPES: Array[StringName] = [OptionTarget.SCOPE_MAXIMUM, OptionTarget.SCOPE_REGEN]

static var _cache: Dictionary = {}


## Candidate option ids for `channel`, canonically ordered so registration order
## never changes a roll.
static func candidate_ids(channel: StringName) -> Array[StringName]:
	var key := String(channel)
	if _cache.has(key):
		return _cache[key]
	var catalog := OptionCatalog.instance()
	var ids: Array[StringName] = catalog.pool_ids(ACTIVATION, channel)
	if ids.is_empty():
		var seen := {}
		for context in FALLBACK_CONTEXTS.get(key, []):
			for option_id in catalog.pool_ids(ACTIVATION, context):
				if seen.has(String(option_id)):
					continue
				if not _eligible(catalog.option_record(option_id)):
					continue
				seen[String(option_id)] = true
				ids.append(option_id)
	ids.sort()
	_cache[key] = ids
	return ids.duplicate()


## Drop the memoized pools. Only a catalog swap needs it; a normal test run
## never does.
static func invalidate() -> void:
	_cache.clear()


## Realize one option for `channel`, skipping ids in `used` and any option whose
## exclusive family is already spoken for. Returns an empty dictionary when
## nothing legal remains, so a caller stops instead of rerolling for a lucky
## legal outcome (ADR 0025).
static func roll(
	channel: StringName,
	used: Array[StringName],
	realm_id: StringName,
	rarity_index: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var catalog := OptionCatalog.instance()
	var candidates := _weighted(channel, used)
	if candidates.is_empty():
		return {}
	var total := 0.0
	for candidate in candidates:
		total += float(candidate["weight"])
	var pick := rng.randf() * total
	var chosen: Dictionary = candidates[candidates.size() - 1]["record"]
	for candidate in candidates:
		pick -= float(candidate["weight"])
		if pick <= 0.0:
			chosen = candidate["record"]
			break
	return catalog.realize(chosen, realm_id, rarity_index, rng)


## What a roll for `channel` may produce right now: every legal option with the
## value window it could legally take. A preview is this list plus costs, so a
## player never has to commit to find out what was possible.
static func permitted(
	channel: StringName, realm_id: StringName, rarity_index: int, used: Array[StringName]
) -> Array[Dictionary]:
	var catalog := OptionCatalog.instance()
	var out: Array[Dictionary] = []
	for candidate in _weighted(channel, used):
		var record: Dictionary = candidate["record"]
		var window := catalog.magnitude_bounds(
			String(record.get("unit", "magnitude")), realm_id, rarity_index
		)
		var target: Dictionary = record.get("target", {})
		(
			out
			. append(
				{
					"option_id": String(record.get("id", "")),
					"label": String(record.get("label", "")),
					"target_type": String(target.get("type", "stat")),
					"target_id": String(target.get("id", "")),
					"op": String(record.get("op", "FLAT")),
					"unit": String(record.get("unit", "magnitude")),
					"value_min": float(window["min"]),
					"value_max": float(window["max"]),
				}
			)
		)
	return out


## Candidate records with their catalog weight, after exclusion. One list feeds
## both the roll and the preview, so what a player was promised and what the
## commit may produce can never disagree.
static func _weighted(channel: StringName, used: Array[StringName]) -> Array[Dictionary]:
	var catalog := OptionCatalog.instance()
	var taken := {}
	for option_id in used:
		taken[String(option_id)] = true
	var families := {}
	for option_id in used:
		var used_record := catalog.option_record(option_id)
		var family := StringName(OptionCatalog.text_field(used_record, "exclusive_family"))
		if family != &"":
			families[String(family)] = true
	var out: Array[Dictionary] = []
	for option_id in candidate_ids(channel):
		if taken.has(String(option_id)):
			continue
		var record := catalog.option_record(option_id)
		if record.is_empty() or not _eligible(record):
			continue
		var family := StringName(OptionCatalog.text_field(record, "exclusive_family"))
		if family != &"" and families.has(String(family)):
			continue
		var weight := float(record.get("weight", 0.0))
		if weight <= 0.0:
			continue
		out.append({"record": record, "weight": weight})
	return out


## Whether a catalog record may sit on an equipped item as a socket, gem or
## enchantment contribution: it needs the equipped activation channel, and a
## target with a consumer that persists while the parent is worn.
static func _eligible(record: Dictionary) -> bool:
	if record.is_empty():
		return false
	var catalog := OptionCatalog.instance()
	if not catalog.activations_for(record).has(ACTIVATION):
		return false
	var target: Dictionary = record.get("target", {})
	var target_type := String(target.get("type", "stat"))
	if target_type == OptionTarget.STAT:
		return true
	if target_type == OptionTarget.RESOURCE:
		return PERSISTENT_SCOPES.has(StringName(target.get("scope", "")))
	return false
