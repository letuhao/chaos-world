class_name DomainFixtures
extends RefCounted

## The `status` module's FACADE, preloaded for the reason `EnvironmentField` states: a
## bare `StatusApi.` out of `modules/*` is invisible to `tools arch`
## (`rules.BARE_REF_UNITS`), and the `res://` reference below is what makes the
## `domain -> status` edge both legal and counted.
const StatusApi := preload("res://src/modules/status/api.gd")

## What an AUTHORED FIXTURE does when a player walks onto it (ADR 0073, ADR 0075).
## `RoomDef.fixtures` was authored on seven rooms, copied faithfully by four paths
## (`to_dict` / `from_dict` / the generator's deep copy / the JSON round trip), and read
## by nothing at runtime: this file is the missing reader.
##
## - `trap` — [method arm] telegraphs, then fires ONCE and marks `spent`. It never
##   subtracts health: the cost is the `StatusEffect` [method _fire] builds, the same
##   shape `EnvironmentField._hazard` builds, so a trap obeys the same duration,
##   stacking and cleanse rules as every other status (ADR 0075).
## - `puzzle` — [method attempt] names one node; correct advances, wrong applies the
##   authored `wrong_status_id` as a CONTROL status and resets the sequence. NEVER
##   health: a puzzle that kills you is a second fight wearing a costume.
## - `treasure` — [method claim] is refused by name without the authored key and realm
##   floor.
##
## ONE ledger at `DomainApi.MODULE_KEY` / [constant STATE_KEY], keyed
## `"<room_id>/<fixture_id>"`, primitive-valued (ADR 0027): `position` / `bounds` are
## read off the FIXTURE every time and never copied in, because a `Vector2` in this
## dictionary would silently break every save. Statuses are session-only (ADR 0089), so
## a trap's potency is re-resolved on arrival rather than stored.
##
## `add_status` alone left the trap INERT, which was the measured defect: a trap fired,
## reported `OK_FIRED`, sat on the actor, passed every presence assertion, and cost zero
## health, because the pulse is paid by `status` out of its own per-actor runtime table.
## [method _settle] is that seam, and it is a facade call.
##
## `domain` declares `core` + `contracts` + `status` only, so this file reaches exactly
## ONE sibling module through its facade ([constant StatusApi]) and names no `items`
## class — the same constraint `DomainSpawner` solved with [method set_minter]. Key
## reach and reward delivery both arrive as ONE injected pair of `Callable`s, so every
## answer about delivery stays in the module that already owns it.

# ── the three authored kinds ─────────────────────────────────────────────────

const KIND_TRAP := &"trap"
const KIND_PUZZLE := &"puzzle"
const KIND_TREASURE := &"treasure"

## CLOSED, so an unrecognised kind is a loud refusal rather than a fixture the game
## quietly ignores — the failure this file exists to end.
const KINDS: Array[StringName] = [KIND_TRAP, KIND_PUZZLE, KIND_TREASURE]

## Where the ledger lives inside the run. Nested under [constant DomainApi.MODULE_KEY]
## rather than beside it because a spent trap is run state: `DomainApi.enter` clears
## it and `DomainApi.leave` discards it, so a second run starts armed.
const STATE_KEY := "fixtures"

## The `damage_share` a trap's status spends PER PULSE, and the cadence it pulses at.
## The cadence is the hazard def's own `tick_interval` read through
## [method EnvironmentField.hazard_cadence], not a literal: two authored numbers and a
## third is a place for them to disagree (`environment_field.gd:203`). The substrate and
## the lever tables it resolves against moved to [DomainFixtureLevers].
const SUBSTRATE := DomainFixtureLevers.SUBSTRATE

## A wrong puzzle node costs the ATTEMPT, not the body: a fully interrupted strike,
## for `duration_s`. CONTROL and not DOT, because a DOT is a damage-over-time channel
## and ADR 0075 forbids a second one outside `StatusEffect` semantics.
const WRONG_GATE := 1.0

## The floor on every authored duration. A fixture that authors `duration_s: 0.0`
## would otherwise hand out a permanent status, which is not something a content
## author gets by accident — the same floor `EnvironmentField.MIN_DURATION` uses.
const MIN_DURATION := 0.5

## The ceiling on the tile walk [method _segment_touches] takes while sweeping a
## movement step across a footprint. Bounded by the step's own length, so it terminates
## on authored data — but a step in TILES can be as long as the map, and a data-derived
## bound is not a small one. Far above any authored room's diagonal, so the cap can never
## change an answer while still naming the condition it reached.
const MAX_FOOTPRINT_WALK := 4096

# --- reasons. Every refusal has a stable id a reader can show. ---------------

const OK_TELEGRAPHING := "telegraphing"
const OK_FIRED := "fired"
const OK_ADVANCED := "advanced"
const OK_WRONG_NODE := "wrong_node"
const OK_CLAIMED := "claimed"
const ERR_NO_ACTOR := "no_actor"
const ERR_NO_RUN := "no_active_domain"
const ERR_UNKNOWN_FIXTURE := "unknown_fixture"
## A fixture whose `kind` is outside the closed [constant KINDS]. Refused here rather
## than skipped, so a fourth kind someone authors lands as a red test instead of a
## fixture the game walks past. `test_domain_content.gd:76` already closes the set.
const ERR_UNKNOWN_KIND := "unknown_fixture_kind"
const ERR_WRONG_KIND := "wrong_kind_for_this_verb"
const ERR_ALREADY_FIRED := "already_fired"
const ERR_ALREADY_CLAIMED := "already_claimed"
## Presence is the trigger, so "the body is not in the footprint" is an ORDINARY answer
## rather than a failure: the actor is standing somewhere else. Reported by name because a
## caller driving a movement step needs to tell "you are elsewhere" from "this trap is
## spent" — the first is free and the second is a one-way state.
const ERR_OUTSIDE := "outside_the_footprint"
## A trap authoring an empty `bounds` cannot be entered, so presence refuses it rather
## than treating an absent footprint as "everywhere" (ADR 0075: a zone is a volume you
## route around, and a volume of nothing is not a volume). An AUTHORING error.
const ERR_NO_FOOTPRINT := "authors_no_footprint"
const ERR_UNKNOWN_NODE := "unknown_node"
const ERR_MISSING_KEY := "missing_key"
const ERR_REALM_TOO_LOW := "realm_below_the_floor"
const ERR_NO_BRIDGE := "no_inventory_bridge"
const ERR_INVENTORY_FULL := "inventory_full"
const ERR_NO_STATUS := "authors_no_status_id"
const ERR_NO_SHARE := "authors_no_damage_share"
const ERR_NOTHING_TO_GRANT := "authors_nothing_to_grant"
## The reward names no item the corpus can resolve. Reported BY NAME, never folded into
## [constant ERR_INVENTORY_FULL]: the player is told their bag is full for a bag that had
## nothing to do with it. An AUTHORING error, and it reads as one because the reason says
## so — `QuestGrants.ITEM_UNKNOWN` is the same distinction and spelling.
const ERR_UNKNOWN_ITEM := "unknown_item"
## The reward resolves and the key does too, but the actor has no `items` module at
## all. Distinct from a full bag for `QuestGrants`' reason (`quest_grants.gd:58`):
## an actor with no inventory cannot have one that is full.
const ERR_NO_INVENTORY := "no_inventory"

## The currencies a domain pays in (ADR 0216), named by WHERE the reward sits in the
## run and never by a roll. A fixture pays ONE of these; the fixture's own `kind`
## and tags decide which, and `_pays_lore` is the only reader.
const PAY_EQUIPMENT := "equipment"
const PAY_LORE := "lore"

## A treasure carries AT MOST ONE gate — keyed *and* realm-gated on the same container
## is two walls on one box, and the second is invisible to the player because the first
## is what stops them. `GATE_OPEN` is the honest name for "no gate": the ROOM is the gate
## (ADR 0217), not a flag.
const GATE_OPEN := "open"
const GATE_KEYED := "keyed"
const GATE_REALM := "realm"

## The formation puzzle's payout is a LEDGER ROW, not an item: the thing a solved
## formation hands over is what the player now knows, so the id it records is
## derived from the fixture and is stable across machines and runs.
const LORE_PREFIX := "fixture_formation_solved"

## How much insight one solved formation records. **A counter, not a currency
## magnitude** (ADR 0216: the lore row is "deliberately the thinnest"), so it is one
## per solve and a re-solve is refused by `already_claimed` rather than paying
## twice.
const LORE_INSIGHT := 1

## The one unit a fixture pays (ADR 0216 §3). `reward_count` leaves the vocabulary:
## a hoard holds a relic, not a stack of relics, and every authored `ItemDef` of
## equipment shape is `stackable = false`, so a second unit has no delivery at all.
const ONE_UNIT := 1

## The two injected contacts with the items module, mirroring `DomainSpawner._minter`
## (`domain_spawner.gd:48`). Declared `static var` and below the consts because
## `gdlintrc`'s `class-definitions-order` puts `staticvars` under `consts`.
static var _key_reach: Callable = Callable()
static var _granter: Callable = Callable()


## Install the two contacts with the items module. Idempotent; a null pair restores the
## refusing default.
##
## `keys` is `Callable(actor, item_id) -> float`, answering the `key_reach` a carried
## `item_id` is worth (0.0 when it is not carried). `granter` is
## `Callable(actor, item_id, seed) -> Dictionary` answering
## `{leftover, reason, instance_id}` — the shape `DomainBoot.grant_item` implements,
## realizing one unit through the items facade's seeded mint (ADR 0216 §4). An INTEGER
## leftover is still
## read as "nothing was handed over", so the older seam degrades rather than breaking,
## but the third argument is the fixture-derived SEED, not a count: a fixture pays ONE
## unit (ADR 0216 §3), and the seed is what makes the relic the same relic on replay.
##
## ## WHY AN INTEGER LEFTOVER AND NOT AN ANSWER DICTIONARY
##
## The docblock here once named a `-> Dictionary` seam, which no caller implemented, so
## every delivery raised a type error and returned `{}` — a treasure reported
## `already_claimed` having claimed nothing. The documented shape had to become the
## SHIPPED shape, which is why [method _grant] reads the answer's type. All-or-nothing is
## still load-bearing: `leftover > 0` leaves the claim untouched, `LootRewards.deliver`'s
## convention.
##
## Bare static functions, not typed lambdas: `app/domain_boot.gd:31-33` records a
## process-killing access violation from a typed lambda forwarding to another script's
## static function, and `DomainSpawner.set_minter` is handed `ActorFactory.spawn_inhabitant`
## itself for the same reason.
static func set_minter(keys: Callable, granter: Callable) -> void:
	_key_reach = keys
	_granter = granter


## Advance a trap standing on `footprint` by `delta` seconds. THE ONLY TRIGGER, because
## ADR 0211 makes a trap fire on PRESENCE and a button may never detonate one.
##
## `presence` is the entry point because `arm` used to be, and its caller was a button:
## a player pressed `Arm` twice, which made the cost payable for having INSPECTED a trap
## rather than for having ENTERED one — a player who walked over a trap was free and one
## who read the room paid — and it made the telegraph unreachable, because the window
## opened and closed inside a single press. The caller passes where the actor IS, never a
## verb.
##
## `armed -> telegraphing -> spent`, never re-armed within a run: a player is never taxed
## twice for one mistake, and a second run starts armed because `DomainApi.enter` clears
## the ledger.
##
## A movement step is not a point sample — it can start and end outside the footprint,
## having crossed the whole thing in one frame. Sweeping the SEGMENT rather than testing
## the endpoint is what keeps such a step honest, and [method arm] always arms on its
## first call whatever `delta` says, so a single long frame still owes the player the
## authored warning. `delta` is a parameter rather than a wall-clock read so a replay
## arms and fires exactly as it was driven, matching `StatusRegistry.tick`.
static func presence(
	actor: Actor, room_id: StringName, fixture_id: StringName, at: Vector2i, delta: float = 0.0
) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not found.get("ok", false):
		return found
	var fixture: Dictionary = found["fixture"]
	var record := _record(actor, String(found["key"]))
	if StringName(fixture.get("kind", "")) != KIND_TRAP:
		# A fixture that genuinely needs an ACTION is an authoring error, not a new code
		# path (ADR 0211). `attempt` and `claim` are the verbs for those kinds, and a
		# puzzle answers wrong with an interruption and never with health.
		return _answer(false, ERR_WRONG_KIND, _about(fixture, room_id))
	var outside := _outside_footprint(actor, fixture, at)
	if outside:
		return outside
	return arm(actor, room_id, fixture_id, delta)


## Look at one fixture WITHOUT touching it: exactly what [method telegraph] already
## returns, and not one byte more. Free and non-mutating by construction — it reads the
## ledger and writes nothing — which is what makes inspecting a trap the RIGHT play rather
## than a mistake (ADR 0211).
static func inspect(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return telegraph(actor, room_id, fixture_id)


## Whether `actor` is inside `fixture`'s authored footprint, tested over the whole
## MOVEMENT STEP and not over one point, preserving ADR 0211's "enters and fully crosses
## in one frame" rule.
##
## A `Rect2i` test, not the realized `Area2D`: `DomainScene._place_zones` realizes a
## ZONE as an area and a fixture has none, and `domain` may not depend on `app/` where
## `DomainScene` lives. The authored `bounds` IS the footprint — it is what
## [method telegraph] publishes to the scene that DRAWS it, and what
## `test_domain_scene.gd:589` already pins as "the authored rect, not a heuristic".
##
## `actor`'s last recorded tile is the segment's start, so a caller that only knows where
## the actor is NOW still gets the crossing. No recorded position is tested as a single
## point at `at`: nothing said it moved.
static func _outside_footprint(actor: Actor, fixture: Dictionary, at: Vector2i) -> Dictionary:
	var box: Rect2i = fixture.get("bounds", Rect2i())
	if box.size.x <= 0 or box.size.y <= 0:
		# A fixture authoring no footprint cannot be entered, so presence never arms it.
		# Refused BY NAME rather than treated as "everywhere", which would make an
		# unauthored trap fire from the whole room — the defect ADR 0075 refuses.
		return _answer(false, ERR_NO_FOOTPRINT, _about(fixture, &""))
	var from := at
	var placed := _placed_tile(actor)
	if not placed.is_empty():
		from = Vector2i(int(placed[0]), int(placed[1]))
	if _segment_touches(box, from, at):
		return {}
	return _answer(false, ERR_OUTSIDE, _about(fixture, &""))


## Whether the straight run `from -> to` meets `box` at all, sampled per TILE rather than
## by a float segment query: the grid is the map's own unit (`EnvironmentZoneDef.bounds`
## is authored in tiles), and a tile walk is exact at any distance where a float
## intersection test would need an epsilon nobody authored.
##
## Bounded by the box's own diagonal in tile steps plus the two endpoints, so a long
## map cannot make this a long loop: the walk stops the moment it leaves the box, and a
## start already outside contributes its single tile.
static func _segment_touches(box: Rect2i, from: Vector2i, to: Vector2i) -> bool:
	if box.has_point(from) or box.has_point(to):
		return true
	# The sign of each axis, taken ONCE: a zero component is copied straight rather than
	# stepping, so an axis-aligned walk terminates on its other axis instead of dividing
	# by zero or looping forever on a degenerate step.
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var remaining := maxi(absi(to.x - from.x), absi(to.y - from.y))
	var walked := 0
	while walked < remaining and walked < MAX_FOOTPRINT_WALK:
		walked += 1
		if step.x != 0:
			from.x += step.x
		if step.y != 0:
			from.y += step.y
		if box.has_point(from):
			return true
	return false


## Where the run last placed `actor`, as `[x, y]`, or `[]` when nothing placed it. Read
## from the SAME `module_data` key `DomainSpawner` writes, so "where the body is" has one
## answer in the game rather than a second one derived here. The PLAYER is not spawned by
## `spawn_map`, so this is empty for them — which is why `at` is the caller's to pass: a
## screen and a tick know where the body is this frame, and a module that never ran the
## spawn cannot invent it.
static func _placed_tile(actor: Actor) -> Array:
	if actor == null:
		return []
	var placed: Variant = actor.get_module_data(DomainSpawner.MODULE_KEY).get("position", null)
	if placed is Array and (placed as Array).size() >= 2:
		return [int((placed as Array)[0]), int((placed as Array)[1])]
	return []


## Advance an armed trap's telegraph by `delta` and fire it when the window has elapsed.
## The TIME HALF of the trigger, and deliberately NOT the entry point: ADR 0211 makes
## presence the only thing that may call this, so no button can reach a trap through it.
## [method presence] is the seam a scene, a tick and a test all go through.
##
## The first call ALWAYS arms, whatever `delta` says: a caller that crossed the telegraph
## window in one long frame still owes the player the warning, and a trap that fires on
## the frame it spawns is the untelegraphed hazard ADR 0075 refuses.
static func arm(
	actor: Actor, room_id: StringName, fixture_id: StringName, delta: float = 0.0
) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not found.get("ok", false):
		return found
	var fixture: Dictionary = found["fixture"]
	var key := String(found["key"])
	var record := _record(actor, key)
	var status_id := StringName(fixture.get("status_id", ""))
	if status_id == &"":
		return _answer(false, ERR_NO_STATUS, _about(fixture, room_id))
	if record.get("spent", false):
		return _answer(false, ERR_ALREADY_FIRED, _about(fixture, room_id))
	var elapsed := float(record.get("armed_s", 0.0)) + maxf(delta, 0.0)
	var telegraph := float(fixture.get("telegraph_s", 0.0))
	if record.get("armed", false) and elapsed >= telegraph:
		return _fire(actor, fixture, key, room_id)
	_write(actor, key, {"armed": true, "armed_s": elapsed})
	var seen := telegraph - elapsed
	return _answer(
		true,
		OK_TELEGRAPHING,
		_merged(
			_about(fixture, room_id),
			{"telegraph_s": telegraph, "telegraph_remaining_s": maxf(0.0, seen), "status_id": ""}
		)
	)


## Strike one node of a puzzle. A correct node advances; the last one completes the
## formation and grants `reward_item_id` x `reward_count` through the same granter a
## treasure uses, so there is one delivery path in the game and not one per fixture kind. A
## wrong node applies the authored `wrong_status_id` and resets progress to the first node —
## reset, not merely frozen, so a player who cannot find the order is never stuck against a
## formation they half-solved and cannot resume.
static func attempt(
	actor: Actor, room_id: StringName, fixture_id: StringName, node_id: StringName
) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not found.get("ok", false):
		return found
	var fixture: Dictionary = found["fixture"]
	var key := String(found["key"])
	var record := _record(actor, key)
	var nodes: Array = fixture.get("nodes", [])
	var sequence: Array = fixture.get("sequence", [])
	if sequence.is_empty():
		return _answer(false, ERR_NOTHING_TO_GRANT, _about(fixture, room_id))
	if record.get("claimed", false):
		return _answer(false, ERR_ALREADY_CLAIMED, _about(fixture, room_id))
	var node := String(node_id)
	if not nodes.has(node) and not nodes.has(node_id):
		return _answer(false, ERR_UNKNOWN_NODE, _about(fixture, room_id))
	var progress := int(record.get("progress", 0))
	if progress >= sequence.size():
		return _answer(false, ERR_ALREADY_CLAIMED, _about(fixture, room_id))
	if node != String(sequence[progress]):
		return _wrong(actor, fixture, key, room_id, node)
	progress += 1
	if progress < sequence.size():
		_write(actor, key, {"progress": progress})
		return _answer(
			true,
			OK_ADVANCED,
			_merged(_about(fixture, room_id), {"progress": progress, "complete": false})
		)
	var payout := _grant(actor, fixture, key)
	if not payout.get("ok", false):
		return payout
	_write(actor, key, {"progress": progress, "complete": true, "claimed": true})
	return _answer(true, OK_CLAIMED, _merged(_about(fixture, room_id), _payout_fields(payout)))


## Open a treasure. Refused by name at every gate, in the order a player meets them:
## already taken, then the key, then the realm floor, then delivery.
static func claim(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not found.get("ok", false):
		return found
	var fixture: Dictionary = found["fixture"]
	var key := String(found["key"])
	var record := _record(actor, key)
	var about := _about(fixture, room_id)
	if record.get("claimed", false):
		return _answer(false, ERR_ALREADY_CLAIMED, about)
	var gate := _key_gate(actor, fixture, about)
	if not gate.is_empty():
		return gate
	var realm_gate := _realm_gate(actor, fixture, about)
	if not realm_gate.is_empty():
		return realm_gate
	var payout := _grant(actor, fixture, key)
	if not payout.get("ok", false):
		return payout
	_write(actor, key, {"claimed": true})
	return _answer(true, OK_CLAIMED, _merged(about, _payout_fields(payout)))


## What this actor would carry from this fixture, WITHOUT touching them: the same
## measure-before-and-after `EnvironmentField.residual_amount` exists for, so a screen
## can show the authored number and the actor's real one side by side.
##
## ## At most ONE lever is ever credited, whatever the actor carries (ADR 0212)
##
## [DomainFixtureLevers.lever_for] returns on first match in identity order, so a hero
## with all four levers gets ONE cap — the strongest that actually fires for them — never
## a sum. That is the per-instance floor: holding everything does not reduce the cost below
## `authored * (1 - strongest_single_cap)`, because a hazard that four budgets had
## cancelled out would have stopped being a hazard.
static func residual_share(actor: Actor, fixture: Dictionary) -> Dictionary:
	var lever := _lever_for(actor, fixture)
	var share := maxf(0.0, float(fixture.get("damage_share", 0.0)))
	var cap := _cap_for(lever)
	if cap <= 0.0:
		# Published but structurally inert on this substrate, so it was never credited
		# and subtracting from the number anyway would report a mitigation that did not
		# happen (`EnvironmentField._amount`).
		return _amounts(share, share, "")
	var held := 1.0
	if lever == String(EnvironmentField.LEVER_AFFINITY):
		held = EnvironmentField.affinity_strength(
			actor, _status_element(StringName(fixture.get("status_id", "")))
		)
	return _amounts(share, share * (1.0 - cap * minf(1.0, held)), lever)


## The boundary a scene draws BEFORE anything lands, as primitives, for one fixture.
## Primitives only, so it crosses into a Node without this module knowing one exists —
## the same contract `EnvironmentField.telegraph` offers a zone.
##
## The `damage_share` telegraphed is the AUTHORED one and never the residual this
## particular actor would suffer: a resolved number would leak their own gear to the UI.
## `residual_share` is the read that answers "what will it actually cost me".
static func telegraph(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not found.get("ok", false):
		return found
	var fixture: Dictionary = found["fixture"]
	var record := _record(actor, String(found["key"]))
	var box: Rect2i = fixture.get("bounds", Rect2i())
	var position: Vector2i = fixture.get("position", Vector2i.ZERO)
	return _answer(
		true,
		"",
		_merged(
			_about(fixture, room_id),
			{
				"bounds": [box.position.x, box.position.y, box.size.x, box.size.y],
				"position": [position.x, position.y],
				"telegraph_s": float(fixture.get("telegraph_s", 0.0)),
				"damage_share": float(fixture.get("damage_share", 0.0)),
				"duration_s": float(fixture.get("duration_s", 0.0)),
				"mitigation_levers": _lever_names(fixture),
				"armed": bool(record.get("armed", false)),
				"spent": bool(record.get("spent", false)),
				"claimed": bool(record.get("claimed", false)),
				# ADR 0217's two tests, answered per fixture so a screen can render
				# "sealed — needs a furnace key" BEFORE the player spends the walk.
				# `gate` is the ONE shape this fixture uses (ADR 0218), named here
				# rather than left for a reader to infer from two fields that could
				# both be set.
				"gate": _gate_shape(fixture),
				"currency": _pays_lore(fixture) and PAY_LORE or PAY_EQUIPMENT,
				# Visible whether or not the actor is already standing in it: the
				# boundary is what makes leaving in time possible at all.
				"boundary_visible": true,
			}
		)
	)


## The whole active run's fixture state as primitives, one row per AUTHORED fixture
## — including the ones nothing has touched, because a reader asking "what is in this
## room" must be able to see a fixture that has not armed yet. Folded into the facade's
## `summary()` read model rather than published as a thirteenth verb.
static func summary(actor: Actor) -> Dictionary:
	var map_summary := DomainApi.map_summary(actor)
	if map_summary.is_empty():
		return {}
	var rows: Array = []
	for room in DomainApi.rooms(actor):
		var room_id := StringName(room.get("room_id", ""))
		for entry in room.get("fixtures", []):
			var fixture: Dictionary = entry
			var fixture_id := StringName(fixture.get("fixture_id", ""))
			var record := _record(actor, _key(room_id, fixture_id))
			(
				rows
				. append(
					_merged(
						_about(fixture, room_id),
						{
							"armed": bool(record.get("armed", false)),
							"spent": bool(record.get("spent", false)),
							"progress": int(record.get("progress", 0)),
							"wrong": int(record.get("wrong", 0)),
							"complete": bool(record.get("complete", false)),
							"claimed": bool(record.get("claimed", false)),
						}
					)
				)
			)
	return {"domain_id": map_summary.get("domain_id", ""), "fixtures": rows, "count": rows.size()}


## The ledger entry for one fixture, normalised, or an empty record. Read-only: it
## never writes, so a caller asking "is this spent?" cannot itself arm it.
static func state_of(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var key := _key(room_id, fixture_id)
	return {} if actor == null else _record(actor, key)


# ── resolution ───────────────────────────────────────────────────────────────


## Hand the trap's status to the `status` module's own runtime bookkeeping, so it
## actually pays. The ONE place this file crosses that boundary, and it is a FACADE call
## (`modules/status/api.gd`) because the pulse lives in that module's per-actor runtime
## table, and `Actor.add_status` is only `core`'s merge-and-age half of it.
##
## ## Why a trap cannot be applied through `StatusApi.apply`
##
## `apply` rebuilds the effect from the def it resolves, so it would spend the def's own
## `share_per_pulse` and discard the fixture's `damage_share` this file just resolved
## against the actor's mitigation — the number `_fire` reports back. And `apply_cultivation`
## REFUSES a COMBAT-scope def, which is what `fire_immolation` (a trap's own authored
## status, `scope = combat`) is; a trap is forced to CULTIVATION scope here only because
## `StatusApply`'s resistance gate never drew on it, and that is a fact about how the trap
## is AUTHORED rather than about which verb receives it. The scope the def declares wins,
## so the trap keeps spending health and stays clearable by combat exit. A status the status
## module will not resolve is an error rather than an ordinary answer.
static func _settle(actor: Actor, effect: StatusEffect) -> void:
	var answer := StatusApi.resolve(actor, effect)
	if not bool(answer.get("ok", false)):
		var refused := "DomainFixtures: trap status '%s' is on the actor but the status module "
		var will_age := "refused to resolve it (%s); the trap will age out without paying a pulse"
		push_error(
			(refused + will_age) % [String(effect.id), String(answer.get("reason", "unknown"))]
		)


## `{fixture, key}` on success, or an ANSWER dictionary on refusal — never a bare `{}`.
## The refusal is non-empty on purpose: every verb tests it with `get("ok", false)` rather
## than `is_empty()`, so "no active domain" and "this room authors no such fixture" are
## answered by name instead of by a shape the caller must interpret.
static func _resolve(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	if actor == null:
		return _answer(false, ERR_NO_ACTOR, {})
	# `DomainApi.room` is `{}` both outside a run and for a room the map does not
	# hold, which is the honest question: a fixture only exists inside a run.
	var room := DomainApi.room(actor, room_id)
	if room.is_empty():
		return _answer(false, ERR_NO_RUN, {"room_id": String(room_id)})
	# Bounded `for` over the authored array, which is a room's own content and small.
	for entry in room.get("fixtures", []):
		var fixture: Dictionary = entry
		if String(fixture.get("fixture_id", "")) != String(fixture_id):
			continue
		if not KINDS.has(StringName(fixture.get("kind", ""))):
			return _answer(
				false,
				ERR_UNKNOWN_KIND,
				_merged(_about(fixture, room_id), {"asked": String(fixture_id)})
			)
		return {"ok": true, "reason": "", "fixture": fixture, "key": _key(room_id, fixture_id)}
	return _answer(
		false, ERR_UNKNOWN_FIXTURE, {"room_id": String(room_id), "fixture_id": String(fixture_id)}
	)


## Fire the trap: resolve the residual for THIS actor, build the status and hand it
## to `Actor.add_status`, then [method _settle] so it actually pays. It subtracts nothing
## here and never will — the whole cost is what `StatusApi.tick_statuses` pays under the
## authored `duration_s`.
static func _fire(
	actor: Actor, fixture: Dictionary, key: String, room_id: StringName
) -> Dictionary:
	var resolved := residual_share(actor, fixture)
	var share := float(resolved["amount"])
	var duration := maxf(float(fixture.get("duration_s", 0.0)), MIN_DURATION)
	var effect := StatusEffect.new(StringName(fixture.get("status_id", "")), duration)
	effect.kind = StatusEffect.Kind.DOT
	# CULTIVATION scope: a trap is a place, and taxing the player for walking onto
	# authored scenery is not a difficulty knob (`EnvironmentField._hazard`).
	effect.scope = StatusEffect.Scope.CULTIVATION
	# REFRESH: the trap fires once by construction, and a re-application must never
	# raise what a stronger one already landed.
	effect.stacking = StatusEffect.Stacking.REFRESH
	effect.magnitude = minf(share, EnvironmentField.MAX_MAGNITUDE)
	effect.magnitude_cap = EnvironmentField.MAX_MAGNITUDE
	effect.tick_interval = EnvironmentField.hazard_cadence()
	# Copied off the FIXTURE rather than invented: ADR 0075 makes the authored levers
	# the hazard's counterplay, and this is what makes the applied status answer true
	# to `StatusEffect.has_mitigation()` instead of looking like nothing answers it.
	effect.mitigation_tags = _levers(fixture)
	actor.add_status(effect)
	_settle(actor, effect)
	_write(actor, key, {"armed": true, "spent": true})
	return _answer(
		true,
		OK_FIRED,
		_merged(
			_about(fixture, room_id),
			{
				"share": share,
				"authored_share": float(resolved["authored"]),
				"mitigated_by": String(resolved["mitigated_by"]),
				"duration_s": duration,
				"status_id": String(fixture.get("status_id", "")),
				"spent": true,
			}
		)
	)


## A wrong node. Applies the authored status as a CONTROL gate for `duration_s` and
## sends the sequence back to its first node. No pool is read or written, and the
## `progress` the sequence had reached is deliberately NOT a parameter: the reset is to the
## first node from wherever the formation was, so a half-solved formation a player cannot
## finish is never left on the board.
static func _wrong(
	actor: Actor, fixture: Dictionary, key: String, room_id: StringName, node: String
) -> Dictionary:
	var status_id := StringName(fixture.get("wrong_status_id", ""))
	var duration := maxf(float(fixture.get("duration_s", 0.0)), MIN_DURATION)
	var effect := StatusEffect.new(status_id, duration)
	effect.kind = StatusEffect.Kind.CONTROL
	effect.scope = StatusEffect.Scope.CULTIVATION
	effect.stacking = StatusEffect.Stacking.REFRESH
	effect.magnitude = WRONG_GATE
	effect.source = &"domain_fixture"
	actor.add_status(effect)
	var wrong := int(_record(actor, key).get("wrong", 0)) + 1
	_write(actor, key, {"progress": 0, "wrong": wrong})
	return _answer(
		true,
		OK_WRONG_NODE,
		_merged(
			_about(fixture, room_id),
			{
				"node": node,
				"expected": String(_expected(fixture)),
				"status_id": String(status_id),
				"progress": 0,
				"wrong": wrong,
				"complete": false,
			}
		)
	)


## `{}` when the fixture is openable, else the named refusal.
##
## An EMPTY `key_item_id` short-circuits BEFORE the bridge is consulted, so an
## unkeyed hoard is openable by an actor whose items module was never wired at all —
## which is exactly what "openable now" means.
static func _key_gate(actor: Actor, fixture: Dictionary, about: Dictionary) -> Dictionary:
	var key_item_id := String(fixture.get("key_item_id", ""))
	if key_item_id == "":
		return {}
	if _key_reach.is_null():
		return _answer(false, ERR_NO_BRIDGE, _merged(about, {"key_item_id": key_item_id}))
	var reach := float(_key_reach.call(actor, StringName(key_item_id)))
	if reach <= 0.0:
		return _answer(false, ERR_MISSING_KEY, _merged(about, {"key_item_id": key_item_id}))
	return {}


## The realm gate, by ladder INDEX and never by string: `RealmDefaults.ladder()` owns
## the order, so adding a realm is data and a locale change cannot reorder it. A floor
## naming no ladder realm is an AUTHORING error refused loudly: the alternative is a
## treasure no actor can ever open, which reads as "sealed" and is in fact unreachable
## content.
static func _realm_gate(actor: Actor, fixture: Dictionary, about: Dictionary) -> Dictionary:
	var realm := String(fixture.get("requires_realm", ""))
	if realm == "":
		return {}
	var ladder := RealmDefaults.ladder()
	var floor_index := ladder.index_of(StringName(realm))
	if floor_index < 0:
		return _answer(false, ERR_UNKNOWN_FIXTURE, _merged(about, {"requires_realm": realm}))
	var realm_index := ladder.index_of(actor.realm())
	if realm_index < floor_index:
		var low := {"requires_realm": realm, "actor_realm": String(actor.realm())}
		low["realm_index"] = realm_index
		return _answer(false, ERR_REALM_TOO_LOW, _merged(about, low))
	return {}


## Pay this fixture's reward in the currency its PLACE in the run names (ADR 0216),
## ONE unit, realized by the injected granter. `{}` never — it returns an answer
## dictionary, because a delivery that fails must NOT consume the claim.
##
## ## THE SEAM IS `(Actor, StringName, int) -> Dictionary | int`, AND THE INT IS THE SEED
##
## The third argument is the fixture-derived SEED (ADR 0216 §4: the roll belongs to the
## fixture), and the dictionary answer's `instance_id` is the realized object. The
## history, because this seam has been wrong in BOTH directions: it once documented a
## `-> Dictionary` shape NO caller implemented while the body called with a THIRD shape
## (`(actor, item_id, String(fixture_id))`), so every delivery raised a type error and 42
## assertions went red; the fix that shipped made the third argument a `count`. Then
## ADR 0216 landed and the count was always ONE_UNIT while the realization needed a seed,
## and a count nobody varies is a seed nobody passed. So: dictionary in, `{leftover,
## reason, instance_id}`; an INTEGER leftover is still read so an older caller degrades
## to "nothing handed over" rather than erroring; the named `reason` passes through.
static func _grant(actor: Actor, fixture: Dictionary, ledger_key: String) -> Dictionary:
	var item_id := StringName(fixture.get("reward_item_id", ""))
	var count := ONE_UNIT
	# Deterministic across machines and replays: the ledger key names the run, the room
	# and the fixture, so the same relic is minted for the same door every time.
	var seed := hash(ledger_key)
	if item_id == &"":
		return _answer(false, ERR_NOTHING_TO_GRANT, {"item_id": "", "count": 0, "pays": ""})
	# A formation ALSO pays LORE, the thinnest of the five currencies (ADR 0216), IN
	# ADDITION to the authored `reward_item_id` rather than instead of it: a ledger row
	# costs no bag slot, so routing a puzzle AROUND the granter meant the authored reward
	# of every solved formation was silently undelivered while the fixture still reported
	# `claimed` — a second delivery path skipping the one contract ("the SAME granter a
	# treasure uses, because one delivery path in the game is the whole point").
	var lore_fields: Dictionary = {}
	if _pays_lore(fixture):
		var lore := _lore(actor, fixture, ledger_key, item_id)
		if not bool(lore.get("ok", false)):
			return lore
		# Carried into the final answer so a formation's LORE row and its `reward_item_id`
		# travel in ONE answer: `pays` names the currency, `lore_id`/`insight` answer what
		# the formation taught.
		lore_fields = {
			"pays": PAY_LORE, "lore_id": lore.get("lore_id", ""), "insight": lore.get("insight", 0)
		}
	if _granter.is_null():
		return _answer(
			false,
			ERR_NO_BRIDGE,
			{"item_id": String(item_id), "count": count, "pays": PAY_EQUIPMENT}
		)
	var instance_id := ""
	var leftover := count
	var reason := ""
	# Both shapes accepted: the dictionary is the SHIPPED shape (realization reports an
	# `instance_id`), the integer is the older one, and reading the answer's TYPE keeps
	# one call site serving both — a lone `as Dictionary` silently yielded `{}` for the
	# integer case, so every caller read a default leftover of the full count.
	var answer: Variant = _granter.call(actor, item_id, seed)
	if answer is Dictionary:
		var named := answer as Dictionary
		leftover = int(named.get("leftover", count))
		reason = String(named.get("reason", ""))
		instance_id = String(named.get("instance_id", ""))
	else:
		leftover = int(answer)
	if leftover > 0:
		# A refusal whose own reason is EMPTY is the integer seam, so it is named here
		# rather than guessed at: an integer granter can only mean "it did not fit".
		var owed := {
			"item_id": String(item_id), "count": count, "leftover": leftover, "pays": PAY_EQUIPMENT
		}
		return _answer(false, ERR_INVENTORY_FULL if reason == "" else reason, owed)
	var delivered := {
		"item_id": String(item_id),
		"count": count,
		"leftover": 0,
		"pays": PAY_EQUIPMENT,
		"instance_id": instance_id,
	}
	return _answer(true, OK_CLAIMED, _merged(delivered, lore_fields))


## Whether this fixture pays LORE rather than an object, read off the fixture's own
## `kind` and never off a tag: ADR 0073 froze the fixture vocabulary to three kinds and a
## tag set is free text — the defect ADR 0218 is about, where `treasure_boss_sealed` was
## applied by hand and was simply false.
static func _pays_lore(fixture: Dictionary) -> bool:
	return String(fixture.get("kind", "")) == String(KIND_PUZZLE)


## Which of ADR 0218's three gate shapes this fixture carries — the read
## [method telegraph] publishes so a screen renders "sealed — needs a furnace key" BEFORE
## the player spends the walk.
##
## Read off the two AUTHORED fields, never off a tag. ADR 0218's whole finding is that
## `treasure_keyed` was applied by hand to a hoard with an empty `key_item_id` and was
## simply false, so a shape derived from the tags would inherit the exact defect the ADR
## exists to end. `key_item_id` is first because a treasure carries AT MOST ONE gate
## (rule 4) and the key is the one a player can go and get.
static func _gate_shape(fixture: Dictionary) -> String:
	if String(fixture.get("key_item_id", "")) != "":
		return GATE_KEYED
	if String(fixture.get("requires_realm", "")) != "":
		return GATE_REALM
	return GATE_OPEN


## Record the ledger row a solved formation pays. One row, keyed by the SAME ledger key
## the run already persists, and written by the SAME `_write` — so it costs nothing: no
## new module, no new persistence, one more field of a record `attempt` was already
## writing. A formation pays LORE because what it hands over is what the player now KNOWS,
## and a thing you know does not occupy a bag slot; `insight` is the carried axis
## `contracts/stat.gd` already declares (`Stat.INSIGHT_GAIN`), so this is a counter and not
## a new resource — ADR 0216's "deliberately the thinnest". The ledger KEY is the
## parameter rather than re-derived, because a fixture carries no `room_id`.
static func _lore(
	actor: Actor, fixture: Dictionary, ledger_key: String, item_id: StringName
) -> Dictionary:
	var lore_id := StringName("%s_%s" % [LORE_PREFIX, String(fixture.get("fixture_id", ""))])
	var record := _record(actor, ledger_key)
	var earned := int(record.get("insight", 0)) + LORE_INSIGHT
	_write(actor, ledger_key, {"insight": earned, "lore_id": lore_id})
	return _answer(
		true,
		OK_CLAIMED,
		{
			"item_id": String(item_id),
			"count": ONE_UNIT,
			"leftover": 0,
			"pays": PAY_LORE,
			"lore_id": String(lore_id),
			"insight": earned,
		}
	)


static func _lever_for(actor: Actor, fixture: Dictionary) -> String:
	return DomainFixtureLevers.lever_for(actor, fixture)


static func _holds(actor: Actor, lever: StringName, fixture: Dictionary) -> bool:
	return DomainFixtureLevers.holds(actor, lever, fixture)


static func _status_element(status_id: StringName) -> StringName:
	return DomainFixtureLevers.status_element(status_id)


static func _cap_for(lever: String) -> float:
	return DomainFixtureLevers.cap_for(lever)


# ── state ────────────────────────────────────────────────────────────────────


static func _key(room_id: StringName, fixture_id: StringName) -> String:
	return "%s/%s" % [String(room_id), String(fixture_id)]


## The ledger, normalised. Absent reads as an empty record rather than a null, so
## every caller asks "is it spent?" and never "does this key exist?".
static func _ledger(actor: Actor) -> Dictionary:
	var value = actor.get_module_data(DomainApi.MODULE_KEY).get(STATE_KEY, {})
	return value if value is Dictionary else {}


static func _record(actor: Actor, key: String) -> Dictionary:
	var raw = _ledger(actor).get(key, {})
	if not raw is Dictionary:
		return _record_of({})
	return _record_of(raw as Dictionary)


## Read straight back out of a save. Every field goes through `int()` / `float()`
## because JSON has no bool and no int/float distinction, so a `true` arrives as
## `1.0`; comparing that against a bool would silently disagree.
static func _record_of(raw: Dictionary) -> Dictionary:
	return {
		"armed": int(raw.get("armed", 0)) != 0,
		"armed_s": maxf(0.0, float(raw.get("armed_s", 0.0))),
		"spent": int(raw.get("spent", 0)) != 0,
		"progress": maxi(0, int(raw.get("progress", 0))),
		"wrong": maxi(0, int(raw.get("wrong", 0))),
		"complete": int(raw.get("complete", 0)) != 0,
		"claimed": int(raw.get("claimed", 0)) != 0,
		# The two LORE fields (ADR 0216): same ledger, same `_write`, same JSON round
		# trip — normalised through `int()` / `String()` for the same reason as the rest
		# of this row, because a save has no bools and no int/float distinction.
		"insight": maxi(0, int(raw.get("insight", 0))),
		"lore_id": StringName(str(raw.get("lore_id", ""))),
	}


## Merge `patch` into one record and write the ledger back. A merge and not an
## assignment: the trap, the puzzle and the treasure write disjoint fields of one
## shape, and a whole-record write from any of them would drop the others'.
static func _write(actor: Actor, key: String, patch: Dictionary) -> void:
	var state := actor.get_module_data(DomainApi.MODULE_KEY)
	if state.is_empty():
		return
	var ledger := _ledger(actor)
	var record := _record(actor, key)
	for field in patch:
		record[String(field)] = patch[field]
	ledger[key] = record
	state[STATE_KEY] = ledger
	actor.set_module_data(DomainApi.MODULE_KEY, state)


# ── views ────────────────────────────────────────────────────────────────────


## The identifying header every answer carries, so a caller never has to re-derive
## which fixture it is holding. `position` / `bounds` are deliberately absent: they
## are `Vector2i` / `Rect2i` in the authored data and this dictionary reaches a save.
static func _about(fixture: Dictionary, room_id: StringName) -> Dictionary:
	return {
		"room_id": String(room_id),
		"fixture_id": String(fixture.get("fixture_id", "")),
		"kind": String(fixture.get("kind", "")),
		"reward_item_id": String(fixture.get("reward_item_id", "")),
		"key_item_id": String(fixture.get("key_item_id", "")),
		"requires_realm": String(fixture.get("requires_realm", "")),
	}


static func _payout_fields(payout: Dictionary) -> Dictionary:
	return {
		"item_id": String(payout.get("item_id", "")),
		"count": int(payout.get("count", 0)),
		"leftover": int(payout.get("leftover", 0)),
		# WHICH of ADR 0216's five currencies this was, so a panel can render "you gained
		# insight" against "you gained a relic" without re-deriving which fixture it came
		# from. `equipment` is the default because a bare `true` payout that omits it
		# would read as nothing at all.
		"pays": String(payout.get("pays", PAY_EQUIPMENT)),
		# The REALIZED object, when one was minted: the instance id is what a save and a
		# reader both need, and a bare `inventory.add(def, count)` had none.
		"instance_id": String(payout.get("instance_id", "")),
		# The lore currency's own two fields. Empty on an equipment payout.
		"lore_id": String(payout.get("lore_id", "")),
		"insight": int(payout.get("insight", 0)),
	}


static func _amounts(authored: float, amount: float, lever: String) -> Dictionary:
	return {"authored": authored, "amount": amount, "mitigated_by": lever}


## The node the player owes next, or `""` once the formation is complete.
static func _expected(fixture: Dictionary) -> String:
	var sequence: Array = fixture.get("sequence", [])
	return "" if sequence.is_empty() else String(sequence[0])


static func _levers(fixture: Dictionary) -> Array[StringName]:
	return DomainFixtureLevers.published(fixture)


static func _lever_names(fixture: Dictionary) -> Array[String]:
	return DomainFixtureLevers.published_names(fixture)


## `base` with `extra` written over it, leaving `base` untouched.
##
## NOT `base.merge(extra, true)`: Godot's `Dictionary.merge` returns `void` and merges
## IN PLACE, so a chained `a.merge(b).merge(c)` is a parse error on the first call. The
## copy is what keeps a caller's dictionary from being rewritten under it.
static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
