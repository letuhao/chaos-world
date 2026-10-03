class_name DomainFixtures
extends RefCounted

## What an AUTHORED FIXTURE does when a player walks onto it (ADR 0073, ADR 0075).
##
## `RoomDef.fixtures` was authored on seven rooms and read by nobody. Four code paths
## copy and serialise the array faithfully — `RoomDef.to_dict` (`room_def.gd:117`),
## `RoomDef.from_dict`, the generator's deep copy, the JSON round trip in
## `test_domain_content.gd:661` — and not one line of the game looked a fixture id up
## at runtime. A telegraphed trap did nothing, a formation puzzle had no node to
## strike, and a hoard had no gate. This file is the missing reader.
##
## ## Three kinds, three verbs, ONE ledger
##
## - `trap` — [method arm] starts the telegraph; arming again once the authored
##   `telegraph_s` has elapsed fires it ONCE and marks it `spent`. It never fires
##   twice in a run, and it never subtracts health: the whole cost is the
##   `StatusEffect` [method _fire] builds, the same shape `EnvironmentField._hazard`
##   builds, so a trap obeys the same duration, stacking and cleanse rules as every
##   other status (ADR 0075).
## - `puzzle` — [method attempt] names one node. Correct advances; wrong applies the
##   authored `wrong_status_id` as a CONTROL status and resets the sequence to its
##   first node. It NEVER costs health, because a puzzle that kills you is a second
##   fight wearing a costume.
## - `treasure` — [method claim] is refused by name unless the actor holds the
##   authored key and stands at or above the authored realm floor.
##
## ## The ledger is part of the RUN, not a slot beside it
##
## One dictionary at `DomainApi.MODULE_KEY` / [constant STATE_KEY], keyed
## `"<room_id>/<fixture_id>"`, String-keyed and primitive-valued (ADR 0027). The
## authored `position` / `bounds` are `Vector2i` / `Rect2i` and are therefore read
## off the FIXTURE every time and never copied in here — a `Vector2` in this
## dictionary would silently break every save. Statuses are session-only
## (ADR 0089), so a trap's potency is re-resolved on arrival rather than stored.
##
## ## What this module deliberately does NOT do
##
## `domain` declares `core` + `contracts` only (`tools/arch/registry.json:60`), so
## this file names no sibling module's class — the same constraint
## `EnvironmentField` wrote a whole docblock about and `DomainSpawner` solved with
## [method set_minter]. Reading a key reach and handing over an item both need the
## items module, so both arrive through ONE injected pair of `Callable`s installed by
## the composition root. Nothing here re-implements a bag, a key rule or the game's
## item resolver: the callables answer "does this actor hold this key, and how far does
## it reach" and "hand over N of this item", and every answer about reward delivery —
## including what a full bag does with it — stays in the module that already owns it.

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
## [method EnvironmentField.hazard_cadence], not a literal: two authored numbers and
## a third is a place for them to disagree (`environment_field.gd:203`).
##
## ## Why `SUBSTRATE_GRADED_BODY` and not a private substrate
##
## A trap hurts IMMEDIATELY and lands once, which is exactly what that substrate is
## described as being ("graded acute damage that conditioning can be trained into",
## `environment_field.gd:97`). Naming it is what makes the lever resolution below
## agree with the environment's by construction: `LEVER_SUBSTRATES` and `LEVER_CAPS`
## are read directly, so a `gear` ward that blunts a zone blunts a trap by the same
## number. A trap's own path is never consulted, because the graded substrate is the
## one mechanism that is deliberately the same for all three paths.
const SUBSTRATE := EnvironmentField.SUBSTRATE_GRADED_BODY

## A wrong puzzle node costs the ATTEMPT, not the body: a fully interrupted strike,
## for `duration_s`. CONTROL and not DOT, because a DOT is a damage-over-time channel
## and ADR 0075 forbids a second one outside `StatusEffect` semantics.
const WRONG_GATE := 1.0

## The floor on every authored duration. A fixture that authors `duration_s: 0.0`
## would otherwise hand out a permanent status, which is not something a content
## author gets by accident — the same floor `EnvironmentField.MIN_DURATION` uses.
const MIN_DURATION := 0.5

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
const ERR_UNKNOWN_NODE := "unknown_node"
const ERR_MISSING_KEY := "missing_key"
const ERR_REALM_TOO_LOW := "realm_below_the_floor"
const ERR_NO_BRIDGE := "no_inventory_bridge"
const ERR_INVENTORY_FULL := "inventory_full"
const ERR_NO_STATUS := "authors_no_status_id"
const ERR_NO_SHARE := "authors_no_damage_share"
const ERR_NOTHING_TO_GRANT := "authors_nothing_to_grant"

## The two injected contacts with the items module, mirroring `DomainSpawner._minter`
## (`domain_spawner.gd:48`). Declared `static var` and below the consts because
## `gdlintrc`'s `class-definitions-order` puts `staticvars` under `consts`.
static var _key_reach: Callable = Callable()
static var _granter: Callable = Callable()


## Install the two contacts with the items module. Idempotent; a null pair restores
## the refusing default.
##
## `keys` is `Callable(actor, item_id) -> float`, answering the `key_reach` a carried
## `item_id` is worth (0.0 when it is not carried). `granter` is
## `Callable(actor, item_id, count) -> int`, answering the LEFTOVER count — the same
## all-or-nothing convention `LootRewards.deliver` uses, so a full bag leaves the
## claim untouched rather than consuming it over a delivery that did not happen.
##
## Bare static functions, not typed lambdas: `app/domain_boot.gd:31-33` records a
## process-killing access violation from a typed lambda forwarding to another
## script's static function, and `DomainSpawner.set_minter` is handed
## `ActorFactory.spawn_inhabitant` itself for the same reason.
static func set_minter(keys: Callable, granter: Callable) -> void:
	_key_reach = keys
	_granter = granter


## Advance a trap by `delta` seconds and arm, telegraph or fire it. The ONLY trap
## entry point, because "is it armed yet" is a question about time and this module
## keeps no clock of its own.
##
## The first call ALWAYS arms, whatever `delta` says: a caller that crossed the
## telegraph window in one long frame still owes the player the warning, and a trap
## that fires on the frame it spawns is the untelegraphed hazard ADR 0075 refuses.
## `delta` is a parameter rather than a wall-clock read so a replay arms and fires
## exactly as it was driven, matching `StatusRegistry.tick`.
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


## Strike one node of a puzzle.
##
## A correct node advances; the last one completes the formation and grants
## `reward_item_id` x `reward_count` through the same granter a treasure uses, so
## there is one delivery path in the game and not one per fixture kind. A wrong node
## applies the authored `wrong_status_id` and resets progress to the first node —
## reset, not merely frozen, so a player who cannot find the order is never stuck
## against a formation they half-solved and cannot resume.
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
	var payout := _grant(actor, fixture)
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
	var payout := _grant(actor, fixture)
	if not payout.get("ok", false):
		return payout
	_write(actor, key, {"claimed": true})
	return _answer(true, OK_CLAIMED, _merged(about, _payout_fields(payout)))


## What this actor would carry from this fixture, WITHOUT touching them: the same
## measure-before-and-after `EnvironmentField.residual_amount` exists for, so a screen
## can show the authored number and the actor's real one side by side.
static func residual_share(actor: Actor, fixture: Dictionary) -> Dictionary:
	var lever := _lever_for(actor, fixture)
	var share := maxf(0.0, float(fixture.get("damage_share", 0.0)))
	var cap := _cap_for(lever)
	if cap <= 0.0:
		# Published but structurally inert on this substrate, so it was never credited
		# and subtracting from the number anyway would report a mitigation that did not
		# happen (`environment_field.gd:_amount`).
		return _amounts(share, share, "")
	return _amounts(share, share * (1.0 - cap), lever)


## The boundary a scene draws BEFORE anything lands, as primitives, for one fixture.
## Primitives only, so it crosses into a Node without this module knowing one exists —
## the same contract `EnvironmentField.telegraph` offers a zone.
##
## The `damage_share` telegraphed is the AUTHORED one and never the residual this
## particular actor would suffer: a resolved number would leak their own gear to the
## UI (`environment_field.gd:449`). `residual_share` is the read that answers "what
## will it actually cost me".
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


## `{fixture, key}` on success, or an ANSWER dictionary on refusal — never a bare `{}`.
##
## The refusal is non-empty on purpose: every verb tests it with `get("ok", false)`
## rather than `is_empty()`, so "no active domain" and "this room authors no such
## fixture" are answered by name instead of by a shape the caller must interpret.
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
## to `Actor.add_status`. It subtracts nothing here and never will — the whole cost is
## what `Actor.tick_statuses` pays under the authored `duration_s`.
static func _fire(
	actor: Actor, fixture: Dictionary, key: String, room_id: StringName
) -> Dictionary:
	var resolved := residual_share(actor, fixture)
	var share := float(resolved["amount"])
	var duration := maxf(float(fixture.get("duration_s", 0.0)), MIN_DURATION)
	var effect := StatusEffect.new(StringName(fixture.get("status_id", "")), duration)
	effect.kind = StatusEffect.Kind.DOT
	# CULTIVATION scope: a trap is a place, and taxing the player for walking onto
	# authored scenery is not a difficulty knob (`environment_field.gd:_hazard`).
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
## sends the sequence back to its first node. No pool is read or written.
##
## The `progress` the sequence had reached is deliberately NOT a parameter: the reset is
## to the first node from wherever the formation was, so a half-solved formation a player
## cannot finish is never left on the board.
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


## The key gate. `{}` when the fixture is openable, else the named refusal.
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


## The realm gate, by ladder INDEX and never by string: `RealmDefaults.ladder()`
## owns the order, so adding a realm is data and a locale change cannot reorder it
## (the same rule `test_domain_content.gd:614` holds the authored content to).
##
## A floor naming no ladder realm is an AUTHORING error and is refused loudly: the
## alternative is a treasure no actor can ever open, which reads as "sealed" and is
## in fact unreachable content.
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
		return _answer(
			false,
			ERR_REALM_TOO_LOW,
			_merged(
				about,
				{
					"requires_realm": realm,
					"actor_realm": String(actor.realm()),
					"realm_index": realm_index
				}
			)
		)
	return {}


## Hand `reward_item_id` x `reward_count` to the granter. `{}` never — it returns an
## answer dictionary, because a delivery that fails must NOT consume the claim.
static func _grant(actor: Actor, fixture: Dictionary) -> Dictionary:
	var item_id := StringName(fixture.get("reward_item_id", ""))
	var count := int(fixture.get("reward_count", 0))
	if item_id == &"" or count <= 0:
		return _answer(false, ERR_NOTHING_TO_GRANT, {"item_id": String(item_id), "count": count})
	if _granter.is_null():
		return _answer(false, ERR_NO_BRIDGE, {"item_id": String(item_id), "count": count})
	var leftover := int(_granter.call(actor, item_id, count))
	if leftover > 0:
		return _answer(
			false,
			ERR_INVENTORY_FULL,
			{"item_id": String(item_id), "count": count, "leftover": leftover}
		)
	return _answer(true, OK_CLAIMED, {"item_id": String(item_id), "count": count, "leftover": 0})


## Which lever actually reduces this fixture for this actor, or `""`.
##
## Read in identity order over `EnvironmentZoneDef.LEVERS` — the closed four, not a
## list restated here — so "what pushes back against a hazard" has exactly one
## vocabulary in the game. A lever has to be PUBLISHED by the fixture, has to MOVE the
## trap's substrate per `EnvironmentField.LEVER_SUBSTRATES`, and has to be one this
## actor actually carries.
static func _lever_for(actor: Actor, fixture: Dictionary) -> String:
	var levers := _levers(fixture)
	for lever in EnvironmentZoneDef.LEVERS:
		if not levers.has(lever):
			continue
		# `LEVER_SUBSTRATES` is the same table `EnvironmentField.mitigates` consults,
		# read directly because `_moves` is private: a lever that does not act on the
		# graded substrate is structurally inert here, and crediting it anyway is the
		# invention `residual_amount`'s docblock refuses.
		if not (EnvironmentField.LEVER_SUBSTRATES.get(lever, []) as Array).has(SUBSTRATE):
			continue
		if _holds(actor, lever):
			return String(lever)
	return ""


## Whether this actor carries `lever`. The three non-affinity levers are read from
## the marker keys `EnvironmentField` itself publishes and reads
## (`environment_field.gd:250-254`), so this file authors no fourth tag slot.
static func _holds(actor: Actor, lever: StringName) -> bool:
	match lever:
		EnvironmentField.LEVER_AFFINITY:
			# INERT on every shipped fixture, and honestly so. A trap authors no
			# element — its `tags` are `ember` / `stone` / `ruined`, none of which any
			# `HOSTILE_ELEMENTS` row names — so no spirit root can answer it. This branch
			# exists so a fixture authored with an element tag lights up on its own; it
			# is not credited a mitigation it did not earn.
			return false
		EnvironmentField.LEVER_GEAR:
			return not _tags(actor, EnvironmentField.GEAR_TAGS_KEY).is_empty()
		EnvironmentField.LEVER_TECHNIQUE:
			return not _tags(actor, EnvironmentField.TECHNIQUE_TAGS_KEY).is_empty()
		EnvironmentField.LEVER_PILL:
			return not _tags(actor, EnvironmentField.PILL_TAGS_KEY).is_empty()
	return false


## The share `lever` removes at full strength, straight out of `EnvironmentField`'s
## table. 0.0 for a lever with no entry: an unrecognised lever must never quietly
## reduce a hazard.
static func _cap_for(lever: String) -> float:
	for key in EnvironmentField.LEVER_CAPS:
		if String(key) == lever:
			return float(EnvironmentField.LEVER_CAPS[key])
	return 0.0


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
	}


static func _amounts(authored: float, amount: float, lever: String) -> Dictionary:
	return {"authored": authored, "amount": amount, "mitigated_by": lever}


## The node the player owes next, or `""` once the formation is complete.
static func _expected(fixture: Dictionary) -> String:
	var sequence: Array = fixture.get("sequence", [])
	return "" if sequence.is_empty() else String(sequence[0])


static func _tags(actor: Actor, key: StringName) -> Array:
	var out: Array = []
	if actor == null:
		return out
	# Bounded `for` over the published tag list, which is authored content and small.
	for entry in actor.get_module_data(key).get("tags", []):
		out.append(StringName(str(entry)))
	return out


static func _levers(fixture: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var authored: Array = fixture.get("mitigation_tags", [])
	for lever in authored:
		if EnvironmentZoneDef.LEVERS.has(StringName(lever)):
			out.append(StringName(lever))
	return out


static func _lever_names(fixture: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for lever in _levers(fixture):
		out.append(String(lever))
	return out


## `base` with `extra` written over it, leaving `base` untouched.
##
## NOT `base.merge(extra, true)`: Godot's `Dictionary.merge` returns `void` and merges
## IN PLACE, so a chained `a.merge(b).merge(c)` is a parse error on the first call. Every
## answer here is built from an immutable `_about` header, so the copy is what keeps a
## caller's dictionary from being rewritten under it.
static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
