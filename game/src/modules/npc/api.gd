class_name NpcApi
extends RefCounted

## Public facade for the `npc` module (ADR 0077). Other modules may reference ONLY this
## file (`api.gd`).
##
## **An npc is an `Actor`, not a class** (ADR 0074). Nothing here returns an `NpcActor`,
## because there is no such type: the constructor is injected by `app/` as a `Callable`,
## and every role — mob, miniboss, boss, npc, rival cultivator — comes out of it as the
## same `Actor` the player is.
##
## **Tracked or not is the one question this module answers.** A `major` or `story` npc
## keeps a roster entry, remembers their stage, and survives leaving the room. A `minor`
## or `transient` npc has no roster entry at all and leaves nothing behind.
##
## **The roster is not a second save file.** It lives in the player actor's `module_data`
## and round-trips through the ordinary `Actor.to_dict`, so nothing here adds a bespoke
## persistence path (ADR 0027, ADR 0074).

## The `actor.module_data` key the roster persists under.
const MODULE_KEY := NpcState.MODULE_KEY
## The `actor.components` slot holding the live roster between saves.
const STATE_COMPONENT := &"npc_state"

## Bounded population for one room visit. A marker list longer than this is served up to
## the cap; the cap is a named constant so a busy settlement is a bounded number, never a
## loop that has to decide when to stop.
const MAX_ROOM_POPULATION := 8

## Roles an author may tag on. A role is a `StringName` on `Actor.tags`, read by content
## and never branched on in damage resolution (ADR 0074).
const ROLE_MOB := &"mob"
const ROLE_MINIBOSS := &"miniboss"
const ROLE_BOSS := &"boss"
const ROLE_NPC := &"npc"
const ROLE_RIVAL := &"rival_cultivator"

## The `social` facade, preloaded. Reached for ONE verb — `forget` — and the dependency is
## declared: `npc` lists `social` in `tools/arch/registry.json`.
const SOCIAL_FACADE := preload("res://src/modules/social/api.gd")

static var _events: NpcEvents = null

## The player actor the roster hangs off, or null when `attach` has never run. Private
## because a consumer is handed its own actor; `attach` is where the roster is bound.
static var _current_player: Actor = null

## The injected actor constructor. Set by `set_minter`; never a concrete actor type, so
## `npc/` cannot name one.
static var _minter: Callable = Callable()


## The event contract, for a consumer to subscribe to. On the facade and not behind a
## projection because a subscriber in another module has to be able to reach it. Returns the
## contract's ONE shared instance rather than a facade-owned one, so `social/` — which may
## not depend on `npc/` — publishes `bond_changed` on the same bus a subscriber here hears.
static func events() -> NpcEvents:
	if _events == null:
		_events = NpcEvents.shared()
	return _events


## Drop the player's bond with a retired npc, so a dead minor does not haunt the ledger
## forever. `SocialApi.forget` is the verb that promises it and until this call site it had
## no production caller at all — the promise was in a docstring and nowhere else.
##
## **Automatic, and deliberately so.** Retirement is TERMINAL: `spawn` refuses a retired id
## and `despawn` refuses to promote them back to KNOWN. A ledger that outlived the individual
## is therefore a permanent, unsatisfiable record — a grudge against someone the player can
## never meet again, still gating `bond_at_least` content that nothing can now open. The one
## counter-case is a bond with an INSTITUTION partner, and `advance_stage` is only ever
## called with a def id, so a sect row is never named here; a dissolved institution has its
## own removal path.
##
## Underscore-prefixed, so it does not count against the facade's twelve-method cap. It
## returns nothing because forgetting a bond that was never there is not a failure the
## caller can act on.
static func _forget_bond(player: Actor, npc_id: StringName) -> void:
	if player == null or npc_id == &"":
		return
	SOCIAL_FACADE.forget(player, npc_id)


## Restore the roster from the player actor's `module_data` and clear the live registry.
## Call at boot and after a load. Idempotent, and the only place that remembers which
## actor the roster hangs off — every mutating verb resolves the player through here.
static func attach(player: Actor) -> void:
	if player == null:
		return
	_current_player = player
	var roster := _roster(player)
	NpcRegistry.instance().release_all()
	for npc_id in roster.npc_ids():
		var entry := roster.entry(npc_id)
		if entry != null:
			events().npc_restored.emit(String(npc_id), entry.tier, entry.stage_id, entry.tracked())


## The player actor the roster hangs off, or null when `attach` has never run. Private
## because a consumer is handed its own actor; `attach` is where the roster is bound.
static func _player() -> Actor:
	return _current_player


## Fold the live roster into `module_data` so `Actor.to_dict` alone is a complete save.
##
## Called from every mutating verb rather than only from `state()`: a caller that spawns an
## npc and then serialises the player should not have to know that a second verb exists to
## flush the ledger. Persisting on change is what keeps the live component and the save
## payload from being able to disagree.
static func _persist(roster: NpcState, player: Actor) -> void:
	if roster == null or player == null:
		return
	roster.mark_changed()
	player.set_module_data(MODULE_KEY, roster.to_dict())


## The roster ledger for `player`, restored from `module_data` on first read and cached
## as a component thereafter.
##
## **The cache is load-bearing, not an optimisation.** Rebuilding from `module_data` on
## every call would hand each verb a fresh object, so `ensure_entry` would write an entry
## into a temporary that the next verb never sees — a tracked npc would be minted and then
## forgotten, and `state()` would report an empty roster. The ledger is therefore the same
## live-object-until-save shape `SocialState` uses.
static func _roster(player: Actor) -> NpcState:
	if player == null:
		return null
	var existing := player.component(STATE_COMPONENT) as NpcState
	if existing != null:
		return existing
	var restored := NpcState.new()
	if player.module_data.has(StringName(MODULE_KEY)):
		restored = NpcState.from_dict(player.module_data[StringName(MODULE_KEY)])
	player.set_component(STATE_COMPONENT, restored)
	return restored


## Inject the constructor. `app/` passes `ActorFactory.spawn_npc`, so this module never
## names a concrete actor type and a null injection fails loudly at `spawn` instead of
## dereferencing nothing (dependency inversion, ADR 0002).
static func set_minter(minter: Callable) -> void:
	_minter = minter


## Mint an npc. For a tracked def this creates the roster entry, applies the starting
## stage and marks the individual present; for an untracked def it mints the actor and
## returns it with no trace. Returns null when there is no constructor, the catalog does
## not ship the id, or a retired npc is asked to appear again.
static func spawn(
	npc_id: StringName, role: StringName = ROLE_NPC, location_id: StringName = &""
) -> Actor:
	if _minter.is_null():
		push_error("NpcApi.spawn: no minter installed; call NpcApi.set_minter first")
		return null
	var def := NpcCatalog.instance().definition(npc_id)
	if def == null:
		push_error("NpcApi.spawn: catalog ships no npc '%s'" % String(npc_id))
		return null
	var player := _player()
	var entry: NpcRosterEntry = null
	if def.tracked() and player != null:
		var state := _roster(player)
		var existing := state.entry(npc_id)
		if existing != null and existing.presence == NpcPresence.RETIRED:
			push_error("NpcApi.spawn: npc '%s' is retired and must not spawn" % String(npc_id))
			return null
		entry = state.ensure_entry(npc_id, npc_id)
		if entry == null:
			push_error("NpcApi.spawn: roster is full at %d entries" % NpcState.MAX_ROSTER)
			return null
		if existing == null:
			entry.tier = def.normalized_tier()
			entry.stage_id = def.starting_stage_id()
			events().npc_tracked.emit(String(npc_id), entry.tier)
	var actor: Actor = _minter.call(def, role)
	if actor == null:
		return null
	actor.tags.append(role)
	NpcStageProjection.apply(
		actor, def.stage(entry.stage_id if entry != null else def.starting_stage_id())
	)
	# Every spawned npc becomes live, tracked or not. A transient one is exactly the case
	# that most needs to be findable: `presence_here` is how a room answers "who is here",
	# and a settlement of unremembered drifters is invisible if only the roster is listed.
	#
	# The instance key AND the location go down together: they are minted from the same
	# call, so a live body with no recorded place is a body a filtered read cannot find
	# (BL-0715). The registry holds the place for the untracked, which has no roster entry
	# to remember it in; the entry below holds it for the tracked, across a save.
	NpcRegistry.instance().set_present(
		NpcRegistry.instance().next_instance_key(npc_id), actor, location_id
	)
	if entry == null:
		events().npc_transient.emit(String(npc_id))
	else:
		entry.presence = NpcPresence.PRESENT
		entry.location_id = location_id
		# The payload is only kept while the individual is off-stage; a live actor is its
		# own truth, and holding both would let a save carry two copies that disagree.
		entry.payload = {}
		_persist(_roster(player), player)
	return actor


## The tracked npc's actor, restored from the roster payload or minted fresh. This is the
## whole off-stage mechanism: an individual the player has met but who is not in the room
## costs one dictionary, not a live actor.
static func resident(npc_id: StringName) -> Actor:
	var live := _live_of(npc_id)
	if live != null:
		return live
	var player := _player()
	if player == null:
		return null
	var entry := _roster(player).entry(npc_id)
	if entry == null:
		return null
	var def := NpcCatalog.instance().definition(entry.def_id)
	if def == null:
		return null
	var actor: Actor
	if not entry.payload.is_empty():
		actor = Actor.from_dict(entry.payload)
	else:
		actor = spawn(npc_id)
		return actor
	NpcStageProjection.apply(actor, def.stage(entry.stage_id))
	return actor


## The live actor for the tracked individual `npc_id`, found by scanning the instance keys.
##
## The registry is keyed by instance while the roster is keyed by the stable id, so a
## tracked npc's live actor is found by prefix. Bounded by `MAX_PRESENCE_READ` live
## entries and returns null rather than looping when a room is larger than that bound —
## a tracked individual is always the first live entry for its def, so the scan stops at
## the first match.
static func _live_of(npc_id: StringName) -> Actor:
	var registry := NpcRegistry.instance()
	for key in registry.present_ids():
		if _is_instance_of(key, npc_id):
			return registry.present(key)
	return null


## The def id behind either a stable id or a live instance key (`drifter#3` -> `drifter`).
static func _def_id_of(key: StringName) -> StringName:
	var text := String(key)
	var hash_at := text.rfind("#")
	if hash_at >= 0:
		return StringName(text.substr(0, hash_at))
	return key


## Whether an instance key names a spawn of `def_id`. The key is `def_id#n`.
static func _is_instance_of(key: StringName, def_id: StringName) -> bool:
	var text := String(key)
	return text == String(def_id) or text.begins_with("%s#" % String(def_id))


## Release an npc from this room. A tracked individual writes its actor payload back to
## the roster first, so they carry their state into the next visit; an untracked one leaves
## nothing at all.
static func despawn(npc_id: StringName) -> bool:
	var player := _player()
	var released := _live_of(npc_id)
	if released != null:
		# Drop the instance, not the roster row: the row is the memory and it outlives
		# the actor. Releasing by stable id would need the registry to look it up too.
		var registry := NpcRegistry.instance()
		for key in registry.present_ids():
			if _is_instance_of(key, npc_id):
				released = registry.release(key)
				break
	if player != null:
		var roster := _roster(player)
		var entry := roster.entry(npc_id)
		if entry != null:
			if released != null:
				entry.payload = released.to_dict()
			# A retired npc stays retired: retirement is terminal, so releasing them from
			# a room must not quietly promote them back to someone the player can meet
			# again. Only a live individual falls back to KNOWN.
			if entry.presence != NpcPresence.RETIRED:
				entry.presence = NpcPresence.KNOWN
				events().presence_changed.emit(String(npc_id), NpcPresence.KNOWN)
			_persist(roster, player)
			return true
	return released != null


## Move a tracked npc to a later authored stage. Monotone and idempotent: a call naming
## the stage they are already at succeeds and changes nothing, and a call naming an
## earlier one is refused rather than rewinding a save. Returns `{ok, reason}`.
static func advance_stage(
	npc_id: StringName, stage_id: StringName, source: String = &""
) -> Dictionary:
	var player := _player()
	if player == null:
		return {"ok": false, "reason": "no_player"}
	var state := _roster(player)
	var entry := state.entry(npc_id)
	if entry == null:
		return {"ok": false, "reason": "unknown_npc"}
	var def := NpcCatalog.instance().definition(entry.def_id)
	if def == null:
		return {"ok": false, "reason": "unknown_def"}
	var target := def.stage(stage_id)
	if target == null:
		return {"ok": false, "reason": "unknown_stage"}
	var current_index := def.stage_index_of(entry.stage_id)
	if target.index < current_index:
		return {"ok": false, "reason": "stage_regression"}
	if target.index == current_index:
		return {"ok": true, "reason": ""}
	var previous := entry.stage_id
	entry.stage_id = stage_id
	entry.set_stage_index(target.index)
	if target.terminal:
		entry.presence = NpcPresence.RETIRED
	var live := _live_of(npc_id)
	if live != null:
		NpcStageProjection.apply(live, target)
		entry.payload = {}
	_persist(state, player)
	events().stage_advanced.emit(String(npc_id), stage_id, String(source))
	if target.terminal:
		events().presence_changed.emit(String(npc_id), NpcPresence.RETIRED)
		_forget_bond(player, npc_id)
	return {"ok": true, "reason": ""}


## Record a computed-progression hit against the npc's current stage, and advance them if
## that stage's `advance_after` is now met. One check per call: a ladder walk is the
## caller's business, so there is no loop here that could fail to terminate.
static func tally(npc_id: StringName, verb: StringName, source: String = &"") -> Dictionary:
	var player := _player()
	if player == null:
		return {"ok": false, "reason": "no_player"}
	var state := _roster(player)
	var entry := state.entry(npc_id)
	if entry == null:
		return {"ok": false, "reason": "unknown_npc"}
	if not entry.bump_tally(verb):
		return {"ok": false, "reason": "tally_full"}
	var def := NpcCatalog.instance().definition(entry.def_id)
	var current := def.stage(entry.stage_id) if def != null else null
	# The verb matters as much as the count. A stage that names `advance_verb` counts ONLY
	# that verb, so an unrelated tally cannot walk a story npc to its last rung; a stage
	# that names none keeps the older "any verb" reading.
	if (
		current != null
		and current.advance_after > 0
		and (current.advance_verb == &"" or current.advance_verb == verb)
	):
		if entry.tally_of(verb) >= current.advance_after:
			var next_id := def.next_stage_id(entry.stage_id)
			if next_id != &"":
				advance_stage(npc_id, next_id, source)
	_persist(state, player)
	return {"ok": true, "reason": ""}


## Mint a room's worth of UNTRACKED population. Bounded by `MAX_ROOM_POPULATION` and never
## by a loop over an open-ended list. Each one leaves no roster entry, so a settlement can
## be busy without a save remembering a single face.
##
## `replace_first` releases whoever is already present before minting. Defaulting to
## true is the safe direction: a room load that forgets this leaves yesterday's cast
## standing in today's room, while a caller that genuinely wants to add passes false.
##
## ## `location_id` is threaded to every spawn, and it is not optional bookkeeping
##
## It was added because `NpcBoot.populate_room` already took a place and dropped it on
## the floor, so every row it minted recorded `location_id: ""` and the `presence_here`
## read on the NEXT LINE filtered all of them out — the boot answered `spawned: 4,
## npcs: []` for a settlement with four people in it (BL-0715). A filter this sharp is
## only safe because the write carries the place; that invariant is why this is a
## parameter on the one verb a room load reaches for rather than something `app/`
## re-derives per id. `NpcApi.spawn` already took a location for exactly this reason.
static func populate(
	def_ids: Array[StringName],
	role: StringName = ROLE_NPC,
	replace_first: bool = true,
	location_id: StringName = &""
) -> Array[Actor]:
	if replace_first:
		_clear_room()
	var out: Array[Actor] = []
	var limit := mini(def_ids.size(), MAX_ROOM_POPULATION)
	for index in range(limit):
		var actor := spawn(def_ids[index], role, location_id)
		if actor != null:
			out.append(actor)
	return out


## Release every npc currently present in this room. Returns how many left. Private
## because `populate` is the entry point a room load should reach for; a caller that
## needs to empty a room without refilling it is a room unload, not a new verb.
static func _clear_room() -> int:
	return NpcRegistry.instance().release_all()


## The read model for one npc: tier, stage, presence and identity as primitives.
## Accepts either a stable `npc_id` or a live instance key (`drifter#3`), so
## `presence_here` can pass registry keys straight through.
##
## `summary` is the OFF-STAGE read too, so the place it publishes is the one the live body
## was minted for and the roster's remembered "where you last met them" only when there is
## no live body to ask (BL-0715). `NpcReadModel.summary` says why the two are not the
## same fact.
static func summary(npc_id: StringName) -> Dictionary:
	var player := _player()
	var def_id := _def_id_of(npc_id)
	var live := NpcRegistry.instance().present(npc_id)
	var instance_key := npc_id
	if live == null:
		live = _live_of(def_id)
		instance_key = _live_key_of(def_id)
	var roster_entry: NpcRosterEntry = null
	if player != null:
		roster_entry = _roster(player).entry(def_id)
	var def := NpcCatalog.instance().definition(def_id)
	return NpcReadModel.summary(
		def_id,
		roster_entry,
		def,
		live != null,
		_presence_of(roster_entry, live),
		NpcRegistry.instance().location_of(instance_key)
	)


## The instance key `def_id`'s live body is filed under, or the stable id when none is
## live. `location_of` is a lookup and not a filter, so a miss answers empty rather than
## refusing — which is why the fallback is harmless. Bounded by `MAX_PRESENCE_READ` live
## entries, the same scan `_live_of` already pays, and it stops at the first match.
static func _live_key_of(def_id: StringName) -> StringName:
	var registry := NpcRegistry.instance()
	for key in registry.present_ids():
		if _is_instance_of(key, def_id):
			return key
	return def_id


## Who is here right now, tracked and untracked in one read. Capped by
## `NpcReadModel.MAX_PRESENCE_READ` and reports `truncated` when it hit the cap, so a
## settlement that would silently lose an npc says so instead.
static func presence_here(location_id: StringName = &"") -> Dictionary:
	var keys := NpcRegistry.instance().present_ids()
	var summaries: Array = []
	for key in keys:
		summaries.append(summary(key))
	return NpcReadModel.presence(location_id, keys, summaries)


## What a panel should read for presence. Retirement outranks being live: an elder who
## finished their stage is `retired` even while their actor is still standing in the room,
## because a save taken in that frame must not resurrect them.
static func _presence_of(entry: NpcRosterEntry, live: Actor) -> StringName:
	if entry == null:
		return NpcPresence.PRESENT if live != null else NpcPresence.UNKNOWN
	if entry.presence == NpcPresence.RETIRED:
		return NpcPresence.RETIRED
	return NpcPresence.PRESENT if live != null else entry.presence


## The roster exactly as it persists, after folding live state back into `module_data`.
## Carries `tracked_ids` as well as the entries, so a "who do I know" screen is one call
## and not a thirteenth verb.
static func state(player: Actor) -> Dictionary:
	if player == null:
		return NpcState.empty()
	var ledger := _roster(player)
	var payload := ledger.to_dict()
	var tracked: Array = []
	for npc_id in ledger.tracked_ids():
		tracked.append(String(npc_id))
	payload["tracked_ids"] = tracked
	player.set_module_data(MODULE_KEY, ledger.to_dict())
	return payload
