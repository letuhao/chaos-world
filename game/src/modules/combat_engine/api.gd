class_name CombatEngineApi
extends RefCounted

## Public facade for the `combat_engine` module (ADR 0067, ADR 0068).
##
## `modules/combat_engine/` owns the shared damage SPINE — the stages every hit passes
## through regardless of which cultivation path threw it — and the seam that lets three
## different damage mechanisms occupy the same two call sites without the spine ever
## branching on a path id.
##
## ## What the spine is, and what a mechanism is
##
## The spine owns eleven stages (ADR 0067). Eleven of them are shared: the rate gate
## that applies the one shared realm ladder, the single-draw band roll, the crit roll,
## the flat `DAMAGE_REDUCTION` subtraction, the linear amplification factor, the
## chip floor that makes immunity arithmetically unreachable, the shield gate, the
## post-shield reflect, and leech. TWO are per-path: `resolve` and `mitigate`. A
## mechanism implements `DamageMechanism`; qi reads an element, body reads a location,
## mind erodes a sea. The spine never asks which.
##
## ## Why this is a separate module from `combat`
##
## `modules/combat/` holds the encounter layer — who is being fought, and what the
## fight is worth. This module holds how a blow is resolved. They are different reasons
## to change and neither one implies the other.
##
## ## The one rule a caller must not break
##
## Do NOT bind a mechanism per hit. `bind_mechanism` is per ACTOR and is idempotent, and
## binding is the only place a path id is ever resolved — deliberately, in `app/`, which
## is the composition root and the only layer allowed to know concrete types.

const SHIELD_COMPONENT := &"Shield"
const MECHANISM_COMPONENT := &"damage_mechanism"
## The component id the wound ledger is bound on. It is also the key the payload slot
## travels under and the key `BodyLocation.wounds_of` reads, so there is ONE spelling of
## "the wound ledger" in the codebase and `Actor._wounds_dict` can find it by name
## without this module's types (ADR 0140).
const WOUNDS_COMPONENT := &"body_wounds"
## The module's payload key for that ledger, which is the ledger's OWN declaration rather
## than a second spelling of it. `Actor.WOUNDS_MODULE_KEY` in core is the third copy and
## is unavoidable: core cannot import this module. These two agree by construction, and
## the round-trip test is what holds them to it.
const WOUNDS_MODULE_KEY := BodyWounds.MODULE_KEY


## The shipped balance numbers, loaded from the module's `.tres`. Every constant the
## spine and the band read comes from here, so a rebalance is a data edit and no test
## re-pins a number that changed on purpose.
static func tuning() -> CombatTuning:
	return CombatTuning.shipped()


## Bind `mechanism` to `actor` as its damage mechanism. Idempotent: a second call with
## the same mechanism does nothing, and a call with a different one replaces it, which
## is how a save-load restores the right mechanism for the path a player actually took.
static func bind_mechanism(actor: Actor, mechanism: DamageMechanism) -> void:
	if actor == null or mechanism == null:
		return
	MechanismSlot.bind(actor, mechanism)


## The mechanism bound to `actor`. Fails LOUDLY when none is: a mechanism is not
## optional, and `Actor.component()` returns `RefCounted`, so a silent downcast would
## surface three stages later as "the mechanism did nothing".
static func mechanism_of(actor: Actor) -> DamageMechanism:
	return MechanismSlot.of(actor)


## Resolve one hit from `attacker` against `target` and apply it. This is the whole
## public surface of the engine: everything else is either tuning, binding, or a read.
##
## `technique` is a `TechniqueDef` (the authored content type, ADR 0056). `ctx_builder`
## is the extension point that carries anything a mechanism needs beyond the two
## `StatContext`s — an element rule table, a location resolver — across the seam without
## adding a stage to the spine.
##
## `rng` may be null, in which case nothing random happens and every attack lands.
static func resolve_hit(
	attacker: Actor,
	target: Actor,
	technique: TechniqueDef,
	tuning: CombatTuning = null,
	rng: Variant = null,
	ctx_builder: Callable = Callable()
) -> CombatOutcome:
	return CombatSpine.resolve_hit(attacker, target, technique, tuning, rng, ctx_builder)


## The same hit decomposed, primitives only, so a readout panel never restates the
## formula. Delegates to [method CombatOutcome.to_dict]; `{}` when `actor` is null.
## This is the ADR 0038 / 0043 screen contract: a screen passes these to a panel and
## the panel owns every `%d` and decimal.
static func breakdown(
	attacker: Actor,
	target: Actor,
	technique: TechniqueDef,
	tuning: CombatTuning = null,
	rng: Variant = null,
	ctx_builder: Callable = Callable()
) -> Dictionary:
	return resolve_hit(attacker, target, technique, tuning, rng, ctx_builder).to_dict()


## The band roll alone, without a mechanism or an apply. Useful for a preview that must
## quote the exact numbers a swing would produce, and for tests that assert the roll
## consumes exactly one draw.
static func band(
	attacker: Actor, target: Actor, tuning: CombatTuning = null, rng: Variant = null
) -> Dictionary:
	var resolved := tuning if tuning != null else CombatTuning.shipped()
	return (
		CombatBand
		. roll(
			resolved,
			CombatSpine.landed_chance(attacker, target, resolved),
			CombatBand.rate_of(CombatStats.PARRY_RATE, target, resolved),
			CombatBand.rate_of(CombatStats.BLOCK_RATE, target, resolved),
			rng
		)
		. to_dict()
	)


## Whether `actor` has a damage mechanism bound. A panel asks this to decide between
## "no build" and "0 damage", which are different messages.
static func has_mechanism(actor: Actor) -> bool:
	return actor != null and actor.component(MECHANISM_COMPONENT) is DamageMechanism


## Bind this actor's wound ledger, RESTORING it from a save when one is stashed and
## creating an empty one when it is not (ADR 0140). Idempotent: an actor that already
## carries a ledger keeps it, so a re-attach never erases wounds earned this session.
##
## This is the composition root's only obligation for wound persistence. `Actor.to_dict`
## reads the ledger straight off the component, so nothing needs to be flushed before a
## save; on load, `Actor._restore_versioned` stashes the raw payload in `module_data`
## and this call turns it back into the typed object. Core never imports `BodyWounds`,
## which is why the module owns the whole half of the round trip.
##
## `tuning` is bound once for the life of the ledger, the same field `BodyDamage.tuning`
## takes — a ledger whose every threshold read as `0.0` would wound on the first gash
## and sit on the necrosis floor immediately.
static func attach_wounds(actor: Actor, tuning: CombatTuning = null) -> BodyWounds:
	if actor == null:
		return null
	var existing := wounds_of(actor)
	if existing != null:
		if tuning != null:
			existing.tuning = tuning
		return existing
	var ledger := BodyWounds.new()
	ledger.tuning = tuning
	# `get_module_data` is the UNTRUSTED read: it answers `{}` for a missing key and for
	# anything under the key that is not a dictionary, so a hand-edited save degrades to
	# an empty ledger here instead of failing the load.
	ledger.load_from(actor.get_module_data(WOUNDS_MODULE_KEY))
	# The raw payload has been consumed. Clearing it keeps the stashed copy and the live
	# ledger from drifting apart, and keeps a later save from writing the stash twice.
	actor.set_module_data(WOUNDS_MODULE_KEY, {})
	actor.set_component(WOUNDS_COMPONENT, ledger)
	return ledger


## The ledger bound on `actor`, or null. The non-loud read, matching
## [method has_mechanism]'s role for the mechanism slot: a caller that genuinely does
## not know whether the actor was ever hit may ask, and production code that expects a
## ledger calls [method attach_wounds] instead.
static func wounds_of(actor: Actor) -> BodyWounds:
	if actor == null:
		return null
	return actor.component(WOUNDS_COMPONENT) as BodyWounds


## Everything a combat readout needs about one actor, primitives only: its own offense
## and defense numbers, whether it has a mechanism, and its shield. `{}` for no actor.
static func summary(actor: Actor, tuning: CombatTuning = null) -> Dictionary:
	if actor == null:
		return {}
	var resolved := tuning if tuning != null else CombatTuning.shipped()
	return {
		"has_mechanism": has_mechanism(actor),
		"attack_physical": actor.stats.derived(Stat.ATTACK_PHYSICAL),
		"attack_spiritual": actor.stats.derived(Stat.ATTACK_SPIRITUAL),
		"defense_physical": actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		"defense_spiritual": actor.stats.derived(Stat.DEFENSE_SPIRITUAL),
		"damage_reduction": actor.stats.derived(Stat.DAMAGE_REDUCTION),
		"evasion": actor.stats.derived(Stat.EVASION),
		"crit_chance": actor.stats.derived(Stat.CRIT_CHANCE),
		"crit_damage": actor.stats.derived(Stat.CRIT_DAMAGE),
		"parry_rate": CombatBand.rate_of(CombatStats.PARRY_RATE, actor, resolved),
		"block_rate": CombatBand.rate_of(CombatStats.BLOCK_RATE, actor, resolved),
		"reflect_rate": CombatBand.rate_of(CombatStats.REFLECT_RATE, actor, resolved),
		"min_chip_abs": resolved.min_chip_abs,
		"avoidance_band_cap": resolved.avoidance_band_cap,
		"realm_id": String(actor.realm()),
		"realm_rate": RealmRate.factor(actor.realm()),
	}
