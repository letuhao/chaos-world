class_name FertilityApi
extends RefCounted

## Public facade for the `fertility` module. Depends on `dual_cultivation` for the shared
## fertility/potency attributes (ADR 0002), and on `race` + `bloodline` for the lineage a child
## is born with (ADR 0108).
##
## Conception -> gestation -> birth is a status machine on the actor:
## NONE -> CONCEIVED -> GESTATING -> LABOR -> POSTPARTUM -> NONE.
##
## **Birth is where the lineage stack runs.** `resolve_offspring` is the single place a child is
## built: it averages the parents' attributes as it always did, then asks `race` and `bloodline`
## what body and what inherited concentration the child gets. Those modules are reached through
## their facades and depend on nothing here, so the stack stays acyclic — race, then bloodline,
## then clan, with birth as the consumer at the top.

## ## The actor-builder seam: why a child is minted, and not born with, a spine
##
## `resolve_offspring` mints its child through an injected constructor rather than calling
## `Actor.new` inline, and the seam exists for one reason: **this module may not name `app/`.**
## `PRIVATE_UNITS` in `tools/arch/rules.py` makes `app/` referenceable only from itself, and
## `ActorFactory` — the one place that knows the provider spine every actor gets — lives there.
## So the constructor is injected from the composition root exactly as `NpcApi.set_minter`
## (`modules/npc/api.gd:115`) and `DomainSpawner.set_minter` (`modules/domain/domain_spawner.gd:52`)
## do it, verbatim: a `Callable`, never a concrete actor type, and this file names neither
## (dependency inversion, ADR 0002).
##
## **What breaks if it is bypassed.** A child born in play would be an `Actor` with NO health
## pool and NO stamina pool: `Actor.attach_core_resources` (`core/actor.gd:126`) is what creates
## them, sized from the derived capacities, and it is called only from `ActorFactory.build`
## (`app/actor_factory.gd:12`). An actor with no `health` key cannot be damaged or healed — not
## "damages oddly", but `Actor.change_resource` finds no pool and does nothing, silently — and it
## would also carry no sect ledger, no clan ledger and no element provider, so
## `element_power_<e>` reads 0.0 on a newborn and every status lands on `status_potency_floor`
## instead of on the child's actual element. That contradicts ADR 0074 ("Every inhabitant of this
## game is an `Actor` ... gets the SAME provider spine the player gets") and ADR 0025 (core
## pools exist for every actor).
##
## **The default is deliberately the bare `Actor.new`, not a "safe" subset.** The headless suites
## in `tests/modules/fertility` drive birth without a composition root, and they assert on lineage
## — race and purity (ADR 0108) — which the spine does not touch. So a caller that never injects
## a builder keeps the exact behaviour it had, and the seam can be added without moving a single
## existing assertion. That is the same contract `DomainSpawner._mint` states: the default is the
## core-only half, and `app/` installs the full spine. If a caller wants the default to carry
## pools, it injects one; nothing here guesses.
static var _actor_builder: Callable = Callable()


## Attach the module to `actor`. Idempotent, and safe on an actor with no race: a body plan is
## read at birth, not baked in at attach, so there is nothing to seed here any more.
static func attach(actor: Actor) -> void:
	if actor == null or _has_provider(actor):
		return
	actor.stats.add_provider(FertilityProvider.new())


## Install the actor builder birth mints through. `app/` passes
## `ActorFactory.build`, so this module never names a concrete actor type and never names
## `app/` (dependency inversion, ADR 0002) — the `NpcApi.set_minter` shape, verbatim.
##
## Signature: `Callable(actor_id: StringName, base: Dictionary) -> Actor`, which is exactly
## `ActorFactory.build`'s own signature (`app/actor_factory.gd:8`), so the direct Callable is
## the whole wiring — the same form `NpcBoot.install` uses at `app/npc_boot.gd:39`, and for
## the same reason: a typed lambda forwarding to another script's static function is not the
## only form the engine boots.
##
## Idempotent, and `Callable()` restores the bare-`Actor.new` default. That is the reset a
## test suite must do in `teardown`, because this is process-wide state on a static: left
## installed it leaks into whatever suite runs next.
static func set_actor_builder(builder: Callable) -> void:
	_actor_builder = builder


static func _has_provider(actor: Actor) -> bool:
	for entry in actor.stats._providers:
		if entry.get_script() == FertilityProvider:
			return true
	return false


static func conception_chance(actor: Actor, partner: Actor) -> float:
	var base := actor.stats.derived(FertilityStats.CONCEPTION_CHANCE)
	var partner_factor := 1.0
	if partner != null:
		partner_factor = 1.0 + partner.stats.get_base(DualCultivationApi.POTENCY) * 0.02
	return clampf(base * partner_factor, 0.0, 0.99)


static func can_conceive(actor: Actor) -> bool:
	return not actor.has_status(FertilityStats.PREGNANCY)


## Begin a pregnancy, for `roll` in `[0, 1)` measured against `conception_chance`.
##
## The lineage inputs are CAPTURED HERE, not read at birth: the partner's race, the purity it
## carries, and both rolls are written onto the status. A child is a function of who conceived
## it, so nothing birth needs may depend on the world's state nine months later (ADR 0108).
## `race_roll` defaults to the conception roll, so a caller that does not care which body wins
## still gets a deterministic child.
static func try_conceive(
	actor: Actor, partner: Actor, roll: float, race_roll: float = -1.0
) -> bool:
	if not can_conceive(actor):
		return false
	if roll >= conception_chance(actor, partner):
		return false
	var status := PregnancyStatus.new(FertilityStats.PREGNANCY)
	status.stage = PregnancyStatus.Stage.CONCEIVED
	status.partner_id = partner.id if partner != null else &""
	status.partner_base = partner.stats.base_dict() if partner != null else {}
	status.conception_roll = roll
	status.race_roll = roll if race_roll < 0.0 else race_roll
	status.species_id = RaceApi.race_of(actor)
	if partner != null:
		status.partner_race = RaceApi.race_of(partner)
		status.partner_purity = purity_snapshot(partner)
	actor.add_status(status)
	return true


## Every `{lineage_id: purity}` an actor currently carries.
##
## Read from the published `state()` ledger rather than through a dedicated facade verb: that
## module is already at its twelve-method cap, and the ledger a caller is given is the same
## truth its other readers see. The one thing this must NOT do is reach past the facade into
## `BloodlineState`, so the union of keys is the whole mechanism.
static func purity_snapshot(actor: Actor) -> Dictionary:
	var out := {}
	for lineage_id in _held_lineages(actor):
		out[String(lineage_id)] = BloodlineApi.purity_of(actor, lineage_id)
	return out


static func _held_lineages(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var ledger := BloodlineApi.state(actor)
	for key in (ledger.get("lineages", {}) as Dictionary).keys():
		out.append(StringName(key))
	out.sort()
	return out


static func advance(actor: Actor, delta: float) -> Array[Actor]:
	var status := pregnancy(actor)
	if status == null:
		return []
	match status.stage:
		PregnancyStatus.Stage.CONCEIVED:
			status.stage = PregnancyStatus.Stage.GESTATING
		PregnancyStatus.Stage.GESTATING:
			status.progress += _gestation_step(actor, delta)
			if status.progress >= 1.0:
				status.stage = PregnancyStatus.Stage.LABOR
		PregnancyStatus.Stage.LABOR:
			var born := resolve_offspring(actor, status)
			status.offspring = born
			status.stage = PregnancyStatus.Stage.POSTPARTUM
			status.recovery_remaining = _recovery_time(actor)
			return born
		PregnancyStatus.Stage.POSTPARTUM:
			status.recovery_remaining -= delta * actor.stats.derived(FertilityStats.RECOVERY_RATE)
			if status.recovery_remaining <= 0.0:
				actor.statuses.erase(status)
	return []


static func pregnancy(actor: Actor) -> PregnancyStatus:
	for status in actor.statuses:
		if status is PregnancyStatus and status.id == FertilityStats.PREGNANCY:
			return status
	return null


static func roll_offspring_count(actor: Actor, roll: float) -> int:
	return 2 if roll < actor.stats.derived(FertilityStats.MULTIPLE_BIRTH_CHANCE) else 1


## Build the child of `mother` and the pregnancy's captured partner.
##
## Three things happen, in this order, and they are deliberately independent:
## 1. **Attributes** are averaged as they always were, scaled by `offspring_quality`. A body
##    plan is not a stat stick, so this is not folded into the lineage below.
## 2. **Race** is resolved through `RaceApi.resolve_race`, which is order-independent and always
##    answers exactly one race — the catalog baseline when nothing contests it, so no actor is
##    ever born raceless and every downstream gate stays answerable.
## 3. **Purity** per lineage is the mean of both parents', through `BloodlineApi.inherit_purity`.
##
## A child is born into NO house. Admission is a gate with its own rules (ADR 0064) and silently
## enrolling a newborn would bypass it; a caller that means it calls `ClanApi.join` afterwards.
##
## ## The child is minted through `set_actor_builder`, never inline
##
## The FIRST of the four steps, and the one with an injection point. The constructor comes from
## `app/` so the child is born with the same provider spine every other actor gets — health and
## stamina pools above all, without which a newborn cannot be damaged or healed. `app/` may not
## be named from here (`tools/arch/rules.py` PRIVATE_UNITS), so the seam IS the mechanism; see
## the module docstring for the full argument. With nothing installed the child is a bare
## `Actor`, exactly as it was before the seam existed, which is what keeps every headless
## lineage assertion unchanged. A builder that returns null is a wiring fault and fails out
## loud: silently falling back would reintroduce the poolless newborn the seam exists to
## prevent, and would do it invisibly.
static func resolve_offspring(mother: Actor, status: PregnancyStatus) -> Array[Actor]:
	if mother == null or status == null:
		return []
	var quality := mother.stats.derived(FertilityStats.OFFSPRING_QUALITY)
	var base := _combine(mother.stats.base_dict(), status.partner_base, quality)
	var child := _build_child(StringName("%s_offspring" % mother.id), base)
	if child == null:
		return []
	child.faction = mother.faction
	# Attach before resolving, so each ledger normalizes against the shipped catalog rather
	# than against whatever the child happens to be holding.
	RaceApi.attach(child)
	BloodlineApi.attach(child)
	RaceApi.set_race(child, RaceApi.resolve_race(mother, _race_holder(status), status.race_roll))
	var inherited := _inherited_purity(mother, status)
	for lineage_id in inherited.keys():
		BloodlineApi.set_purity(child, StringName(lineage_id), float(inherited[lineage_id]))
	return [child]


## Mint one child through the injected builder, or through the bare default when none is
## installed.
##
## The default is `Actor.new` and nothing else: no pool is invented here, because `core` owns
## the pool stats and the size rule (`Actor.attach_core_resources`, ADR 0025) and a second copy
## of that sizing would be a second thing to retune — the same argument the purity blend makes
## for not reimplementing `BloodlineApi.inherit_from`. The pools come from whoever injected the
## builder, and in the running game that is `ActorFactory.build`.
static func _build_child(actor_id: StringName, base: Dictionary) -> Actor:
	if _actor_builder.is_null():
		return Actor.new(actor_id, base)
	var built := _actor_builder.call(actor_id, base) as Actor
	if built == null:
		push_error(
			(
				(
					"FertilityApi: the installed actor builder returned null for '%s'; the pregnancy "
					+ "resolved to no child. Check the Callable installed by set_actor_builder."
				)
				% String(actor_id)
			)
		)
	return built


## The per-lineage concentration a child of these two parents starts with. The partner's half is
## read from the pregnancy's SNAPSHOT rather than from a live actor: birth does not require the
## partnership to still exist, and reading a live actor would make the outcome depend on who
## happens to still be around.
##
## The blend is delegated, never reimplemented. `BloodlineApi.inherit_from` takes two ACTORS, so
## the snapshot is replayed through two holders — which keeps the mean, the constants and ADR
## 0063's dilution curve in exactly one place, in the module that owns them. A second copy of
## the formula here would be a second thing to retune and would drift on the first retune.
static func _inherited_purity(mother: Actor, status: PregnancyStatus) -> Dictionary:
	var partner_holder := _purity_holder(status.partner_purity)
	var mother_holder := _purity_holder(purity_snapshot(mother))
	var lineage_ids := _lineage_ids(purity_snapshot(mother), status.partner_purity)
	var out := {}
	for lineage_id in lineage_ids:
		out[String(lineage_id)] = BloodlineApi.inherit_from(
			mother_holder, partner_holder, lineage_id
		)
	return out


## An actor carrying exactly `purity`, so the bloodline facade's actor-shaped verbs can be used
## on a snapshot. Deliberately raceless and statless: this holder exists only to answer "what
## would this lineage read as on a parent", and any other value it carried could leak into the
## child's own numbers.
static func _purity_holder(purity: Dictionary) -> Actor:
	var holder := Actor.new(&"")
	BloodlineApi.attach(holder)
	for key in purity.keys():
		BloodlineApi.set_purity(holder, StringName(key), float(purity[key]))
	return holder


static func _lineage_ids(a: Dictionary, b: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for key in a.keys():
		out.append(StringName(key))
	for key in b.keys():
		var lineage_id := StringName(key)
		if not out.has(lineage_id):
			out.append(lineage_id)
	out.sort()
	return out


## A stand-in actor carrying the partner's captured race, so `resolve_race` sees two parents
## without needing the partner to still exist. Attributes are deliberately empty: this actor
## exists only to answer "what race did the other parent hold", and giving it invented stats
## would let a snapshot leak into the child's attribute average.
static func _race_holder(status: PregnancyStatus) -> Actor:
	if status.partner_race == &"":
		return null
	var holder := Actor.new(&"")
	RaceApi.attach(holder)
	RaceApi.set_race(holder, status.partner_race)
	return holder


static func inherit_base(parent_a: Actor, parent_b: Actor, quality: float) -> Dictionary:
	var b_base := {} if parent_b == null else parent_b.stats.base_dict()
	return _combine(parent_a.stats.base_dict(), b_base, quality)


static func _combine(a_base: Dictionary, b_base: Dictionary, quality: float) -> Dictionary:
	var out := {}
	for id in a_base.keys():
		var a := float(a_base[id])
		var b := float(b_base.get(id, 0.0))
		out[id] = maxf(0.0, (a + b) * 0.5 * quality)
	for id in b_base.keys():
		if not out.has(id):
			out[id] = maxf(0.0, float(b_base[id]) * 0.5 * quality)
	return out


## One step of gestation for this body. Reads `gestation_days` from the mother's RACE now that
## reproduction parameters live there (ADR 0062); an actor with no race uses the published
## default, because a content gap is not a reason to stall a pregnancy.
static func _gestation_step(actor: Actor, delta: float) -> float:
	var days := _gestation_days(actor)
	if days <= 0.0:
		return 1.0
	return actor.stats.derived(FertilityStats.GESTATION_SPEED) * delta / days


static func _gestation_days(actor: Actor) -> float:
	var def := RaceApi.race_definition(actor)
	if def == null or def.gestation_days <= 0.0:
		return FertilityStats.DEFAULT_GESTATION_DAYS
	return def.gestation_days


static func _recovery_time(actor: Actor) -> float:
	return 10.0 / maxf(0.1, actor.stats.derived(FertilityStats.RECOVERY_RATE))
