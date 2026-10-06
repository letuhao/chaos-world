class_name TechniqueCasting
extends RefCounted

## Active execution: the per-technique cooldown table, the cost block, and the one
## action that fires an active technique (ADR 0053, ADR 0055, ADR 0056, DEF-0125).
##
## ## Why this is a component and not a facade method
##
## `TechniquesApi` names this the way it names `TechniqueUpkeep` — a component id on
## the actor, published as a constant on the facade rather than a method on it. ADR
## 0056 forced that shape with a twelve-verb cap that ADR 0265 removed; cohesion is
## what keeps it now, because the verb would forward straight into this component.
##
## ```
## var casting := actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting
## var fired := casting.activate(actor, def, target, resolver)
## ```
##
## ## Time belongs to the caller
##
## There is no `_process` and no `Time.get_ticks_*`. [method tick] takes an explicit
## `delta`, exactly as `EquipmentUpkeep.settle` takes an explicit interval rather
## than a clock of its own: this module is `RefCounted`, is never a node, and must
## stay testable without a scene tree. A cooldown that silently advanced between two
## assertions would be untestable and unreproducible.
##
## ## The damage pipeline is INJECTED, never named
##
## The hit itself belongs to `combat_engine` and this module writes no damage
## arithmetic at all — not even a copy of the base formula. `activate` takes a
## `resolver` Callable and the composition root binds the spine to it:
##
## ```
## casting.activate(actor, def, target,
##     func(a: Actor, t: Actor, d: TechniqueDef) -> Variant:
##         return CombatEngineApi.resolve_hit(a, t, d, CombatEngineApi.tuning(), rng))
## ```
##
## `app/` may depend on anything by construction (`tools/arch/rules.py`), so this is
## where the one legitimate edge between the two modules is made. Naming
## `CombatEngineApi` here instead would need `combat_engine` in this module's
## `registry.json` deps, and a bare class reference out of `modules/*` is not even
## an edge the checker sees (`BARE_REF_UNITS`), so it would have been an UNDECLARED
## dependency rather than a real one. The resolver keeps the seam honest: a caller
## that has no target, or no resolver, still fires and still pays — it simply gets an
## empty descriptor.
##
## ## What an activation owns, and what it must not touch
##
## It pays qi and stamina all-or-nothing, starts the cooldown at the rung the
## technique fired AT, resolves the hit, and then raises mastery by one rung —
## because ADR 0053's "mastery accrues through use" and because a refused activation
## taught the actor nothing. It never learns, never equips, never unequips, and never
## rebuilds a passive contribution: the three states stay three states, and using a
## technique is not an acquisition or a build choice.

## The `mastery_by` an ACTIVE technique's ladder is published under: a rung per
## fired activation, which is what `_grant_mastery` has always granted and what ADR
## 0053's "mastery accrues through use" means.
##
## Paired with `TechniqueUpkeep.MASTERY_BY` (ADR 0247), which is the passive's. Both
## are published so the codex screen can say which of the two a row is climbed by
## rather than printing the same ladder for a technique that fires and one that
## cannot — the read model picks between them, and the settle loop is the thing that
## has to agree.
const MASTERY_BY := &"cast"

## The pool ids an activation drains. Core owns both: stamina is a core pool
## (ADR 0025) and qi is the path's reservoir, which is created by the qi module and
## read here through `Actor.resource`.
const QI_POOL := &"qi"
const STAMINA_POOL := &"stamina"

## The module's own persistence key, a SIBLING of `TechniqueCodex.STATE_KEY` rather
## than a field inside it. A cooldown is a fact about this moment, the codex is a
## fact about the actor forever, and folding one into the other's payload would make
## a v1 codex save carry a shape it was never written against.
const STATE_KEY := &"technique_cooldowns"
const VERSION := 1

## `Stat.COOLDOWN_REDUCTION`'s clamp, the same 0.4 `core/actor_stats.gd` derives it
## under. Re-clamped here because `_put` composes PERCENT and MULT on top of that
## baseline, so a build can author a derived value well past 0.4 — and a reduction
## over 1.0 would make a cooldown negative, which is a technique that is permanently
## ready rather than a defensive stat.
const REDUCTION_CAP := 0.4

## `QiStats.TECHNIQUE_COST_REDUCTION`'s own clamp — the 0.5
## `modules/qi_cultivation/provider.gd` clamps its contribution under, and the same
## 0.5 core derives `Stat.QI_COST_REDUCTION` under.
##
## A SEPARATE constant from `REDUCTION_CAP` rather than a shared one, and the
## difference is authored rather than accidental: the cooldown's ceiling is 0.4
## because a longer one is a defensive stat approaching immunity (ADR 0068), while
## this one is a PRICE and its whole job is to stop a cast being able to pay
## negative qi. Reusing 0.4 would have quietly made a qi reduction authored between
## 0.4 and 0.5 read as 0.4 — a rate that exists, is authored, and would be
## discarded by a constant borrowed from a different quantity.
const COST_REDUCTION_CAP := 0.5

## `QiStats.TECHNIQUE_COST_REDUCTION` — the qi module's published rate, spelled
## here as data rather than as a class reference so this module declares no edge
## into one it does not depend on. See [method cost_reduction_of].
const TECHNIQUE_COST_REDUCTION_ID := &"technique_cost_reduction"

## `QiStats.TECHNIQUE_POWER` — the qi module's published multiplier, spelled on
## the same terms and for the same reason as the cost id above.
const TECHNIQUE_POWER_ID := &"technique_power"

## Affordability is compared with a tolerance so a pool holding exactly the cost pays
## rather than being short by one float ULP.
const EPSILON := 0.000001

## The composition root's damage seam, for a caller that does not pass one per call:
## `func(attacker: Actor, target: Actor, def: TechniqueDef) -> Variant`.
##
## A `static var` rather than a component, because the binding is a fact about how
## this process was wired rather than about any one actor — the same shape
## `TechniqueDelivery.install` and `NpcApi.set_minter` use. `app/` installs it once;
## a suite that installs one clears it in `teardown`, because `run_tests.gd` calls
## `teardown` after EVERY test precisely because a process-wide binding leaks
## between suites otherwise.
static var _installed_resolver: Callable = Callable()

## technique_id (String) -> `[seconds_left, seconds_total]`. Absent means ready.
##
## The pair, not a bare number, because a cooldown is only meaningful against its own
## length: `ratio` is the share a bar draws, and a bare remainder would have to
## re-derive the total from a mastery rung that moves every time the technique fires.
var _remaining: Dictionary = {}


func _init(payload: Dictionary = {}) -> void:
	_remaining = TechniqueCasting.migrate(payload)


## Install the resolver [method activate] falls back to when its caller passes
## none. Passing an empty Callable clears it, so an uninstall is deterministic
## rather than only an overwrite.
static func set_resolver(resolver: Callable) -> void:
	_installed_resolver = resolver


## Whether a fallback resolver is installed, so a caller can say "no target" and
## "no spine" as two different messages rather than one empty descriptor.
static func has_resolver() -> bool:
	return not _installed_resolver.is_null() and _installed_resolver.is_valid()


# --- Persistence: ids and numbers, never a definition --------------------------


## Bring any stored payload up to the current shape. A payload with no version, and
## no entries at all, loads as an empty table rather than failing — same rule the
## codex follows, so a save written before cooldowns existed loads unchanged.
static func migrate(payload: Dictionary) -> Dictionary:
	var out := {}
	for raw in payload.get("entries", []):
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var technique_id := StringName(row.get("id", ""))
		if technique_id == &"":
			continue
		var left := maxf(0.0, float(row.get("remaining", 0.0)))
		if left <= 0.0:
			continue
		var total := maxf(left, float(row.get("total", 0.0)))
		out[String(technique_id)] = [left, total]
	return out


## The persisted snapshot: a version and a flat Array of `{id, remaining, total}`
## rows. ADR 0056's rule in its most literal form — a designer retuning `cooldown` on
## a `.tres` must not rewrite every existing save, so no AUTHORED field is stored,
## only the technique id and the two numbers the actor was actually charged. `total`
## is the running cooldown's own length, not `def.cooldown`: re-deriving it from the
## def on load would quote the current tuning rather than the one the actor paid
## under, and a bar drawn against the wrong total is a bar that lies.
func to_dict() -> Dictionary:
	var ids: Array = []
	for technique_id in _remaining.keys():
		ids.append(technique_id)
	ids.sort()
	var entries: Array = []
	for technique_id in ids:
		(
			entries
			. append(
				{
					"id": String(technique_id),
					"remaining": float(_remaining[technique_id][0]),
					"total": float(_remaining[technique_id][1]),
				}
			)
		)
	return {"version": VERSION, "entries": entries}


static func from_dict(payload: Dictionary) -> TechniqueCasting:
	return TechniqueCasting.new(payload)


## Copy the snapshot onto the actor. Called after every mutation, so the persisted
## cooldown can never lag the live one — which is the whole point of persisting it
## instead of keeping it in a session-only table.
func commit(actor: Actor) -> void:
	if actor != null:
		actor.set_module_data(STATE_KEY, to_dict())


# --- The tick, driven by the caller --------------------------------------------


## Advance every running cooldown by `delta` SECONDS. Returns the technique ids that
## came off cooldown on this tick, so a caller repaints only those.
##
## `delta` is required and is never read from a clock. A negative or zero delta is
## ignored rather than treated as time running backwards, so a mis-driven loop cannot
## re-arm a cooldown that has already expired.
func tick(actor: Actor, delta: float) -> Array[StringName]:
	var expired: Array[StringName] = []
	if delta <= 0.0 or _remaining.is_empty():
		return expired
	for raw_id in _remaining.keys():
		var technique_id := StringName(raw_id)
		var left := maxf(0.0, float(_remaining[raw_id][0]) - delta)
		if left <= 0.0:
			_remaining.erase(raw_id)
			expired.append(technique_id)
		else:
			_remaining[raw_id] = [left, float(_remaining[raw_id][1])]
	commit(actor)
	return expired


## Seconds still owed on `technique_id`, or 0.0 when it is ready.
func remaining(technique_id: StringName) -> float:
	if not _remaining.has(String(technique_id)):
		return 0.0
	return float(_remaining[String(technique_id)][0])


## The length of the cooldown currently running, or 0.0 when none is. The number
## that running cooldown STARTED at, never `duration_for` — see [method to_dict].
func running_total(technique_id: StringName) -> float:
	if not _remaining.has(String(technique_id)):
		return 0.0
	return float(_remaining[String(technique_id)][1])


func is_ready(technique_id: StringName) -> bool:
	return remaining(technique_id) <= 0.0


## How much of the cooldown that is actually running one technique still owes, `1.0`
## just used and `0.0` ready. The number a cooldown bar renders, so the bar never
## restates the formula and never divides by a rung that moved since the cast.
##
## `_actor` is accepted and unread because the record is keyed by technique id, not
## per hero: there is one hero, so a second argument would be a second source of
## truth about whose cooldown this is. Callers pass it positionally, so it stays.
func ratio(_actor: Actor, def: TechniqueDef) -> float:
	if def == null or not _remaining.has(String(def.id)):
		return 0.0
	var total := float(_remaining[String(def.id)][1])
	if total <= 0.0:
		return 0.0
	return clampf(float(_remaining[String(def.id)][0]) / total, 0.0, 1.0)


## Drop a technique's record, for content that is no longer a technique at all.
## Deliberately NOT called on unequip: a cooldown is an escape timer, so swapping a
## technique out and back in must not hand the player a second free cast.
func forget(technique_id: StringName) -> void:
	_remaining.erase(String(technique_id))


# --- The scaled numbers --------------------------------------------------------


## The actor's cooldown reduction, clamped. `Stat.COOLDOWN_REDUCTION` is a RATE with
## a `0.0` baseline and a 0.4 cap (`core/actor_stats.gd:170`); a FLAT modifier is the
## only form that can move it, and the clamp is re-applied here because a PERCENT or
## MULT modifier composes past the derived cap.
static func reduction_of(actor: Actor) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return clampf(actor.stats.derived(Stat.COOLDOWN_REDUCTION), 0.0, REDUCTION_CAP)


## How many seconds one activation of `def` costs the actor: the authored cooldown,
## times ADR 0055's per-rung `COOLDOWN_STEP` (0.96^n), times one minus the reduction.
## The mastery multiplier comes FIRST, so a rung-4 technique at the 0.4 cap still
## clears 0.5 and no rung is ever a trap rung (ADR 0055's own guard).
func duration_for(actor: Actor, def: TechniqueDef) -> float:
	if actor == null or def == null:
		return 0.0
	var authored := maxf(0.0, def.cooldown)
	if authored <= 0.0:
		return 0.0
	var multipliers := TechniqueScales.multipliers_at(_rung_of(actor, def), def.mastery_rungs)
	return authored * float(multipliers["cooldown"]) * (1.0 - reduction_of(actor))


## The actor's TECHNIQUE cost reduction, clamped. `QiStats.TECHNIQUE_COST_REDUCTION`
## is published by `QiProvider` as `clamp(qi_control * 0.002, 0.0, 0.5)` — a 0..1
## SHARE, the same shape as the `Stat.COOLDOWN_REDUCTION` above, which is why the
## two share a cap constant and a read shape rather than each inventing one.
##
## ## Why the clamp is re-applied here when the provider already clamps
##
## The provider clamps its OWN contribution. `ActorStats` composes the modifier
## stack ON TOP of that (ADR 0026), and a FLAT modifier is added after the cap —
## which is precisely the ADR 0039 content error, and precisely why the shipped
## `cult_technique_cost_reduction` option declares `op: PERCENT`. Re-clamping is
## what makes a bad author still pay a real, bounded price instead of a negative
## one: at a reduction of 1.0 the cast is FREE, and past it the cost floors at
## zero rather than paying the actor qi.
##
## ## Why this id and not core's `Stat.QI_COST_REDUCTION`
##
## Both exist and both are 0..1 shares, and reading the wrong one is a silent
## no-op: core's baseline is `minf(0.5, aptitude * 0.001)`, and reaching any of
## it needs aptitude 500 while every authored stat tops out an order of magnitude
## below that, so core's reads `0.0` for EVERY actor this game can build (see
## `Stat.RATE_STATS`'s own docstring and ADR 0022). The qi provider's is the one
## a cultivation actually moves, and the one the authored option targets.
##
## ## Why the id is a LOCAL STRING and not `QiStats.TECHNIQUE_COST_REDUCTION`
##
## Naming that constant would put a compile-time edge from this module into
## `qi_cultivation`, which `registry.json` does not list among this module's
## deps. The discipline `CombatTuning` already uses for exactly this problem is
## adopted here: a module-owned stat id is a STRING in the consuming module,
## spelled once, because the VALUE is data and the vocabulary belongs to whoever
## published it. `test_technique_provider_stats.gd` asserts each literal equals
## its `QiStats` constant, so the two spellings cannot drift — the string costs
## no edge and the test is what makes it safe. The alternative, widening
## `registry.json` and taking a dependency on a module at its own facade cap for
## two id constants, buys nothing.
static func cost_reduction_of(actor: Actor) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return clampf(actor.stats.derived(TECHNIQUE_COST_REDUCTION_ID), 0.0, COST_REDUCTION_CAP)


## The qi one activation costs, at ADR 0055's per-rung `QI_COST_STEP` (0.94^n),
## times one minus the actor's technique cost reduction.
##
## Stamina is NOT scaled: ADR 0055 publishes a qi-cost column and no stamina
## column, so there is no rung multiplier for it and inventing one here would be
## a second ladder disagreeing with the ADR. Nor is stamina reduced — a reduction
## is authored against qi, and applying it to a second pool would be a discount
## nobody wrote.
##
## ## The ORDER of the two multipliers, and why it is this one
##
## The rung's `qi_cost` comes FIRST and the reduction LAST, exactly as
## [method duration_for] puts the rung's cooldown before the cooldown reduction.
## The reason is that the reduction is the only unbounded-of-the-two term: it is
## driven by a stat a player allocates, while the rung ladder is ADR 0055's own
## bounded column. Reading it first would let a reduction near the cap discount
## the discounted cost, so two such casts would compound toward free.
func qi_cost_for(actor: Actor, def: TechniqueDef) -> float:
	if actor == null or def == null:
		return 0.0
	var authored := maxf(0.0, def.qi_cost)
	if authored <= 0.0:
		return 0.0
	var multipliers := TechniqueScales.multipliers_at(_rung_of(actor, def), def.mastery_rungs)
	return authored * float(multipliers["qi_cost"]) * (1.0 - cost_reduction_of(actor))


## ## The actor's raw published `technique_power` — and why NOTHING here multiplies
## by it yet
##
## The read exists; the spend deliberately does not, and that is DEF-0101's honest
## answer for this stat. The boundary is the reason, not an omission.
##
## `CombatSpine.base_damage` (`combat_engine/spine.gd:194-200`) is the only place
## in the game that turns a technique into a number a hit is built on, and it
## reads `technique.magnitude`:
##
## ```
## var base := technique.magnitude
## base *= RealmRate.factor(attacker.realm())
## ```
##
## It already holds BOTH the attacker and the technique, so it is the correct
## owner of a "technique power" multiplier — and `combat_engine` is not this
## module's to edit, nor a dep `registry.json` declares, so this module cannot
## reach it.
##
## The tempting wrong answer, which stays inside this lane, is to hand the
## resolver a copy of `def` with its magnitude pre-scaled. It is refused for a
## reason that is observable rather than stylistic: `CombatBoot.resolve_hit` is
## called DIRECTLY by `app/` and by other modules for hits that never pass
## through `TechniqueCasting.activate`. A stat applied only on the technique
## route is a stat that is on for one route and off for the same actor's next
## technique-driven hit from any other — the same "one stat, two answers" hazard
## DEF-0101 describes, arriving from the other direction.
##
## ## And it must NOT become a second multiplier inside this module either
##
## ADR 0160 already scales a PASSIVE's authored stat values by
## `TechniqueScales.multipliers_at(rung)["power"]`. Scaling an ACTIVE's magnitude
## by a provider stat as well puts two multipliers on the base of one hit whose
## subjects differ only in which technique granted what — precisely the shape of
## the capacity-channel double-count ADR 0160 refuses.
##
## So this publishes the number under the name that says what it is, and no
## quantity in this module is scaled by it. `test_technique_provider_stats.gd`
## pins the reader census that keeps the gap visible rather than forgotten.
##
## ## What the stat IS, precisely
##
## The provider contributes `(1.0 + qi_affinity * 0.05) * RealmRate.factor`, so
## the value is `1.0` for an actor with no affinity, never below it, and it
## carries a realm-rate term. It is therefore a MULTIPLIER already — 1.0 meaning
## "unchanged" — not a 0..1 share. That is why the shipped `cult_technique_power`
## option declares `op: PERCENT` (ADR 0039 licenses PERCENT on a 1.0-baseline
## multiplier and forbids FLAT, which would ADD to a factor) and why a consumer
## must multiply by it DIRECTLY rather than treating it as `1 + value`. Reading it
## as `1 + value` would double every technique's damage for an actor with no qi
## affinity at all.
static func power_rate(actor: Actor) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return maxf(0.0, actor.stats.derived(TECHNIQUE_POWER_ID))


## Every pool this activation drains and how much, so the afford check and the pay
## read ONE table and can never disagree about what was owed.
func charges_for(actor: Actor, def: TechniqueDef) -> Dictionary:
	var out := {}
	if def == null:
		return out
	var qi := qi_cost_for(actor, def)
	if qi > 0.0:
		out[QI_POOL] = qi
	var stamina := maxf(0.0, def.stamina_cost)
	if stamina > 0.0:
		out[STAMINA_POOL] = stamina
	return out


# --- The action -----------------------------------------------------------------


## Fire `def`. Refuses with `{ok: false, reason, id, ...}` and changes NOTHING when
## the technique is not equipped, is a passive, is still on cooldown, or cannot pay
## every pool. On success it pays, starts the cooldown, resolves the hit through
## `resolver`, and raises mastery by one rung.
##
## `resolver` is the composition root's damage seam — see the file header. It is
## called AFTER the payment, because the qi is spent whether the swing lands or not,
## and ADR 0053's "mastery accrues through use" counts a whiffed swing as a use.
##
## When the caller passes no `resolver`, the INSTALLED one is used — the
## process-wide binding [method set_resolver] publishes. That fallback exists
## because a per-call argument alone leaves the module unreachable from
## production: every caller would have to re-derive the spine binding, and
## `app/` cannot be named from a `ui/` screen (`PRIVATE_UNITS` in
## `tools/arch/rules.py` makes `app/` referenceable only from itself). A per-call
## argument still WINS, so a caller that wants its own rng — a replay, a test — is
## never overruled by the installed default.
func activate(
	actor: Actor, def_or_id, target: Actor = null, resolver: Callable = Callable()
) -> Dictionary:
	var def := _as_def(def_or_id)
	if actor == null or def == null:
		return _refused(&"unknown_definition", &"")
	if not TechniquesApi.slots(actor).is_equipped(def.id):
		return _refused(&"not_equipped", def.id)
	# A passive is ADR 0054's contribution, not an action: it has no cost block and no
	# cooldown, and asking it to fire is a mistake worth naming rather than a silent
	# no-op that would pay nothing and look like it worked.
	if def.is_passive():
		return _refused(&"not_active", def.id)
	var left := remaining(def.id)
	if left > 0.0:
		# The duration reported is the one the STARTED cooldown was, carried on the
		# record, never one re-derived from `duration_for` — that would read the rung
		# the last firing just earned and quote a number that was never owed. A
		# rung-0 technique that just fired owes ten seconds against a ten second
		# cooldown, even though it is rung 1 now and a fresh cast would cost 9.6.
		var cooling := _refused(&"on_cooldown", def.id)
		cooling["cooldown_remaining"] = left
		cooling["cooldown_duration"] = running_total(def.id)
		return cooling
	# All-or-nothing: every pool is checked before ANY pool is drained, which is the
	# same shape `EquipmentUpkeep._pay` uses. Paying qi and then discovering the
	# stamina was short would be a technique that costs resources and does nothing.
	var charges := charges_for(actor, def)
	var short := _short(actor, charges)
	if not short.is_empty():
		var broke := _refused(&"insufficient_resources", def.id)
		broke["short"] = short
		return broke
	for pool_id in charges.keys():
		actor.change_resource(StringName(pool_id), -float(charges[pool_id]))
	var started := duration_for(actor, def)
	if started > 0.0:
		_remaining[String(def.id)] = [started, started]
	commit(actor)
	var damage := _resolve(actor, target, def, _seam_for(resolver))
	var rung := _grant_mastery(actor, def)
	return {
		"ok": true,
		"id": String(def.id),
		"fired": true,
		"paid": charges,
		"cooldown": started,
		"cooldown_remaining": started,
		"rung": rung,
		"damage": damage,
		"resolved": not damage.is_empty(),
	}


## What this activation still owes, for a refusal that says so.
func cooldown_view(actor: Actor, def: TechniqueDef) -> Dictionary:
	if def == null:
		return {"cooldown_remaining": 0.0, "cooldown_duration": 0.0, "cooldown_ratio": 0.0}
	return {
		"cooldown_remaining": remaining(def.id),
		"cooldown_duration": running_total(def.id),
		"cooldown_ratio": ratio(actor, def),
		# What a cast WOULD cost right now at the actor's current rung — the other
		# number, and deliberately not the one above.
		"cooldown_next": duration_for(actor, def),
	}


# --- internals ------------------------------------------------------------------


## The resolver this call will use: the caller's own when it passed one, else the
## installed composition-root seam. A per-call argument WINS, always — the fallback
## exists only so production has a spine, and it must never quietly overrule a
## caller that injected a specific one (a replay's rng, a test's recorder).
func _seam_for(resolver: Callable) -> Callable:
	if not resolver.is_null() and resolver.is_valid():
		return resolver
	return _installed_resolver


## Every pool this activation cannot pay, with what it owed and what it held. Checked
## whole before anything moves.
func _short(actor: Actor, charges: Dictionary) -> Array:
	var out: Array = []
	for pool_id in charges.keys():
		var amount := float(charges[pool_id])
		var pool := actor.resource(StringName(pool_id))
		var available := 0.0 if pool == null else pool.current
		if available + EPSILON >= amount:
			continue
		out.append({"resource": String(pool_id), "required": amount, "current": available})
	return out


## Run the composition root's damage seam and hand back what it produced, verbatim.
##
## Nothing here interprets the result and nothing here computes a number of its own:
## a `Dictionary` is the descriptor already, an object answering `to_dict()` is
## `CombatOutcome` in its own shape, and a bare number is a preview that reported an
## amount. Anything else is no descriptor, and the empty dictionary says so rather
## than guessing.
func _resolve(actor: Actor, target: Actor, def: TechniqueDef, resolver: Callable) -> Dictionary:
	if target == null or not resolver.is_valid():
		return {}
	var produced: Variant = resolver.call(actor, target, def)
	if produced is Dictionary:
		var descriptor: Dictionary = produced
		return descriptor
	if produced is float or produced is int:
		return {"amount": float(produced)}
	if produced is Object:
		var object := produced as Object
		if object.has_method(&"to_dict"):
			var read: Variant = object.call(&"to_dict")
			if read is Dictionary:
				var descriptor: Dictionary = read
				return descriptor
	return {}


## Mastery moves by ONE rung per fired activation and never past the def's authored
## `mastery_rungs`, so a capped technique simply stops climbing rather than banking
## a rung it cannot spend. Called only after a successful activation: a refusal
## teaches the actor nothing, and a study cost paid for nothing is worse than none.
func _grant_mastery(actor: Actor, def: TechniqueDef) -> int:
	var codex := TechniquesApi.codex(actor)
	var rung := int(codex.row(def.id).get("rung", 0))
	var reached := TechniqueScales.rung_for(rung + 1, def.mastery_rungs)
	if reached <= rung:
		return rung
	# The codex and the slot table share ONE payload, so the whole snapshot has to be
	# rewritten whenever a rung moves — writing only the codex half would drop every
	# equipped binding on the next load (DEF-0154). The commit is reached through the
	# facade's own `raise_mastery`, which performs set + commit + rebuild together.
	# The rung is therefore NOT set locally first: that would make `set_rung` inside
	# the facade return false and skip the commit entirely.
	var applied := TechniquesApi.raise_mastery(actor, def.id, reached)
	return int(applied.get("rung", reached)) if bool(applied.get("ok", false)) else reached


func _rung_of(actor: Actor, def: TechniqueDef) -> int:
	var entry_rung := int(TechniquesApi.codex(actor).row(def.id).get("rung", 0))
	return TechniqueScales.rung_for(entry_rung, def.mastery_rungs)


static func _as_def(def_or_id) -> TechniqueDef:
	if def_or_id is TechniqueDef:
		return def_or_id
	return TechniqueCatalog.instance().definition(StringName(def_or_id))


func _refused(reason: StringName, technique_id: StringName) -> Dictionary:
	return {"ok": false, "fired": false, "reason": String(reason), "id": String(technique_id)}
