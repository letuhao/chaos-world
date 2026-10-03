class_name SoulState
extends RefCounted

## The versioned soul ledger, stored in an INJECTED store rather than in
## `actor.module_data` (ADR 0127).
##
## ## Why not `module_data`
##
## Every other module's ledger lives in `actor.module_data`, because every other module's
## state dies with its actor. A soul is the one thing here that does not: the whole feature is
## a body dying and the soul continuing. A ledger stored on the actor therefore dies with
## exactly the thing it exists to outlive, and the failure is silent — every single-actor test
## passes. ADR 0101 already recorded that a per-actor copy of a world fact is a correctness
## bug the moment a second holder exists, and this is that case again with one holder.
##
## The actor mirror is kept, but only because a save carries it. It is never read as truth.
##
## ## The numbers are separate on purpose
##
## `integrity` and `lives` answer different questions and never derive from one another. A
## soul can be undamaged and out of lives, or damaged and still able to re-body. Reading one
## from the other is the and-rule failure ADR 0066 names: a second place to disagree.

const SCHEMA_VERSION := 1
## The store's ledger key, and the actor mirror's `module_data` key.
const MODULE_KEY := &"soul_state"
## The damage and repair trails explain what happened to a soul. They are not an audit log,
## and a save cannot grow without limit — the `DestinyState.HISTORY_LIMIT` reason.
const HISTORY_LIMIT := 32
## The default a soul starts at. Authored nowhere on purpose: a soul is not content, and
## letting a `.tres` move it would make the ledger's floor a second place to retune.
const DEFAULT_INTEGRITY := 100
const DEFAULT_LIVES := 3


## Normalize a payload into the one shape this module reads.
##
## `known_origins` is the catalog's answer, and an entry naming an origin the catalog no
## longer ships is DROPPED rather than persisted — the `DestinyState.normalize` rule, so a
## save written by a wider content build cannot smuggle in an arrival this build does not
## define. An empty filter means "unanswered question, keep everything", which is what a
## caller with no catalog installed means.
static func normalize(payload: Dictionary, known_origins: Dictionary = {}) -> Dictionary:
	var out := {
		"version": SCHEMA_VERSION,
		"integrity": DEFAULT_INTEGRITY,
		"integrity_max": DEFAULT_INTEGRITY,
		"lives": DEFAULT_LIVES,
		"lives_max": DEFAULT_LIVES,
		"incarnation": 0,
		"origin_id": "",
		"body_id": "",
		"difficulty_id": "",
		"origins": [],
		"damage": [],
		"repair": [],
	}
	if payload.is_empty():
		return out
	var max_integrity := _number(payload.get("integrity_max", DEFAULT_INTEGRITY), DEFAULT_INTEGRITY)
	var max_lives := _number(payload.get("lives_max", DEFAULT_LIVES), DEFAULT_LIVES)
	# A maximum of zero would make every later value meaningless and the ledger could never
	# move, so it is floored at one. A maximum is an authored floor, not a difficulty dial.
	out["integrity_max"] = maxi(1, max_integrity)
	out["lives_max"] = maxi(1, max_lives)
	out["integrity"] = clampi(
		_number(payload.get("integrity", out["integrity_max"]), out["integrity_max"]),
		0,
		out["integrity_max"]
	)
	out["lives"] = clampi(
		_number(payload.get("lives", out["lives_max"]), out["lives_max"]), 0, out["lives_max"]
	)
	out["incarnation"] = maxi(0, _number(payload.get("incarnation", 0), 0))
	out["body_id"] = String(payload.get("body_id", ""))
	out["difficulty_id"] = String(payload.get("difficulty_id", ""))
	# A payload that cannot be read is diagnosed as empty, never partially applied. Half a
	# ledger is worse than none: it silently changes what the player is owed a body for.
	out["origins"] = _origins(payload.get("origins", []), known_origins)
	out["origin_id"] = _origin_id(payload, out["origins"] as Array)
	out["damage"] = _trail(payload.get("damage", []))
	out["repair"] = _trail(payload.get("repair", []))
	return out


## The empty ledger.
static func empty() -> Dictionary:
	return normalize({})


## Apply `amount` of damage, returning the value integrity moved BY.
##
## Returned rather than inferred because the caller announces the delta: once the new total
## is in the ledger, `new - old` can only be recovered by a caller that was told the real
## amount. This is the same thread-through that `DestinyApi.record` uses.
static func apply_damage(ledger: Dictionary, amount: int, reason: String) -> int:
	var applied := maxi(0, mini(amount, int(ledger.get("integrity", 0))))
	if applied <= 0:
		return 0
	ledger["integrity"] = int(ledger.get("integrity", 0)) - applied
	_append(ledger, "damage", applied, reason)
	return applied


## Apply `amount` of repair, returning the value integrity moved BY. Repair only ever raises
## integrity and never above the maximum: a repair that overflowed would hand a soul more than
## its own authored ceiling.
static func apply_repair(ledger: Dictionary, amount: int, reason: String) -> int:
	var room := int(ledger.get("integrity_max", 0)) - int(ledger.get("integrity", 0))
	var applied := maxi(0, mini(amount, room))
	if applied <= 0:
		return 0
	ledger["integrity"] = int(ledger.get("integrity", 0)) + applied
	_append(ledger, "repair", applied, reason)
	return applied


## Whether this soul still has a body to lose.
static func has_lives(ledger: Dictionary) -> bool:
	return int(ledger.get("lives", 0)) > 0


## Whether the ledger already records `origin_id`.
static func has_origin(ledger: Dictionary, origin_id: StringName) -> bool:
	return (ledger.get("origins", []) as Array).has(String(origin_id))


## Record a re-embodiment: one more incarnation, one fewer life, a new body, and the arrival
## it earned. Returns the incarnation number it landed on.
static func incarnate(
	ledger: Dictionary, body_id: StringName, origin_id: StringName, _known_origins: Dictionary = {}
) -> int:
	ledger["incarnation"] = int(ledger.get("incarnation", 0)) + 1
	ledger["lives"] = maxi(0, int(ledger.get("lives", 0)) - 1)
	ledger["body_id"] = String(body_id)
	if origin_id != &"" and not has_origin(ledger, origin_id):
		(ledger["origins"] as Array).append(String(origin_id))
	ledger["origin_id"] = String(origin_id)
	return int(ledger["incarnation"])


# --- Internals -------------------------------------------------------------


## `value` as an int, or `fallback` when it is not a number at all.
##
## `int()` on a String is a RUNTIME error in GDScript rather than a coercion, so a save
## carrying `"integrity": "not a number"` would abort `normalize` instead of being diagnosed —
## and an unreadable payload must normalize, never throw. That is the `DestinyState` rule
## ("diagnosed as empty, never partially applied") applied to the numbers a death decides on.
static func _number(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


## The arrival the ledger currently sits in: the named one when it is still a real origin,
## otherwise the most recent recorded arrival. A payload naming an origin this build does not
## ship reads as no arrival rather than as an arrival nothing can explain.
static func _origin_id(payload: Dictionary, origins: Array) -> String:
	var named := String(payload.get("origin_id", ""))
	if not named.is_empty() and origins.has(named):
		return named
	if origins.is_empty():
		return ""
	return String(origins[origins.size() - 1])


## The earned arrivals, oldest first, capped and filtered.
static func _origins(value, known_origins: Dictionary) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		var id := String(entry)
		if id.is_empty() or out.has(id):
			continue
		if not known_origins.is_empty() and not known_origins.has(id):
			continue
		out.append(id)
		if out.size() >= HISTORY_LIMIT:
			break
	return out


## One damage or repair trail. Rebuilt field by field rather than duplicated, because a
## file-backed save makes one JSON hop and JSON has a single number type: a copied amount
## comes back as a float and the ledger stops comparing equal to itself across a save. This
## is `DestinyState.normalize`'s reason, applied to numbers that are read back.
static func _trail(value) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		(
			out
			. append(
				{
					"amount": int(row.get("amount", 0)),
					"integrity_after": int(row.get("integrity_after", 0)),
					"reason": String(row.get("reason", "")),
					"incarnation": int(row.get("incarnation", 0)),
				}
			)
		)
		if out.size() >= HISTORY_LIMIT:
			break
	return out


## Append one bounded trail row. The oldest is dropped once the cap is reached, so the trail
## explains the recent past rather than growing with the run.
static func _append(ledger: Dictionary, key: String, amount: int, reason: String) -> void:
	var trail := ledger[key] as Array
	(
		trail
		. append(
			{
				"amount": amount,
				"integrity_after": int(ledger.get("integrity", 0)),
				"reason": reason,
				"incarnation": int(ledger.get("incarnation", 0)),
			}
		)
	)
	if trail.size() > HISTORY_LIMIT:
		trail = trail.slice(trail.size() - HISTORY_LIMIT)
		ledger[key] = trail
