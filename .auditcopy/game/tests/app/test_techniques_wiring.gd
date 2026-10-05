extends TestCase

## The composition root's wiring of the `techniques` module (ADR 0056).
##
## This file used to be `test_consumable_system.gd` and held two unrelated things:
## the retired prototype's consumable slot table, and these three cases about what
## `app/` hands a player actor. The consumable half moved with the feature it
## described — `ConsumableSystem` was a stateful per-actor system in `app/`, which
## ADR 0056 forbids and DEF-0098 recorded as owed, and it now lives behind
## `QuickUseApi` in `modules/quick_use/`, tested in `tests/modules/quick_use/`.
##
## What is left here is only what `app/` is for: `ActorFactory` builds an actor that
## already carries the technique components, so the module is attached by the
## composition root rather than by whoever first asks for a codex. Renamed rather
## than kept, because a file named for a class that no longer exists is a stale name
## that reads as coverage of a class that no longer exists.
##
## ## The prototype assertions that went with it, and why none survived
##
##   - skill slots / equip / unequip / `use_skill` cost+cooldown+descriptor: superseded
##     by `TechniquesApi` learn/equip/unequip, tested in `tests/modules/techniques/`.
##     Cooldowns are deliberately NOT implemented (DEF-0090 — no damage pipeline), so
##     there is nothing here to pin.
##   - combat state toggling, combat timeout, auto-combat: DEF-0098 says delete the
##     duplicate combat state machines in favour of one CombatApi-owned component.
##     `combat/api.gd` does not expose one yet.
##   - `press_key` / `click` routing, input buffering, key tables: the router is gone;
##     combo identity is a technique field, not a key sequence (DEF-0098).
##   - `COMBO_PATTERNS` and its `multiplier: 1.5`: read by nothing but this suite's own
##     existence. Deleted.
##
## Run just this suite with:
##   uv run python -m tools test --suite techniques_wiring


func _wired(id: StringName) -> Actor:
	var actor := ActorFactory.build(id, {Stat.SPIRIT: 20.0})
	ItemsApi.attach(actor)
	TechniquesApi.attach(actor)
	return actor


func test_a_freshly_wired_actor_carries_the_technique_components() -> void:
	# The load-bearing assertion of this file: `app/` attaches the techniques module
	# (ADR 0056 says app/ wires it and the module owns it), and a player actor built by
	# the composition root comes out with a codex, a slot table and an upkeep tracker
	# already on it.
	var actor := _wired(&"techniqued")
	assert_ne(actor.component(TechniquesApi.CODEX_COMPONENT), null, "the codex is attached")
	assert_ne(actor.component(TechniquesApi.SLOTS_COMPONENT), null, "the slot table is attached")
	assert_ne(
		actor.component(TechniquesApi.UPKEEP_COMPONENT), null, "the upkeep tracker is attached"
	)


func test_attach_is_idempotent() -> void:
	# A restored save adopts its own snapshot, so a second attach must not replace the
	# codex with a fresh empty one.
	var actor := _wired(&"twice")
	var first: Variant = actor.component(TechniquesApi.CODEX_COMPONENT)
	TechniquesApi.attach(actor)
	assert_eq(
		actor.component(TechniquesApi.CODEX_COMPONENT).get_instance_id(),
		first.get_instance_id(),
		"a second attach leaves the existing codex in place"
	)


func test_attach_writes_the_technique_state_key() -> void:
	# The module persists its own payload under its own key, so a save carries
	# technique ids and rungs rather than authored definitions.
	var actor := _wired(&"persisted")
	assert_eq(
		actor.get_module_data(TechniquesApi.STATE_KEY).has("version"),
		true,
		"the technique state is written under the module's own key"
	)
