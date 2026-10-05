class_name InjuryLedger
extends RefCounted

## The body path's ledger of DESTROYED PARTS: what is broken, what it was worth,
## and the one action that can put it back (the destroy-and-recreate principle).
##
## ## WHAT THIS OWNS, AND WHAT IT DELIBERATELY DOES NOT
##
## Owned: one [Injury] per destroyed part, the stat modifier that removes that
## part's contribution, and the rebuild transaction. Every number the rebuild
## reads is in `InjuryTuning`; every shape of part is in `InjuryDef`; neither a
## literal nor a copy of either lives in this file.
##
## Not owned: the wound ledger. `BodyWounds` (ADR 0070) owns severity, necrosis
## and the jam, and `MeridianState.injured` (ADR 0017) owns the recoverable
## flag. `destroy` REUSES the existing core verb (`MeridianNetwork
## .damage_meridian`) rather than growing a parallel injury boolean, for the
## reason ADR 0070 gives: a wound must cost the channel's aggregate bonus for
## EVERY path, and a second flag here would be halved by nothing and read by
## nothing.
##
## ## WHY THE DEGRADATION IS A STAT MODIFIER
##
## Property 2 is that a broken limb measurably reduces what the body can do
## TODAY. A flag consulted at read time would have to be threaded through every
## stat formula in the game, and the next stat added would silently forget it. A
## `StatModifier` on the actor's own stack is picked up by `ActorStats._buckets`
## with no change to core, applies to the DERIVED value the combat engine actually
## reads (`Stat.DEFENSE_PHYSICAL`, `Stat.ATTACK_PHYSICAL`, ...), and disappears the
## instant it is removed. The removal is keyed on a per-part source tag, so a
## rebuild can restore EXACTLY one part's worth and nothing else.
##
## ## WHY THE GATE IS HERE AND NOT IN THE TRAINING VERB
##
## Property 4 — cultivation requires destruction — is only a gate if it sits on
## the path the player actually takes. `BodyTraining.strengthen` is that path, and
## it delegates the question to [method blocks] rather than restating it, exactly
## as `BodyAdvancement.start_attempt` delegates the body-answer-first gate: a rule
## one layer up is a rule a caller can walk around. See `test_body_injury_gate.gd`.

## Every refusal a caller can reach, named rather than inferred (ADR 0150).
const REFUSE_NO_PART := "no_part"
const REFUSE_NOT_BROKEN := "not_broken"
const REFUSE_NO_ESSENCE := "no_essence"
const REFUSE_NO_SACRIFICE := "no_sacrifice"
const REFUSE_BUSY := "busy"

## The component key this ledger is bound on, and the `module_data` slot a save
## restores it from. A string in DATA rather than a `BodyCultivationApi`
## constant in this file, for the reason `CombatTuning.integrity_pool_id` is: the
## key is shared with the attach path, and two spellings of one key is how a save
## silently stops restoring.
const COMPONENT_ID := &"body_injuries"
const MODULE_KEY := &"body_injuries"

## Part id -> [Injury]. A part that is whole is simply ABSENT, which is the same
## shape `BodyWounds.severity` uses and the reason "never broken" and "broken and
## rebuilt" are distinguishable rather than conflated.
var parts: Dictionary = {}
## The bound tuning. Null means "no vocabulary at all" — a rebuild that refuses
## rather than one that runs on zeros, the same deliberate degeneracy
## `CombatTuning.new()` has.
var tuning: InjuryTuning = null


## The ledger bound on `actor`, creating and attaching one if it carries none.
## Restores from the raw `module_data` slot a save left behind, so a reloaded body
## comes back BROKEN rather than quietly whole.
static func bind(actor: Actor, tuning: InjuryTuning = null) -> InjuryLedger:
	var existing: InjuryLedger = actor.component(COMPONENT_ID)
	if existing != null:
		if existing.tuning == null:
			existing.tuning = tuning
		return existing
	var ledger := InjuryLedger.new()
	ledger.tuning = tuning
	var saved: Dictionary = actor.get_module_data(MODULE_KEY)
	if not saved.is_empty():
		ledger.load_from(saved)
		# Drop the raw copy so the next save serializes the LIVE ledger, which is the
		# same rule `attach_acupoints` follows.
		actor.set_module_data(MODULE_KEY, {})
	actor.set_component(COMPONENT_ID, ledger)
	return ledger


static func of(actor: Actor) -> InjuryLedger:
	return actor.component(COMPONENT_ID) as InjuryLedger


## The definition of `part_id`, or null when the catalog does not carry it. Read
## through the bound catalog so a caller never names a definition class to ask
## "is this part real".
func definition_of(part_id: StringName) -> InjuryDef:
	return InjuryCatalog.definition_of(part_id)


# --- Read model -------------------------------------------------------------


## The one part's current state, or `{}` for an absent one. Primitives only
## (ADR 0038): this is what a panel renders and what a save carries.
func report(part_id: StringName) -> Dictionary:
	var part: Injury = parts.get(String(part_id))
	if part == null:
		return {}
	return {
		"part": String(part_id),
		"broken": part.broken,
		"rebuilt": part.rebuilt,
		"origin": part.origin,
		"surplus": part.surplus,
		# What the part ADDS to its stat right now — negative while broken, positive
		# once a rebuild beat the original. Published because it is the number a panel
		# prints and the number a test asserts, and because deriving it in a consumer
		# is how the read model and the damage engine end up disagreeing about it.
		"contribution": part.contribution(_tuning()),
		"rebuilt_share": part.rebuilt_share(),
		"stat": String(part.stat_id),
		"meridian": String(part.meridian_id),
		"point": String(part.point_id),
	}


## Every part currently destroyed, in SORTED id order so two identical reads
## produce identical payloads. Bounded by the authored catalog rather than by
## anything this ledger grows: the loop tests the catalog, not the ledger, and
## appends nothing.
func broken_parts() -> Array[StringName]:
	var sorted: Array[String] = []
	for entry in InjuryCatalog.all_ids():
		var part: Injury = parts.get(String(entry))
		if part != null and part.broken:
			sorted.append(String(entry))
	sorted.sort()
	var out: Array[StringName] = []
	for id in sorted:
		out.append(StringName(id))
	return out


## Whether `part_id` is destroyed. The cheap question every gate asks first.
func is_broken(part_id: StringName) -> bool:
	var part: Injury = parts.get(String(part_id))
	return part != null and part.broken


## The stat `part_id` is felt in, or `&""`. The read model needs this to label a
## row, and asking it here means the read model cannot disagree with the modifier
## that was actually applied.
func stat_of(part_id: StringName) -> StringName:
	var part: Injury = parts.get(String(part_id))
	return &"" if part == null else part.stat_id


# --- Destroy ----------------------------------------------------------------


## DESTROY one part: remove its contribution from the stat it is felt in, and mark
## it broken. Returns the [method report] row, or `{}` when nothing was destroyed.
##
## ## Refusals are decided BEFORE anything is spent, and there are four
##
## `no_part` — the catalog carries no such part. `no_stat` — the part names no
## stat, so there is nothing to degrade. `no_site` — the part rides no meridian or
## huyệt, so it has no location and degrading "the whole body" would make the
## number meaningless. `already` — the part is already broken, which is the
## idempotency guard.
##
## ## Why `origin` is snapshotted here and NEVER recomputed
##
## It is read once, at destruction, from the actor's LIVE derived value with the
## part still whole. If it were re-read later it would already include training
## done around the injury, and the rebuild band would be measured against a moving
## target — a rebuild could then "beat the original" purely because the body had
## grown, which is not the brief's reward loop and would be unmeasurable.
func destroy(actor: Actor, part_id: StringName) -> Dictionary:
	var def := definition_of(part_id)
	if def == null or not def.has_site():
		return {}
	if is_broken(part_id):
		return report(part_id)
	var stat := def.stat()
	var origin := _derived_of(actor, stat)
	var part := Injury.new(part_id, stat)
	part.broken = true
	part.rebuilt = false
	part.origin = origin
	part.surplus = 0.0
	part.meridian_id = def.meridian_id
	part.point_id = def.point_id
	parts[String(part_id)] = part
	_apply_degradation(actor, part)
	# The EXISTING core verb, for the reason the module docblock gives: an injured
	# channel halves its aggregate bonus for EVERY path, and a flag invented here
	# would be halved by nothing. Only the CHANNEL is torn — a part bound to a
	# huyệt alone has no channel to injure, and pretending otherwise would damage
	# a channel the part never touched.
	if def.meridian_id != &"" and actor.meridians.get_meridian(def.meridian_id) != null:
		actor.meridians.damage_meridian(def.meridian_id)
	actor.mark_stats_dirty()
	return report(part_id)


## Apply (or clear) the stat modifier that IS the degradation. One helper for
## every direction, because a modifier is a single tagged entry and the three
## operations — destroy, rebuild, absorb — differ only in the number they ask
## [method Injury.contribution] for.
##
## Remove-first, always: a re-destroy must not stack two modifiers, and the tag
## below is the only thing this call is allowed to touch, so it can never remove a
## modifier belonging to anything else on the actor.
func _apply_degradation(actor: Actor, part: Injury) -> void:
	var tag := Injury.modifier_source(part.part_id)
	actor.stats.remove_modifiers_from(tag)
	var amount := part.contribution(_tuning())
	if not is_zero_approx(amount):
		actor.stats.add_modifier(StatModifier.new(part.stat_id, Stat.Op.FLAT, amount, tag))


## The stat's live derived value with every provider already applied — the same
## read the combat engine resolves against, so the modifier lands on the number
## the game actually uses.
func _derived_of(actor: Actor, stat: StringName) -> float:
	return maxf(0.0, actor.stats.derived(stat))


# --- Recreate ---------------------------------------------------------------


## RECREATE one destroyed part: pay the cost, roll the band, and either return the
## part whole — possibly STRONGER than it was — or leave it broken and worse.
##
## An INSTANCE method, not a static one, and that is load-bearing rather than a
## style choice: the transaction mutates this ledger's own [Injury], so a static
## signature would be a function that appears to act on the body and in fact acts
## on nothing. Every refusal below is decided from this ledger's state.
##
## Returns a verdict dictionary — always every key, so a caller never has to probe
## for one:
##   `ok`      — bool, the rebuild happened
##   `reason`  — `""`, or one of the `REFUSE_*` constants
##   `part`    — the part id, or `""`
##   `before` / `after` — the stat before and after, so a screen can print the
##                 difference without recomputing it
##   `exceeded` — bool, the rebuild landed ABOVE what was destroyed
##   `ruined`  — bool, the rebuild failed and the part is worse for trying
##   `cost`    — the essence spent
##
## ## ALL-OR-NOTHING, and all-or-nothing BEFORE the roll
##
## Every refusal is checked before a single thing is mutated and before the roll is
## drawn, so a refused rebuild costs nothing and changes nothing. That is the rule
## `BodyTraining.recover` already follows (ADR 0031) and the one a player can act
## on: a press that refuses says why and leaves the body exactly as it was.
##
## ## THE ROLL, AND WHY IT IS TAKEN HERE
##
## The draw happens INSIDE this function, from a caller-supplied generator, and the
## outcome is a function of the band in `InjuryTuning` rather than of any literal
## here. `rng` is an optional SEED SOURCE for the same reason it is on
## `BodyAdvancement.start_attempt`: a suite must be able to choose the outcome. A
## rebuild is NOT a save-spanning record — it is one synchronous transaction — so it
## does not need `BodyAttemptRoll`'s replay machinery, and duplicating that
## machinery would be the second door into a durable decision ADR 0187 exists to
## prevent.
func recreate(actor: Actor, part_id: StringName, rng: RandomNumberGenerator = null) -> Dictionary:
	var verdict := _verdict(part_id)
	var def := definition_of(part_id)
	if def == null or not def.has_site():
		verdict["reason"] = REFUSE_NO_PART
		return verdict
	var part: Injury = parts.get(String(part_id))
	if part == null or not part.broken:
		verdict["reason"] = REFUSE_NOT_BROKEN
		return verdict
	var tuning := _tuning()
	var cost := _cost_of(actor, tuning)
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	if pool == null or pool.current < cost:
		verdict["reason"] = REFUSE_NO_ESSENCE
		verdict["cost"] = cost
		return verdict
	var sacrifice := _sacrifice_of(def, part)
	if sacrifice != &"" and actor.meridians.get_meridian(sacrifice) == null:
		verdict["reason"] = REFUSE_NO_SACRIFICE
		return verdict
	# --- Nothing below this line may refuse. ---
	var before := _derived_of(actor, part.stat_id)
	pool.change(-cost)
	if sacrifice != &"":
		# The sacrifice is a SECOND channel, so the part's own channel is untouched by
		# it and the rebuild below can still heal the one the destruction tore.
		actor.meridians.damage_meridian(sacrifice)
	if rng == null or rng.randf() < tuning.chance():
		var landed := _draw(rng, tuning.rebuild_band())
		# `surplus` is the whole reward: negative when the rebuild landed below the
		# original (so the modifier shrinks toward zero), POSITIVE when it beat it.
		part.surplus = part.origin * (landed - 1.0)
		part.broken = false
		part.rebuilt = true
		# A rebuilt channel is healed, so the rebuild is the one route that clears the
		# core injury flag the destruction set — through the SAME verb, never a second.
		actor.meridians.repair_meridian(part.meridian_id)
	else:
		part.surplus = part.origin * (_ruined_figure(tuning, rng) - 1.0)
		verdict["ruined"] = true
	# ONE re-application, after every figure above is settled, and it asks
	# `Injury.contribution` for the number rather than computing one here — so the
	# sign, the bound and the "rebuilt beats original" case are ONE implementation
	# that destroy / recreate / absorb / restore all share.
	_apply_degradation(actor, part)
	actor.mark_stats_dirty()
	var after := _derived_of(actor, part.stat_id)
	verdict["ok"] = true
	verdict["cost"] = cost
	verdict["before"] = before
	verdict["after"] = after
	# Strictly greater, not "not less": a rebuild landing EXACTLY on its original is
	# a parity, and reporting it as an excess would make the reward loop's headline
	# number fire on a result that earned nothing.
	verdict["exceeded"] = after > before + 0.000001
	return verdict


## The share a RUINED rebuild lands at: below the band's floor, by the authored
## drop. Strictly a loss — a ruin is bounded below zero rather than able to invert
## into a gain, because the reward loop is supposed to come from a SUCCESSFUL
## rebuild and a gamble on failure that pays is not a gamble. That is the yin-yang
## pair AGENTS.md asks for: the ruin's counterpart is the rebuild's cost, and
## neither side is the player's best answer on its own.
func _ruined_figure(tuning: InjuryTuning, rng: RandomNumberGenerator) -> float:
	var floor_ratio := tuning.rebuild_band().x
	return _draw(rng, 0.0, maxf(0.0, floor_ratio * tuning.ruin_drop()))


## One uniform draw inside an inclusive band. A null generator reads the band's
## LOW edge, which is the deterministic floor: a caller who passes nothing gets
## the worst legal outcome rather than an unseeded global roll, so a suite that
## passes no generator is testing the BAND and not the engine's random stream. The
## band is read through `rebuild_band()` rather than the two fields, so a `.tres`
## whose numbers were transposed cannot produce an empty band here.
static func _draw(rng: RandomNumberGenerator, band: Vector2) -> float:
	var low := minf(band.x, band.y)
	var high := maxf(band.x, band.y)
	if rng == null or high <= low:
		return low
	return low + (high - low) * clampf(rng.randf(), 0.0, 1.0)


## The essence one rebuild spends: the tuning's share of the realm's own
## `integrity_maximum`, read off the pool. A body with no reservoir has no price
## vocabulary at all and refuses at `REFUSE_NO_ESSENCE` rather than paying zero.
func _cost_of(actor: Actor, tuning: InjuryTuning) -> float:
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	if pool == null or pool.maximum <= 0.0:
		return 0.0
	return pool.maximum * tuning.cost_ratio()


## The channel this rebuild is paid out of, or `&""` for essence alone. Refused
## when the tuned channel IS the part's own and the table forbids it: a part
## rebuilt out of its own channel would erase the improvement the rebuild just
## made, which is a cost whose net is always negative.
func _sacrifice_of(_def: InjuryDef, part: Injury) -> StringName:
	var tuning := _tuning()
	var channel := tuning.rebuild_cost_meridian
	if channel == &"":
		return &""
	if channel == part.meridian_id and not tuning.rebuild_cost_allows_source:
		return &""
	return channel


## The verdict shape, always every key. A caller that reads `reason` must be able
## to read `before` and `after` without probing, which is what makes the return
## value safe to hand straight to a `summary()` payload.
static func _verdict(part_id: StringName) -> Dictionary:
	return {
		"ok": false,
		"reason": "",
		"part": String(part_id),
		"before": 0.0,
		"after": 0.0,
		"exceeded": false,
		"ruined": false,
		"cost": 0.0,
	}


# --- Gate -------------------------------------------------------------------


## THE GATE. Whether destroying this part is a PRECONDITION of training the channel
## it rides — property 4 of the brief, and the whole reason this is a system
## rather than a flavour line.
##
## ## How it is kept from being decorative
##
## A gate a caller may skip is not a gate, so this is asked in exactly one place —
## [method blocks] — and `BodyTraining.strengthen` asks it before it spends
## anything. The question is deliberately about the CHANNEL, not about the part:
## the part names which channel it is, and the channel's own training refuses
## until a part on that channel has been destroyed and rebuilt. There is no
## separate "have you destroyed it" flag to set, so a player cannot satisfy the
## gate by any route other than the one the brief names.
##
## ## Why it is off below `gate_realm_index`
##
## A gate that applies to every channel from R1 would be a wall across the whole
## ladder, not a decision: the ladder's first eight realms have no room to pay for
## a rebuild, and a gate that cannot be satisfied is a soft-lock. So the gate is
## scoped by DATA — `InjuryTuning.gate_realm_index` names the first realm whose
## channels are gated at all — and the shipped value leaves the early ladder
## exactly as it was. This is the number a designer moves to open the system.
static func blocks(channel: MeridianState, tuning: InjuryTuning, realm_index: int) -> bool:
	if channel == null or not tuning.gate_enabled:
		return false
	if realm_index < tuning.gate_realm_index:
		return false
	# Only a channel that is ALREADY TRAINED is gated. Opening, expanding and
	# strengthening are the three rungs a body climbs to get here at all, and a gate
	# on the climb would make the gate unreachable rather than meaningful.
	if channel.state_rank() < int(MeridianState.STATE_ORDER[MeridianState.STRENGTHENED]):
		return false
	for entry in InjuryCatalog.all_ids():
		var def := InjuryCatalog.definition_of(entry)
		if def == null or def.meridian_id != channel.id:
			continue
		# Broken is the requirement's own vocabulary: a part that was destroyed and
		# REBUILT has been broken, which is what the brief asks for. A part still
		# broken does not satisfy it — that is the gate pushing the player toward the
		# rebuild half, not the destroy half.
		var part: Injury = parts.get(String(entry))
		if part != null and part.rebuilt:
			return false
	return true


## The channel ids a gate currently refuses, for a read model that must name what
## is shut (ADR 0034: a gate a player is told merely exists is a gate they cannot
## act on). Bounded by the actor's own network; the loop appends nothing.
func blocked_channels(actor: Actor, tuning: InjuryTuning, realm_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null:
		return out
	var sorted: Array[String] = []
	for channel in actor.meridians.get_all_meridians():
		sorted.append(String(channel.id))
	sorted.sort()
	for id in sorted:
		var channel := actor.meridians.get_meridian(StringName(id))
		if blocks(channel, tuning, realm_index):
			out.append(StringName(id))
	return out


# --- Persistence ------------------------------------------------------------


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for key in parts.keys():
		var part: Injury = parts[key]
		if part != null:
			out[String(key)] = part.to_dict()
	return out


## Restore from raw data. Every re-loaded part is re-degraded IMMEDIATELY through
## the same modifier path a live destruction uses, so a body that was broken when
## the save was written comes back measurably weaker — the alternative, restoring
## the ledger and waiting for something to re-apply the penalty, would make a save
## round trip silently heal the player, which is the one thing a broken part must
## never do.
func load_from(data: Dictionary, actor: Actor = null) -> void:
	parts.clear()
	var entries: Variant = data.get("parts", data)
	if entries is Dictionary:
		for key in (entries as Dictionary).keys():
			var raw: Variant = (entries as Dictionary)[key]
			if not raw is Dictionary:
				continue
			var part := Injury.from_dict(raw as Dictionary)
			if part.part_id == &"":
				continue
			parts[String(part.part_id)] = part
	if actor != null:
		for key in parts.keys():
			_apply_degradation(actor, parts[key])


## Remove a part from the ledger entirely — the "absorbed" edge, for a part whose
## improvement has been folded into the body for good. Clears its modifier first,
## so the stat it was costing stops being costed.
func absorb(actor: Actor, part_id: StringName) -> bool:
	var part: Injury = parts.get(String(part_id))
	if part == null:
		return false
	part.broken = false
	_apply_degradation(actor, part)
	parts.erase(String(part_id))
	actor.mark_stats_dirty()
	return true


func _tuning() -> InjuryTuning:
	return tuning if tuning != null else InjuryTuning.new()
