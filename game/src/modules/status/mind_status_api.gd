class_name MindStatusApi
extends RefCounted

## The verbs behind `StatusApi` for the mind-control vocabulary. NOT a facade:
## `status/api.gd` is the facade and it delegates here, exactly as it delegates
## `_pulse` to `StatusRuntime`. A second `api.gd` beside the first would be a second
## facade, which is the thing `tools arch`'s ISP check exists to prevent.
##
## ## The apply gate, and the ONE invariant this whole module is built around
##
## ```
## p_answer = clampf(floor_resist + headroom * (1 - p_land), floor_resist, 1)
## ```
##
## `p_answer` is the share of applications the TARGET REFUSES, and it can never
## fall below `floor_resist` at ANY attacker investment and at ANY realm. That is
## the property the owner's brief names as a defect when it is absent: a mind
## cultivator imposing an unanswerable disable. It is enforced in two places that
## cannot drift — the arithmetic above, and `MindStatusDef.problems()` refusing a
## `floor_resist` of `0.0` at load — and asserted from the DEFS rather than from a
## restated number by `test_mind_status_no_lock.gd`.
##
## ## What lands is WEAKER, never ABSENT
##
## A resisted application still lands, at `potency * spend`. That is the second half
## of "legible": a player watching the fight sees a bar fall to a smaller value
## rather than seeing nothing happen and not knowing why. The alternative — a binary
## apply or nothing — is what makes a resistance invisible, and an invisible
## resistance is a status the target cannot plan against.
##
## ## Why a null `rng` is the CONSERVATIVE reading
##
## A deterministic caller (a test, a replay, a preview panel) is asking for the one
## answer that consults no randomness (ADR 0067). For a contest the conservative
## reading is the DEFENDER's: the status lands at `floor_resist`-strength spend and
## the target is never silently freed. A null generator can therefore never mint a
## free CC, and it can never mint an unanswerable one either.

## The refusal vocabulary, matching `StatusApply`'s existing reasons so a caller
## reads one shape for both status systems.
const REFUSED_NO_ACTOR := &"no_actor"
const REFUSED_UNKNOWN := &"unknown_status"
const REFUSED_NO_DEF := &"no_defence_stat"
const REFUSED_CEILING := &"magnitude_ceiling"
const REFUSED_WRITTEN := &"unwritable"

## Combat-scope statuses get the ONE purge vocabulary this repo already owns.
## A mind status is never CULTIVATION scope: `Stat.STATUS_RESISTANCE` does not
## answer a confrontation, `MindContest`'s own defence stat does, and giving a mind
## status the general resist term as well would be a second, invisible contest
## layered on the one the player can read.
const SCOPE_COMBAT := &"combat"

## The namespace every modifier and runtime record a mind status writes is tagged
## with, so a purge cannot collide with `StatusRuntime`'s own `status:` prefix.
const SOURCE_PREFIX := "mind_status:"

## The purge levers a mind status publishes, reusing `StatusDef.LEVERS` where one
## applies. `composure` is this vocabulary's own lever — `cleanse` takes ONE lever
## and answers through `mitigation_tags`, so a `composure`-tagged status is
## removable by a composure-restoring item and by nothing else, which is the
## "a resistance nothing answers to is a flat tax" rule honoured in both directions.
const LEVER_COMPOSURE := MindVocabulary.ROLE_COMPOSURE
const LEVER_GEAR := &"gear"
const LEVER_PILL := &"pill"


## ## `impose` — the CC group
##
## Runs the contest, banks the mastery, and applies the status at whatever strength
## the contest left. Returns
## `{ok, id, class, shape, magnitude, duration, spent, contest}` where `contest` is
## the full `MindContest` breakdown so a readout renders the resistance without
## recomputing it.
##
## The two refusals that are design rather than failure are named: `no_defence_stat`
## says the TARGET had nothing to bring, and `magnitude_ceiling` says the attacker
## out-invested the author and the status is running at its authored cap. Both are
## legible answers a player can act on, and neither is ever a silent `false`.
static func impose(
	attacker: Actor, target: Actor, status_id: StringName, rng: Variant = null
) -> Dictionary:
	if attacker == null or target == null:
		return {"ok": false, "reason": String(REFUSED_NO_ACTOR), "id": String(status_id)}
	var def := MindStatusCatalog.instance().definition(status_id)
	if def == null:
		return {"ok": false, "reason": String(REFUSED_UNKNOWN), "id": String(status_id)}
	if def.role != MindVocabulary.ROLE_CONTROL:
		return {
			"ok": false,
			"reason": String(REFUSED_UNKNOWN),
			"id": String(status_id),
			"detail": "not a control def",
		}
	var defence_stat := _defence_stat_for(def)
	if defence_stat == &"":
		return {"ok": false, "reason": String(REFUSED_NO_DEF), "id": String(def.id)}
	var contest := MindContest.resolve(
		def, _offence_of(attacker, def), _stat_of(target, defence_stat), rng
	)
	# Banked on ATTEMPT, not on success: the act of confronting someone is the
	# practice, whether or not this particular throw landed. That is what makes
	# mastery a loop over attempts rather than a reward the player farms by
	# succeeding — and it is why a run of resisted attempts still teaches. A ledger
	# the attacker does not carry is not a failure, so the verdict is not inspected.
	earn_mastery(attacker, def, 1.0)
	var potency := _potency_of(attacker, def)
	var magnitude := clampf(potency, 0.0, def.magnitude_cap())
	# A refused throw costs the attacker nothing, so `spend` — the share of the
	# magnitude that survives — is `(1 - p_answer)`, and it is what is written
	# rather than `p_answer`. The `spend_of` docblock is why a second caller's own
	# `1 - p` is the one refactor that could let a refused status land in full.
	var landed := clampf(magnitude * MindContest.spend_of(contest), 0.0, def.magnitude_cap())
	if landed <= 0.0:
		return {
			"ok": false,
			"reason": String(REFUSED_CEILING),
			"id": String(def.id),
			"contest": contest,
			"magnitude": 0.0,
		}
	var effect := _effect_for(def, landed)
	if effect == null:
		return {"ok": false, "reason": String(REFUSED_WRITTEN), "id": String(def.id)}
	var answer: Variant = target.call(&"add_status", effect)
	if not _accepted(answer):
		return {
			"ok": false,
			"reason": String(REFUSED_WRITTEN),
			"id": String(def.id),
			"contest": contest,
		}
	return {
		"ok": true,
		"reason": "",
		"id": String(def.id),
		"class": String(def.role),
		"shape": String(def.shape()),
		"magnitude": landed,
		"duration": effect.remaining,
		"spent": MindContest.spend_of(contest),
		"contest": contest,
	}


## ## `project` — the expression channels
##
## The same contest, a different currency: this one does not impose a state, it
## SPENDS the target's composure pool and the target refills it on their own beat.
## The defender's answer is `recovery`, which is a quantity, not a chance — see
## `MindExpression` for why that difference is what makes the two tracks distinct
## rather than reskins.
##
## Returns `{ok, id, channel, spent, recovered, remain, breakdown}`. `ok` is false
## only for a genuine refusal (no pool bound, or the target had no composure left to
## take); a projection that is fully answered is `ok: true` with `spent: 0.0`,
## because "the defender out-held it" is a real outcome and not a failure.
static func project(
	attacker: Actor, target: Actor, status_id: StringName, rng: Variant = null
) -> Dictionary:
	if attacker == null or target == null:
		return {"ok": false, "reason": String(REFUSED_NO_ACTOR), "id": String(status_id)}
	var def := MindStatusCatalog.instance().definition(status_id)
	if def == null or def.role != MindVocabulary.ROLE_EXPRESSION:
		return {"ok": false, "reason": String(REFUSED_UNKNOWN), "id": String(status_id)}
	var parts := MindExpression.breakdown(def, target, rng)
	earn_mastery(attacker, def, 1.0)
	if not bool(parts.get("pool_bound", false)):
		return {
			"ok": false, "reason": String(REFUSED_NO_DEF), "id": String(def.id), "breakdown": parts
		}
	var wrote := MindExpression.apply(target, parts)
	return {
		"ok": true,
		"reason": "",
		"id": String(def.id),
		"channel": String(def.channel()),
		"spent": -minf(0.0, wrote),
		"recovered": maxf(0.0, wrote),
		"remain": float(parts.get("remain", 0.0)),
		"breakdown": parts,
	}


## ## `preview` — what is true before anything is rolled
##
## The same three reads `impose` performs, with NO draw and NO write. It is what a
## combat readout calls, and it is why the resistance is legible: the numbers a
## player sees are the numbers the roll used, not a re-derivation of them.
static func preview(attacker: Actor, target: Actor, status_id: StringName) -> Dictionary:
	var def := MindStatusCatalog.instance().definition(status_id)
	if def == null or attacker == null or target == null:
		return {"ok": false, "reason": String(REFUSED_UNKNOWN), "id": String(status_id)}
	if def.role == MindVocabulary.ROLE_CONTROL:
		var defence_stat := _defence_stat_for(def)
		if defence_stat == &"":
			return {"ok": false, "reason": String(REFUSED_NO_DEF), "id": String(def.id)}
		return {
			"ok": true,
			"id": String(def.id),
			"class": String(def.role),
			"contest":
			MindContest.resolve(
				def, _offence_of(attacker, def), _stat_of(target, defence_stat), null
			),
		}
	if def.role == MindVocabulary.ROLE_EXPRESSION:
		return {
			"ok": true,
			"id": String(def.id),
			"class": String(def.role),
			"breakdown": MindExpression.breakdown(def, target, null),
		}
	return {"ok": false, "reason": String(REFUSED_UNKNOWN), "id": String(def.id)}


## ## `summary` — the catalogue read model, primitives only
##
## `defs` carries every authored mind status in the closed three roles, so a screen
## can list them; `rejected` carries the authored files the gate refused, so a
## designer finds out which `.tres` to delete rather than wondering why a status
## they wrote does not appear. `active` carries what is on the actor right now.
static func summary(actor: Actor = null) -> Dictionary:
	var catalog := MindStatusCatalog.instance()
	var ids := catalog.ids()
	var defs: Array = []
	for status_id in ids:
		(defs as Array).append((catalog.definition(status_id) as MindStatusDef).to_dict())
	var report := {
		"count": ids.size(),
		"ids": [],
		"controls": [],
		"channels": [],
		"defs": defs,
		"rejected": [],
		"active": [],
	}
	for status_id in ids:
		(report["ids"] as Array).append(String(status_id))
	(report["controls"] as Array).append_array(
		_strings(catalog.ids_of_role(MindVocabulary.ROLE_CONTROL))
	)
	(report["channels"] as Array).append_array(
		_strings(catalog.ids_of_role(MindVocabulary.ROLE_EXPRESSION))
	)
	for entry in catalog.rejected():
		(report["rejected"] as Array).append(entry)
	if actor == null:
		return report
	for status in actor.statuses:
		var def := catalog.definition(status.id)
		if def == null:
			continue
		(
			(report["active"] as Array)
			. append(
				{
					"id": String(def.id),
					"class": String(def.role),
					"shape": String(def.shape()),
					"channel": String(def.channel()),
					"remaining": status.remaining,
					"magnitude": status.magnitude,
				}
			)
		)
	return report


# --- internals ---------------------------------------------------------------------


## Bank one act against the attacker's mastery ledger, through the
## `mind_cultivation` FACADE.
##
## ## Why the facade, and why it is optional
##
## `mind_cultivation` declares `["contracts", "core", "destiny", "items", "race"]`
## and `status` declares `["contracts", "core"]`, so `status` may NOT depend on
## `mind_cultivation` in `registry.json` even as a facade — the edge is undeclared in
## that direction. So this calls the facade BY NAME with no `preload`, which is the
## AGENTS.md-sanctioned escape for exactly this: a bare class reference is invisible
## to `tools arch`'s bare resolver (`BARE_REF_UNITS` excludes `modules/*`), so it
## cannot make the registry lie about an edge that exists only as a name.
##
## And it is OPTIONAL. An actor with no mind ledger — a stock body that never enrolled
## on the path — is not an error: it simply does not bank, and the contest still
## resolves. That is what keeps this module's CC group usable by `app/` before the
## mind path is wired, which is the same degradation every other read on this file
## gives.
static func earn_mastery(actor: Actor, def: MindStatusDef, uses: float = 1.0) -> Dictionary:
	if actor == null or def == null:
		return {"ok": false, "reason": "no_actor"}
	var ledger: Variant = MindAccess.mastery(actor)
	if ledger == null or not (ledger is Object):
		return {"ok": false, "reason": "no_ledger"}
	# The ledger is handed back as a `Variant` on purpose: naming `MindMasteryState`
	# here is the class-resolution CYCLE `MindVocabulary`'s docblock describes — this
	# module's own def type is a parameter of `MindMastery.earn`, so a typed reference
	# makes both classes depend on each other and neither compiles. The spelling is
	# gone, not the read: the component key is the one shared handle, and `earn`'s own
	# signature does the typing.
	return MindMastery.earn(ledger, def, uses)


## The defence stat a CONTROL def contests on. A `composure` def is not imposed and
## has no target-side battlefield, which is why it answers `&""` rather than
## resolving to a nonsense id.
static func _defence_stat_for(def: MindStatusDef) -> StringName:
	if def == null:
		return &""
	var authored := def.defence_stat()
	if authored != &"":
		return authored
	if def.role != MindVocabulary.ROLE_CONTROL:
		return &""
	return MindVocabulary.defence_id(def.shape())


## The attacker's stat for a control def, through the shared spelling.
static func _offence_of(attacker: Actor, def: MindStatusDef) -> float:
	var authored := def.offence_stat()
	if authored != &"":
		return _stat_of(attacker, authored)
	return _stat_of(attacker, MindVocabulary.offence_id(def.shape()))


## How strong a throw is: the attacker's projection stat, so a `slow` is thrown with
## the same stat a `voice` costs composure with and the two scales together.
static func _potency_of(attacker: Actor, def: MindStatusDef) -> float:
	var suffix := def.shape()
	if suffix == &"":
		suffix = def.channel()
	return _stat_of(attacker, MindVocabulary.offence_id(suffix))


## The live `StatusEffect` an authored mind def resolves to, or null when the
## constructor cannot make one. Built through the CONTRACT's own fields rather than
## through `StatusApi._effect_for`, because a mind def is not a `StatusDef` and a
## cast would be the exact "two content types shaped as one" coupling the split was
## meant to remove.
static func _effect_for(def: MindStatusDef, magnitude: float) -> StatusEffect:
	if def == null or magnitude <= 0.0:
		return null
	var effect := StatusEffect.new(def.id, def.duration())
	if effect == null:
		return null
	effect.magnitude = magnitude
	effect.magnitude_cap = def.magnitude_cap()
	effect.scope = StatusEffect.Scope.COMBAT
	effect.kind = StatusEffect.Kind.CONTROL
	effect.stacking = StatusEffect.Stacking.REFRESH
	effect.source = StringName("%s:%s" % [MindStatusApi.SOURCE_PREFIX, String(def.id)])
	effect.mitigation_tags = [
		MindVocabulary.ROLE_COMPOSURE, MindStatusApi.LEVER_GEAR, MindStatusApi.LEVER_PILL
	]
	effect.payload = {
		"class": String(def.role),
		"shape": String(def.shape()),
		"channel": String(def.channel()),
		"beat": def.beat(),
	}
	return effect


static func _stat_of(actor: Actor, stat_id: StringName) -> float:
	if actor == null or stat_id == &"" or actor.stats == null:
		return 0.0
	var value := float(actor.stats.derived(stat_id))
	return value if is_finite(value) else 0.0


static func _strings(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id in ids:
		out.append(String(id))
	return out


## Whether `Actor.add_status`'s answer means ACCEPTED. The same deliberately
## permissive reading `StatusApply._accepted` uses, for the same reason: `core` is
## owned elsewhere and its return shape is in flight, and a void answer must not be
## mistaken for a refusal.
static func _accepted(answer: Variant) -> bool:
	if answer is Dictionary:
		return not (answer as Dictionary).has(&"ok") or bool((answer as Dictionary)[&"ok"])
	return true
