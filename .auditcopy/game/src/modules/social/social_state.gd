class_name SocialState
extends RefCounted

## An actor's whole social ledger (ADR 0076).
##
## **One ledger per actor, and it is symmetric by construction.** The player and every
## npc carry the identical type, so "npcs have social stats, same for player" is a fact
## about the type rather than a promise two code paths have to keep (ADR 0001 shape).
##
## The ledger is stored in `actor.module_data[MODULE_KEY]`, never in a bespoke save slot:
## `Actor.to_dict` already round-trips `module_data`, so core never names a social type
## and no schema bump is owed (ADR 0027).
##
## `changed` is emitted on every mutation so a `StatProvider` reading this ledger is
## invalidated the same way `NameList` and `AffinityMap` are.

signal changed

## The versioned ledger key. Bumped only if the payload shape changes incompatibly.
const MODULE_KEY := &"social_state"
const SCHEMA_VERSION := 1

## Aggregate regard with an institution (a clan, a sect, a market), keyed by id. Separate
## from bonds because a player regards a *clan* without having met any single member, and
## the clan module owns that number already (ADR 0064) — this is the read model, not a
## second writer of it.
##
## ## It is DERIVED, never stored — which is what BL-0200 turned it into
##
## It was declared, persisted, restored, published through `summary()` and written by
## NOTHING: the read model ADR 0091 promised was permanently empty. The fix is not a
## second number and not an assignment from `sect/` — it is the same bonds, filtered to
## the rows whose partner is an INSTITUTION (`SocialBond.institutional`). So the cause
## ledger, the floors, the decay and the anti-farm distinct-cause rule all apply to an
## institution exactly as they do to a person, which is the property that makes "why
## does the world think well of you here" answerable from a save.
##
## **A separate copy is the ADR 0066 failure mode.** `AGENTS.md` forbids the three
## tiers growing a second copy of one fact, and a float `sect/` wrote itself would be
## that copy with no cause ledger behind it. There is one source of truth — the bond —
## and this is a read of it.
##
## **Still JSON-safe**: `String` keys, float values, nothing else. The persistence
## contract is unchanged, so an older save with `regard: {}` restores and is then
## rebuilt by the next cause, and a save carrying `regard` restores the BONDS that
## produce it (see `from_dict`).
var regard: Dictionary = {}

var _bonds: Dictionary = {}


func _init() -> void:
	pass


## The bond with `partner_id`, or null when they have never met.
func bond(partner_id: StringName) -> SocialBond:
	return _bonds.get(String(partner_id))


## Get or create the bond with `partner_id`. Creation alone is not a change worth
## announcing, so only `apply` signals.
func ensure_bond(partner_id: StringName) -> SocialBond:
	var key := String(partner_id)
	if not _bonds.has(key):
		_bonds[key] = SocialBond.new(partner_id)
	return _bonds[key]


func partner_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _bonds.keys():
		out.append(StringName(key))
	out.sort()
	return out


func bond_count() -> int:
	return _bonds.size()


## Forget a bond entirely. Used when an npc is retired, so a dead minor does not haunt
## the ledger forever. An institutional bond forgotten this way leaves `regard` too —
## a dissolved sect is no longer one you are regarded by, and a read model that kept
## naming it would outlive the row that produced it.
func forget(partner_id: StringName) -> bool:
	if not _bonds.has(String(partner_id)):
		return false
	_bonds.erase(String(partner_id))
	mark_changed()
	return true


func mark_changed() -> void:
	_rebuild_regard()
	changed.emit()


## Rebuild `regard` from the institutional bonds. Called on every mutation, so the
## published read model can never disagree with the ledger it claims to summarise.
##
## **Why it is a rebuild rather than an `+=` at each call site.** ADR 0091's decay
## moves a bond toward its floor without going through `apply`, so an additive writer
## would leave `regard` naming a number the axes no longer hold. One projection, run
## from the one place mutations are announced, is the shape `RaceProjection` and
## `SectProjection` already use for exactly this reason.
##
## A bond with no institutional cause is not a row here: a partner the player has
## never sworn, served or been cast out of is not an institution they are regarded by,
## and `{}` for them is ADR 0083's first state rather than a zero standing.
func _rebuild_regard() -> void:
	var out := {}
	for partner_id in partner_ids():
		var row := _bonds.get(String(partner_id)) as SocialBond
		if row == null or not row.institutional:
			continue
		out[String(partner_id)] = row.standing
	regard = out


func to_dict() -> Dictionary:
	var bonds := {}
	for key in _bonds.keys():
		bonds[String(key)] = _bonds[key].to_dict()
	return {
		"version": SCHEMA_VERSION,
		"bonds": bonds,
		"regard": regard.duplicate(),
	}


static func from_dict(data: Dictionary) -> SocialState:
	var state := SocialState.new()
	for key in data.get("bonds", {}).keys():
		state._bonds[String(key)] = SocialBond.from_dict(data["bonds"][key])
	# `regard` is NOT restored from the payload. It is a projection, and restoring a
	# derived value is how a read model starts disagreeing with the ledger it claims
	# to summarise — the bonds are restored and `_rebuild_regard` recomputes the same
	# answer, so a save written before BL-0200 (whose `regard` was always `{}`) reads
	# exactly the same as one written after.
	state._rebuild_regard()
	return state


static func empty() -> Dictionary:
	return {"version": SCHEMA_VERSION, "bonds": {}, "regard": {}}
