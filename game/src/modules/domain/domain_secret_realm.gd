class_name DomainSecretRealm
extends RefCounted

## The `foundation` module's facade, preloaded for the reason `DomainFixtures` states: a
## bare `FoundationApi.` out of `modules/*` is invisible to `tools arch`
## (`rules.BARE_REF_UNITS`), and the `res://` reference below is what makes the
## `domain -> foundation` edge both legal and counted.
const FoundationApi := preload("res://src/modules/foundation/api.gd")

## The `status` module's facade, for the same reason: the trial a site inflicts is a
## status, never a bespoke damage channel (ADR 0075).
const StatusApi := preload("res://src/modules/status/api.gd")

## A SECRET REALM is a one-time authored SITE that reforges a scarred foundation — the
## third of BL-0951 / ADR 0939's eight mending avenues (S9).
##
## ## What the avenue is, and what it costs
##
## The genre shape is a place that exists once, is dangerous to stand in, and is spent
## afterwards. Both halves of its price are real and neither is invented here:
##
## - **danger** — the site inflicts its authored `status_id` for `duration_s`, at its
##   authored `damage_share`, through the SAME `EnvironmentField` cadence a trap uses, so a
##   site hurts exactly the way every other authored hazard in a domain hurts and is
##   answered by the same four levers (ADR 0075). Nothing here subtracts health.
## - **time** — the reforge consumes the BODY's life through `FoundationApi.spend_periods`
##   (BL-0951 S6). Modules may not advance the world clock (ADR 0089 / DEF-0111), so the
##   cost is the cultivator's years and never the world's periods: closed-door work ages
##   the worker.
##
## It pays through the ONE contract S7 built: `FoundationApi.mend`, which still enforces
## `MEND_CAP`. The avenue owns its STEP and its PRICE; the foundation module owns the
## ceiling, and no avenue raises it.
##
## ## Why a SITE and not a fourth fixture kind
##
## `DomainFixtures.KINDS` is CLOSED and `DomainFixtures._resolve` refuses an unrecognised
## kind BY NAME — the guard that stops a typo becoming a fixture the game walks past. So a
## site carries the fourth kind in that closed set and is read by THIS file's verb rather
## than by `arm` / `attempt` / `claim`, which refuse it by kind: the authored row is the
## same shared shape, the run is the same run, and no verb changes meaning.
##
## ## One time EVER, not one time per run
##
## The site's ledger is a sibling of `DomainFixtures.STATE_KEY` under the same
## `DomainApi.MODULE_KEY`, and it is deliberately NOT cleared by `DomainApi.enter` (which
## clears only the fixture ledger, because a trap RE-ARMS on the next run). A secret realm
## is consumed: once reforged, that site is spent for the life of the actor, which is what
## makes it a one-time authored site rather than a reusable one wearing the name.
##
## ## This file reaches every sibling through a facade
##
## The ledger is `module_data` (ADR 0027), the life cost is `FoundationApi.spend_periods`,
## the trial is `Actor.add_status` + `StatusApi.resolve`, the mend is `FoundationApi.mend`,
## and the room comes from `DomainApi.room`. Nothing here reads a sibling's internals.

## The authored kind a site's `fixtures` row carries. One literal, one place, and it is
## the fourth member of `DomainFixtures.KINDS`.
const KIND := &"secret_realm"

## Where the site's own ledger lives inside the run — a SIBLING of
## `DomainFixtures.STATE_KEY`, never a nested row of it, because a site is not a fixture
## kind's ledger and folding one into the other would make `_record_of`'s shape the site's
## shape too.
const STATE_KEY := "secret_realms"

# --- reasons. Every refusal has a stable id a reader can show. ---------------

const OK_REFORGED := "reforged"
const ERR_NO_ACTOR := "no_actor"
const ERR_NO_RUN := "no_active_domain"
const ERR_UNKNOWN_SITE := "unknown_site"
const ERR_ALREADY_REFORGED := "already_reforged"
const ERR_NO_SNAPSHOT := "no_snapshot_to_mend"
const ERR_MEND_CAPPED := "already_at_the_mended_ceiling"
const ERR_NO_STEP := "authors_no_mend_step"
const ERR_NO_TRIAL := "authors_no_status_id"
const ERR_MEND_REFUSED := "mend_refused"

## How much of the body's life one reforge consumes, in PERIODS, when the site authors no
## cost of its own. Twelve periods is one day at the authored `TimeLadder` ratios — the
## same unit `FoundationApi.TRAINING_PRESS_PERIODS` prices a sitting in, so a reforge is
## priced in the currency the program already uses. A site MAY author more; the avenue owns
## this default only.
const DEFAULT_PERIOD_COST := 12

## The floor on an authored trial duration, for the reason `DomainFixtures.MIN_DURATION`
## carries one: a site that authored `duration_s: 0.0` would hand out a status that ages
## out before it pays, which is a price that reads as real and costs nothing.
const MIN_DURATION := 0.5

## The status a site inflicts when it authors none: `env_scourge`, the AMBIENT status
## (`res://src/data/statuses`, `StatusCatalog.AMBIENT_SOURCES_ROOT`) — the one status in
## the game authored for being STOOD IN rather than for being struck by, which is exactly
## what a site is.
const DEFAULT_TRIAL_STATUS := &"env_scourge"


## Reforge a scarred past realm at the site `fixture_id` inside `room_id`: the one verb
## this avenue publishes (BL-0951 / ADR 0939, S9).
##
## Answers `{"ok": true, "reason": "", "mended": {...}, "years": <float>, "spent": true}`
## on success and `{"ok": false, "reason": <named>}` on every refusal — never a bare `{}`,
## because a caller cannot tell "no such room" from "no such site" from a site already
## spent.
##
## ## The order of the gates is the order a player meets them
##
## already reforged, then the target realm, then the trial, then the step, then the mend —
## and **a refusal costs nothing** (ADR 0044): the years are spent only once the mend has
## been accepted, so a site that could not pay does not age the actor who asked it to.
##
## ## Which realm it lands on
##
## The caller's `realm_id` if it named one, else the site's own authored `realm_id`, else
## the WEAKEST scar (`FoundationApi.mend_target`) — the same default the elixir uses, for
## the same reason: lifting the worst scar raises the carried mean the fastest.
static func reforge(
	actor: Actor, room_id: StringName, fixture_id: StringName, realm_id: StringName = &""
) -> Dictionary:
	if actor == null:
		return _answer(false, ERR_NO_ACTOR, {})
	var site := _site(actor, room_id, fixture_id)
	if not site.get("ok", false):
		return site
	var fixture: Dictionary = site["fixture"]
	var about := _about(fixture, room_id)
	var key := String(site["key"])
	if _spent(actor, key):
		return _answer(false, ERR_ALREADY_REFORGED, about)
	var target := realm_id
	if target == &"":
		target = StringName(fixture.get("realm_id", ""))
	if target == &"":
		target = FoundationApi.mend_target(actor)
	about["realm_id"] = String(target)
	if target == &"":
		return _answer(false, ERR_NO_SNAPSHOT, about)
	# The site is FOR a scar: a realm never left has nothing to mend and a realm already at
	# the ceiling has nothing left to win. Both are read through the foundation module's
	# own readers rather than re-derived here.
	var standing := FoundationApi.snapshot_for(actor, target)
	if standing < 0.0:
		return _answer(false, ERR_NO_SNAPSHOT, about)
	if standing >= FoundationApi.MEND_CAP:
		return _answer(false, ERR_MEND_CAPPED, about)
	var step := float(fixture.get("foundation_mend", 0.0))
	if step <= 0.0:
		return _answer(false, ERR_NO_STEP, about)
	var trial := _inflict(actor, fixture, about)
	if not trial.get("ok", false):
		return trial
	var mended := FoundationApi.mend(actor, target, step, "secret_realm")
	if not bool(mended.get("ok", false)):
		return _answer(
			false,
			ERR_MEND_REFUSED,
			_merged(about, {"mend_reason": String(mended.get("reason", ""))})
		)
	var periods := int(fixture.get("period_cost", DEFAULT_PERIOD_COST))
	var years := FoundationApi.spend_periods(actor, periods)
	_write(actor, key, {"spent": true, "realm_id": String(target)})
	return _answer(
		true,
		OK_REFORGED,
		_merged(
			about,
			{
				"mended": mended,
				"periods": periods,
				"years": years,
				"trial_status": String(trial.get("status_id", "")),
				"spent": true,
			}
		)
	)


## What the site would do, WITHOUT touching the actor: the read a screen renders before a
## player commits, in the shape `DomainFixtures.telegraph` established. Free and
## non-mutating by construction — it reads the ledger and the record and writes nothing.
static func telegraph(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var site := _site(actor, room_id, fixture_id)
	if not site.get("ok", false):
		return site
	var fixture: Dictionary = site["fixture"]
	var about := _about(fixture, room_id)
	var target := StringName(fixture.get("realm_id", ""))
	if target == &"":
		target = FoundationApi.mend_target(actor)
	about["realm_id"] = String(target)
	about["standing"] = FoundationApi.snapshot_for(actor, target)
	about["mend_step"] = float(fixture.get("foundation_mend", 0.0))
	about["period_cost"] = int(fixture.get("period_cost", DEFAULT_PERIOD_COST))
	about["trial_status"] = String(_trial_status(fixture))
	about["damage_share"] = float(fixture.get("damage_share", 0.0))
	about["duration_s"] = maxf(float(fixture.get("duration_s", 0.0)), MIN_DURATION)
	about["mitigation_levers"] = _levers(fixture)
	about["spent"] = _spent(actor, String(site["key"]))
	return _answer(true, "", about)


# ── resolution ───────────────────────────────


## `{fixture, key}` on success, or an ANSWER on refusal. A row is a site when its authored
## `kind` says so AND it carries a mend step; a row that names the kind and mends nothing
## is an AUTHORING error refused by name, never a site that pays nothing while reading as a
## reward.
##
## Bounded by the room's authored array, and the room itself comes from `DomainApi.room`,
## which answers `{}` both outside a run and for a room the map does not hold.
static func _site(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	if actor == null:
		return _answer(false, ERR_NO_ACTOR, {})
	var room := DomainApi.room(actor, room_id)
	if room.is_empty():
		return _answer(false, ERR_NO_RUN, {"room_id": String(room_id)})
	for entry in room.get("fixtures", []):
		var fixture: Dictionary = entry
		if String(fixture.get("fixture_id", "")) != String(fixture_id):
			continue
		if StringName(fixture.get("kind", "")) != KIND:
			return _answer(false, ERR_UNKNOWN_SITE, _about(fixture, room_id))
		if float(fixture.get("foundation_mend", 0.0)) <= 0.0:
			return _answer(false, ERR_NO_STEP, _about(fixture, room_id))
		return {
			"ok": true,
			"reason": "",
			"fixture": fixture,
			"key": "%s/%s" % [String(room_id), String(fixture_id)],
		}
	return _answer(
		false, ERR_UNKNOWN_SITE, {"room_id": String(room_id), "fixture_id": String(fixture_id)}
	)


## Apply the site's authored trial, through the SAME status path every other authored
## hazard uses: `Actor.add_status` for the record and `StatusApi.resolve` for the runtime
## bookkeeping that makes it actually pay. A trial the status module will not resolve is a
## site that costs nothing, so it is refused BY NAME rather than passed over.
static func _inflict(actor: Actor, fixture: Dictionary, about: Dictionary) -> Dictionary:
	var status_id := _trial_status(fixture)
	if status_id == &"":
		return _answer(false, ERR_NO_TRIAL, about)
	var duration := maxf(float(fixture.get("duration_s", 0.0)), MIN_DURATION)
	var effect := StatusEffect.new(status_id, duration)
	effect.kind = StatusEffect.Kind.DOT
	# CULTIVATION scope for the same reason a trap is: a site is a place, and taxing the
	# player for standing on authored scenery is not a difficulty knob
	# (`EnvironmentField._hazard`).
	effect.scope = StatusEffect.Scope.CULTIVATION
	# REFRESH, not STACK: one site is one hazard, and a re-entry must never raise what a
	# stronger trial already landed.
	effect.stacking = StatusEffect.Stacking.REFRESH
	effect.magnitude = minf(float(fixture.get("damage_share", 0.0)), EnvironmentField.MAX_MAGNITUDE)
	effect.magnitude_cap = EnvironmentField.MAX_MAGNITUDE
	effect.tick_interval = EnvironmentField.hazard_cadence()
	# Copied off the fixture, never invented: the authored levers ARE the trial's
	# counterplay (ADR 0075), and this is what makes the applied status answer true to
	# `StatusEffect.has_mitigation()`.
	effect.mitigation_tags = _levers(fixture)
	effect.source = &"domain_secret_realm"
	actor.add_status(effect)
	var answer := StatusApi.resolve(actor, effect)
	if not bool(answer.get("ok", false)):
		return _answer(
			false,
			ERR_NO_TRIAL,
			_merged(
				about,
				{"status_id": String(status_id), "status_reason": String(answer.get("reason", ""))}
			)
		)
	return _answer(true, "", {"status_id": String(status_id)})


static func _trial_status(fixture: Dictionary) -> StringName:
	var authored := StringName(fixture.get("status_id", ""))
	return authored if authored != &"" else DEFAULT_TRIAL_STATUS


## The closed-set levers this site publishes, in authored order — the same reading
## `DomainFixtureLevers.published` performs, kept here rather than reached for because a
## site is not a trap and this file owns its own row shape.
static func _levers(fixture: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for lever in fixture.get("mitigation_tags", []) as Array:
		if EnvironmentZoneDef.LEVERS.has(StringName(lever)):
			out.append(StringName(lever))
	return out


# ── the ledger ───────────────────────────────


## Whether the site has been reforged. Read from the same `DomainApi.MODULE_KEY` payload
## the rest of the run lives in, under this file's own [constant STATE_KEY], which
## `DomainApi.enter` deliberately does NOT clear: a consumed site stays consumed.
static func _spent(actor: Actor, key: String) -> bool:
	if actor == null:
		return false
	var state := actor.get_module_data(DomainApi.MODULE_KEY)
	if state.is_empty():
		return false
	var ledger: Variant = state.get(STATE_KEY, {})
	if not ledger is Dictionary:
		return false
	var row: Variant = (ledger as Dictionary).get(key, {})
	if not row is Dictionary:
		return false
	# `int()` because a save has no bools and no int/float distinction — the same
	# normalisation `DomainFixtures._record_of` performs.
	return int((row as Dictionary).get("spent", 0)) != 0


static func _write(actor: Actor, key: String, patch: Dictionary) -> void:
	var state := actor.get_module_data(DomainApi.MODULE_KEY)
	if state.is_empty():
		return
	var ledger: Dictionary = state.get(STATE_KEY, {})
	ledger[key] = patch
	state[STATE_KEY] = ledger
	actor.set_module_data(DomainApi.MODULE_KEY, state)


## The whole run's sites as primitives, one row per authored site — including the ones
## nothing has touched, because a reader asking "what is in this room" must be able to see
## a site before it is spent. Folded into `DomainApi.summary()`'s read model rather than
## published as a new facade verb, the same move `fixtures` made.
static func summary(actor: Actor) -> Dictionary:
	var map_summary := DomainApi.map_summary(actor)
	if map_summary.is_empty():
		return {}
	var rows: Array = []
	for room in DomainApi.rooms(actor):
		var room_id := StringName(room.get("room_id", ""))
		for entry in room.get("fixtures", []):
			var fixture: Dictionary = entry
			if StringName(fixture.get("kind", "")) != KIND:
				continue
			var fixture_id := StringName(fixture.get("fixture_id", ""))
			var key := "%s/%s" % [String(room_id), String(fixture_id)]
			(
				rows
				. append(
					_merged(
						_about(fixture, room_id),
						{
							"realm_id": String(fixture.get("realm_id", "")),
							"mend_step": float(fixture.get("foundation_mend", 0.0)),
							"period_cost": int(fixture.get("period_cost", DEFAULT_PERIOD_COST)),
							"trial_status": String(_trial_status(fixture)),
							"spent": _spent(actor, key),
						}
					)
				)
			)
	return {"domain_id": map_summary.get("domain_id", ""), "sites": rows, "count": rows.size()}


# ── internals ────────────────────────────────


static func _about(fixture: Dictionary, room_id: StringName) -> Dictionary:
	return {
		"room_id": String(room_id),
		"fixture_id": String(fixture.get("fixture_id", "")),
		"kind": String(fixture.get("kind", "")),
	}


static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
