class_name DomainBoot
extends RefCounted

## The composition root's domain wiring (ADR 0072-0075). Wiring, not rules: `app/`
## injects the constructor; the `domain` module owns what a map, a room and an inhabitant
## mean.
##
## ## Why this file exists
##
## The audit measured it: **13 of 13 domain source files had zero production call sites.**
## `DomainSpawner.spawn` needed a constructor to mint an `Actor` and nothing installed one,
## so it could only ever return null — a feature nobody can start is decoration, which is
## the same failure ADR 0089 measured for statuses and ADR 0074 for npcs.
##
## This is the domain twin of `NpcBoot`, and it exists for exactly the same reason. It is
## deliberately wiring-only: no rules, no state of its own, nothing that ticks.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. Severe environments resolve through `EnvironmentField`, which is
## driven from the same `StatusLoop` tick every other status uses (ADR 0089); a second
## `_process` would be the stateful-`app/` shape `tools/arch/rules.py` rejects.

## The item property a fixture's key is measured by. Spelled once so the granter seam
## below and the loot module's own entry gate cannot drift onto different properties.
const KEY_REACH := &"key_reach"


## Install the inhabitant constructor AND the fixtures' two contacts with the items
## module. Idempotent, so calling it on boot and again after a load is the intended
## usage rather than a mistake.
##
## ## Why the fixture seam belongs in `install` and not beside its callers
##
## `DomainFixtures` gates a treasure behind a key and pays a puzzle's reward through
## an injected granter, and BOTH contact points default to refusing
## (`domain_fixtures.gd:118`). So a domain whose fixtures are wired by nobody answers
## `no_inventory_bridge` to every treasure and every formation — a treasure that reads
## as sealed and is in fact unreachable content, which is the exact failure
## `_realm_gate`'s own docblock calls out. `install` is the one place that already
## resolves the concrete constructor `domain/` may not name, so the items side belongs
## here beside it; both seams are then installed by the SAME call a boot makes, and a
## screen that wants to generate a run cannot get a half-wired one.
##
## `items` is not a declared `domain` dependency (`registry.json` gives it `core` +
## `contracts` only), which is the reason these are `Callable`s and not direct calls.
static func install() -> void:
	# The one place that knows the concrete constructor. Handing the module the static
	# function itself, rather than a lambda that forwards to it, is what keeps `domain/`
	# free of any reference to `ActorFactory` (ADR 0002) — and it is also the only form the
	# engine boots: a typed lambda whose body calls another script's static function killed
	# the process with an access violation on the shell's first frame, with nothing logged.
	# `spawn_inhabitant` takes the minter's two arguments positionally.
	DomainSpawner.set_minter(ActorFactory.spawn_inhabitant)
	DomainFixtures.set_minter(
		Callable(DomainBoot, "key_reach_of"), Callable(DomainBoot, "grant_item")
	)


## The `key_reach` a carried `item_id` is worth, through the items module's own
## property reader — so a fixture's key is measured by exactly the rule a loot
## encounter's entry gate uses (`loot/api.gd:_key_reach`), and `key_reach` keeps ONE
## meaning in the game. 0.0 when nothing carried answers, which is the honest
## "this actor opens nothing".
static func key_reach_of(player: Actor, item_id: StringName) -> float:
	var inventory := ItemsApi.inventory(player)
	if inventory == null:
		return 0.0
	var best := 0.0
	for batch in inventory.stacks():
		var def := batch.def_ref
		if def != null:
			best = maxf(best, float(def.property_total(inventory.sample(batch.def_id), KEY_REACH)))
	for instance in inventory.instances():
		var def := instance.def_ref
		if def != null:
			best = maxf(best, float(def.property_total(instance, KEY_REACH)))
	return best


## Hand `count` of `item_id` to the actor, answering the LEFTOVER that did not fit —
## the all-or-nothing convention `LootRewards.deliver` uses, so a full bag leaves the
## claim untouched rather than consuming it over a delivery that did not happen.
##
## `Crafting.resolve` is `items` internals that only `app/` may name, and `ItemsApi` is
## at its twelve-method cap so no def-resolution verb could be added to it. This adapter
## is the whole reason the seam is legal where it is.
static func grant_item(player: Actor, item_id: StringName, count: int) -> int:
	var def := Crafting.resolve(item_id)
	if def == null:
		# Nothing handed over, so the whole count is leftover. Reported rather than
		# swallowed: a reward for an undefined item is a content defect.
		return maxi(0, count)
	var inventory := ItemsApi.inventory(player)
	if inventory == null:
		return maxi(0, count)
	return maxi(0, inventory.add(def, count))


## The whole domain read model for one screen or the headless driver (BL-0220): which
## domains are authored, what is in the active one, and who is standing there.
##
## Deliberately does NOT call `install` on a read path beyond the constructor injection,
## because installing is idempotent and a read must never mint anything.
static func read_model(player: Actor) -> Dictionary:
	return {
		"has_actor": player != null,
		"templates": DomainApi.templates(),
		"active": DomainApi.summary(player),
	}


## Generate and enter an authored domain in one call, then report what the player is
## standing in. This is the production entry point that closes the chain the audit found
## severed: a template is loaded, a map is generated, the contract is enforced, and the
## run becomes the actor's active domain.
##
## A template that cannot produce a contract-valid map is refused BY NAME. A run that
## begins in a broken map is a run the player cannot finish, and the generator has already
## reported exactly why.
static func enter_domain(player: Actor, template_id: StringName, seed_value: int = 0) -> Dictionary:
	install()
	var entered := DomainApi.generate_and_enter(player, template_id, seed_value)
	if not entered.get("ok", false):
		return entered
	return {
		"ok": true,
		"domain_id": entered.get("domain_id", ""),
		"room_count": entered.get("room_count", 0),
		"map": DomainApi.map_summary(player),
		"population": DomainApi.population(player),
		"zones": DomainApi.environment_zones(player),
	}


## Leave the domain. The run is discarded; the discovered set is KEPT, because the map
## remembers where you have been even though the inhabitants do not (BL-0252).
static func leave_domain(player: Actor) -> Dictionary:
	return DomainApi.leave(player)


## Record that the player walked into `room_id`. Thin on purpose: the facade owns the
## discovery ledger and the weather bias, and this exists only so a screen asks one
## verb of `app/` instead of naming `DomainApi`.
static func visit_room(player: Actor, room_id: StringName, weather: StringName = &"") -> Dictionary:
	return DomainApi.visit_room(player, room_id, weather)


## The room graph the map screen's minimap draws: the laid-out rects, the corridor
## polylines, the POI markers derived from authored room tags, the severe zones with
## their mitigation levers, and the tier each discovered room promises (ADR 0073).
##
## `{}` outside a run — the repo's does-not-exist vocabulary, and a minimap of nothing
## must not read like a minimap of a room with no markers.
##
## ## Why this is a single read and not five
##
## `DomainMinimap.render` needs a `DomainMap`, which is a module type `ui/` may not
## name, and the facade caps at twelve verbs with no room for a thirteenth (api.gd
## says so). So the five reads a floor plan needs travel through here, and they travel
## TOGETHER because `DomainMinimap.render` is the one call that already produces all of
## them: asking it once and handing the payload over means this screen and the headless
## driver read the SAME dictionary, which is the contract `DomainMinimap`'s own docblock
## is written around.
static func minimap(player: Actor) -> Dictionary:
	var state := _active_map(player)
	if state == null:
		return {}
	return DomainMinimap.render(player, state)


## The active domain's rooms as primitives, canonical order, each carrying the tags its
## POI markers are derived from and the authored fixtures it holds — the room LIST, as
## distinct from the room GRAPH [method minimap] draws. Also `{}` outside a run.
static func rooms(player: Actor) -> Array[Dictionary]:
	if _active_map(player) == null:
		return [] as Array[Dictionary]
	return DomainApi.rooms(player)


## The seams the UI program gets, as plain callables.
##
## ## Why this exists rather than a direct `DomainApi` call
##
## `ui/` is a pure consumer (AGENTS.md, `tools/arch/rules.py`): it may reach a module
## only through that module's facade AND only if the module is declared in
## `rules.UI_MODULES`. `domain` is NOT, and `app/` is a private unit no screen may
## reference at all — so a screen calling `DomainBoot.enter_domain` directly is an
## arch violation on two counts, not a style preference. This is therefore the same
## shape `LootBridge` and `WorldPulseBridge` already established (ADR 0143): the
## composition root hands over verbs as `Callable`s and every module type stays on this
## side of the boundary. A screen bound to nothing reads empty rather than crashing.
##
## One bridge per screen instance and no state of its own: a field on the screen that
## the shell sets once is the whole contract, and `bind_bridge` is idempotent so the
## shell may call it after every navigation without stacking handlers.
static func bridge() -> DomainBridge:
	var seam := DomainBridge.new()
	seam.list_templates = Callable(DomainBoot, "_templates")
	seam.read_active = Callable(DomainBoot, "read_model")
	seam.enter = Callable(DomainBoot, "enter_domain")
	seam.leave = Callable(DomainBoot, "leave_domain")
	seam.visit = Callable(DomainBoot, "visit_room")
	seam.minimap = Callable(DomainBoot, "minimap")
	seam.rooms = Callable(DomainBoot, "rooms")
	seam.arm_fixture = Callable(DomainBoot, "arm_fixture")
	seam.attempt_fixture = Callable(DomainBoot, "attempt_fixture")
	seam.claim_fixture = Callable(DomainBoot, "claim_fixture")
	return seam


## The authored template catalogue, as primitives. A one-line forwarder so the bridge
## above binds a bare static function — the same "no typed lambda" rule `install`
## documents — rather than a closure.
static func _templates() -> Array[Dictionary]:
	return DomainApi.templates()


## Start a trap's telegraph, or fire it when the authored window has already elapsed.
##
## `delta` is the caller's, never a wall-clock read, because the module keeps no clock
## of its own (ADR 0089). A screen drives it with an explicit tick; a headless test
## drives it with the number it means.
static func arm_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName, delta: float = 0.0
) -> Dictionary:
	return DomainFixtures.arm(player, room_id, fixture_id, delta)


## Strike one node of a formation puzzle.
static func attempt_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName, node_id: StringName
) -> Dictionary:
	return DomainFixtures.attempt(player, room_id, fixture_id, node_id)


## Open a treasure. Refused by name at every gate, in the order a player meets them.
static func claim_fixture(player: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.claim(player, room_id, fixture_id)


## The active run's map, or null outside one. Private, so a caller can never hold a
## `DomainMap` past the run that produced it.
static func _active_map(player: Actor) -> DomainMap:
	if player == null:
		return null
	var state := player.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])
