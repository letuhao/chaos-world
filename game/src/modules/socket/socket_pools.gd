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
## A reforge re-draws ONE affix on an instance an actor already holds, so its
## pool is the instance's OWN affix contexts rather than a fixed socket context:
## the replacement is drawn from exactly the pool the item was generated from,
## which is what keeps a reforged item indistinguishable from one that dropped
## lucky. It reads the rarity, so it carries no authored context list of its own.
const CHANNEL_REFORGE := &"reforge"
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
	return catalog.realize(_pick(candidates, rng), realm_id, rarity_index, rng)


## Realize one replacement affix for an instance of `rarity`, honouring `floor`.
##
## The pool is the rarity's own affix contexts and the exclusions are exactly the
## ones a generation roll applies — every other option the instance carries and
## every exclusive family already spoken for are off the table — so a reforge can
## neither duplicate an affix nor stack a second copy of a family. The replaced
## affix is NOT in `used`, so drawing it again is legal; that is the only way a
## reforge can return what it was given.
##
## `floor` is the effect being replaced. It is a floor on the DELIVERED magnitude
## of the same measure, not on the option id: a candidate feeding another stat is
## free to realize at any point in its own window, while a candidate feeding the
## same stat the same way cannot land below the value already realized. This is
## what makes the verb an investment rather than a coin flip — an attempt can cost
## material and time and still return the same affix, but never a weaker version
## of the one it replaced.
static func roll_reforge(
	rarity: StringName,
	used: Array[StringName],
	realm_id: StringName,
	rarity_index: int,
	rng: RandomNumberGenerator,
	floor: Dictionary
) -> Dictionary:
	var catalog := OptionCatalog.instance()
	var candidates := _weighted_reforge(rarity, used, floor)
	if candidates.is_empty():
		return {}
	var effect := catalog.realize(_pick(candidates, rng), realm_id, rarity_index, rng)
	return _raised_to_floor(effect, floor)


## What a reforge could produce on an instance of `rarity`, with the value window
## each candidate may legally take AFTER the floor. A preview is this list, so a
## player is shown the same interval the commit draws from.
static func permitted_reforge(
	rarity: StringName,
	used: Array[StringName],
	realm_id: StringName,
	rarity_index: int,
	floor: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for candidate in _weighted_reforge(rarity, used, floor):
		var record: Dictionary = candidate["record"]
		var window := OptionCatalog.instance().magnitude_bounds(
			String(record.get("unit", "magnitude")), realm_id, rarity_index
		)
		var low := _floored_min(record, floor, window)
		(
			out
			. append(
				{
					"option_id": String(record.get("id", "")),
					"label": String(record.get("label", "")),
					"target_type":
					String((record.get("target", {}) as Dictionary).get("type", "stat")),
					"target_id": String((record.get("target", {}) as Dictionary).get("id", "")),
					"op": String(record.get("op", "FLAT")),
					"unit": String(record.get("unit", "magnitude")),
					"value_min": low,
					"value_max": float(window["max"]),
				}
			)
		)
	return out


## The weighted draw, split out so the reforge path can reuse the identical
## selection over a different candidate list. Never an unbounded walk: `candidates`
## is the whole filtered pool and each is visited once.
static func _pick(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
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
	return chosen


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
	return _weighted_from(candidate_ids(channel), used, {})


## The reforge pool: the rarity's own affix contexts, with the same exclusions a
## generation roll applies. An empty `floor` accepts every candidate, so the only
## thing distinguishing this from a plain roll is WHERE the ids came from.
static func _weighted_reforge(
	rarity: StringName, used: Array[StringName], floor: Dictionary
) -> Array[Dictionary]:
	var catalog := OptionCatalog.instance()
	var ids: Array[StringName] = []
	var seen := {}
	# The rarity's contexts are already canonically ordered by `contexts`, and the
	# pool is memoized, so a repeat read costs nothing. Bounded by the contexts a
	# rarity authorises, never by the size of the catalog.
	for context in ItemRarity.contexts(rarity):
		for option_id in catalog.pool_ids(ACTIVATION, context):
			if seen.has(String(option_id)):
				continue
			seen[String(option_id)] = true
			ids.append(option_id)
	ids.sort()
	return _weighted_from(ids, used, floor)


## Candidates from `ids` with their catalog weight, after every exclusion. One
## filter feeds the roll and the preview for both paths, so what a player was
## promised and what a commit may produce cannot disagree.
##
## The walk is bounded by `ids`, which the catalog or the rarity's contexts fixed
## before this ran: it appends to `out` while reading `ids`, never a container it
## is growing.
static func _weighted_from(
	ids: Array[StringName], used: Array[StringName], _floor: Dictionary
) -> Array[Dictionary]:
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
	for option_id in ids:
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


## Whether a realized `effect` already meets `floor`, and if not the value it
## would need. An effect feeding another measure always meets it, so the floor
## never turns a re-draw into a search for one exact answer.
static func _meets_floor(effect: Dictionary, floor: Dictionary) -> bool:
	if floor.is_empty():
		return true
	if not _same_measure(effect, floor):
		return true
	return float(effect.get("value", 0.0)) >= float(floor["value"]) - 0.0


## Two effects feed the SAME measure when they move the same target the same
## way. `unit` is deliberately absent: a flat count and a percentage are the same
## verb on the same stat and compare directly, and the catalog's own
## `precision`-rounded values are the numbers a player reads.
static func _same_measure(left: Dictionary, right: Dictionary) -> bool:
	if floor_keys(right).is_empty():
		return false
	return (
		String(left.get("target_id", "")) == String(right.get("target_id", ""))
		and String(left.get("target_type", "")) == String(right.get("target_type", ""))
		and String(left.get("op", "")) == String(right.get("op", ""))
	)


## Every key a floor must carry to be comparable. Read as a set rather than a
## `has` chain so a floor built by a caller that forgot a field is refused as
## incomparable instead of silently matching everything.
static func floor_keys(floor: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in ["target_id", "target_type", "op", "value"]:
		if floor.has(key):
			out.append(key)
	return out


## The lowest value `record` may legally take given `floor`: its own catalog
## window, raised to the floor when it feeds the same measure.
static func _floored_min(record: Dictionary, floor: Dictionary, window: Dictionary) -> float:
	var probe := OptionCatalog.instance().make_effect(record, 0.0, &"probe")
	if not _same_measure(probe, floor):
		return float(window["min"])
	return maxf(float(window["min"]), float(floor["value"]))


## The realized `effect` with its value lifted to `floor` when it feeds the same
## measure and landed below it. The window ceiling is NOT re-applied: a floor
## above the candidate's maximum simply leaves this effect unchanged, and the
## candidate list already refused to offer one whose maximum was under the floor.
static func _raised_to_floor(effect: Dictionary, floor: Dictionary) -> Dictionary:
	if _meets_floor(effect, floor):
		return effect
	var out := effect.duplicate(true)
	out["value"] = float(floor["value"])
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
