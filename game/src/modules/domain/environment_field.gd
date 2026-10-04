class_name EnvironmentField
extends RefCounted

## The `status` module's FACADE, preloaded because it is the one cross-module edge this
## file owns. `tools arch` reads the `res://` reference and `rules.is_facade` names this
## path `api.gd`, so the edge is legal exactly as `combat -> status` and `loot -> status`
## already are; the preload is what makes it VISIBLE to that checker at all, since a
## bare `StatusApi.` out of `modules/*` is in neither `res://` nor `extends` and
## `BARE_REF_UNITS` excludes every module (`tools/arch/rules.py:61`).
const StatusApi := preload("res://src/modules/status/api.gd")

## What standing inside an environment zone DOES (ADR 0075, AC4).
##
## A zone applies ONE status id and this class resolves what that status means for the
## actor who received it. **It never subtracts health, qi or stamina directly** — there
## is no `health -= f(x)` here and there never will be, because a second damage channel
## outside `StatusEffect` is exactly what ADR 0075 forbids. `apply` hands the status to
## `Actor.add_status` AND to the `status` module's runtime (see below); the consequences
## unfold under `StatusApi.tick_statuses`, so a hazard obeys the same duration, stacking
## and cleanse rules as every other status.
##
## ## The status is not a label; it carries the resolved strength
##
## The status handed over carries `magnitude` = the residual THIS actor carries after
## mitigation, a non-zero `tick_interval`, and a declared `stacking` mode, so a pulse is
## worth something and a re-entry is a refresh rather than an unbounded stack. A caller
## that only checks `has_status` is reading presence, not consequence: the load-bearing
## assertions live on `magnitude` and on what `tick_statuses` actually pays.
##
## ## `add_status` is not enough, and that was the live defect
##
## This docblock once claimed "the consequences unfold under `Actor.tick_statuses`". They
## did not. `Actor.add_status` is `core`'s ADR 0086 merge — it appends, merges and ages
## — and the pulse lives in the `status` module's own per-actor runtime table, which only
## `StatusApi.apply` / `apply_cultivation` ever populated. A zone that called
## `add_status` alone landed a status that `has_status` reported, `Actor.tick_statuses`
## aged out on the authored budget, and never cost a single point of health — a furnace
## the player could stand in forever. Every zone now hands the effect to
## [method _resolve] as well, which is the seam, and `apply_cultivation` is deliberately
## NOT used instead: it REFUSES a COMBAT-scope def, and a zone is CULTIVATION scope for
## a reason.
##
## The load-bearing rule is ONE status id and THREE structurally different substrates.
## qi, body and mind share exactly ONE power ladder (`RealmRate`) and must otherwise
## have different mechanisms (ADR 0066). A zone that handed all three paths the same
## number would be the flat damage tax the repo refuses. So for `super_hot`:
##
## - **qi** loses the QI POOL — they cannot cast or flee. The cheap failure, and the
##   counterplay is simply leaving.
## - **body** loses health_regen and stamina_regen and takes almost NO acute damage.
##   The zone is a DEADLINE, not a damage race: leave with time to spare and nothing
##   happens.
## - **mind** gets perception attenuation and a false-positive exit read. The hazard is
##   MISINFORMATION, not injury.
##
## The branch is on the CULTIVATION PATH and on nothing else. It never branches on a
## zone's role, a room's band or an actor's tags: three mechanisms that each branch on
## a role are three mechanisms that disagree.
##
## Mitigation is per substrate, not per zone.
## `EnvironmentZoneDef.mitigation_tags` says what a zone PUBLISHES. That is not the
## same question as what reduces it for a given actor, and conflating them is the trap
## this class exists to avoid. A body cultivator in `super_hot` is not being drained,
## and a fire root reduces *drain* — so a zone that names `affinity` has published a
## counterplay this actor cannot use. `mitigates(lever, path_id, kind)` is the honest
## question and `mitigated_by` answers it against the actor's own path.
##
## The module boundary is deliberate.
##
## `domain` declares `core` + `contracts` only, so this file reads no sibling module's
## class. Gear, techniques and pills are read as TAG LISTS under the three
## `module_data` keys this file owns, which is the repo's established seam for module
## state on an `Actor` (see `CombatDuel.MODULE_KEY`, `LootState.MODULE_KEY`). Nothing
## here walks another module's payload, so a save written by a newer version of one
## cannot break this resolution.
##
## ## Who writes the three tag keys, and when
##
## They were, for a long while, named here and written by NOTHING — three live caps
## (`GEAR_CAP`, `TECHNIQUE_CAP`, `PILL_CAP`) over lists that were always empty, so a
## cultivator wearing an authored fire ward got zero mitigation while the screen still
## printed "answered by: gear, pill, affinity". That was a read model advertising
## counterplay the game could not deliver.
##
## They are now WRITTEN BY `DomainBoot.publish_ward_tags`, called from `enter_domain`
## and from every `visit_room`. It reads what the actor actually carries through the
## `items` and `techniques` FACADES and writes flat element tag lists into the three
## keys below. `domain` cannot do this itself: it declares `core` + `contracts` only
## (`tools/arch/registry.json`), so the owning modules are reached from `app/`, which is
## the composition root and may depend on anything.
##
## The tags are ELEMENTS (`&"fire"`, `&"ice"`, …) because that is the join key this
## module already asks a zone for: `EnvironmentZoneDef.tags` is the "elements this zone
## is hostile to" list, so a wardrobe or a satchel answers the same question a spirit
## root does. Nothing here walks a sibling's payload — each key is still read as
## `{"tags": [...]}` and nothing more, so a save written by a newer version of `items`
## or `techniques` cannot break this resolution.
##
## `LEVER_AFFINITY` still needs no key: a spirit root is on the actor from character
## creation. It remains the only lever that fires with NOTHING carried, which is the
## point — it is the one counterplay a player cannot lose by dropping their gear.

# ── the three cultivation paths, and nothing else branches on them ────────────

const PATH_BODY := PathState.BODY
const PATH_MIND := PathState.MIND
const PATH_QI := PathState.QI
## CLOSED. An unknown path id is a loud failure with a named reason, never a default:
## defaulting here would hand a fourth mechanism to a path that has no design for it.
const PATHS: Array[StringName] = [PATH_QI, PATH_BODY, PATH_MIND]

# ── substrates ───────────────────────────────────────────────────────────────
#
# A substrate names WHICH MECHANISM a status resolves to. These are different systems,
# not three magnitudes of one number: `effect_for` is what a test asserts on to prove a
# per-path split is structural rather than a swapped number.

## The qi pool is suppressed and the actor cannot spend it to escape.
const SUBSTRATE_QI_POOL := &"qi_pool_suppression"
## Regeneration stops, so existing health and stamina bleed out on a timer. Almost no
## acute damage — the deadline is the un-regenerated body.
const SUBSTRATE_REGEN_DEADLINE := &"regen_deadline"
## Perception is attenuated and an exit reads clear when it is not. The body is fine.
const SUBSTRATE_PERCEPTION_FAULT := &"perception_fault"
## Qi throughput is ceilinged rather than cut off, so a trained path suffers less.
const SUBSTRATE_QI_THROUGHPUT := &"qi_throughput_ceiling"
## Graded acute damage that conditioning can be trained into. The one substrate that
## genuinely hurts immediately.
const SUBSTRATE_GRADED_BODY := &"graded_body_trauma"
## Background noise that is, once you learn to read it, an actual signal.
const SUBSTRATE_SIGNAL_NOISE := &"signal_in_noise"
## Will-shaping: the payload is will, not flesh, so the body is barely touched.
const SUBSTRATE_WILL_PRESSURE := &"will_pressure"
## Ambient qi flows in unbidden and clogs a cultivator's channels.
const SUBSTRATE_OVERGROWTH := &"verdant_overgrowth"

## Every authored kind, resolved to a substrate per path. Read as a table: a reviewer
## should be able to take in the whole mechanic without reading a branch.
const SUBSTRATES: Dictionary = {
	&"super_hot":
	{
		PATH_QI: SUBSTRATE_QI_POOL,
		PATH_BODY: SUBSTRATE_REGEN_DEADLINE,
		PATH_MIND: SUBSTRATE_PERCEPTION_FAULT,
	},
	&"super_cold":
	{
		PATH_QI: SUBSTRATE_QI_POOL,
		PATH_BODY: SUBSTRATE_REGEN_DEADLINE,
		PATH_MIND: SUBSTRATE_PERCEPTION_FAULT,
	},
	&"static":
	{
		PATH_QI: SUBSTRATE_QI_POOL,
		PATH_BODY: SUBSTRATE_REGEN_DEADLINE,
		PATH_MIND: SUBSTRATE_PERCEPTION_FAULT,
	},
	&"toxic":
	{
		PATH_QI: SUBSTRATE_QI_POOL,
		PATH_BODY: SUBSTRATE_GRADED_BODY,
		PATH_MIND: SUBSTRATE_WILL_PRESSURE,
	},
	&"void":
	{
		PATH_QI: SUBSTRATE_QI_POOL,
		PATH_BODY: SUBSTRATE_REGEN_DEADLINE,
		PATH_MIND: SUBSTRATE_PERCEPTION_FAULT,
	},
	# BL-0247: for pressure NO spirit root mitigates at all. A root is a lens on an
	# element and pressure is not an element, so affinity is structurally inert here
	# even on a zone whose `mitigation_tags` happen to name it.
	&"pressure":
	{
		PATH_QI: SUBSTRATE_QI_THROUGHPUT,
		PATH_BODY: SUBSTRATE_GRADED_BODY,
		PATH_MIND: SUBSTRATE_SIGNAL_NOISE,
	},
	&"sorrow":
	{
		PATH_QI: SUBSTRATE_WILL_PRESSURE,
		PATH_BODY: SUBSTRATE_REGEN_DEADLINE,
		PATH_MIND: SUBSTRATE_PERCEPTION_FAULT,
	},
	&"verdant":
	{
		PATH_QI: SUBSTRATE_OVERGROWTH,
		PATH_BODY: SUBSTRATE_QI_THROUGHPUT,
		PATH_MIND: SUBSTRATE_WILL_PRESSURE,
	},
}

# ── the four levers, expressed against each substrate ─────────────────────────
#
# A lever is only a real counterplay if it can move the number. Naming the substrates a
# lever acts on is what stops "this zone publishes affinity" and "affinity reduces what
# this actor is standing in" from drifting apart as more kinds are authored.
#
# `cap` is the share of the authored magnitude the lever removes at full strength. An
# affinity that perfectly negated the hazard would delete the counterplay the other
# three levers exist to provide.

const LEVER_AFFINITY := &"affinity"
const LEVER_GEAR := &"gear"
const LEVER_TECHNIQUE := &"technique"
const LEVER_PILL := &"pill"

const AFFINITY_CAP := 0.50
const GEAR_CAP := 0.40
const TECHNIQUE_CAP := 0.30
const PILL_CAP := 0.35

const LEVER_SUBSTRATES: Dictionary = {
	# `SUBSTRATE_GRADED_BODY` is here because it is the ONE substrate that grades
	# acute damage by an element, which is what makes a spirit root the honest
	# answer to it. BL-0247 gives `toxic`/`pressure` a `graded_body_trauma` on
	# `PATH_BODY` (`:106,:121`) precisely so a wrong-root body cultivator is hurt
	# MORE, and `toxic` is hostile to `wood`/`verdant` to `wood` (`:202,:206`) —
	# a wood root blunting that is the design, not a side effect. It was missing
	# from this list, so `_moves` said `false` for every affinity-rooted body
	# cultivator and the lever never fired at all.
	LEVER_AFFINITY:
	[
		SUBSTRATE_QI_POOL,
		SUBSTRATE_QI_THROUGHPUT,
		SUBSTRATE_OVERGROWTH,
		SUBSTRATE_GRADED_BODY,
	],
	LEVER_GEAR:
	[
		SUBSTRATE_QI_POOL,
		SUBSTRATE_REGEN_DEADLINE,
		SUBSTRATE_GRADED_BODY,
		SUBSTRATE_QI_THROUGHPUT,
	],
	LEVER_TECHNIQUE:
	[
		SUBSTRATE_REGEN_DEADLINE,
		SUBSTRATE_PERCEPTION_FAULT,
		SUBSTRATE_GRADED_BODY,
		SUBSTRATE_WILL_PRESSURE,
	],
	LEVER_PILL:
	[
		SUBSTRATE_QI_POOL,
		SUBSTRATE_REGEN_DEADLINE,
		SUBSTRATE_QI_THROUGHPUT,
		SUBSTRATE_SIGNAL_NOISE,
	],
}

const LEVER_CAPS: Dictionary = {
	LEVER_AFFINITY: AFFINITY_CAP,
	LEVER_GEAR: GEAR_CAP,
	LEVER_TECHNIQUE: TECHNIQUE_CAP,
	LEVER_PILL: PILL_CAP,
}

## Element ids that answer `kind`. A kind with no entry here is hostile to NO element,
## so no spirit root mitigates it at all — which is the honest reading and the reason
# `pressure` has no affinity lever however its def is tagged.
const HOSTILE_ELEMENTS: Dictionary = {
	&"super_hot": [&"fire"],
	&"super_cold": [&"ice", &"water"],
	&"static": [&"lightning", &"metal"],
	&"toxic": [&"wood", &"water"],
	&"void": [&"dark"],
	&"pressure": [],
	&"sorrow": [&"dark"],
	&"verdant": [&"wood"],
}

## The affinity strength at which a spirit root fully answers a hazard, read against
## the authored race scale (`emberblood` grants `fire: 10.0`, `tidecaller` grants
## `water: 10.0` alongside `ice: 3.0`). Below the floor the root is not specialised
## enough to blunt it and is not credited as a mitigation at all.
const AFFINITY_STRONG := 10.0
const AFFINITY_FLOOR := 3.0

## Gear a `body` cultivator is already wearing counts at less than face value: the
## deadline case is a body already losing its regeneration, so plate buys less there
## than it would against a graded blow. Applied to the GEAR cap only.
const BODY_GEAR_FACTOR := 0.75

## The `stay_budget` floor. A zone renewing its status every zero seconds would be
## permanent, and permanence is not something an authored band grants by accident.
const MIN_DURATION := 0.5

## The authored `env_scourge` def. The hazard's cadence, magnitude ceiling and
## share-per-pulse are BALANCE, and this repo authors balance as content:
## `EnvironmentZoneDef.MAGNITUDES` is a table rather than a curve
## (`environment_zone_def.gd:54`), and ADR 0090's whole claim is that adding a status
## is a file rather than a literal inside a rule. Retuning the hazard is a `.tres` edit.
##
## ## Why `res://src/data/` and not `res://data/statuses/`
##
## `StatusCatalog.STATUSES_ROOT` is `res://data/statuses` (`status_catalog.gd:35`) and
## that tree is a CLOSED twenty whose exact id set is pinned by
## `tests/modules/status/test_status_catalogue.gd:60` — adding a twenty-first id breaks
## that suite, which is not this file's to change. `env_scourge` could not live there in
## any case: it rides NO element, because a hazard is hostile to whichever elements its
## ZONE names rather than to one of its own, and naming `fire` here would be a lie the
## shipped catalogue would act on (`StatusApi.status_for_element` would answer with it
## for every fire blow in the game).
##
## Both reasons are now answered by the `status` module rather than worked around here:
## `env_scourge.tres` authors `ambient = true`, which is the def's own statement that a
## place — not a blow — inflicts it, and `StatusCatalog.AMBIENT_SOURCES_ROOT` is this
## path. So the def loads through the SAME `StatusDef.problems()` gate as the twenty and
## [method _resolve]'s facade call resolves it, with the twenty untouched.
##
## `domain` keeps its authored content under `res://src/data/` for the same reason
## `domain/api.gd:28-33` gives: `tools data audit` scans `game/data`, so a domain def
## authored there would be graded by rules it was never written against.
const SCOURGE_DEF_PATH := "res://src/data/statuses/env_scourge.tres"

## How many pulses one stay window pays. Derived from the authored `stay_budget` and
## the def's `tick_interval` rather than authored separately, because it is the ratio
## between two authored numbers and a third literal is a place for them to disagree.
const PULSES_PER_STAY := 4

## The cadence the hazard falls back to when the def cannot be read. Matches the
## authored `tick_interval` in `env_scourge.tres` so the degradation is invisible, and
## is `stay_budget / PULSES_PER_STAY` for the shipped `8.0` budget.
##
## **Authored CONTENT cadence, deliberately not on the clock.** ADR 0090's claim is that
## retuning the hazard is a `.tres` edit, and this is the value that `.tres` holds
## (`tick_interval = 2.0`) — the literal here exists so a MISSING def degrades to the
## shipped cadence rather than to a zero interval. It is not a magnitude of world time:
## the hazard is applied by `StatusLoop`'s frame delta, not by a period, and no
## `TimeLadder` ratio is two seconds. Deriving it would put content balance on the
## world's clock, so it stays authored and is reported to the single-source guard.
const TICK_INTERVAL := 2.0

## The strongest hazard this field can resolve, and the ceiling a re-application is held
## under. It is `EnvironmentZoneDef.MAGNITUDES`'s loudest row (`void` band 3 = `2.00`):
## a residual is the authored magnitude times one minus a lever cap, so it can never
## exceed the authored value, and this is that value's maximum.
const MAX_MAGNITUDE := 2.0

## Marker slots an owning module publishes the tags this field reads under. `domain`
## reads exactly these three keys and no others.
##
## ## PUBLISHED: `DomainBoot.publish_ward_tags` writes these
##
## `enter_domain` and every `visit_room` call it, so `GEAR_CAP`, `TECHNIQUE_CAP` and
## `PILL_CAP` now gate a real list rather than an empty one. The payload is
## `{"tags": [StringName, ...]}` and NOTHING else — `domain` never walks the owning
## module's payload, which is what keeps a save written by a newer `items` or
## `techniques` from breaking this resolution.
##
## The list holds ELEMENTS, because `EnvironmentZoneDef.tags` is already the "elements
## this zone is hostile to" list and a piece of gear or a consumable is published
## against that same vocabulary. A test may still write any string here: the lever asks
## only "is this list non-empty", so a hand-written key keeps working exactly as it did.
##
## `LEVER_AFFINITY` needs no key — a spirit root is on the actor from character
## creation — which is why it is the only lever that fires with nothing carried.
## See the class docblock for why these live in `app/` rather than in this file.
const GEAR_TAGS_KEY := &"env_gear_tags"
const TECHNIQUE_TAGS_KEY := &"env_technique_tags"
const PILL_TAGS_KEY := &"env_pill_tags"

## The authored def, cached after the first read, or null when the file is missing or
## unreadable. A missing def is NOT fatal: `_hazard` falls back to `TICK_INTERVAL` so a
## content gap degrades the hazard rather than refusing the whole zone. `static`
## because the content tree is immutable for the length of a run and every actor
## resolves the same cadence — the one-cache-per-tree shape `StatusCatalog.shared` uses
## (`status_catalog.gd:34`). Declared after the consts because `gdlintrc` orders
## `staticvars` below `consts`, so a block placed with the ladder it belongs to would
## fail the whole file on a style rule.
static var _def_cache: Variant = null
static var _def_loaded: bool = false


## What standing in `zone` does to `actor`, who cultivates `path_id`.
##
## Returns `{applied, status_id, amount, mitigated_by, reason}`. `amount` is the
## RESIDUAL magnitude for this actor on this substrate; it is not dealt to any pool
## here, it is the resolved strength the status carries. `reason` is `""` on success
## and a named, actionable string on every refusal.
##
## Never subtracts health. Never throws.
static func apply(actor: Actor, zone: EnvironmentZoneDef, path_id: StringName) -> Dictionary:
	if zone == null:
		return _result(false, &"", 0.0, "", "zone is null")
	if actor == null:
		return _result(false, zone.status_id, 0.0, "", "actor is null")
	if not PATHS.has(path_id):
		return _result(
			false,
			zone.status_id,
			0.0,
			"",
			"unknown cultivation path '%s'; allowed: %s" % [String(path_id), _names(PATHS)]
		)
	var substrate := effect_for(path_id, zone.kind)
	if substrate == &"":
		return _result(
			false,
			zone.status_id,
			0.0,
			"",
			(
				"zone '%s' has unknown kind '%s'; allowed: %s"
				% [String(zone.zone_id), String(zone.kind), _names(EnvironmentZoneDef.KINDS)]
			)
		)
	if zone.status_id == &"":
		return _result(false, &"", 0.0, "", "zone '%s' authors no status_id" % String(zone.zone_id))

	# An affinity belongs to whoever HAS it, so a mitigation resolved for the actor's
	# own path is not transferable to a path they do not hold. Two zones sharing a
	# status id would have the same problem from the other direction, which is why a
	# ref authored twice for different hazards must mint distinct ids.
	var lever := _lever_for(actor, zone, path_id)
	var amount := _amount(zone, lever, actor, path_id)

	var duration := maxf(zone.stay_budget, MIN_DURATION)
	var existing := _status(actor, zone.status_id)
	if existing != null:
		# Standing inside a zone re-applies on `stay_budget`, so the timer is refreshed
		# rather than a second entry appended. Refusing instead would let the status
		# lapse mid-stay; appending would stack it without a stacking rule anywhere.
		#
		# REFRESH keeps the STRONGER magnitude (`status_registry.gd:151`), so this also
		# carries a re-resolved amount rather than only the timer: a player who equips
		# a ward mid-stay must get the smaller number, not keep the pre-ward one. The
		# cap is the zone's own authored ceiling rather than a floor, so a zone whose
		# band is authored BELOW what is already held cannot be talked up by refresh.
		existing.remaining = duration
		existing.magnitude = minf(amount, existing.magnitude)
		# The refresh reaches the tick channel too, or a re-application would lower the
		# pulse WITHOUT touching the runtime that pays it. This is the measured defect
		# this module had: `actor.add_status` alone left no `StatusRuntime` record, so
		# `StatusApi.tick_statuses` skipped the status entirely and a furnace cost zero
		# health however long a player stood in it.
		_resolve(actor, existing)
		return _result(false, zone.status_id, amount, lever, "refreshed an existing status")
	var effect := _hazard(zone, duration, amount)
	actor.add_status(effect)
	_resolve(actor, effect)
	return _result(true, zone.status_id, amount, lever, "")


## The residual magnitude this actor would carry in `zone` on `path_id`, without
## touching them. Separate from `apply` so the same actor on the same zone can be
## measured before and after a mitigation is equipped, which is what proves a lever is
## real rather than merely asserted.
static func residual_amount(
	actor: Actor, zone: EnvironmentZoneDef, path_id: StringName = &""
) -> float:
	if actor == null or zone == null:
		return 0.0
	var path := path_id
	if path == &"":
		path = primary_path(actor)
	if effect_for(path, zone.kind) == &"":
		return 0.0
	return _amount(zone, _lever_for(actor, zone, path), actor, path)


## Which lever reduced this zone for this actor, or `""` for none.
##
## Read in the order identity loads: spirit-root affinity, then equipped gear, then
## known techniques, then a carried pill. Affinity comes first because it is the only
## lever a character is born with — it cannot be sold, dropped or consumed mid-run.
## Affinity is resolved against the actor's OWN cultivation path, so it returns `""`
## for a body cultivator standing in a `super_hot` zone even though that zone
## publishes `affinity`.
static func mitigated_by(actor: Actor, zone: EnvironmentZoneDef) -> String:
	if actor == null or zone == null:
		return ""
	return _lever_for(actor, zone, primary_path(actor))


## The substrate `path_id` reads `kind` through. `""` when either is unknown, so a
## caller refuses rather than silently inheriting a default mechanism.
static func effect_for(path_id: StringName, kind: StringName) -> String:
	var row: Dictionary = SUBSTRATES.get(kind, {})
	if row.is_empty():
		return ""
	return StringName(row.get(path_id, &""))


## Whether `lever` genuinely reduces what `path_id` is standing in under `kind`.
##
## NOT the same question as `zone.mitigates(lever)`, which asks what the zone
## PUBLISHES. A zone can publish a lever that does nothing here — which is the whole
## body-cultivator-in-super-hot case.
static func mitigates(lever: StringName, path_id: StringName, kind: StringName) -> bool:
	return _moves(String(lever), effect_for(path_id, kind))


## The boundary a scene draws BEFORE anything is applied (ADR 0075: telegraph before
## damage). Primitives only, so it crosses into a Node without this module knowing one
## exists.
##
## `touches` is the entry test. `false` for an actor outside `bounds`, and the status
## is NOT applied. That ordering is the point: a hazard that cannot be seen before it
## bites is a trap, not an environment.
static func telegraph(zone: EnvironmentZoneDef, touches: bool = false) -> Dictionary:
	if zone == null:
		return {}
	var box := zone.bounds
	return {
		"zone_id": String(zone.zone_id),
		"kind": String(zone.kind),
		"intensity": zone.resolved_intensity(),
		"status_id": String(zone.status_id),
		# Tiles, relative to the owning room's origin — the frame `bounds` is already in.
		"bounds": [box.position.x, box.position.y, box.size.x, box.size.y],
		"stay_budget": zone.stay_budget,
		# The authored magnitude UNMITIGATED. Telegraphing the number this particular
		# actor would suffer would leak their own gear to the UI.
		"amount": zone.magnitude(),
		"mitigation_levers": _lever_names(zone.mitigation_tags),
		# Visible whether or not the actor is already inside: the boundary is what makes
		# it possible to leave in time.
		"boundary_visible": true,
		# True only on the frame the boundary is crossed. An actor who never enters is
		# never taxed.
		"entered": bool(touches),
		"applies_status_on_entry": true,
	}


## The path this actor actually cultivates: the lowest `PathState.ALL` ordinal it
## holds. `""` when it cultivates none, which callers then refuse by name rather than
## guessing a path on the actor's behalf.
static func primary_path(actor: Actor) -> StringName:
	if actor == null:
		return &""
	# Bounded `for` over the closed three-path set, in a fixed order, so the answer is
	# deterministic rather than dependent on Dictionary iteration order.
	for path_id in PathState.ALL:
		if actor.paths.has(path_id):
			return path_id
	return &""


# ── resolution ───────────────────────────────────────────────────────────────


## The `StatusEffect` a zone actually lands, carrying the residual `amount` the field
## resolved FOR THIS ACTOR — not the authored magnitude and not zero.
##
## ## Why this is not `StatusEffect.new(id, life)`
##
## The two-argument constructor leaves every other field at its contract default
## (`contracts/status_effect.gd:52-96`), and those defaults are the silent kind: a DOT
## with `magnitude = 0.0` and `tick_interval = 0.0` still ages out, still answers
## `has_status` true, and pays nothing. That was the live state of this file: the
## residual was computed at `_amount` and then thrown into a return dictionary nobody
## acted on, so a player standing in a hazard was mechanically untouched.
##
## Each field is set because the tick path reads it:
## - `magnitude` — what `StatusRegistry.tick` reports on `status_ticked`
##   (`status_registry.gd:109`), so a pulse is worth something.
## - `tick_interval` — a non-zero cadence, because `_pulses_due` returns `0` for a
##   status with none and the DOT never fires.
## - `stacking` — REFRESH, which is the whole re-entry rule: one instance per
##   `(actor, status_id)`, and a weaker re-application never shortens a stronger one.
## - `kind` — DOT, so a consumer reading the contract knows this spends over time
##   rather than holding a stat.
##
## `mitigation_tags` is copied off the ZONE, and that is the honest source rather than
## a fallback: ADR 0075 makes `EnvironmentZoneDef.mitigation_tags` the authored
## counterplay for a zone, and `has_mitigation()` (`contracts/status_effect.gd:114`)
## reads the same four levers. Copying them is what makes the applied status answer
## true to `has_mitigation()` instead of looking like a hazard nothing can push back
## against. `EnvironmentZoneDef` is a `Resource` of THIS module, so reading it is
## in-module and crosses no `domain` -> `status` edge (`tools/arch/registry.json:54`).
static func _hazard(zone: EnvironmentZoneDef, duration: float, amount: float) -> StatusEffect:
	var effect := StatusEffect.new(zone.status_id, duration)
	effect.kind = StatusEffect.Kind.DOT
	# CULTIVATION scope, not COMBAT: an environment is never opposed by
	# `Stat.STATUS_RESISTANCE`, because the hazard is a place rather than an attack and
	# taxing the player for walking into authored scenery is not a difficulty knob.
	effect.scope = StatusEffect.Scope.CULTIVATION
	# REFRESH, not STACK: a zone re-applies on `stay_budget` from one entry point, so a
	# stack would make standing still RAISE the damage on every re-apply. REFRESH is the
	# rule that keeps one hazard one hazard, and it is the same rule the refresh branch
	# in `apply` honours by hand.
	effect.stacking = StatusEffect.Stacking.REFRESH
	effect.magnitude = minf(maxf(amount, 0.0), MAX_MAGNITUDE)
	effect.magnitude_cap = MAX_MAGNITUDE
	effect.tick_interval = hazard_cadence()
	effect.mitigation_tags = zone.mitigation_tags.duplicate()
	return effect


## The authored hazard def, or null when it cannot be read. Public so a screen or an
## audit can ask whether the hazard has content behind it rather than discovering it
## from a hazard that silently pays nothing.
static func hazard_def() -> StatusDef:
	if _def_loaded:
		return _def_cache as StatusDef
	_def_loaded = true
	if not ResourceLoader.exists(SCOURGE_DEF_PATH):
		_def_cache = null
		return null
	var loaded := load(SCOURGE_DEF_PATH)
	_def_cache = loaded as StatusDef
	return _def_cache as StatusDef


## Seconds between hazard pulses: the def's authored `tick_interval`, else [constant
## TICK_INTERVAL]. A zero would be the silent failure this file exists to have fixed —
## `_pulses_due` returns `0` for a status with no interval (`status_registry.gd:168`),
## so a DOT would age out and never pay.
static func hazard_cadence() -> float:
	var def := hazard_def()
	if def == null or def.tick_interval <= 0.0:
		return TICK_INTERVAL
	return def.tick_interval


## The lever that actually reduces this zone for this actor on this path, or `""`.
static func _lever_for(actor: Actor, zone: EnvironmentZoneDef, path_id: StringName) -> String:
	var substrate := effect_for(path_id, zone.kind)
	if substrate == &"":
		return ""
	# A lever is only the actor's to spend if they CULTIVATE the path the substrate was
	# resolved for. `Actor.affinities` belongs to whoever carries it, so crediting it
	# on a path the actor does not hold would invent a mitigation.
	var holds := actor != null and actor.paths.has(path_id)
	# Bounded `for` over the four declared levers, in identity order.
	for lever in EnvironmentZoneDef.LEVERS:
		if not zone.mitigates(lever) or not _moves(String(lever), substrate):
			continue
		if holds and _lever_applies(actor, lever, zone):
			return String(lever)
	return ""


static func _amount(
	zone: EnvironmentZoneDef, lever: String, actor: Actor, path_id: StringName
) -> float:
	var cap := _cap_for(lever)
	if cap <= 0.0:
		# The lever is published but structurally inert on this substrate, so it was
		# never credited. Subtracting from it anyway would report a mitigation that did
		# not happen.
		return zone.magnitude()
	var held := 1.0
	if lever == String(LEVER_AFFINITY):
		held = _affinity_weight(actor, zone)
	elif lever == String(LEVER_GEAR) and path_id == PATH_BODY:
		held = BODY_GEAR_FACTOR
	# A tagged source counts once, not per tag: the cap is the authored strength of the
	# lever, so a full set of gear is exactly as good as the data claims and no more.
	return zone.magnitude() * (1.0 - cap * minf(1.0, held))


## The share of a zone's magnitude `lever` removes at full strength, 0.0 when the lever
## has nothing to act on. 0.0 rather than a guess for a lever this file does not know:
## an unrecognised lever must never quietly reduce a hazard.
static func _cap_for(lever: String) -> float:
	for key in LEVER_CAPS:
		if String(key) == lever:
			return float(LEVER_CAPS[key])
	return 0.0


## Whether `lever` acts on `substrate` at all.
static func _moves(lever: String, substrate: StringName) -> bool:
	for key in LEVER_SUBSTRATES:
		if String(key) != lever:
			continue
		return (LEVER_SUBSTRATES[key] as Array).has(substrate)
	return false


## Whether this actor actually carries the lever. Each source is read only from the
## marker key this file owns, so no sibling module's payload shape is depended on.
static func _lever_applies(actor: Actor, lever: StringName, zone: EnvironmentZoneDef) -> bool:
	match lever:
		LEVER_AFFINITY:
			return _affinity_weight(actor, zone) >= AFFINITY_FLOOR / AFFINITY_STRONG
		LEVER_GEAR:
			return not _tags(actor, GEAR_TAGS_KEY).is_empty()
		LEVER_TECHNIQUE:
			return not _tags(actor, TECHNIQUE_TAGS_KEY).is_empty()
		LEVER_PILL:
			return not _tags(actor, PILL_TAGS_KEY).is_empty()
	return false


## How hard this actor's spirit root bears on this zone, 0.0 when it does not.
## Scaled against `AFFINITY_STRONG` so a fully-rooted actor gets the full cap and a
## partial one is proportionally worth less.
static func _affinity_weight(actor: Actor, zone: EnvironmentZoneDef) -> float:
	if actor == null:
		return 0.0
	# Bounded `for` over the element ids this kind is hostile to. A kind with no entry
	# is hostile to nothing, so no spirit root can answer it.
	for entry in HOSTILE_ELEMENTS.get(zone.kind, []):
		var strength := actor.affinities.get_value(StringName(str(entry)))
		if strength >= AFFINITY_STRONG:
			return 1.0
		if strength >= AFFINITY_FLOOR:
			return strength / AFFINITY_STRONG
	return 0.0


static func _tags(actor: Actor, key: StringName) -> Array:
	var out: Array = []
	if actor == null:
		return out
	# Bounded `for` over the published tag list, which is authored content and small.
	for entry in actor.get_module_data(key).get("tags", []):
		out.append(StringName(str(entry)))
	return out


static func _status(actor: Actor, status_id: StringName) -> StatusEffect:
	# Bounded `for` over the actor's status list, which `tick_statuses` keeps pruned.
	for status in actor.statuses:
		if status.id == status_id:
			return status
	return null


## Hand the hazard to the `status` module's own runtime bookkeeping. The ONE place
## this file crosses that boundary, and it is a FACADE call (`modules/status/api.gd`),
## never a reach into `StatusRuntime` — the same edge `combat` and `loot` already hold.
##
## ## Why the hazard cannot be applied through `StatusApi.apply`
##
## `apply` builds its own `StatusEffect` from the def it resolves
## (`status/api.gd:_effect_for`), so it would spend the def's `share_per_pulse` against
## the def's `magnitude_cap` and throw away the residual THIS actor resolved against
## their own mitigation (`_amount`). `env_scourge` is also an AMBIENT def
## (`ambient = true`) and `apply` resolves the element-riding catalogue alone, so it
## refuses the hazard by name — which is correct: a landed blow can never inflict a
## place. `resolve` is the verb that keeps the instance this file built and gives it the
## runtime the tick path reads, and it resolves from either tree.
##
## ## Why a REFUSAL here is a loud failure, never a silent no-op
##
## A hazard that cannot register its runtime is exactly the defect this seam exists to
## close — a furnace that ages out and pays nothing — so it says so rather than
## returning the ordinary success shape. `tools arch` cannot see a refusal, only the edge.
## This is now a state the shipped content never reaches: `env_scourge` is an admitted
## ambient def, so a refusal here means an authored hazard stopped loading.
static func _resolve(actor: Actor, effect: StatusEffect) -> void:
	var answer := StatusApi.resolve(actor, effect)
	if not bool(answer.get("ok", false)):
		push_error(
			(
				(
					"EnvironmentField: status '%s' is on the actor but the status module refused "
					+ "to resolve it (%s); the hazard will age out without paying a pulse"
				)
				% [String(effect.id), String(answer.get("reason", "unknown"))]
			)
		)


static func _result(
	ok: bool, status_id: StringName, amount: float, lever: String, reason: String
) -> Dictionary:
	return {
		"applied": ok,
		"status_id": String(status_id),
		"amount": amount,
		"mitigated_by": lever,
		"reason": reason,
	}


static func _names(values: Array) -> String:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return ", ".join(out)


static func _lever_names(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return out
