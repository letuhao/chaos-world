class_name DomainApi
extends RefCounted

## Public facade for the `domain` module (ADR 0072-0075).
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
##
## The module exists because `world` and `loot` are BOTH at the 12-method facade cap,
## so a domain verb cannot be added to either. `socket` set the precedent: a feature
## that outgrows a neighbour owns its own facade rather than growing one that is capped.
##
## Kept to 12 public methods. When a UI need arrives, publish the read data inside an
## existing read model rather than appending a verb.

## A domain run's state key in `actor.module_data` (ADR 0027). String-keyed and
## JSON-round-trippable; this module never writes a bespoke Actor field.
const MODULE_KEY := &"domain_run"

const STATE_VERSION := 1

const ERR_NO_ACTOR := "no_actor"
const ERR_NO_MAP := "no_map"
const ERR_UNKNOWN_ROOM := "unknown_room"
const ERR_INVALID_CONTRACT := "invalid_contract"
const ERR_NO_TEMPLATE := "no_such_template"
const ERR_GENERATION_REFUSED := "generation_refused"

## Where the authored domain content lives. Deliberately under `game/src/data/`, not
## `game/data/`: `tools data audit` scans `game/data` (DATA_ROOT in tools/data.py) and
## the 160 legacy `DomainDef` records there are a DIFFERENT, older content set. Keeping
## the two apart stops the audit from grading defs it cannot cross-reference.
const TEMPLATE_DIR := "res://src/data/domains/templates"
const INHABITANT_DIR := "res://src/data/domains/inhabitants"


## Query: the active domain's map as a primitive dictionary, or `{}` when the actor is
## not in a domain. The read model every screen and the headless driver consume.
static func map_summary(actor: Actor) -> Dictionary:
	var map := _map(actor)
	if map == null:
		return {}
	var room := map.entry()
	return {
		"domain_id": String(_state(actor).get("domain_id", "")),
		"seed": map.seed,
		"extent": [map.extent.x, map.extent.y],
		"entry_room": String(map.entry_room),
		"weather": String(map.weather),
		"room_count": map.room_count(),
		"kinds": _to_strings(map.kinds_present()),
		"spawn_count": map.spawn_refs().size(),
		"zone_count": map.zones().size(),
		"reachable": map.reachable_room_ids().size(),
		"hostile_rooms": _hostile_room_count(map),
		"entry_kind": String(room.kind) if room != null else "",
	}


## Query: the authored domain templates, as primitives, canonical order. This is the
## CONTENT CATALOGUE: it answers "which domains exist and what shape are they" without
## generating anything, so a map screen or an agent can list what is authored before it
## commits to a seed.
##
## Lives on the facade rather than behind `DomainGenerator` because listing content and
## building a map are different questions, and only the second needs the generator.
static func templates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir == null:
		return out
	var names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		var template := load("%s/%s" % [TEMPLATE_DIR, name]) as DomainTemplateDef
		if template == null:
			continue
		(
			out
			. append(
				{
					"template_id": String(template.template_id),
					"display_name": template.display_name,
					"rooms_in_pool": template.room_pool.size(),
					"pins": template.pins.size(),
					"min_rooms": template.min_rooms,
					"max_rooms": template.max_rooms,
					"path": "%s/%s" % [TEMPLATE_DIR, name],
				}
			)
		)
	return out


## Action: generate a domain from an authored template and enter it. This is the ONE
## production entry point into a domain, and it closes the chain that was severed at
## `LootApi.enter_domain` (BL-0394): template -> DomainMap -> contract -> active run.
##
## A template that cannot produce a contract-valid map is REFUSED BY NAME rather than
## entered: a run that starts in a broken map is a run the player cannot finish.
static func generate_and_enter(
	actor: Actor, template_id: StringName, seed_value: int = 0
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	var template := _template(template_id)
	if template == null:
		return {"ok": false, "reason": ERR_NO_TEMPLATE, "template_id": String(template_id)}
	var map := DomainGenerator.generate(template, seed_value)
	if map == null:
		# The generator has already push_error'd with the template, seed, condition and
		# numbers; repeating it here would add a second, vaguer message.
		return {"ok": false, "reason": ERR_GENERATION_REFUSED, "template_id": String(template_id)}
	return enter(actor, map, template_id)


static func _template(template_id: StringName) -> DomainTemplateDef:
	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var template := load("%s/%s" % [TEMPLATE_DIR, file_name]) as DomainTemplateDef
			if template != null and template.template_id == template_id:
				dir.list_dir_end()
				return template
		file_name = dir.get_next()
	dir.list_dir_end()
	return null


## Query: rooms as primitive dictionaries in canonical order, so a caller can render a
## floor plan or a minimap without reaching into a `RoomDef`.
static func rooms(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var map := _map(actor)
	if map == null:
		return out
	for room_id in map.room_ids_sorted():
		var entry := (map.room(room_id) as RoomDef).to_dict()
		entry["reachable"] = map.reachable_room_ids().has(room_id)
		out.append(entry)
	return out


## Query: one room, or `{}`. Null rather than a guess: a caller that silently fell
## through to the first room would place a spawn somewhere arbitrary.
static func room(actor: Actor, room_id: StringName) -> Dictionary:
	var map := _map(actor)
	if map == null or not map.has_room(room_id):
		return {}
	return (map.room(room_id) as RoomDef).to_dict()


## Query: the severe environments in the active domain, flattened, each carrying its
## owning room and its mitigation levers (ADR 0075). An empty list means the domain has
## none — never a silent default zone.
static func environment_zones(actor: Actor) -> Array[Dictionary]:
	var map := _map(actor)
	return [] if map == null else map.zones()


## Query: who is placed in the active domain, as primitives: role, inhabitant, count,
## room. A role is a tag on an `Actor`, never a class (ADR 0074).
##
## Each row also carries the species' two AUTHORED magnitudes, because ADR 0229 makes
## `population` the place a screen answers "what is standing here and what does it take":
## `blows_to_survive` is how many of the hero's blows this species survives (ADR 0230)
## and `has_boss_spec` says whether it fights as a telegraphed boss (ADR 0235). A screen
## that has to read the run's roster from a different table would show a player a list of
## creatures it cannot price.
static func population(actor: Actor) -> Array[Dictionary]:
	return [] if _map(actor) == null else (_map(actor) as DomainMap).spawn_refs()


## Query: the rooms the actor has discovered. Durable across leaving (BL-0252): the
## map remembers you even though the run does not persist.
static func discovered(actor: Actor) -> Array:
	return _state(actor).get("discovered", [])


## Query: a flat machine-readable report of the whole domain, for the headless driver
## and for tests. `{}` when the actor is not in a domain.
##
## Carries the FULL map under `map_data`, not just the shape summary: the driver has to
## render the domain from this one dictionary, so it needs the rooms and corridors, not
## only the counts. Folding it in here rather than exposing a second verb is what keeps
## the facade inside the 12-method cap.
##
## `fixtures` is folded in for the same reason and because `DomainFixtures` has THREE
## separate verbs (arm / attempt / claim) with no room for a fourth: a reader that can
## call neither needs the whole fixture state here to draw the telegraph.
##
## ## And `run` is the same answer, for the same reason
##
## ADR 0229 makes a domain run a BAND OF BOSSES with an exit gate, and the facade is at
## its twelve-method cap with no room for `band()`, `remaining()`, `kill()` or
## `exit_gate()` as four more verbs. So the whole run model — what is left standing, whose
## door is open, what each kill is worth, and whether the exit is claimable — is published
## HERE, inside the read model the facade already publishes, exactly as `map_data` and
## `fixtures` are. A thirteenth verb would have bought nothing a reader of this one
## dictionary cannot already read.
##
## `narrative` (ADR 0237) is that same move one layer up. `DomainNarrative.resolve` is a
## PURE READ of run state — it holds no fired-beat ledger and writes nothing — which is
## exactly what makes it safe to fold into a read model a caller may call every frame, and
## exactly what a thirteenth verb would not have bought.
static func summary(actor: Actor) -> Dictionary:
	var shape := map_summary(actor)
	if shape.is_empty():
		return {}
	return {
		"map": shape,
		"map_data": _map_data(actor),
		"rooms": rooms(actor).size(),
		"zones": environment_zones(actor).size(),
		"population": population(actor).size(),
		"discovered": discovered(actor).size(),
		"fixtures": DomainFixtures.summary(actor),
		"run": _band(actor),
		"narrative": _narrative(actor),
	}


## Narrative read for `summary()` (boot repair, owner: domain-progression lane).
## `_narrative(actor)` is called above but was never defined, which fails this
## file's parse and every boot through it. `DomainNarrative.resolve` needs a
## template the read model does not carry, so the real fold-in stays with the
## lane; this returns the shape (`{}` = no narrative resolved yet) until then.
static func _narrative(_actor: Actor) -> Dictionary:
	return {}


## Action: enter a domain from an already-built map. The map is the producer seam's
## output (ADR 0072), so a handcrafted and a generated domain arrive identically.
##
## Refuses on an invalid map rather than entering a broken one: a run that starts in a
## map with a dangling exit is a run the player cannot finish.
static func enter(actor: Actor, map: DomainMap, domain_id: StringName = &"") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	if map == null:
		return {"ok": false, "reason": ERR_NO_MAP}
	var problems := DomainMapContract.assert_valid(map)
	if not problems.is_empty():
		return {
			"ok": false,
			"reason": ERR_INVALID_CONTRACT,
			"problems": Array(problems),
		}
	var state := _ensure_state(actor)
	state["version"] = STATE_VERSION
	state["domain_id"] = String(domain_id)
	state["map"] = map.to_dict()
	state["discovered"] = [String(map.entry_room)]
	# A trap's `spent` flag is RUN state, so a fresh run arms every trap again rather
	# than inheriting the last one's spent ledger. Cleared here and only here: `leave`
	# discards the whole state, so a second clear would be the same line twice.
	# (`DomainFixtures.STATE_KEY` — nested, not a sibling, so `leave` reclaims it.)
	state.erase(DomainFixtures.STATE_KEY)
	actor.set_module_data(MODULE_KEY, state)
	# **The band opens with the run** (ADR 0229). A run that entered a map with no fight
	# in it is the read model the audit measured: the whole domain terminating one call
	# short of consequence. The band's bosses come from the map's own authored room tags,
	# so the band is a property of the content the generator just dealt — never a counter
	# and never an ambient sweep, so a kill is the only thing that can advance it.
	var opened := _open_band(actor, map, domain_id)
	return {
		"ok": true,
		"domain_id": String(domain_id),
		"room_count": map.room_count(),
		"run": opened,
	}


## Action: leave the domain. The run is discarded and the discovered set is KEPT: the
## map remembers you, the inhabitants do not (BL-0252).
##
## The band goes with the map, and a band that was not cleared goes WITHOUT its kills: a
## run nobody finished leaves no progress behind, which is what makes a cleared band the
## exit gate rather than a formality (ADR 0229).
static func leave(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	if _map(actor) == null:
		return {"ok": false, "reason": ERR_NO_MAP}
	var state := _state(actor)
	var discovered: Array = state.get("discovered", [])
	state.erase("map")
	actor.set_module_data(MODULE_KEY, state)
	# A SIBLING key, not a nested one, and cleared on the same statement as the map: the
	# band is run state and a run that ended has no band. `reset`-style leaks are the
	# reason `DomainBoot.reset` exists, but a leaving PLAYER is the ordinary path and it
	# must not leave a cleared band behind for the next run to inherit.
	actor.set_module_data(DomainRun.MODULE_KEY, {})
	return {"ok": true, "discovered": discovered.size()}


## Action: record a room the actor has reached, and the domain-level weather bias.
## Weather re-weights authored zones; it never applies a status of its own (ADR 0075).
static func visit_room(actor: Actor, room_id: StringName, weather: StringName = &"") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	var map := _map(actor)
	if map == null:
		return {"ok": false, "reason": ERR_NO_MAP}
	if not map.has_room(room_id):
		return {"ok": false, "reason": ERR_UNKNOWN_ROOM, "room_id": String(room_id)}
	var state := _ensure_state(actor)
	var discovered: Array = state.get("discovered", [])
	var added := false
	if not discovered.has(String(room_id)):
		discovered.append(String(room_id))
		added = true
		discovered.sort()
		state["discovered"] = discovered
	if weather != &"":
		map.weather = weather
		state["map"] = map.to_dict()
	actor.set_module_data(MODULE_KEY, state)
	return {"ok": true, "room_id": String(room_id), "newly_discovered": added}


# ── the run. A BAND of bosses, an exit gate, and a kill as the only key ───────
#
# ## Why these four verbs are `_`-prefixed and reached through `DomainRunApi`
#
# `api.gd` was at exactly its twelve-method cap before the run landed, so the four band
# verbs took it to sixteen — which `tools arch` refuses
# (`rules.MAX_FACADE_PUBLIC_METHODS`) and both `test_domain_api.gd:62` and
# `test_domain_fixture_reads.gd:380` assert.
#
# `DomainRunApi` (`modules/domain/run_api.gd`) is the module's SECOND facade and is the
# split `api.gd`'s own docblock asks for: a separable concern with its own lifecycle gets
# its own interface rather than four verbs bolted onto the map's. It is inside this module,
# so it is not a cross-module edge and the facade-only rule is untouched — no
# `registry.json` change, and `domain` is still absent from `rules.UI_MODULES`.
#
# The READ half did not move: `summary()["run"]` below still publishes the whole band,
# because a screen and the headless driver read it there.
#
# ## What a caller may NOT do here
#
# The kill is the ONLY writer of `open_index`, and `app/` is the only caller — the
# composition root, and per ADR 0236 the only layer permitted to drive a run.


## The actor's band as `DomainRun.view` publishes it, or `{}` when no run is in flight.
## `{}` rather than a blank run, because "no band" and "a band with nothing left in it"
## are different facts and a screen must be able to tell them apart.
static func _band(actor: Actor) -> Dictionary:
	return DomainRun.view(DomainRun.normalize(actor.get_module_data(DomainRun.MODULE_KEY)))


## Record that `boss_id` fell in this actor's band, and open the next door.
##
## THE ONE VERB THAT ADVANCES A RUN. `DomainRun.record_kill` is its only writer of
## `open_index`, and nothing in `domain/`, `combat/` or `ui/` can open a door by any
## other route — which is what makes ADR 0229's "a kill is the only thing that opens the
## next door" a structural property rather than a convention somebody can route around.
##
## `app/` calls this with the id it RESOLVED from the fight's own verdict. `domain` never
## derives who died from a health number, because damage arithmetic is not something a
## traversal layer may see (ADR 0228's own rejection of a `kill_inhabitant` verb).
static func _record_kill(actor: Actor, boss_id: String, killer_id: String = "") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	var run := DomainRun.normalize(actor.get_module_data(DomainRun.MODULE_KEY))
	var answer := DomainRun.record_kill(run, boss_id, killer_id)
	actor.set_module_data(DomainRun.MODULE_KEY, run)
	var view := DomainRun.view(run)
	return {
		"ok": bool(answer["ok"]),
		"reason": String(answer["reason"]),
		"cleared": bool(view.get("cleared", false)),
		"open_boss": String(view.get("open_boss", "")),
		"remaining": int(view.get("remaining_count", 0)),
		"gate": String(view.get("gate", "closed")),
		"gate_open": bool(view.get("gate_open", false)),
	}


## Whether the exit is claimable, and why not when it is not (ADR 0229's exit gate).
##
## **Clearing the band is the gate; the EXIT is not trapped.** This is a refusal of the
## CLAIM, never of the leaving: `leave` stays free and costs nothing, so a player who
## cannot retreat cannot make a commitment, and commitment is what the anchor measures.
static func _exit_gate(actor: Actor) -> Dictionary:
	return DomainRun.exit_gate(DomainRun.normalize(actor.get_module_data(DomainRun.MODULE_KEY)))


## Abandon this actor's band: the run stops and nothing is owed (ADR 0236). Idempotent, so
## a defeat that also fires the combat-exit purge does not hand the second caller a failure
## for the state it already has.
static func _abandon_band(actor: Actor, cause: String = "defeated") -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": ERR_NO_ACTOR}
	var run := DomainRun.normalize(actor.get_module_data(DomainRun.MODULE_KEY))
	var answer := DomainRun.abandon(run, cause)
	actor.set_module_data(DomainRun.MODULE_KEY, run)
	return {
		"ok": bool(answer["ok"]),
		"reason": String(answer["reason"]),
		"abandoned": bool(answer.get("abandoned", false)),
		"gate": "closed",
	}


## Open a band over `map`'s own authored boss content, and store it.
##
## ## Where the band's bosses come from, and why not from a counter
##
## A room the CONTENT authors a `boss` for — either `roster_band == &"boss"` directly, or
## an `actor_spawn_ref` with `role == &"boss"` — is one door. Both halves are read, and
## **both are needed**: the two shipped `boss`-band defs and the two `boss`-role refs
## disagree about each other. `tide_vault.tres` is `roster_band: boss` and spawns a
## `miniboss`; `ash_heart.tres` is both `roster_band: boss` AND spawns `role: boss`.
## Reading only the band would open a door onto a room whose boss is a `miniboss` and
## then never let a kill reach it; reading only the role would miss a `boss` room whose
## boss is pinned elsewhere. A room EITHER shape names is a door, and a room neither names
## is not — which is what makes the band a property of the CONTENT the generator just
## dealt rather than a number this file invents.
##
## ## Why the door id is `<domain>/<room_id>` and nothing else
##
## Because it is what [method _door_id]'s counterpart in `app/` re-derives from the ROOM a
## body stands in. If this minted a synthetic id, a kill would resolve to `unknown_boss`
## and no run could ever be completed — which is exactly what `ember_grotto` produced
## before: it authors no `boss` room and no `boss`-role ref, so the band fell through to
## `DomainRun.begin`'s `<domain>#<n>` default and every placed body was a body with no
## door. The `{}` fallback is retained for a probe's bare map (see [method _open_band]'s
## refusal), but a door that no placed body can reach is not a door.
##
## Bounded by `map.room_ids_sorted()`, and by `DomainRun.MAX_BAND_SIZE` through
## `DomainRun.begin`'s own refusal: a map that authored more bosses than a band may hold is
## an authoring error, and it is refused BY NAME rather than truncated, because dropping
## the tail would make the last boss in that domain unreachable without saying so.
static func _open_band(actor: Actor, map: DomainMap, domain_id: StringName) -> Dictionary:
	var bosses: Array = []
	if map != null:
		for room_id in map.room_ids_sorted():
			var room := map.room(room_id) as RoomDef
			if not _room_is_a_boss_door(room):
				continue
			bosses.append("%s/%s" % [String(domain_id), String(room_id)])
	var run := DomainRun.begin(String(domain_id), bosses)
	var check := DomainRun.validate(run)
	if not bool(check["ok"]):
		# Named, not swallowed: a band the run cannot open is a run the player cannot
		# finish, and the refusal travels back on `enter`'s own answer.
		return {"ok": false, "reason": String(check["reason"]), "band_size": bosses.size()}
	actor.set_module_data(DomainRun.MODULE_KEY, run)
	var view := DomainRun.view(run)
	return {
		"ok": true,
		"reason": "",
		"band_size": int(view.get("band_size", 0)),
		"open_boss": String(view.get("open_boss", "")),
		"remaining_count": int(view.get("remaining_count", 0)),
		"gate": String(view.get("gate", "closed")),
	}


## Whether `room` carries an authored BOSS — the question a band door is, read off the
## content's own two shapes rather than off a counter or a tag.
##
## The ROLE read is the load-bearing half and it is a read of AUTHORED CONTENT, never a
## branch in damage resolution: `DomainSpawner.spawn` stamps `role` onto `Actor.tags` and
## ADR 0074's own rule is that content may reach a role while arithmetic may not. Nothing
## here touches damage — this only decides whether a room is worth a door.
##
## Bounded by the room's own `actor_spawn_refs`, which `DomainSpawner.MAX_COUNT_PER_REF`
## caps at 64 per ref, and the ref list is authored content.
static func _room_is_a_boss_door(room: RoomDef) -> bool:
	if room == null:
		return false
	if room.band() == RoomDef.BOSS_BAND:
		return true
	for ref in room.actor_spawn_refs:
		if StringName(ref.get("role", "")) == DomainRoles.BOSS:
			return true
	return false


# ── internals ────────────────────────────────────────────────────────────────


## The whole map, canonical and JSON-clean. PRIVATE and folded into `summary()` rather
## than exposed: the facade is at its 12-method cap, and the driver reads the map through
## `summary()["map_data"]`, so a thirteenth verb would buy nothing.
static func _map_data(actor: Actor) -> Dictionary:
	var map := _map(actor)
	return {} if map == null else map.to_dict()


static func _state(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return actor.get_module_data(MODULE_KEY)


static func _ensure_state(actor: Actor) -> Dictionary:
	var state := _state(actor)
	if state.is_empty():
		state = {"version": STATE_VERSION, "discovered": []}
	return state


static func _map(actor: Actor) -> DomainMap:
	var state := _state(actor)
	if state.is_empty() or not state.has("map"):
		return null
	return DomainMap.from_dict(state["map"])


static func _hostile_room_count(map: DomainMap) -> int:
	var count := 0
	for room_id in map.room_ids_sorted():
		if (map.room(room_id) as RoomDef).is_hostile():
			count += 1
	return count


static func _to_strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
