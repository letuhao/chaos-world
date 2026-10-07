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
## the rule and for why the both-paths case resolves to qi there.
##
## ## And a second answer to the same question, because the first is not the one asked
##
## The binding is per ACTOR, and the shipped player is enrolled on THREE paths, so the
## binding is qi for every player actor and body and mind can never fire at all — not
## rarely, never. That is not a defect in the binding rule; it is the rule answering a
## different question. **Which mechanism is BOUND when nothing says otherwise** is an
## actor question, and qi is the right answer to it. **Which mechanism is THIS HIT
## worth** is a question about the ATTACKING TECHNIQUE, and `TechniqueDef.path` already
## answers it on every authored `.tres`. So [method mechanism_for_hit] is that second
## answer, [method resolve_hit] uses it, and [method install] wires it beside the
## binding. ADR 0154.
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
## The component key `BodyCultivationApi.attach_acupoints` writes and
## `BodyLocation.ACUPOINTS_KEY` reads. Spelled here rather than reached into the body
## module's own `_`-private constant, because a private constant is a private detail —
## and this file now asks the SAME question twice (does this actor have a location axis?)
## in `_mechanism_for` and in the per-hit gate, so it must have one spelling.
const _ACUPOINTS_COMPONENT := &"acupoints"
## The magnitude of a BARE SWING: the one number a swing with no authored technique
## behind it is worth.
##
## ## Why this is a constant and not a ladder
##
## The spine's S1 is `technique.magnitude x RealmRate.factor(realm)`, and
## `RealmRate` is a sub-2x rate (ADR 0050) — so a fixed magnitude produces a
## sub-2x spread of damage ACROSS the ladder and leaves the realm table to
## `RealmScaling`, which multiplies `ATTACK_SPIRITUAL` and `element_power_<e>` by
## `RealmDef.power` on BOTH sides of a PvP blow. Measured over the thirty realms
## with the shipped `combat_damage.tres`, a magnitude of `2.0` costs a
## `commonborn` 14.3 hits to kill at R1 and 8.0 at R30 — a 1.8x drift against
## pools that grow 551x, which is the whole content of the drift: two numbers
## scaled by one table instead of one number scaled by two.
##
## `2.0` is chosen over `4.0` (7.1 -> 4.0 hits) and `1.0` (28.6 -> 16.1) because it
## is the median of the authored band: the 51 shipped `.tres` magnitudes run
## 0.5 -> 4.3 with a mean near 1.5, so a bare swing priced at `2.0` sits inside the
## authored range rather than above or below it. A swing is not a technique and
## must not be the strongest thing an actor owns, and it must not be the chip floor
## either — this is the middle of the catalogue, which is the only honest answer for
## "a blow with no technique on it".
const BARE_SWING_MAGNITUDE := 2.0
## The elemental share a bare swing carries: NONE, because the blow is elementless and
## an elementless attack reads its OWN authored share and never the tuning default. The
## owner's ruling is that an un-authored attack is PHYSICAL by default (BL-0348), so a
## `0.0` here is what keeps the swing raw; a pure-qi blow is a technique that AUTHORS a
## share, which is the omni channel's own door (ADR 0004). An ELEMENTAL swing is
## unaffected either way: a named element with a non-positive share reads the tuning
## default, exactly as before.
const BARE_SWING_SHARE := 0.0

## The injected attack callable: `func(attacker: Actor, defender: Actor, seed_value: int)
## -> Variant`. Null means no adapter can land a blow, which [method strike] reports by
## name rather than swallowing.
static var _resolver: Callable = Callable()

## The injected per-hit callable: `func(attacker: Actor, target: Actor, technique:
## Variant, tuning: CombatTuning, rng: Variant) -> CombatOutcome`. The SECOND seam, and
## it exists because the first one cannot reach the mechanism: `strike` answers the
## encounter layer's exchange and has no `TechniqueDef` to select by, while the authored
## inputs (`element_share`, `aim_meridian`) travel only on a `ctx_builder`. Same static-
## by-convention shape as [member _resolver] and for the same reason — the hit is
## initiated by something that has no place to hang state, exactly as `attack` is.
static var _hit_resolver: Callable = Callable()


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
## ## The BOTH-paths case is deliberate, and qi is the answer at INSTALL time
##
## `MechanismSlot` stores one mechanism, so a dual-cultivator must pick, and the pick
## cannot be data — nothing in the authored content says which of two paths a blow
## belongs to. qi is the only pick that is correct for a mixed build rather than
## arbitrarily wrong for half of it: it always has its input (the element provider
## `ActorFactory.build` mounts for everyone), and qi explicitly never raises immunity
## (BRIEF 2.2), so it cannot dominate a build that has spent nothing on
## `ATTACK_SPIRITUAL`. This remains the right answer for "which mechanism is bound when
## nobody says otherwise". It was NOT the right answer for "which mechanism is this hit
## worth", and the docblock used to say so without saying anything that fixed it:
## `ItemWorkbenchApp._build_actor` and `CharacterCreationFlow._body` enrol THREE paths,
## so `has_body == has_mind` was true for every player actor and the binding below was
## `QiDamage` for all of them, forever. **ADR 0154** is that fix: the per-hit question
## is answered by [method mechanism_for_hit], off the ATTACKING TECHNIQUE's path.
##
## ## Idempotent by contract, not by luck
##
## `bind_mechanism` is per-ACTOR and idempotent, so calling this on boot and again after a
## save load is the intended usage. Re-binding after a save load is also how an actor that
## gained a path gets the right mechanism: `ActorFactory` enrols AFTER `ActorFactory.build`
## returns, so the order `ItemWorkbenchApp` uses (`build` -> three enrolments ->
## `CombatBoot.install`) is the only order in which the components exist by the
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
	var mechanism: DamageMechanism = _instance(chosen, actor)
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


## A fresh mechanism for `chosen`, configured for `actor`. One place that names the
## three concrete types, shared by the install-time binding above and the per-hit
## selection below so the two can never disagree about what a name MEANS.
static func _instance(chosen: StringName, actor: Actor) -> DamageMechanism:
	match chosen:
		_BODY_MECHANISM:
			return BodyDamage.new()
		_MIND_MECHANISM:
			var mind := MindDamage.new()
			# The sea, INJECTED rather than left to the mechanism's own component lookup:
			# binding it once here is what makes `CombatBoot` the composition root for the
			# mind path the way `ElementsApi.attach` is the root for qi. A null sea reads
			# `structural_capacity 0.0` and the erosion is visibly inert, and the gate in
			# `_mechanism_for` is what stops an actor without one getting here at all.
			mind.sea = MindCultivationApi.sea(actor)
			return mind
		_:
			return QiDamage.new()


## The mechanism `actor`'s own components support, or `&""` for the qi fallback. Split out
## as one pure read so the rule above is stated once and the binding above is the only
## place a concrete type is named — which is what keeps this file's rule auditable.
##
## Reads components, not paths, FIRST: a path flag says what was enrolled, a component
## says what the mechanism will actually find, and only the second one can make S4 read
## zeros.
##
## ## This is the INSTALLED mechanism, and it is deliberately the neutral one
##
## `MechanismSlot` holds one mechanism per actor and `CombatSpine.resolve_hit` reads it
## off the ATTACKER at S4, so this is the answer to "which mechanism will run if nobody
## says otherwise" — never "which mechanism is this hit worth". The hit-level answer is
## [method mechanism_for_hit], and [method install] binds BOTH: the slot so the spine's
## loud read can never assert on an actor this root built, and the per-hit resolver so a
## body technique on a tri-path actor still lands at a meridian (ADR 0154).
static func _mechanism_for(actor: Actor) -> StringName:
	var has_body := (
		actor.component(_ACUPOINTS_COMPONENT) != null and actor.path(PathState.BODY) != null
	)
	var has_mind := (
		actor.component(MindCultivationApi.SEA_COMPONENT) != null
		and actor.path(PathState.MIND) != null
	)
	# Exactly one, never "body wins" and never "mind wins": two paths is the ambiguous
	# case the docblock above resolves to qi on purpose.
	if has_body == has_mind:
		return _DEFAULT_MECHANISM
	return _BODY_MECHANISM if has_body else _MIND_MECHANISM


## The mechanism THIS HIT is resolved through, which is the ATTACKING TECHNIQUE's path
## rather than the attacker's enrolment (ADR 0154).
##
## ## Why the technique, and why not the actor
##
## The enrolment-based rule above is not wrong, it is just answering a different
## question, and it answers the wrong one in production for a reason that no fix to it
## can reach: `ItemWorkbenchApp._build_actor` and `CharacterCreationFlow._body` both
## enrol the player on all three paths, so `has_body == has_mind` is true on EVERY
## player actor and every one of them fell to `_QI`. Body and mind could not fire in the
## shipped app at all — not rarely, NEVER — which makes the three-mechanism program
## unreachable regardless of how correct the mechanisms are. Narrowing the enrolment to
## one path would "fix" that by deleting the dual-cultivator the game ships, and the
## audit's own framing ("select by the attacking technique's path") is the one that
## needs no new authored data: `TechniqueDef.path` already exists and is populated on
## every `.tres` under `game/data/techniques/`.
##
## ## The gate is still the attacker's INPUTS, not its enrolment
##
## Selection asks two questions in order and both must answer yes:
##
##   1. does the technique ASK for this mechanism? — `TechniqueDef.path`;
##   2. can this attacker actually PRODUCE it? — it carries the input that mechanism
##      reads: an `acupoints` component for body, a `sea_of_consciousness` for mind.
##
## Question 2 is what makes this safe rather than merely different. `BodyDamage` and
## `MindDamage` read the DEFENDER's acupoints and sea and the ATTACKER's
## `ATTACK_PHYSICAL` / `MENTAL_ATTACK`; an actor with none of those reads `0.0` at S4 and
## every hit collapses to the chip floor. So the per-hit switch refuses a mechanism whose
## inputs this attacker does not carry and falls back to the INSTALLED mechanism — which
## is the one `bind_mechanisms` chose because those inputs were present.
##
## **The gate reads COMPONENTS, not the currently-bound mechanism, and that is not a
## restatement.** Reading `MechanismSlot.peek(attacker)` here would make the rule
## self-defeating and silently so: the shipped player's bound mechanism is qi precisely
## BECAUSE it carries both other sets, so "can this attacker run `BodyDamage`?" answered
## "is my bound mechanism `BodyDamage`?" answers NO on every player actor and the rule
## rejects body for exactly the actors it exists to enable — a tautology that reads as a
## working guard and is not one. The components are the fact; the slot is a cache of a
## decision made elsewhere.
##
## Selection is therefore strictly a WIDENING of the reachable set: a body technique on a
## tri-path actor now reaches `BodyDamage`, and nothing that worked before can stop
## working — an actor lacking the inputs falls back to the installed mechanism, which is
## the old behaviour verbatim.
##
## ## A DUAL technique and a SHARED one
##
## Neither names one path, and the rule must not invent a coin flip for them. A DUAL
## technique's own docblock says it "commits BOTH" paths (ADR 0059), so it is asked of
## both mechanisms and takes the first the attacker can actually run — enumerated in the
## authored order (`qi_cultivation+body_cultivation` prefers qi), which is deterministic
## and is the author's stated ordering rather than one this file invented. A SHARED
## technique names no path at all and gates on `TechniqueGate.best_ordinal`, so it has
## no mechanism to ask for: it takes the INSTALLED one, which is exactly the qi fallback
## a pathless technique wants and is what every `shared_*.tres` shipped before.
##
## ## Reads are `Variant`-based and unbound reads never throw
##
## `TechniqueDef` lives in `modules/techniques/` and the concrete mechanisms are named
## here because `app/` is the composition root, but a null technique or an actor with no
## bound mechanism is an ordinary state, not a failure: `_bound` uses `MechanismSlot.peek`
## — the NON-loud read — because `MechanismSlot.of` asserts, and this runs per hit on
## whatever the caller handed in. Nothing here can raise.
static func mechanism_for_hit(attacker: Actor, technique: Variant) -> StringName:
	var bound := _bound(attacker)
	if technique == null or not (technique is Object):
		return bound
	var asked := _mechanisms_for_technique(technique)
	for candidate in asked:
		if _runs_for(candidate, attacker):
			return candidate
	return bound


## Whether `attacker` carries the input that mechanism `candidate` reads. The input
## gate of [method mechanism_for_hit], and the component is the fact rather than the
## currently-bound mechanism — see that method's own docblock for why reading the slot
## here would be a tautology that disabled body on every player actor.
##
## qi is NOT gated, and that asymmetry is deliberate rather than an oversight. Its inputs
## are STATS (`ATTACK_SPIRITUAL`, `element_power_<e>`) read through `ctx.attacker_value`,
## and `ElementsApi.attach` registers the element side as a STAT PROVIDER on
## `actor.stats` — not as a component — so there is no component to test and a gate
## written against one would be permanently false and would reject every qi hit. Every
## `Actor` carries an `ActorStats`, so the honest statement is that qi has no component
## input to be missing, and the fallback below handles the rest.
static func _runs_for(candidate: StringName, attacker: Actor) -> bool:
	if attacker == null:
		return false
	match candidate:
		_BODY_MECHANISM:
			return attacker.component(_ACUPOINTS_COMPONENT) != null
		_MIND_MECHANISM:
			return MindCultivationApi.sea(attacker) != null
		_DEFAULT_MECHANISM:
			return true
		_:
			return false


## The mechanisms `technique` asks for, in authored order. `TechniqueDef.path_ids()`
## already parses the DUAL `"a+b"` spelling (ADR 0059), so nothing here re-derives it
## and a fourth path added there is answerable here without an edit to this file.
static func _mechanisms_for_technique(technique: Object) -> Array[StringName]:
	# A DECLARED typed local, not `[...] as Array[StringName]`: this engine returns an
	# UNTYPED array for an as-cast literal, and the caller's `var asked :=` then fails
	# at runtime — the defect this shape replaces.
	var fallback: Array[StringName] = [_DEFAULT_MECHANISM]
	if technique.has_method(&"path_ids"):
		var ids: Variant = technique.call(&"path_ids")
		if ids is Array:
			return _mechanisms_for_paths(ids as Array)
		return fallback
	# A def that cannot answer its own paths is a def the seam cannot read, and qi is
	# the one mechanism whose inputs every root-built actor is guaranteed to carry.
	return fallback


static func _mechanisms_for_paths(paths: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for path_id in paths:
		var mechanism := StringName(path_id) if path_id is StringName or path_id is String else &""
		match mechanism:
			PathState.BODY:
				out.append(_BODY_MECHANISM)
			PathState.MIND:
				out.append(_MIND_MECHANISM)
			PathState.QI:
				out.append(_DEFAULT_MECHANISM)
	if out.is_empty():
		# The same declared typed local, for the same reason as above.
		out.append(_DEFAULT_MECHANISM)
	return out


## The name of the mechanism `attacker` currently carries, or the qi fallback when it
## carries none. The NON-loud read on purpose — see [method mechanism_for_hit].
static func _bound(attacker: Actor) -> StringName:
	var mechanism := MechanismSlot.peek(attacker)
	if mechanism is BodyDamage:
		return _BODY_MECHANISM
	if mechanism is MindDamage:
		return _MIND_MECHANISM
	return _DEFAULT_MECHANISM


## Whether `candidate` is a `DamageMechanism` this composition root did not build, and
## must therefore keep rather than replace. The complement of [method _instance]: that
## function creates the three shipped mechanisms, so anything outside it is a caller's.
static func _is_foreign(candidate: Variant) -> bool:
	return (
		candidate is DamageMechanism
		and not (candidate is QiDamage)
		and not (candidate is BodyDamage)
		and not (candidate is MindDamage)
	)


## Install the callable `PlayerAdapter.attack` lands its blow through, and report the
## install. A `CombatApi.hit` Callable is the intended value; passing an empty Callable
## clears the binding, so an uninstall is deterministic rather than only an overwrite.
static func set_attack_resolver(resolver: Callable) -> Dictionary:
	_resolver = resolver
	return {"ok": _resolver.is_valid(), "reason": "" if _resolver.is_valid() else "no_resolver"}


## Whether a resolver is installed, so a caller can say "no target" and "no spine" as two
## different messages rather than one empty descriptor.
##
## ## The `or` that used to be here, and why it is `and`
##
## This read `_resolver.is_null() or _resolver.is_valid()`, and a `Callable` answers
## `is_valid() == false` when it is null OR when it names something that no longer
## exists — so the disjunction was `true` in BOTH cases and the function answered
## "yes, a resolver is installed" before a single one had been. `PlayerAdapter.attack`
## reads this as its only gate, so the gate was open: it warned about a missing
## resolver on a process that had never installed one and then walked straight into
## `strike`, which refused with `no_resolver` and the blow was silently dropped.
## `CombatBoot.strike` has the same dead check, which is how the refusal was invisible
## from the outside: two guards that could not both fail loudly.
##
## The correct question is one conjunct: is there a callable that is both non-null and
## valid? `_resolver.is_valid()` already implies non-null, so it is the whole answer —
## and it is the SAME read `set_attack_resolver` reports as `ok`, so a caller can trust
## that the install that reported success is the one this confirms.
static func has_attack_resolver() -> bool:
	return _resolver.is_valid()


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


## ## Everything a booted combat stack needs for one actor, in the order that order
## matters: the mechanism first (so `CombatSpine.resolve_hit` cannot assert on it), then
## the resolver (so `PlayerAdapter.attack` has something to call), then the per-hit
## resolver (so a body technique on a tri-path actor lands at a meridian).
##
## Idempotent, so it is the intended usage on boot AND after a save load — and the
## save-load case is the one that can CHANGE the answer, because a load is where an actor
## may gain the acupoint set or the sea it lacked when it was first bound. `mechanism` is
## the name actually bound, so a caller reads which of the three it got rather than
## assuming the qi default — and `hit` is the INSTALLED name, which on a tri-path player
## is `QiDamage` while the hits that player throws are resolved by [method
## resolve_hit]. Those are two different questions and the report now names both.
static func install(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false,
			"bound": false,
			"mechanism": "",
			"wounds": false,
			"resolver": false,
			"hit_resolver": false,
			"reason": "no_actor"
		}
	var bound: Dictionary = bind_mechanisms(actor)
	# The ONE line that decides which model resolves a player-facing blow (ADR 0165).
	# It used to install `CombatApi.hit`, so every swing spent a SHARE of the
	# defender's pool through `combat/damage.gd` and `CombatSpine` was never reached
	# from a live fight. It installs [method duel_blow] instead, which resolves the
	# same blow through the spine. `CombatApi.exchange` — the BOSS fight — still
	# installs nothing here and still resolves through the share model, because that
	# one is a content-scaling question. See [method duel_blow] for the measurements
	# that make that split the honest one.
	var resolver: Dictionary = set_attack_resolver(Callable(CombatBoot, "duel_blow"))
	var hits: Dictionary = set_hit_resolver(Callable(CombatBoot, "resolve_hit"))
	# The MERCY seam, third and last. `CombatMercy.commit` is what reaches
	# `CombatApi.spare` — the only writer of `third_man_spared`, a fact three authored
	# gates watch and one authored fate is named for. Installed HERE rather than on the
	# first press so `PlayerAdapter.interact` can ask before it acts, and so a boot order
	# that never reached this line leaves the seam uniformly unbound, which the report
	# below then says.
	var mercy: Dictionary = CombatMercy.install()
	return {
		"ok": bool(bound["ok"]) and bool(resolver["ok"]) and bool(hits["ok"]) and mercy["ok"],
		"bound": bool(bound["bound"]),
		"mechanism": bound["mechanism"],
		"wounds": bool(bound["wounds"]),
		"resolver": bool(resolver["ok"]),
		"hit_resolver": bool(hits["ok"]),
		"spare_resolver": mercy["ok"],
		"reason": "",
	}


## Install the per-hit resolver, and report the install. An empty Callable clears the
## binding, exactly as [method set_attack_resolver] does — so an uninstall is a decision
## a test can make and undo rather than a process-wide thing it has to survive.
static func set_hit_resolver(resolver: Callable) -> Dictionary:
	_hit_resolver = resolver
	return {
		"ok": _hit_resolver.is_valid(),
		"reason": "" if _hit_resolver.is_valid() else "no_hit_resolver"
	}


## One bare swing from `attacker` against `defender`, resolved through the SPINE.
##
## This is what `PlayerAdapter.attack` lands its blow through, and it is the answer
## to BL-0522's second half: a player-facing fight between two `Actor`s now reaches
## `CombatSpine.resolve_hit` -> a `DamageMechanism` -> S5 -> S8 -> S9, so ADR 0133's
## claim that `combat_engine` is the single source of truth for damage is true of
## the actor-facing path rather than merely asserted of it.
##
## ## Why `CombatApi.hit` was the wrong resolver, measured
##
## `CombatApi.hit` -> `CombatDuelHit.resolve` -> `CombatDamage.resolve_hit` spends a
## SHARE of the defender's own pool. That is safe against a pool that does not scale
## with the realm, and an `Actor`'s health pool DOES: `RealmScaling.SCALED_STATS`
## carries `Stat.MAX_HEALTH`, so a same-realm pair has both sides moving together
## and the share model is merely redundant there. Measured, a same-realm PvP blow
## through the share model costs 6.6 hits at R1 and 3.7 at R30 — a 1.8x drift the
## engine does NOT have, because the engine pays the realm through the defender's
## `health` pool rather than through a fraction of it.
##
## The share model's `REFERENCE_ATTACK` is also 5.3x off the shipped game: it
## declares `24.0` "the point at which a blow is par", while a `commonborn`'s
## `ATTACK_PHYSICAL + ATTACK_SPIRITUAL` is 4.5 at every realm, so the model reads
## every real actor as a fraction of par.
##
## ## What is NOT here, and why the boss fight is untouched
##
## `CombatExchange.exchange` — the boss — keeps the share model, and
## `LootEncounterScreen` is still wired to `CombatApi.exchange`. Routing THAT through
## the spine is (a) in the options, and it is measured to be a one-press kill from
## `heaven_immortal` (R19): authored boss vitality spans 40 -> 800 across the thirty
## realms, and engine damage grows with `RealmDef.power`, so the engine does 14.1% of
## a boss's pool at R1 and 2032% at R30 — a 144x runaway with nothing on the other
## side of it. That is the content-side desync ADR 0133 records as OPEN, and it is
## the OWNER's call. This function deliberately does not reach into the boss path.
##
## ## The refusal vocabulary is `CombatDuelHit`'s, unchanged
##
## `no_attacker`, `no_defender`, `same_actor`, `defender_slain`, `defender_spared`,
## `no_health_pool`. They are the words `CombatApi.hit` already answered with and the
## words `CombatApi.spare` / `CombatDuel` are written against, so the mercy path
## keeps working unchanged: a spared opponent is still refused before the roll, and
## `CombatApi.spare` never has to learn about this function.
##
## ## And the ledger still records the same two facts
##
## `CombatDuelHit` wrote `duels_won` onto the winner's ledger and `CombatFacts` onto
## the world. Both writes are re-made here, from the spine's own `CombatOutcome`,
## because `what_the_rotation_cost.tres` gates on them (ADR 0137). Routing the blow
## through a different model must not silently retire a quest gate — so it does not.
static func duel_blow(attacker: Actor, defender: Actor, seed_value: int = 0) -> Dictionary:
	if attacker == null:
		return _blow_refusal("no_attacker")
	if defender == null:
		return _blow_refusal("no_defender")
	if attacker == defender:
		# An actor spending its OWN pool would read as a wound inflicted by somebody,
		# and `same_actor` is the only honest answer — `CombatDuelHit`'s own rule.
		return _blow_refusal("same_actor")
	var pool := defender.resource(&"health") as ResourcePool
	if pool == null:
		return _blow_refusal("no_health_pool")
	if pool.current <= 0.0:
		# Refused BEFORE the roll, as `CombatDuelHit` refuses it: a corpse spends
		# nothing, so an evaded blow and a blow on a body already down are not
		# distinguishable by their arithmetic.
		return _blow_refusal("defender_slain")
	if CombatDuel.spared(CombatDuel.normalize(defender.get_module_data(CombatDuel.MODULE_KEY))):
		# Also before the roll, for `CombatDuelHit`'s reason: the duel is already OVER
		# with this opponent, and spending their health after a mercy would make the
		# mercy a note the next swing quietly cancels.
		return _blow_refusal("defender_spared")
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		(
			seed_value * 2654435761
			+ absi(hash(String(attacker.id)))
			+ absi(hash(String(defender.id)))
		)
		& 0x7FFFFFFF
	)
	var before := pool.current
	var outcome := resolve_hit(attacker, defender, _swing_def(), CombatEngineApi.tuning(), rng)
	var spent := before - pool.current
	var slain := pool.current <= 0.0
	if slain:
		_record_win(attacker, defender)
	return {
		"ok": true,
		"reason": "",
		# Primitives only, so a caller can render this without naming a module. `share`
		# is retained as the fraction of the defender's MAXIMUM pool the blow spent —
		# the same number `CombatApi.hit` returned, so a readout that printed it keeps
		# working — and `taken` is the absolute spend the spine actually made.
		"share": 0.0 if pool.maximum <= 0.0 else spent / pool.maximum,
		"taken": spent,
		"crit": bool(outcome.crit),
		"evaded": bool(outcome.missed),
		# The share model published `power` and `mitigation`, neither of which the
		# spine has an analogue for, and inventing one here would be a second opinion
		# about what they meant. They are 0.0 rather than absent so a readout indexing
		# them does not read a missing key.
		"power": 0.0,
		"mitigation": 0.0,
		"defender_slain": slain,
		# Proof the blow went through the SPINE, published for a test and for a panel
		# that must never restate the formula: `model` is the module that answered.
		"model": &"combat_engine",
		"amount": float(outcome.amount),
		"health_delta": float(outcome.health_delta),
	}


## The bare swing's authored inputs: a `TechniqueDef` built in memory.
##
## In-memory and never a `.tres`, for three reasons. It is not CONTENT — there is
## no authored bare swing, and inventing one in `game/data/techniques/` would be
## authoring a technique the design does not have. It must not be persisted: a
## swing leaves no record, so a def that could be saved would be a lie about the
## shape. And it is rebuilt per blow rather than cached, so a bare swing can never
## accumulate state a technique def would carry.
##
## The qi path and the shipped default share, so a bare swing resolves through
## `QiDamage` and therefore through [method mechanism_for_hit]'s own gate — an
## attacker with no `acupoints` still fights, and one with them still cannot be
## reached by a swing that never names a body technique.
static func _swing_def() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = PathState.QI
	def.magnitude = BARE_SWING_MAGNITUDE
	def.element_share = BARE_SWING_SHARE
	return def


## Count the duel this blow ended, on the winner's own record.
##
## The same write [method CombatDuelHit._record_win] makes, and it is still made
## HERE rather than inside `modules/combat/`: the ledger is the one thing this
## module uniquely owns and ADR 0133 keeps it there, so the routing change above
## re-uses it instead of re-implementing or deleting it.
static func _record_win(attacker: Actor, defender: Actor) -> void:
	var duel := CombatDuel.normalize(attacker.get_module_data(CombatDuel.MODULE_KEY))
	(
		CombatDuel
		. record_win(
			duel,
			{
				"outcome": "duel_won",
				"opponent_id": String(defender.id),
				"wins": int(duel.get("wins", 0)) + 1,
			},
			# THE ACTOR, and this is the SECOND copy of DEF-0320: `duel_hit.gd`'s
			# `_record_win` had the identical omission, so two of the three production
			# win-recording sites recorded the win and paid nothing. Omitting it takes
			# `record_win`'s `actor: Actor = null` default, whose `if actor != null:`
			# skips the earn with no refusal, no warning and no type error.
			attacker
		)
	)
	attacker.set_module_data(CombatDuel.MODULE_KEY, duel)
	# LAST, once the record it describes is on the ledger (ADR 0137).
	CombatFacts.record_duel_won(attacker)


## One refusal, in the shape [method duel_blow] returns: `ok: false`, every number
## zero, and no claim that the defender died. `model` names the engine anyway —
## a refusal is a refusal to SPEND, never a refusal to resolve through the spine, so
## a test asserting the route does not have to tell the two apart.
static func _blow_refusal(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"share": 0.0,
		"taken": 0.0,
		"crit": false,
		"evaded": false,
		"power": 0.0,
		"mitigation": 0.0,
		"defender_slain": false,
		"model": &"combat_engine",
		"amount": 0.0,
		"health_delta": 0.0,
	}


## Whether a per-hit resolver is installed, the twin of [method has_attack_resolver] for
## the second seam. [method resolve_hit] falls back to the engine's own facade call when
## this is false, so an uninstall is a degradation rather than a crash.
static func has_hit_resolver() -> bool:
	return _hit_resolver.is_valid()


## One hit resolved the way the SHIPPED app resolves one, through the same entry point
## `ItemWorkbenchApp._resolve_technique_hit` uses.
##
## ## Why this exists at all
##
## `CombatSpine.resolve_hit`'s `ctx_builder` parameter defaults to an empty `Callable`,
## and the only production caller passed five arguments — `(attacker, target, technique,
## tuning, null)` — so `ctx_builder` was always empty in production. That is not a
## default, it is a hole with two symptoms:
##
##   - `QiDamage.builder` / `BodyDamage.builder` / `MindDamage.builder` were never called
##     from `src/` at all, so `ctx.data` carried NONE of the authored inputs;
##   - `element_share` therefore always read `0.0`, fell to `default_element_share` from
##     the `.tres`, and the per-technique share every one of the 55 authored `.tres`
##     files sets was INERT. `aim_meridian` had the same fate, and a `named` body aim
##     resolved as `random` because `_mode_of` reads the authored id from `ctx.data`.
##
## The three `builder` statics exist for exactly this call and take the authored def as a
## `Variant` precisely so a composition root can hand them one without the mechanism
## acquiring a compile-time edge to `modules/techniques/`. This is that call.
##
## ## It selects the mechanism AND carries the context, in one pass
##
## Both halves belong together: which mechanism runs and what it reads are the same
## question. `QiDamage.builder` is meaningless under `BodyDamage` and vice versa, so
## building the context for the INSTALLED mechanism while resolving through the SELECTED
## one would ship a body hit carrying `element_share`. The two are chosen from the same
## [method mechanism_for_hit] answer, which is what makes them impossible to desync.
##
## ## The scoped swap, and why the spine does not learn about it
##
## `CombatSpine.resolve_hit` reads the mechanism off `MechanismSlot.of(attacker)` at S4
## and has no parameter for "unless the caller says otherwise" — deliberately, because
## that parameter would put a per-path concept into the one file in the module that must
## never name one. So the selection is made by TEMPORARILY binding the selected mechanism
## to the attacker and restoring the previous one in the same function. The alternative
## was editing `combat_engine/spine.gd`, which is not this task's file and is shared.
##
## The swap is restore-on-return rather than restore-on-success on purpose: a mechanism
## that returns null or throws must not leave the attacker bound to a body mechanism it
## was not built with. `CombatOutcome` is a `RefCounted` and the bind is one dictionary
## write, so the cost is bounded and the scope is a single call — never a frame.
##
## ## The `CombatEngineApi` fallback is deliberate, not a stub
##
## With no per-hit resolver installed this still returns a real `CombatOutcome` through
## the module's own facade, so a caller that has not booted the composition root gets the
## old behaviour rather than a null. That is what lets the engine's 5500-odd tests keep
## binding through `MechanismSlot.bind` directly and prove the spine without any of this.
static func resolve_hit(
	attacker: Actor,
	target: Actor,
	technique: Variant,
	tuning: CombatTuning = null,
	rng: Variant = null
) -> CombatOutcome:
	var resolved := tuning if tuning != null else CombatEngineApi.tuning()
	var selected := mechanism_for_hit(attacker, technique)
	var previous := MechanismSlot.peek(attacker)
	# A mechanism ALREADY bound that is NOT one of the three this file builds is KEPT,
	# and the spine runs it. That branch is what lets a caller — a test, or any future
	# composition-root decision — supply its own `DamageMechanism` and have it actually
	# resolve, without editing `spine.gd` to add a parameter for it. Before this,
	# `bind_mechanism` was reachable but UNREACHABLE from a resolution: every call
	# replaced the binding with `_instance(mechanism_for_hit(...))`, so a bound
	# mechanism could only be OBSERVED, never run — which is what made ADR 0067's seam
	# untestable from the production entry point.
	#
	# The three built-ins are named rather than probed, because `app/` is the only layer
	# allowed to know concrete types and this file already names all three in `_instance`.
	# A fourth mechanism needs no edit here: it is not built-in, so it is kept, which is
	# the correct default for anything this root did not create.
	var outcome: CombatOutcome = null
	if _is_foreign(previous):
		var injected := ctx_builder_for(attacker, target, technique, selected)
		outcome = CombatEngineApi.resolve_hit(attacker, target, technique, resolved, rng, injected)
	elif previous == null:
		outcome = CombatEngineApi.resolve_hit(attacker, target, technique, resolved, rng)
	elif has_hit_resolver():
		CombatEngineApi.bind_mechanism(attacker, _instance(selected, attacker))
		var ctx := ctx_builder_for(attacker, target, technique, selected)
		outcome = CombatEngineApi.resolve_hit(attacker, target, technique, resolved, rng, ctx)
		CombatEngineApi.bind_mechanism(attacker, previous)
	else:
		CombatEngineApi.bind_mechanism(attacker, _instance(selected, attacker))
		outcome = CombatEngineApi.resolve_hit(attacker, target, technique, resolved, rng)
		CombatEngineApi.bind_mechanism(attacker, previous)
	# ADR 0902 (P6=C): the landed blow reaches the counter store through ONE status
	# facade verb — this funnel is the caller that already holds both edges.
	_fire_status_counters(target, outcome)
	return outcome


## ADR 0902 (P6=C): the spine's landed blow, delivered to the counter store through
## the status facade. Every `status_application` row the S12 stage filed on this outcome
## that NAMES a status is offered to `StatusApi.record_landed_blow`, which advances a
## counter only when the status's def authors `payload.counter` — no shipped def does,
## so the shipped content is byte-identical and the wiring is what makes a future
## authored counter live. An `already_held` row counts too: the blow landed and carried
## the status even when the merge had nothing to do. No module edge is invented: `app/`
## is the caller.
static func _fire_status_counters(target: Actor, outcome: CombatOutcome) -> void:
	if target == null or outcome == null:
		return
	for entry in CombatProposalReader.effects_of(outcome.proposal):
		if not entry is Dictionary:
			continue
		var row := entry as Dictionary
		if StringName(row.get("kind", &"")) != StatusApply.EFFECT_KIND:
			continue
		if StringName(row.get("status_id", &"")) == &"":
			continue
		StatusApi.record_landed_blow(target, row)


## The `ctx_builder` for one hit: the builder for the `selected` mechanism [method
## mechanism_for_hit] chose, carrying the authored inputs that mechanism reads.
##
## `selected` is a PARAMETER rather than recomputed here, and that is the point of the
## whole file: one answer drives both which mechanism runs at S4 and what `ctx.data`
## carries, so the two cannot be selected from different rules and drift. A caller that
## wants the builder alone may pass `&""` and get the selection for [code]attacker[/code]
## and [code]technique[/code]; [method resolve_hit] never does, because it has already
## paid for the selection.
##
## ## Why the INJECTED side, and never a rule of its own
##
## Each `builder` already decides what its own mechanism needs — `QiDamage` carries
## `element` + `element_share` + the rules table, `BodyDamage` carries `aim_meridian` +
## the aim mode + the tuning, `MindDamage` carries the kind. This method's whole
## judgement is WHICH builder, and it re-implements none of theirs. A fourth mechanism
## is one `match` arm here and one `builder` in its own module.
##
## ## `target` is a parameter, not derived from `attacker`
##
## The spine's `ctx_builder` receives only the `AttackContext`, so everything not
## derivable from it has to be bound at BUILD time — which is why this takes the target
## rather than reading it off the attacker. Body and qi read the defender's acupoints,
## affinities and resistances straight off `ctx`; mind needs the defender's SEA as an
## object, and there is no accessor for that on the context, so it is captured here.
##
## ## Why `ElementsApi.default_rules()` is passed for qi
##
## Without a rules table `QiDamage._matchup_of` answers `NEUTRAL` (1.0) for every
## strike, so the five-elements matchup graph — the whole reason qi has a resistance
## axis at all — is dead in production. `ElementsApi.default_rules()` is the module's own
## memoised table, and this is `app/` naming a facade, which is the one thing a
## composition root is for. It is passed but NOT bound to the mechanism, so
## `_rules_of`'s per-attack injection stays the first route and a caller that wants a
## different table for one hit still can.
##
## ## The mind sea is read off the DEFENDER
##
## `MindDamage.builder`'s `p_sea` is the defender's sea: `structural_capacity` is the
## denominator of the erosion (ADR 0071), so injecting the ATTACKER's sea would divide a
## strike by the wrong sea. A target with no sea leaves it null and the mechanism reports
## `sea_bound == false` rather than inventing one — inert and visible, which is the
## degradation `mind_damage.gd` hole 2 documents.
##
## ## The erosion KIND is the technique's, and hardcoding it here killed two of three
##
## This read `MindDamage.Kind.DISRUPT` on a literal, so every mind strike in the game
## was a plain disrupt no matter what it was. That is not a weak default, it is a
## dead program: `_illusion_resistance_of` returns `0.0` for anything but `OBSCURE`, so
## the whole illusion branch of `_mitigation_of` never ran and `ILLUSION_RESISTANCE` was
## a stat no attack ever read; and `_awareness_delta_of` returns `0.0` for anything but
## `ATTEND`, so the AWARENESS reserve ADR 0152 gave a writer was never spent by an
## attack. `mind_illusion_lattice.tres` is authored as an illusion — its own tags say
## `illusion` — and resolved as a plain disrupt.
##
## The authored intent now rides [member TechniqueDef.mind_kind], and it is read as
## `get()` on a `Variant` exactly as `BodyDamage.builder` reads `aim_meridian` and
## `QiDamage.builder` reads `element_share`. Three reasons for that shape over a typed
## read: this file already treats a technique as untrusted (`mechanism_for_hit` checks
## `technique is Object` before asking it anything), a def authored before the field
## existed answers `&""`, and `MindDamage._kind_of` already resolves `&""` to `DISRUPT`.
## So an unauthored `.tres` behaves byte-identically to the day this call was written.
static func ctx_builder_for(
	attacker: Actor, target: Actor, technique: Variant, selected: StringName = &""
) -> Callable:
	var chosen := selected if selected != &"" else mechanism_for_hit(attacker, technique)
	var base: Callable
	match chosen:
		_BODY_MECHANISM:
			base = BodyDamage.builder(technique, &"", CombatEngineApi.tuning())
		_MIND_MECHANISM:
			base = MindDamage.builder(
				_mind_kind_of(technique), MindCultivationApi.sea(target), technique
			)
		_:
			base = QiDamage.builder(ElementsApi.default_rules(), technique)
	return _with_status_request(base, technique)


## ADR 0105's status request, staged over whichever mechanism builder won. The
## carrier is the ELEMENT, never the technique: `StatusApi.status_for_element`
## answers the id the authored catalogue claims for a landed blow of that
## element, or `&""` when nothing claims it. An elementless blow and an
## unclaimed element stage nothing, so S12 withholds quietly rather than
## guessing — degrade, never throw. The gate is the shipped tuning's
## `status_gate_chance`, read here rather than restated, and a closed gate
## closes the mapping itself rather than staging a request S12 would refuse.
static func _with_status_request(base: Callable, technique: Variant) -> Callable:
	return func(ctx: AttackContext) -> AttackContext:
		var out: AttackContext = ctx
		if base.is_valid():
			var built: Variant = base.call(ctx)
			if built is AttackContext:
				out = built
		_stage_status_request(out, technique)
		return out


## Stage one ADR 0105 request onto `ctx.data`, or nothing when the blow carries
## no claimable element. Separated so the shape (one gate, element-carried) is
## asserted in one place rather than in every mechanism arm above.
static func _stage_status_request(ctx: AttackContext, technique: Variant) -> void:
	if ctx == null:
		return
	var element := _element_of(technique)
	if element == &"":
		return
	var tuning := CombatEngineApi.tuning()
	var gate := float(tuning.status_gate_chance)
	var status_id := StatusApi.status_for_element(element, gate)
	if status_id == &"":
		return
	# ADR 0884: the status's own `kind` rides the request so S12 can read the
	# per-category channel without knowing a `status` module class.
	var def := StatusApi.definition(status_id)
	(
		ctx
		. set_data(
			StatusApply.REQUEST_KEY,
			{
				"id": status_id,
				"element": element,
				"kind": &"" if def == null else def.kind,
				"immunity_tags": [] if def == null else def.immunity_tags,
				"family": &"" if def == null else def.family,
				"categories": [] if def == null else def.categories,
				"potency": 0.0 if def == null else def.potency_base,
				"chance": gate,
				"scope": StatusApply.SCOPE_COMBAT,
			}
		)
	)


## The element a technique carries, or `&""`. Variant-read exactly as
## `_mind_kind_of` reads `mind_kind`, so a def authored before the field
## existed degrades to elementless rather than throwing.
static func _element_of(technique: Variant) -> StringName:
	if technique is Object:
		var authored: Variant = (technique as Object).get(&"element")
		if authored is StringName or authored is String:
			return StringName(authored)
	return &""


## The erosion kind `technique` authors, or `DISRUPT` when it authors none.
##
## Returned as a `Variant`, not a `StringName`, because the two arms are different TYPES
## on purpose and GDScript will not let a declared `StringName` return hold either:
## `MindDamage.Kind.DISRUPT` is an enum ordinal — an `int` — not a name. Both arms are
## what `MindDamage.builder`'s `p_kind: Variant` already accepts and what
## [method MindDamage._kind_of] already resolves, a name and an ordinal through the same
## branch.
##
## The `Variant` read of the def is deliberate and is the same one `QiDamage.builder` and
## `BodyDamage.builder` already make: this is `app/` handing a `combat_engine` builder an
## authored content type it may not have a compile-time edge to, and a def that is null,
## is not an object, or predates the field must all degrade to the plain strike rather
## than crash a combat tick. The NAME travels unresolved — `_kind_of` is the only function
## that reads the vocabulary, so there is one place a kind can be added.
static func _mind_kind_of(technique: Variant) -> Variant:
	if technique is Object:
		var authored: Variant = (technique as Object).get(&"mind_kind")
		if authored is StringName or authored is String:
			return StringName(authored)
	return MindDamage.Kind.DISRUPT
