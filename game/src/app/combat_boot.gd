class_name CombatBoot
extends RefCounted

## The composition root's combat wiring (ADR 0126). Wiring, not rules: `app/` names the
## concrete mechanism and installs the resolver, and the `combat` module owns what a blow
## is worth.
##
## ## Why this file exists
##
## Two bindings had no production caller, and both of them made a live path dead rather
## than merely unwired:
##
##   - `CombatEngineApi.bind_mechanism` had ZERO callers in `src/` AND in `tests/` — every
##     suite binds through `MechanismSlot.bind` directly. But `CombatSpine.resolve_hit`
##     reads `MechanismSlot.of(attacker)` (`spine.gd:109`), which ASSERTS when nothing is
##     bound. So `item_workbench_app._resolve_technique_hit` — a real production caller —
##     would assert the moment a technique fired on any actor this root had not bound.
##     Binding here retires that assert as a side effect rather than as a separate change.
##   - `PlayerAdapter.attack()` was a stub whose body ended in a comment promising that
##     combat resolution would be wired by this module's facade. It is now wired, by the
##     same injection pattern `NpcApi.set_minter` already uses.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. A `tick`/`_process` method plus a state table is the stateful-`app/`
## shape `tools/arch/rules.py` rejects (`APP_STATE_MARKERS`), and a combat boot that ran a
## clock would be a second time wire next to the one `StatusLoop` already owns. Every
## method here is a caller-initiated binding.
##
## ## Why the resolver is a `static var` and not an argument
##
## `PlayerAdapter.attack` is an LLM-drivable entry point with a `(Node2D)` signature, so
## the target it found is the only argument it has; the thing that turns that target into
## a blow is a fact about how THIS process was wired. That is exactly what
## `TechniqueCasting._installed_resolver` and `NpcApi._minter` already are, so this is the
## same shape and not a new one. It is static for the same reason it is private-by-
## convention: `attack` needs to read it and nothing else should.

## The mechanism [method bind_mechanisms] binds. A named constant rather than
## `QiDamage.name()`: `name()` is an OBJECT lifecycle method that a `GDScript` class does
## not answer, so calling it is a parse error that takes every dependant down with it.
const _MECHANISM := &"QiDamage"
## `true` on both reads rather than the object, so a caller is never handed a module type
## it has to downcast — the same primitives-only rule every other facade answer follows.
const _BOUND := true

## The injected attack callable: `func(attacker: Actor, defender: Actor, seed_value: int)
## -> Variant`. Null means no adapter can land a blow, which [method strike] reports by
## name rather than swallowing.
static var _resolver: Callable = Callable()


## Bind `QiDamage` to `actor` as its damage mechanism, and report what that binding did.
##
## ## Why `QiDamage` and not a caller-chosen mechanism
##
## `MechanismSlot` holds ONE mechanism per actor because one actor fights one way, and
## re-binding replaces. `QiDamage` is the mechanism the root already builds every actor
## for — the element provider is mounted by `ActorFactory.build` and `ElementsApi.
## apply_realm_modifiers` refreshes its realm half in `_build_actor` — so qi is the one
## mechanism whose inputs are actually present on a root-built actor. `BodyDamage` and
## `MindDamage` are deliberately NOT bound here: ADR 0070/0071 stay design only, and a
## bound body mechanism whose acupoints nothing attached would make S4 read zeros.
##
## ## Idempotent by contract, not by luck
##
## `bind_mechanism` is per-ACTOR and idempotent, so calling this on boot and again after a
## save load is the intended usage. The report says so rather than leaving a caller to
## guess: `{ok, bound, mechanism, already_bound}`.
static func bind_mechanisms(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false,
			"bound": false,
			"mechanism": "",
			"already_bound": false,
			"reason": "no_actor"
		}
	var already: bool = CombatEngineApi.has_mechanism(actor)
	# The one place that knows the concrete mechanism. `app/` is the composition root
	# and the only layer allowed to name a concrete type; the module itself never does.
	CombatEngineApi.bind_mechanism(actor, QiDamage.new())
	var bound: bool = CombatEngineApi.has_mechanism(actor)
	# `bound` is asserted AND reported so one read answers for both: a second read is a
	# second chance for the two to disagree.
	assert(bound, "CombatBoot.bind_mechanisms: QiDamage did not bind to '%s'" % String(actor.id))
	return {
		"ok": bound,
		"bound": _BOUND,
		"mechanism": _MECHANISM,
		"already_bound": already,
		"reason": "",
	}


## Install the callable `PlayerAdapter.attack` lands its blow through, and report the
## install. A `CombatApi.hit` Callable is the intended value; passing an empty Callable
## clears the binding, so an uninstall is deterministic rather than only an overwrite.
static func set_attack_resolver(resolver: Callable) -> Dictionary:
	_resolver = resolver
	return {"ok": _resolver.is_valid(), "reason": "" if _resolver.is_valid() else "no_resolver"}


## Whether a resolver is installed, so a caller can say "no target" and "no spine" as two
## different messages rather than one empty descriptor.
static func has_attack_resolver() -> bool:
	return _resolver.is_null() or _resolver.is_valid()


## One blow through the installed resolver. `{ok, reason, result}`: the refusal is named
## and the resolver's own dictionary is passed through UNCHANGED, because the resolver
## answers for a module (`combat`) and this file only injects it.
static func strike(attacker: Actor, defender: Actor, seed_value: int = 0) -> Dictionary:
	if not has_attack_resolver():
		return {"ok": false, "reason": "no_resolver", "result": {}}
	# Explicitly typed, not `:=`: a `Callable.call` returns a `Variant`, and inferring
	# from one is a warning-as-error in this repo.
	var called: Variant = _resolver.call(attacker, defender, seed_value)
	var answer: Dictionary = called if called is Dictionary else {}
	return {"ok": true, "reason": "", "result": answer}


## Everything a booted combat stack needs for one actor, in the order that order matters:
## the mechanism first (so `CombatSpine.resolve_hit` cannot assert on it), then the
## resolver (so `PlayerAdapter.attack` has something to call). Idempotent, so it is the
## intended usage on boot AND after a save load.
static func install(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false, "bound": false, "mechanism": "", "resolver": false, "reason": "no_actor"
		}
	var bound: Dictionary = bind_mechanisms(actor)
	var resolver: Dictionary = set_attack_resolver(Callable(CombatApi, "hit"))
	return {
		"ok": bool(bound["ok"]) and bool(resolver["ok"]),
		"bound": bool(bound["bound"]),
		"mechanism": bound["mechanism"],
		"resolver": bool(resolver["ok"]),
		"reason": "",
	}
