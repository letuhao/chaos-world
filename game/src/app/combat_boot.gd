class_name CombatBoot
extends RefCounted

## The composition root's combat wiring (ADR 0126). Wiring, not rules: `app/` names the
## concrete mechanism and installs the resolver, and the `combat` module owns what a blow
## is worth.
##
## ## Which mechanism, and why it is decided here at all
##
## All three mechanisms SHIP (`qi_damage.gd`, `body_damage.gd`, `mind_damage.gd` — ADR
## 0069, 0070 and 0071 are implemented, not design only) and none of them is chosen by
## anything in `modules/`: `MechanismSlot` stores one per actor and the spine never
## inspects a path. So which mechanism an actor fights with is a COMPOSITION decision and
## `app/` is the only layer allowed to make it — the same reason `ElementsApi.attach` and
## `MindCultivationApi.attach` live here rather than in a module. This file used to bind
## `QiDamage` unconditionally and refuse the other two on an INPUTS argument, which was
## true and has stopped being true: `ActorFactory.with_body_cultivation` and
## `ActorFactory.with_mind_cultivation` now both run in production (BL-0523), so a
## root-built actor CAN carry an `acupoints` set or a `sea_of_consciousness`. It binds
## all three now, gated on the inputs being present — see [method bind_mechanisms] for
## the rule and for why the both-paths case resolves to qi rather than to a coin flip.
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

## The three mechanism names [method bind_mechanisms] chooses between, as NAMED CONSTANTS
## rather than `SomeDamage.name()`: `name()` is an OBJECT lifecycle method that a
## `GDScript` class does not answer, so calling it is a parse error that takes every
## dependant down with it. `_DEFAULT_MECHANISM` is the fallback the other two are chosen
## over, not a constant that says "this is what an actor gets".
const _DEFAULT_MECHANISM := &"QiDamage"
const _BODY_MECHANISM := &"BodyDamage"
const _MIND_MECHANISM := &"MindDamage"
## `true` on both reads rather than the object, so a caller is never handed a module type
## it has to downcast — the same primitives-only rule every other facade answer follows.
const _BOUND := true

## The injected attack callable: `func(attacker: Actor, defender: Actor, seed_value: int)
## -> Variant`. Null means no adapter can land a blow, which [method strike] reports by
## name rather than swallowing.
static var _resolver: Callable = Callable()


## Bind the mechanism `actor`'s own inputs support, and its wound ledger, and report what
## that binding did. `{ok, bound, mechanism, already_bound, wounds, reason}`.
##
## ## The rule, and why it is a rule about INPUTS rather than about paths
##
## `MechanismSlot` holds ONE mechanism per actor because one actor fights one way, and
## re-binding replaces. So this picks:
##
##   1. an actor carrying an `acupoints` component AND enrolled on the body path
##      gets `BodyDamage`;
##   2. an actor carrying a `sea_of_consciousness` component AND enrolled on the mind
##      path gets `MindDamage`;
##   3. anything else — neither path, both paths, or a path whose component is missing —
##      keeps `QiDamage`.
##
## **Each rule needs BOTH halves, and that is the whole point.** `BodyDamage` reads its
## acupoint set through `&"acupoints"` (`BodyLocation.ACUPOINTS_KEY`), which
## `BodyCultivationApi.attach_acupoints` is the only production writer of, and
## `ActorFactory.with_body_cultivation` is the only production call site of that. So the
## component IS the enrolment, read directly off the actor rather than inferred from a
## path flag — and `MindDamage` reads its denominator through
## `&"sea_of_consciousness"` (`CombatTuning.sea_component`), written by exactly one
## production call site, `MindCultivationApi.attach`, which
## `ActorFactory.with_mind_cultivation` owns. Binding a mechanism whose inputs are absent
## is what the previous version of this file refused to do, and it was right: S4 would
## read zeros and every hit would land at the chip floor. The component check is that
## refusal, kept as code.
##
## **Why the path flag is checked as well as the component.** The component is necessary
## and not sufficient — it is state, and a save can restore it onto an actor whose path
## was never enrolled. Requiring both means the two halves cannot disagree, and it costs
## one dictionary read. Note that `ItemWorkbenchApp._build_actor` and
## `CharacterCreationFlow._body` both enrol THREE paths on the player, which lands every
## player actor in case 3: qi is the fallback, and `element_share` is the only mechanism
## whose input the element provider every actor has.
##
## **The BOTH-paths case is deliberate, and qi is the answer.** `MechanismSlot` stores one
## mechanism, so a dual-cultivator must pick, and the pick cannot be data — nothing in the
## authored content says which of two paths a blow belongs to. qi is the only pick that is
## correct for a mixed build rather than arbitrarily wrong for half of it: it always has
## its input (the element provider `ActorFactory.build` mounts for everyone), and qi
## explicitly never raises immunity (BRIEF 2.2), so it cannot dominate a build that has
## spent nothing on `ATTACK_SPIRITUAL`. Any richer rule needs an ADR: "an actor on two
## paths fights by the path it last trained" is a decision, not a derivation, and this file
## reports it rather than inventing it.
##
## ## Idempotent by contract, not by luck
##
## `bind_mechanism` is per-ACTOR and idempotent, so calling this on boot and again after a
## save load is the intended usage. Re-binding after a save load is also how an actor that
## gained a path gets the right mechanism: `ActorFactory` enrols AFTER `ActorFactory.build`
## returns, so the order `ItemWorkbenchApp` uses (`build` -> three enrolments ->
## `CombatBoot.bind_mechanisms`) is the only order in which the components exist by the
## time this reads them. The report says what it did rather than leaving a caller to guess.
static func bind_mechanisms(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false,
			"bound": false,
			"mechanism": "",
			"already_bound": false,
			"wounds": false,
			"reason": "no_actor"
		}
	var already: bool = CombatEngineApi.has_mechanism(actor)
	var chosen := _mechanism_for(actor)
	# The one place that knows the concrete mechanisms. `app/` is the composition root
	# and the only layer allowed to name a concrete type; the module itself never does.
	var mechanism: DamageMechanism = null
	match chosen:
		_BODY_MECHANISM:
			mechanism = BodyDamage.new()
		_MIND_MECHANISM:
			var mind := MindDamage.new()
			# The sea, INJECTED rather than left to the mechanism's own component lookup:
			# binding it once here is what makes `CombatBoot` the composition root for the
			# mind path the way `ElementsApi.attach` is the root for qi. A null sea reads
			# `structural_capacity 0.0` and the erosion is visibly inert, and the guard
			# below is what stops an actor without one getting here at all.
			mind.sea = MindCultivationApi.sea(actor)
			mechanism = mind
		_:
			mechanism = QiDamage.new()
	CombatEngineApi.bind_mechanism(actor, mechanism)
	# The wound ledger, bound HERE rather than lazily at the first wound, because it is
	# the other half of the same wiring and it is the only thing that can restore a save:
	# `attach_wounds` consumes the raw `body_wounds` payload `Actor._restore_versioned`
	# stashed, and `bind_mechanisms` is the call the documented save-load path makes a
	# second time. Binding it at the FIRST hit instead would settle the first wound onto a
	# fresh ledger and then restore the old one over the top on the next load.
	#
	# The tuning is the shipped `.tres` and not a null, for the reason
	# `CombatEngineApi.attach_wounds` documents: a ledger whose every threshold read as
	# `0.0` wounds on the first gash and sits on the necrosis floor immediately. This is
	# idempotent like the mechanism binding above it — an actor that already carries a
	# ledger keeps it, so a re-boot can never erase wounds earned this session.
	var wounds := CombatEngineApi.attach_wounds(actor, CombatEngineApi.tuning())
	var bound: bool = CombatEngineApi.has_mechanism(actor)
	# `bound` is asserted AND reported so one read answers for both: a second read is a
	# second chance for the two to disagree.
	assert(
		bound,
		"CombatBoot.bind_mechanisms: %s did not bind to '%s'" % [String(chosen), String(actor.id)]
	)
	return {
		"ok": bound,
		"bound": _BOUND,
		"mechanism": chosen,
		"already_bound": already,
		"wounds": wounds != null,
		"reason": "",
	}


## The mechanism `actor`'s own components support, or `&""` for the qi fallback. Split out
## as one pure read so the rule above is stated once and the binding above is the only
## place a concrete type is named — which is what keeps this file's rule auditable.
##
## Reads components, not paths, FIRST: a path flag says what was enrolled, a component
## says what the mechanism will actually find, and only the second one can make S4 read
## zeros.
static func _mechanism_for(actor: Actor) -> StringName:
	var has_body := actor.component(&"acupoints") != null and actor.path(PathState.BODY) != null
	var has_mind := (
		actor.component(MindCultivationApi.SEA_COMPONENT) != null
		and actor.path(PathState.MIND) != null
	)
	# Exactly one, never "body wins" and never "mind wins": two paths is the ambiguous
	# case the docblock above resolves to qi on purpose.
	if has_body == has_mind:
		return _DEFAULT_MECHANISM
	return _BODY_MECHANISM if has_body else _MIND_MECHANISM


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
## intended usage on boot AND after a save load — and the save-load case is the one that
## can CHANGE the answer, because a load is where an actor may gain the acupoint set or
## the sea it lacked when it was first bound. `mechanism` is the name actually bound, so a
## caller reads which of the three it got rather than assuming the qi default.
static func install(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false,
			"bound": false,
			"mechanism": "",
			"wounds": false,
			"resolver": false,
			"reason": "no_actor"
		}
	var bound: Dictionary = bind_mechanisms(actor)
	var resolver: Dictionary = set_attack_resolver(Callable(CombatApi, "hit"))
	return {
		"ok": bool(bound["ok"]) and bool(resolver["ok"]),
		"bound": bool(bound["bound"]),
		"mechanism": bound["mechanism"],
		"wounds": bool(bound["wounds"]),
		"resolver": bool(resolver["ok"]),
		"reason": "",
	}
