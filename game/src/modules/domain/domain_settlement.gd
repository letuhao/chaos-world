class_name DomainSettlement
extends RefCounted

## What a settlement room HOLDS and who stands in it (ADR 0163). The seam, and only
## the seam: a typed ref plus a lookup.
##
## ## The requirement this answers
##
## *"other place like sect, castle can be inside a domain, it also can become a inner
## world."* ADR 0073 decided a settlement is a ROOM KIND rather than a system and left
## one collision open — `InsideWorld` and `WorldState` already exist in `core/`. ADR
## 0163 resolves that collision (an inner world is a domain template of settlement
## rooms; those two stay milestone ledgers and are NOT read here) and this file is the
## smallest real proof the seam works end to end.
##
## ## A settlement NAMES an institution; it never IS one
##
## A sect-in-a-domain is a `RoomDef` of `kind = settlement` carrying a typed, STRING-
## KEYED ref. The ref rides the room's existing `fixtures` array as a
## [constant FIXTURE_KIND] entry naming a `SectDef.id`. It is an **id, never a
## `SectDef` sub-resource**: a sect names the room, the room does not hold the sect, and
## a ref that pointed at the resource would put a `domain -> sect` edge into the authored
## data as well as into the code.
##
## ## The lookup is INJECTED, for the reason every other one in this module is
##
## `domain` declares `core` + `contracts` only (`tools/arch/registry.json`), and
## `BARE_REF_UNITS` excludes `modules/*`, so a bare `SectApi` name here would report
## ZERO violations while still being a real cross-module edge. [method set_institution_lookup]
## is the same seam [method DomainSpawner.set_minter] and [method DomainFixtures.set_minter]
## already use, and `app/` is where the adapter belongs.
##
## With no lookup installed, a ref is **refused by name** rather than reported unknown:
## "we could not check" and "this sect does not exist" are different statements, and
## collapsing them would make an unwired build silently call every sect an authoring bug.
##
## ## This file writes NOTHING
##
## Every verb is a read. Not to the `Actor`, not to `actor.module_data`, not to the ref.
## A settlement names an institution and reports who is standing there; it does not
## found, staff, admit, expel or schedule anybody. A sect simulator is `sect`'s to own,
## and this module must not grow a second roster to answer for it (the ADR 0066 failure
## mode).
##
## ## Residents are the ROOM's spawn refs, in canonical order
##
## A role is a TAG on an `Actor`, never a class (`domain_roles.gd:29`), so a resident
## row is `{ref_id, inhabitant_id, role, count}` — ids and numbers, no class, no
## `Actor`, no sect roster. `count` is a GROUP, not that many rows, which is the shape
## `DomainMap.spawn_refs()` already publishes.

## The tag a settlement's authored ref carries in the room's `fixtures` array.
##
## It rides `fixtures` rather than a new `@export` on `RoomDef` for two reasons: that
## array is already authored, already `to_dict`'d and already JSON-round-tripped, and
## `RoomDef` is the CLOSED kit ADR 0073 froze — the set it admits is hard-failed by
## `tools data audit` rather than extended by a second room-level concept.
##
## Consequence, stated because it is real: [class DomainFixtures] has its own closed
## `KINDS` set and REFUSES an unrecognised one by name, so a `settlement_ref` row can
## never be armed or claimed as a fixture — it is a row that answers to a different
## reader. That is the repo's loud-failure rule working, not a collision.
const FIXTURE_KIND := &"settlement_ref"

## `RoomDef.KINDS`' settlement entry, restated because this file may not edit
## `room_def.gd`. One literal, in one place, for one kind.
const KIND_SETTLEMENT := &"settlement"

## The CLOSED set of institutions a settlement may name. One value, so a second kind is
## a content error reported by name instead of a word this file quietly accepts.
const REF_KIND_SECT := &"sect"
const REF_KINDS: Array[StringName] = [REF_KIND_SECT]

# --- reasons. Every refusal has a stable id a reader can show. ---------------

const ERR_NO_ACTOR := "no_actor"
const ERR_NO_RUN := "no_active_domain"
const ERR_NOT_SETTLEMENT := "not_a_settlement"
const ERR_NO_REF := "authors_no_settlement_ref"
const ERR_UNKNOWN_REF_KIND := "unknown_ref_kind"
const ERR_UNKNOWN_REF := "unknown_settlement_ref"
const ERR_NO_LOOKUP := "no_institution_lookup"

## Ceiling on the `fixtures` entries one room may carry. An authored array is small,
## but a hand-edited `.tres` is data and the walk below is bounded rather than trusted;
## a room over the ceiling is an authoring defect that must be visible, not a loop that
## has to be trusted.
const MAX_FIXTURES_PER_ROOM := 64

## The injected contact with the institution modules.
## `Callable(sect_id: StringName) -> Dictionary`: `{}` when nothing ships that id, else
## primitives — `{sect_id, display_name}`. A bare static function, not a typed lambda,
## for the reason `DomainFixtures.set_minter` records.
static var _institution: Callable = Callable()


## Install the institution lookup. Idempotent; a null injection restores the refusing
## default. `app/` passes an adapter over `SectApi`/`SectCatalog`.
static func set_institution_lookup(lookup: Callable) -> void:
	_institution = lookup


## What the settlement at `room_id` holds: its authored ref, and whether the catalog
## ships that institution. `{"ok": false, "reason": <named>}` on every refusal —
## never `{}`, because a caller cannot tell "no such room" from "no ref" from a bare
## `{}` and would have to guess which one it got.
##
## A settlement that authors NO ref is a refusal ([constant ERR_NO_REF]), not an empty
## success: a castle is a settlement with nothing named, and reporting that as `ok` with
## blank fields would render as a broken sect rather than as a building.
static func summary(actor: Actor, room_id: StringName) -> Dictionary:
	var room := _room_of(actor, room_id)
	if not room.get("ok", false):
		return room
	if String(room.get("room_kind", "")) != String(KIND_SETTLEMENT):
		return _answer(
			false,
			ERR_NOT_SETTLEMENT,
			{"room_id": String(room_id), "room_kind": String(room.get("room_kind", ""))}
		)
	var ref := _find_ref(room_id, room["fixtures"] as Array)
	if not ref.get("ok", false):
		return ref
	var ref_kind := StringName(ref["ref_kind"])
	if not REF_KINDS.has(ref_kind):
		return _answer(
			false,
			ERR_UNKNOWN_REF_KIND,
			{"room_id": String(room_id), "ref_kind": String(ref_kind), "asked": REF_KINDS}
		)
	var sect_id := StringName(ref["ref_id"])
	if _institution.is_null():
		return _answer(
			false,
			ERR_NO_LOOKUP,
			{"room_id": String(room_id), "ref_kind": String(ref_kind), "ref_id": String(sect_id)}
		)
	var found: Variant = _institution.call(sect_id)
	var institution: Dictionary = found if found is Dictionary else {}
	if institution.is_empty():
		return _answer(
			false,
			ERR_UNKNOWN_REF,
			{"room_id": String(room_id), "ref_kind": String(ref_kind), "ref_id": String(sect_id)}
		)
	return _answer(
		true,
		"",
		{
			"room_id": String(room_id),
			"display_name": String(room.get("display_name", "")),
			"room_kind": String(room.get("room_kind", "")),
			"ref_kind": String(ref_kind),
			"ref_id": String(sect_id),
			"institution":
			{
				"sect_id": String(institution.get("sect_id", "")),
				"display_name": String(institution.get("display_name", "")),
			},
		}
	)


## Who stands in the settlement at `room_id`, as primitives in canonical `ref_id`
## order. Works for ANY settlement — a castle with no ref has residents too, so this
## never consults the institution lookup and never refuses on one.
static func residents(actor: Actor, room_id: StringName) -> Dictionary:
	var room := _room_of(actor, room_id)
	if not room.get("ok", false):
		return room
	var rows: Array = []
	# Bounded `for` over the room's OWN authored array, copied and sorted before it is
	# read: the sort is what makes "same map, same order" a claim rather than a hope,
	# and nothing below grows the array it is walking.
	for entry in (room["spawn_refs"] as Array).duplicate():
		rows.append(_resident_row(entry))
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["ref_id"]) < String(b["ref_id"])
	)
	return _answer(true, "", {"room_id": String(room_id), "residents": rows, "count": rows.size()})


# ── internals ────────────────────────────────────────────────────────────────


## The room, or a named refusal. `DomainApi.room` is `{}` both outside a run and for a
## room the map does not hold — one honest question: a settlement exists only inside a
## run — so `no_active_domain` is the single reason for both.
static func _room_of(actor: Actor, room_id: StringName) -> Dictionary:
	if actor == null:
		return _answer(false, ERR_NO_ACTOR, {"room_id": String(room_id)})
	var room := DomainApi.room(actor, room_id)
	if room.is_empty():
		return _answer(false, ERR_NO_RUN, {"room_id": String(room_id)})
	return _answer(
		true,
		"",
		{
			"room_id": String(room_id),
			"room_kind": String(room.get("kind", "")),
			"display_name": String(room.get("display_name", "")),
			"fixtures": room.get("fixtures", []),
			"spawn_refs": room.get("actor_spawn_refs", []),
		}
	)


## The authored settlement ref, or a named refusal. Bounded by
## [constant MAX_FIXTURES_PER_ROOM] and reports the overflow rather than walking it: the
## bound is over the array's OWN size, taken before the loop, so it cannot grow in
## lockstep with the counter.
static func _find_ref(room_id: StringName, fixtures: Array) -> Dictionary:
	var seen := 0
	for entry in fixtures:
		if seen >= MAX_FIXTURES_PER_ROOM:
			return _answer(
				false, ERR_UNKNOWN_REF_KIND, {"room_id": String(room_id), "asked": REF_KINDS}
			)
		seen += 1
		if not entry is Dictionary:
			continue
		var fixture: Dictionary = entry
		if StringName(fixture.get("kind", "")) != FIXTURE_KIND:
			continue
		return _merged(
			{"ok": true, "reason": ""},
			{
				"ref_kind": String(fixture.get("ref_kind", "")),
				"ref_id": String(fixture.get("ref_id", "")),
			}
		)
	return _answer(false, ERR_NO_REF, {"room_id": String(room_id)})


## One resident row. Ids, a role tag and a count — never an `Actor`, never a class,
## never a sect roster copied in.
static func _resident_row(ref: Dictionary) -> Dictionary:
	return {
		"ref_id": String(ref.get("ref_id", "")),
		"inhabitant_id": String(ref.get("inhabitant_id", "")),
		"role": String(ref.get("role", "")),
		"count": maxi(1, int(ref.get("count", 1))),
	}


## `base` with `extra` written over it, leaving `base` untouched. `Dictionary.merge`
## returns `void` and merges in place, so the copy is what keeps a caller's dictionary
## from being rewritten under it — the same note `DomainFixtures._merged` carries.
static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
