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
## the ledger forever.
func forget(partner_id: StringName) -> bool:
	if not _bonds.has(String(partner_id)):
		return false
	_bonds.erase(String(partner_id))
	changed.emit()
	return true


func mark_changed() -> void:
	changed.emit()


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
	for key in data.get("regard", {}).keys():
		state.regard[String(key)] = float(data["regard"][key])
	return state


static func empty() -> Dictionary:
	return {"version": SCHEMA_VERSION, "bonds": {}, "regard": {}}
