class_name BodyLocation
extends LocationResolver

## Where a body strike LANDS: the meridian, the huyệt within it, and the multiplier that
## follows (ADR 0070, and `contracts/location_resolver.gd` for the shape of the answer).
##
## ## Granularity is the MERIDIAN, and the map is DATA
##
## `resolve_location` returns ONE `(meridian_id, point_id, multiplier)` triple — 20 aim
## buckets, legible at 2D sprite scale — and `broad_sites` returns one row per unlocked
## meridian. The 60 huyệt are the weak point WITHIN a location, never a second axis. The
## point -> meridian map is read from the authored `.tres` files through
## `CombatTuning.acupoint_data_dir`, so **no `.gd` here knows how many points a meridian
## has**: the shipped data is 3 for the fourteen primary/organ meridians, 4 for
## `chong_mai`/`dai_mai`/`du_mai`/`ren_mai` and 2 for the four `qiao`/`wei` ones, and a
## balance pass is entitled to move any of that without touching this module. Caching a
## constant of 3 here is exactly the defect that data exists to prevent.
##
## ## Deterministic aim, in all three modes
##
## `named` (the technique authored an id) / `random` / `broad`, and **no mode ever rolls**:
## every choice is a function of state, so the same body answers the same strike the same
## way twice and a readout can name the answer ("it found the jammed Lung node") instead of
## describing a coin flip. `random` is therefore the highest combined multiplier over
## every point of every unlocked meridian, with ties broken by id — a closed channel still
## answers, because an untrained channel is the softest place on a body and that is the
## read a player is owed. The `rng` argument exists only because the contract declares it,
## and it is never used: a resolver that rolled would make the same hit replay differently.
##
## ## What is locked, and what is a lever
##
## A huyệt the body HASN'T unlocked cannot be struck: there is no acupoint on the actor
## to hit, so the site falls back to the first point of the best-scoring channel, whose
## multiplier reads the neutral `1.0` — visibly ungated rather than silently 1.5x.
## `CombatStats.PENETRATION` is a resistance CUTTER and never appears here, because this is
## `resolve` and penetration is a mechanism's own mitigation (ADR 0068).
##
## ## Which classes it names, and why
##
## `LocationResolver`, `CombatTuning` and `BodyWounds` are all named here, and all three
## are permitted: the first is `contracts/`, the second is this module's own tuning type,
## and the third is a sibling file in `modules/combat_engine/`. Core's `MeridianState` is
## reached only by the CALL to `get_meridian()` / `state_rank()` — never by a type
## annotation — because `contracts/` cannot name a `core/` type and a bare annotation to
## one would make the file's shape disagree with the contract's. `body_cultivation` is
## named NOWHERE: no `AcupointSet`, no `Acupoint`, no `BodyStats`.

## An aim the technique did not author. Reads the highest multiplier, deterministically.
const MODE_RANDOM := &"random"
## The technique authored a meridian through `TechniqueDef.aim_meridian`.
const MODE_NAMED := &"named"
## An area strike: every unlocked meridian at `BROAD_MULT`.
const MODE_BROAD := &"broad"
## The `ctx.data` key carrying the aim mode. A per-HIT choice, unlike `aim_meridian`,
## which is authored on the `.tres` and never changes mid-exchange.
const AIM_MODE_KEY := &"aim_mode"
## The `ctx.data` key carrying the authored aim id.
const AIM_MERIDIAN_KEY := &"aim_meridian"
## The `ctx.data` key carrying a `BodyWounds` ledger for the defender, so the wound layer
## rides `ctx.data` — where a mechanism's own state crosses the seam — instead of a
## component lookup that `Actor.component()` would answer null for.
const WOUNDS_KEY := &"body_wounds"
## The `ctx.data` key overriding the tuning for one hit, matching `QiDamage.TUNING_KEY`:
## two mechanisms reading the same field by the same name is a feature.
const TUNING_KEY := &"tuning"
## The component key the acupoint set is read through. A `StringName` here because this
## module may not name the module that owns it; the same key `AcupointProvider` and
## `BodyCultivationApi` use, so there is one spelling of it in the codebase.
const ACUPOINTS_KEY := &"acupoints"

## The reserved row a strike on an empty network returns, so a caller can iterate a
## location answer without branching on "there was none".
const EMPTY_SITE := {"meridian_id": &"", "point_id": &"", "multiplier": 1.0}

static var _shipped: CombatTuning = null
static var _cached_dir: String = ""
static var _cached_map: Dictionary = {}


## The wound ledger for `actor`: the one already bound on the context, the one on the
## actor as a component, or a fresh one. A missing ledger is a supported state, not a
## failure — the caller binds one and the next hit finds it.
func wounds_of(target: Variant, _tuning: CombatTuning = null) -> BodyWounds:
	var existing: Variant = _read(target, &"components", null)
	if existing is Dictionary:
		var bound: Variant = (existing as Dictionary).get(WOUNDS_KEY, null)
		if bound is BodyWounds:
			return bound as BodyWounds
	return BodyWounds.new()


## Whether `actor` has a location axis at all. The honest question the contract asks,
## and the reason the contract exists rather than a null check: `Actor.component()`
## returns `RefCounted`, so `as BodyWounds` on null is silent and the failure surfaces
## three stages later as "the mechanism did nothing". Answered through the SAME network
## the mechanism reads its channels from, so the two can never disagree about who has a
## body.
func supports(_actor: Variant) -> bool:
	return _network_of(_actor) != null


## S4's location read. `technique` is a `Variant` read through `get()`, so this file
## acquires no compile-time edge to `modules/techniques/` — the same discipline
## `QiDamage.builder` uses for its authored inputs.
func resolve_location(
	_attacker: Variant, target: Variant, technique: Variant, _rng: RandomNumberGenerator = null
) -> Dictionary:
	# The `rng` the contract declares is NOT forwarded as `mode`: this resolver never
	# rolls (see the module docblock), so the aim mode can only come from the authored
	# id, and passing a generator where a `StringName` belongs is both a type error and
	# the one call shape that could have made a roll look intentional.
	return site_of(target, technique, &"")


## The location vocabulary itself, published so `BodyDamage` and a readout share ONE
## implementation of "where does this land" rather than two that could disagree.
##
## `mode` may be `&""`, which is the authored-`&""` answer and reads as `random`.
func site_of(target: Variant, technique: Variant, mode: StringName = &"") -> Dictionary:
	var network: Variant = _network_of(target)
	if network == null:
		return EMPTY_SITE.duplicate()
	var requested := _id_of(_mode_from(technique, mode))
	var candidate := &""
	if requested == MODE_NAMED:
		candidate = _aim_id(technique)
		# A `named` aim at a meridian this body never unlocked is a miss, not a
		# relabel: the technique is aimed at something that is not there.
		if candidate == &"" or _channel_of(network, candidate) == null:
			return EMPTY_SITE.duplicate()
	else:
		candidate = _best_meridian(network, target)
		if candidate == &"":
			return EMPTY_SITE.duplicate()
	return _site_in(network, target, candidate)


## Every site one `broad` strike touches: one row per UNLOCKED meridian, at
## `BROAD_MULT`, in sorted id order so two identical sweeps produce identical payloads.
## A broad strike on a body with no network is `[]`, and never one synthetic row.
##
## ## `BROAD_MULT` is clamped into `[0, 1]` on read — hole 3 in `BodyDamage`'s docblock
##
## `_positive(..., 1.0)` only floored it at zero and fell back to `1.0` for a non-finite
## value, so an authored `4.0` reached the multiplier untouched and a sweep's per-channel
## share out-scaled the single strike on that same channel — which is precisely the
## "strongest single hit in the game, twenty times over" the module exists to prevent.
## Clamped to `[0, 1]` the shipped `0.35` is BIT-FOR-BIT unchanged, while `4.0` and
## `1.0e9` both read `1.0`: a sweep is still the SUM of its channels, so it beats one
## strike and loses to twenty of them either way, and no authored number can invert it
## into twenty crits. A negative still reads `0.0` rather than inverting the sweep into a
## negative. `_share` is `BodyDamage`'s `[0, 1]` rate reader; this is `BodyLocation`'s own
## so neither file reaches through the other's internals for one clamp.
func broad_sites(target: Variant, tuning: CombatTuning = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var network: Variant = _network_of(target)
	if network == null:
		return out
	var resolved := _tuning_of(tuning)
	var share := _share(resolved.broad_mult)
	var ids: Array[StringName] = []
	for state in _all_meridians(network):
		var id := _id_of(_read(state, &"id", &""))
		if id != &"":
			ids.append(id)
	ids.sort_custom(_by_text)
	for id in ids:
		var site := _site_in(network, target, id)
		site["multiplier"] = maxf(0.0, site["multiplier"]) * share
		site["mode"] = String(MODE_BROAD)
		out.append(site)
	return out


## The three aim modes, as the mechanism reports them. A `String`, not a `StringName`, so
## `breakdown()` stays primitives-only in the shape `DamageProposal` itself demands.
static func mode_name(mode: StringName) -> String:
	return String(mode) if mode != &"" else String(MODE_RANDOM)


# --- internals -----------------------------------------------------------------


## One meridian, fully resolved. The multiplier is `point_multiplier * channel_mult * broad
## multiplier`, and every factor is clamped non-negative, so no corrupted acupoint state
## can produce a negative hit that S9's one sign flip would spend as a heal.
func _site_in(network: Variant, target: Variant, meridian_id: StringName) -> Dictionary:
	var channel: Variant = _channel_of(network, meridian_id)
	if channel == null:
		return EMPTY_SITE.duplicate()
	var tuning := _tuning_of(null)
	var point: Variant = _best_point(target, meridian_id, tuning)
	var point_mult := _point_multiplier_of(point, tuning)
	var channel_mult := _channel_multiplier(channel, tuning)
	var site := {
		"meridian_id": String(meridian_id),
		"point_id": String(_id_of(_read(point, &"id", &""))),
		"multiplier": _finite(maxf(0.0, point_mult) * maxf(0.0, channel_mult)),
		"point_multiplier": point_mult,
		"channel_multiplier": channel_mult,
		"point_score": 0.0 if point == null else _point_score(point, tuning),
		"state_rank": _rank_of(channel),
		"injured": bool(_read(channel, &"injured", false)),
		"locked": false,
		"tier": String(_read(_id_of(_read(point, &"tier", &"")), &"", &"")),
	}
	if site["point_id"] == "":
		# A channel with no huyệt ON the actor: the meridian exists, the weak point does
		# not. The site is still returned at the neutral multiplier so a caller can say
		# "the meridian was struck, nothing on it answered" instead of reporting no hit.
		site["locked"] = true
		site["point_multiplier"] = 1.0
		site["multiplier"] = _finite(maxf(0.0, 1.0 * maxf(0.0, channel_mult)))
	return site


## `1 + point_quality_step * quality`, with a JAMMED point reading `blocked_mult`
## instead — ADR 0070's one-flag-opposite-meaning inversion. Clamped into `[0, 1]` on the
## quality, so a hand-edited `.tres` cannot make the best point a damage reducer; and
## `blocked_mult` is read through the same non-negative guard as every other multiplier,
## because a negative one would invert the identity of a lost investment.
func _point_multiplier_of(point: Variant, tuning: CombatTuning) -> float:
	if point == null:
		return 1.0
	if bool(_read(point, &"blocked", false)):
		return _positive(tuning.blocked_mult, 1.0)
	return _finite(1.0 + _point_score(point, tuning))


## `1 + channel_mult_step * state_rank + injured_mult_step * (injured ? 1 : 0)`.
##
## The two halves of ADR 0070's second inversion: training a channel makes it a bigger
## target, and `MeridianState.injured` — the SAME flag whose `get_bonus() == 0.5` costs the
## cultivator half of every path's aggregate — pays the attacker back here.
func _channel_multiplier(channel: Variant, tuning: CombatTuning) -> float:
	var value := (
		1.0
		+ _non_negative(tuning.channel_mult_step) * float(_rank_of(channel))
		+ (
			_non_negative(tuning.injured_mult_step)
			if bool(_read(channel, &"injured", false))
			else 0.0
		)
	)
	return _finite(maxf(0.0, value))


## The highest-multiplier point on one meridian, ties broken by id. `random` and `named`
## both resolve through here, so there is one definition of "this meridian's weak point"
## and the two modes cannot each grow their own.
func _best_point(target: Variant, meridian_id: StringName, tuning: CombatTuning) -> Variant:
	var best: Variant = null
	var best_id := ""
	var best_score := -INF
	for point in _points_of(target, meridian_id):
		var id := String(_read(point, &"id", ""))
		var score := _point_score(point, tuning)
		if best == null or score > best_score or (score == best_score and id < best_id):
			best = point
			best_id = id
			best_score = score
	return best


## The `point_multiplier` a huyệt is worth, MINUS ONE, as a RANKING score. Deliberately
## SHAPE-equivalent to [method _point_multiplier_of] and built from the SAME two
## quantities in the SAME ratio — a ranking that ranked on anything else could pick a
## point whose own multiplier is LOWER than a point it beat, and `random` aim would then
## be aimed somewhere worse than the best available. A jam is the only discontinuity
## (`1.0 -> blocked_mult`, with no `quality` involved), and it lifts a jammed point above a
## maximum-quality one exactly by `blocked_mult - (1 + point_quality_step)`, which is the
## same margin by which it raises the multiplier — so ranking and damage cannot disagree
## about which huyệt is the weak point.
func _point_score(point: Variant, tuning: CombatTuning) -> float:
	if point == null:
		return 0.0
	var quality := clampf(_finite(float(_read(point, &"quality", 0.0))), 0.0, 1.0)
	var step := _non_negative(tuning.point_quality_step)
	if bool(_read(point, &"blocked", false)):
		return step + maxf(0.0, _positive(tuning.blocked_mult, 1.0) - 1.0 - step)
	return _finite(step * quality)


## The channel this strike lands on for a `random` aim: the highest combined multiplier
## over every point of every unlocked meridian. A CLOSED channel still answers — a
## `state_rank` of 0 contributes no armour AND no channel multiplier, so an untrained
## meridian is the softest place on a body, which is the read ADR 0070 wants and the one
## a player can be shown.
func _best_meridian(network: Variant, target: Variant) -> StringName:
	var best := &""
	var best_score := -INF
	var best_id := ""
	for state in _all_meridians(network):
		var id := _id_of(_read(state, &"id", &""))
		if id == &"":
			continue
		var site := _site_in(network, target, id)
		var score := float(site.get("multiplier", 0.0)) + float(site.get("point_score", 0.0))
		if best == &"" or score > best_score or (score == best_score and String(id) < best_id):
			best = id
			best_id = String(id)
			best_score = score
	return best


## The actor's huyệt bound to one meridian, through the authored map. `[]` for a body
## nobody attached an acupoint set to — a training dummy, not a crash.
func _points_of(target: Variant, meridian_id: StringName) -> Array:
	var out: Array = []
	var points: Variant = _read(_acupoint_set(target), &"points", null)
	if not (points is Array):
		return out
	for point in points as Array:
		if meridian_of_point(_id_of(_read(point, &"id", &""))) == meridian_id:
			out.append(point)
	return out


## The actor's acupoint set, read through the same key the body's own provider and its
## `api.gd` use, so there is one spelling. Null for a body nobody attached one to.
func _acupoint_set(target: Variant) -> Variant:
	var holder: Variant = _read(target, &"components", null)
	if not (holder is Dictionary):
		return null
	return (holder as Dictionary).get(ACUPOINTS_KEY, null)


## The meridian a huyệt trains, or `&""` when the id is unknown. The whole map, read
## once from DATA. Each authored `.tres` is read through `get()` for `id` and
## `meridian_id`, so this names no class of the module that owns the files; the result is
## cached per directory and re-read when the tuning points somewhere else.
static func meridian_of_point(point_id: StringName) -> StringName:
	if point_id == &"":
		return &""
	var map := _point_map(_tuning_of(null))
	return _id_of(map.get(String(point_id), &""))


## Every huyệt the authored definitions carry, as `{point_id: meridian_id}`. Built by
## listing the directory rather than by counting: the shipped data is 60 files over 20
## meridians at 3/4/2 per meridian, and a `3` written anywhere in a `.gd` would be a
## statement about content that lives somewhere else.
##
## **`ResourceLoader.load`, NOT `DirAccess.get_resource` — the latter does not exist.**
## Godot 4's `DirAccess` has `get_resource_file` (a probe that returns a path or `""`),
## not a loader; calling it raised `Invalid call. Nonexistent function 'get_resource' in
## base 'DirAccess'` on EVERY entry, so the map silently came back EMPTY for all sixty
## files. That is the whole reason `_points_of` found no acupoints on any body: no point
## ids, no point multipliers, no jam ranking, every site `locked` at the neutral `1.0`,
## and a location axis that could not tell a lung from a spleen. A `.tres` is loaded
## through `ResourceLoader` by path; `DirAccess` only ever tells you what is THERE.
static func _point_map(tuning: CombatTuning) -> Dictionary:
	var directory := tuning.acupoint_data_dir
	if directory.is_empty():
		return {}
	if directory == _cached_dir and not _cached_map.is_empty():
		return _cached_map
	var map: Dictionary = {}
	var dir := DirAccess.open(directory)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with(".") and entry.ends_with(".tres"):
				var def: Variant = ResourceLoader.load("%s/%s" % [directory, entry])
				var point_id := _id_of(_read(def, &"id", &""))
				var meridian_id := _id_of(_read(def, &"meridian_id", &""))
				if point_id != &"" and meridian_id != &"":
					map[String(point_id)] = meridian_id
			entry = dir.get_next()
		dir.list_dir_end()
	_cached_dir = directory
	_cached_map = map
	return map


## The aim mode for this hit: the per-hit override on `ctx.data`, else whatever the
## technique's authored id implies (`named` when it authored one, `random` when it did
## not). An unrecognised mode reads as `random`, never as an ungated strike.
static func _mode_from(technique: Variant, mode: StringName) -> StringName:
	if mode != &"":
		return mode
	return MODE_NAMED if _aim_id(technique) != &"" else MODE_RANDOM


## The authored aim id off a `TechniqueDef` OR a plain `{aim_meridian: id}` dictionary.
##
## The dictionary shape is not a convenience: `AttackContext` does not retain the
## `TechniqueDef` (see [method BodyDamage._aim_of]), so a mechanism reading the authored
## meridian back off `ctx.data` has to hand the resolver something. Reading both shapes
## here keeps `_aim_id` the ONE place that knows how an aim id is spelled, so `site_of`,
## `resolve_location` and `_mode_from` cannot each grow their own answer — and `Object`
## duck-typing still works for the real def.
static func _aim_id(technique: Variant) -> StringName:
	if technique is Object:
		return _id_of((technique as Object).get(&"aim_meridian"))
	if technique is Dictionary:
		return _id_of((technique as Dictionary).get(&"aim_meridian", &""))
	return &""


## The tuning for this read: the per-hit override, the shipped `.tres`, then a bare
## `CombatTuning.new()` whose every bound is 0.0 — a visibly broken balance rather than a
## plausible one (BRIEF 1.7).
static func _tuning_of(tuning: CombatTuning) -> CombatTuning:
	if tuning != null:
		return tuning
	if _shipped == null:
		_shipped = CombatTuning.shipped()
	return _shipped if _shipped != null else CombatTuning.new()


static func _network_of(value: Variant) -> Variant:
	return _read(value, &"meridians", null)


## One `MeridianState` off the network, or null. Duck-typed: `core/` may be named only
## through its own accessors, never through a type annotation.
static func _channel_of(network: Variant, meridian_id: StringName) -> Variant:
	if network == null or not (network is Object):
		return null
	if not (network as Object).has_method(&"get_meridian"):
		return null
	return (network as Object).call(&"get_meridian", meridian_id)


static func _all_meridians(network: Variant) -> Array:
	if network == null or not (network is Object):
		return []
	if (network as Object).has_method(&"get_all_meridians"):
		var listed: Variant = (network as Object).call(&"get_all_meridians")
		return listed if listed is Array else []
	return []


## `MeridianState.STATE_ORDER` lookup through the state's own method: closed 0, open 1,
## expanded 2, strengthened 3. Read rather than restated, so core is the only place the
## four states are numbered.
static func _rank_of(channel: Variant) -> int:
	if channel == null or not (channel is Object):
		return 0
	if not (channel as Object).has_method(&"state_rank"):
		return 0
	var value: Variant = (channel as Object).call(&"state_rank")
	return maxi(0, int(value)) if (value is float or value is int) else 0


## A read off any value that might be an `Object`, with a fallback. Named `_read` rather
## than `_get` because `Object` already defines `_get(StringName)` as an engine hook and
## a same-arity declaration collides with it, which fails the whole file to compile.
static func _read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


static func _id_of(value: Variant) -> StringName:
	return StringName(value) if value is StringName or value is String else &""


## `Array[StringName]`'s own `<` is a HANDLE comparison, not a text one: two ids interned
## from equal text are the same handle and compare equal, and two different ids compare
## by pointer, which is an allocation order nothing in this file controls. `broad_sites`
## documents "sorted id order so two identical sweeps produce identical payloads", so the
## order has to be the ORDER OF THE TEXT. `_meridian_ids` in the fixture sorts `String`
## for the same reason and the two must agree.
static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


static func _non_negative(value: Variant) -> float:
	return maxf(0.0, _finite(float(value))) if (value is float or value is int) else 0.0


static func _positive(value: Variant, fallback: float) -> float:
	return _finite(maxf(0.0, float(value))) if (value is float or value is int) else fallback


## A rate read out of DATA and clamped into `[0, 1]`: `BROAD_MULT` is the only one this
## file reads, and above `1.0` it makes a sweep's per-channel share out-scale the single
## strike on that same channel — see [method broad_sites]. Deliberately NOT `_positive`,
## which floors at zero and stops there; a negative `BROAD_MULT` is clamped to `0.0` (a
## sweep that deals nothing, which is the refusal) rather than turned into a negative
## damage that S9's one sign flip would spend as a heal.
static func _share(value: Variant) -> float:
	return clampf(_finite(float(value)), 0.0, 1.0) if (value is float or value is int) else 0.0


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
