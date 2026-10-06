class_name DomainNarrative
extends RefCounted

## What a domain SAYS, keyed to the run's own state (ADR 0237).
##
## A domain run is a band of bosses with an exit gate (ADR 0229), and every layer above
## this one describes it as MECHANICS: rooms, bands, fixtures, a `remaining` list. What
## was missing is the sentence a player reads while walking it. A run that clears three
## doors and is published as `open_index: 3` has told the player nothing about why they
## are still inside.
##
## ## The whole model, in four facts
##
## 1. **A beat is AUTHORED CONTENT** — `beat_id`, a trigger, the lines it publishes, and
##    optional tags. It lives in `DomainTemplateDef.beats`, never hardcoded here, because
##    prose that ships in a script is prose a content author cannot edit.
## 2. **A trigger reads the RUN's own state** and answers yes or no: the room reached,
##    the discovered set, band progress (`open_index` / `cleared`), a fixture's ledger
##    row. Every unmet trigger returns a NAMED reason — a beat that stays silent is
##    indistinguishable from a beat nobody authored (AGENTS.md's refusal rule, ADR 0150).
## 3. **Resolution is a READ.** There is no `set_module_data` call anywhere in this file,
##    which is what makes it safe to fold into `summary()` — the read model a screen and
##    the headless driver already consume.
## 4. **There is NO fired-beat ledger, deliberately** (see the ADR-0066 note below).
##
## ## WHY THERE IS NO LEDGER OF WHICH BEATS FIRED
##
## "Did this beat already fire" is already answerable: a beat fires exactly when its
## trigger is met, and the trigger reads state that PERSISTS (`actor.module_data` — the
## discovered set, the band ledger, the fixture ledger). A parallel `fired: [ids]` array
## would be a second copy of a truth the first copy owns, and would disagree with it
## after a save/load — the exact failure `WorldBeat` and `BeatDirector` refuse in their own
## docblocks ("no registry of applied ids ... which is the ADR 0066 failure mode with a
## different name"). So the save round trip this class owes is the RUN's: a narrative read
## survives an `Actor.to_dict()` / `from_dict()` because it was never state of its own.
##
## ## WHAT THIS IS NOT: A SECOND "WHAT IS INTERESTING WHERE"
##
## `DomainMinimap` derives POI markers from authored ROOM TAGS, and its `POI_BY_TAG` is
## the one marker vocabulary in the game. A narrative beat names a room only as the
## CONDITION for firing — "once you have stood in `frost_laboratory`" — which is a
## question about the player, never a claim about the place. Nothing here ranks rooms,
## marks them, or answers "what is worth walking to"; that stays one vocabulary, read off
## one source (ADR 0073).
##
## ## EVERY WALK IS A BOUNDED `for`
##
## There is no `while` in this file. Every iteration is over a room array or an authored
## `Array`, and [method authored] stops one past [constant MAX_BEATS] so a hand-edited
## template cannot make this file build an unbounded row list. Oversize content is REFUSED
## BY NAME ([constant R_TOO_MANY_BEATS]) rather than truncated, because a truncated read
## model is one a screen renders as truth.

# ── the trigger vocabulary. CLOSED, so a typo is a red test, not a silent skip ──

## The player has stood in `room_id`. Matches the room's DEF id, so a beat authored
## against `frost_throne` fires in `frost_throne#0` — the generator namespaces a reused
## def, and an author writes the def they can see in the content tree.
const TRIGGER_ROOM_REACHED := &"room_reached"
## The discovered set has reached `count` rooms. The FOG measure (ADR 0207), read
## through the same durable set the minimap reads.
const TRIGGER_DISCOVERED := &"discovered"
## The band has opened `count` doors — ADR 0229's `open_index`, whose only writer is
## `DomainRun.record_kill`. So a progress beat can only fire on a kill.
const TRIGGER_BAND_PROGRESS := &"band_progress"
## The band is clear and the exit is claimable. The one beat that keys off the whole run.
const TRIGGER_BAND_CLEARED := &"band_cleared"
## A named fixture's ledger row has reached `field`. How a treasure claimed or a puzzle
## solved becomes a line rather than a `true` a player never sees.
const TRIGGER_FIXTURE := &"fixture"

const TRIGGERS: Array[StringName] = [
	TRIGGER_ROOM_REACHED,
	TRIGGER_DISCOVERED,
	TRIGGER_BAND_PROGRESS,
	TRIGGER_BAND_CLEARED,
	TRIGGER_FIXTURE,
]

## The ledger fields a `fixture` beat may read, and how each compares. `progress` is an
## int threshold; the other three are FLAGS, so a beat sets them and `count` is spare.
## Closed so a beat naming a field no ledger row carries refuses by name instead of
## silently reading a missing key as `false` forever.
const FIELD_PROGRESS := &"progress"
const FIELD_CLAIMED := &"claimed"
const FIELD_COMPLETE := &"complete"
const FIELD_SPENT := &"spent"
const FIXTURE_FIELDS: Array[StringName] = [
	FIELD_PROGRESS,
	FIELD_CLAIMED,
	FIELD_COMPLETE,
	FIELD_SPENT,
]

# ── reasons. Every refusal has a stable id a reader can show ─────────────────

## Published on the beat row whose trigger is met. `""` is the unfired row's reason, and
## `fired` is the boolean a caller branches on — the same split `DomainRun.exit_gate`
## makes between `gate` and `reason`.
const OK_FIRED := "fired"

## Nobody is in a domain, so there is no run for a trigger to read.
const R_NO_RUN := "no_run"
## The band was lost. A player who was defeated must not be reading a victory line, so
## EVERY trigger refuses rather than the cleared one alone firing.
const R_ABANDONED := "abandoned"
## A `room_reached` beat names no room. An authoring error: it could never fire.
const R_NO_ROOM_ID := "authors_no_room_id"
## The named room is not one this domain's own map built. Refused rather than assumed,
## because assuming would make a beat fire in a domain it was never written for.
const R_UNKNOWN_ROOM := "unknown_room"
## The player has not stood there yet.
const R_ROOM_NOT_REACHED := "room_not_reached"
## A `fixture` beat names no room or no fixture.
const R_NO_FIXTURE_ID := "authors_no_fixture_id"
## The ledger field is outside the closed [constant FIXTURE_FIELDS].
const R_UNKNOWN_FIELD := "unknown_fixture_field"
## The map authors no such fixture in that room.
const R_UNKNOWN_FIXTURE := "unknown_fixture"
## The fixture exists and its field has not reached `count` yet.
const R_FIXTURE_BELOW := "fixture_below"
## The band has opened fewer doors than `count`.
const R_BAND_BELOW := "band_below"
## The band is not clear.
const R_BAND_NOT_CLEARED := "band_not_cleared"
## The player has discovered fewer rooms than `count`.
const R_DISCOVERY_BELOW := "discovery_below"
## The trigger is outside the closed [constant TRIGGERS].
const R_UNKNOWN_TRIGGER := "unknown_trigger"
## A beat with no `beat_id`. It could not be named in a read model, which is most of what
## a beat is for.
const R_NO_BEAT_ID := "authors_no_beat_id"
## A beat that publishes nothing. Inert content would inflate `fired` while saying
## nothing, which reads as a broken narrative rather than an absent one.
const R_NO_LINES := "authors_no_lines"
## More lines than [constant MAX_LINES]. Refused, never truncated: a truncated line list
## is a story that stops mid-sentence and reports itself as complete.
const R_TOO_MANY_LINES := "authors_too_many_lines"
## The template authors more beats than [constant MAX_BEATS]. The whole read model is
## refused rather than published short.
const R_TOO_MANY_BEATS := "too_many_beats"

## How many beats one template may author. Beats are content, so a hand-edited count of
## ten thousand is a defect that must fail out loud rather than mint ten thousand rows a
## screen would hold; one step over is refused by name.
const MAX_BEATS := 64

## How many lines one beat may publish. The same bound on the other authored collection,
## and for the same reason: every line is copied into the read model a headless driver
## stringifies, so an unbounded one is the memory shape AGENTS.md records.
const MAX_LINES := 8


## The whole run's beat state as primitives, or `{}` when no domain is active.
##
## ## `{}` rather than a blank narrative
##
## "Not in a domain" and "in a domain that authors no beats" are different facts, and a
## screen must be able to tell them apart — the same reason `DomainRun.view` and
## `DomainFixtures.summary` both answer `{}`. Everything published is a String, an int, a
## bool, an Array or a Dictionary, so it survives the `JSON.stringify` hop the headless
## driver reads `summary()` through.
##
## ## One shape on every path
##
## `ok` and `reason` are always present, and `count` / `fired` / `lines` / `beats` are
## always present too — an oversize refusal publishes an EMPTY row list rather than a
## truncated one, so a caller never has to ask which shape it holds.
##
## ## It is a read, and only a read
##
## Nothing here writes. Folding this into `DomainApi.summary()` is therefore free, which
## is why it is a key in the read model rather than a thirteenth facade verb
## (`test_domain_api.gd:62` counts them).
static func resolve(actor: Actor, template: DomainTemplateDef) -> Dictionary:
	var shape := DomainApi.map_summary(actor)
	if shape.is_empty():
		return {}
	var beats := authored(template)
	var out := {
		"ok": true,
		"reason": "",
		"domain_id": String(shape.get("domain_id", "")),
		"template_id": "" if template == null else String(template.template_id),
		"count": beats.size(),
		"fired": 0,
		"lines": [],
		"beats": [],
	}
	if beats.size() > MAX_BEATS:
		# Named, loud, and EMPTY rather than short: a partially published narrative is a
		# story whose middle is missing and whose end is still asserted.
		out["ok"] = false
		out["reason"] = R_TOO_MANY_BEATS
		out["count"] = 0
		return out
	var ctx := _context(actor)
	var rows: Array = []
	var lines: Array = []
	for beat in beats:
		var row := _row(beat, ctx)
		rows.append(row)
		if not bool(row["fired"]):
			continue
		out["fired"] = int(out["fired"]) + 1
		for line in row["lines"]:
			lines.append(String(line))
	out["beats"] = rows
	out["lines"] = lines
	return out


## Whether ONE authored beat's trigger is met for `actor` right now, as
## `{ok, reason}`. NEVER `{}`, so "not in a domain" and "the trigger is unmet" are two
## answers a caller can tell apart rather than one absence.
##
## The single-beat read is what a scene resolving one line at the moment the player walks
## into a room goes through, and it shares [method _verdict] with [method resolve] so the
## two can never disagree about what a trigger means.
static func trigger_met(actor: Actor, beat: Dictionary) -> Dictionary:
	var meta := normalize(beat)
	var problem := _shape_problem(meta)
	if problem == "":
		problem = _line_problem(meta)
	if problem != "":
		return {"ok": false, "reason": problem}
	if DomainApi.map_summary(actor).is_empty():
		return {"ok": false, "reason": R_NO_RUN}
	return _verdict(meta, _context(actor))


## A template's authored beats, normalised, capped one past [constant MAX_BEATS].
##
## The cap is here and not only in [method resolve] because this is the function that
## COPIES every authored row: an uncapped caller would build the unbounded list first and
## refuse it afterwards. The extra element past the cap is what lets the caller tell
## "exactly at the limit" from "over it".
static func authored(template: DomainTemplateDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if template == null:
		return out
	# Bounded `for` over the template's own array with a `break`: the loop moves `out`
	# toward a FIXED count, so it cannot grow in lockstep with its own bound the way
	# `while out.size() < template.beats.size()` would (INC-0002).
	for raw in template.beats:
		if out.size() > MAX_BEATS:
			break
		out.append(normalize(raw as Dictionary))
	return out


## One authored beat, every field coerced and every key present.
##
## Normalised on read for the reason `DomainFixtures._record_of` gives: a beat can arrive
## from a hand-edited `.tres` or from `JSON.parse_string`, where a `true` comes back as
## `1.0` and an int as a float. Comparing `1.0` against a bool would silently disagree,
## so every field goes through `int()` / `String()` here and no caller does it twice.
static func normalize(raw: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	for line in raw.get("lines", []):
		lines.append(String(line))
	var tags: Array[String] = []
	for tag in raw.get("tags", []):
		tags.append(String(tag))
	return {
		"beat_id": String(raw.get("beat_id", "")),
		"trigger": String(raw.get("trigger", "")),
		"room_id": String(raw.get("room_id", "")),
		"fixture_id": String(raw.get("fixture_id", "")),
		"field": String(raw.get("field", "")),
		# `maxi(0, ...)`: a negative threshold is repaired rather than refused, because it
		# would otherwise make the beat fire unconditionally and read as authored intent.
		"count": maxi(0, int(raw.get("count", 0))),
		"tags": tags,
		"lines": lines,
	}


# ── internals ────────────────────────────────────────────────────────────────


## One published beat row: `fired` is the boolean, `reason` the word. Both present on
## every row so a caller never branches on the absence of a key.
static func _row(beat: Dictionary, ctx: Dictionary) -> Dictionary:
	var meta := normalize(beat)
	var problem := _shape_problem(meta)
	if problem == "":
		problem = _line_problem(meta)
	if problem != "":
		return _row_of(meta, false, problem, [])
	var verdict := _verdict(meta, ctx)
	var met := bool(verdict["ok"])
	var published: Array = (meta["lines"] as Array) if met else []
	return _row_of(meta, met, OK_FIRED if met else String(verdict["reason"]), published)


static func _row_of(meta: Dictionary, fired: bool, reason: String, lines: Array) -> Dictionary:
	var tags: Array = []
	for tag in meta["tags"]:
		tags.append(String(tag))
	return {
		"beat_id": String(meta["beat_id"]),
		"trigger": String(meta["trigger"]),
		"fired": fired,
		"reason": reason,
		"tags": tags,
		"lines": lines.duplicate(),
	}


## What is wrong with the beat's own SHAPE, before any state is read. A trigger outside
## the closed set is caught here so [method _verdict]'s final refusal stays the
## belt-and-braces one rather than the only one.
static func _shape_problem(meta: Dictionary) -> String:
	if String(meta["beat_id"]) == "":
		return R_NO_BEAT_ID
	if not TRIGGERS.has(StringName(meta["trigger"])):
		return R_UNKNOWN_TRIGGER
	return ""


## What is wrong with the beat's authored LINES. Kept apart from
## [method _shape_problem] because both [method resolve] and [method trigger_met] apply
## the same two, and one merged helper would make the "shape then lines" order implicit.
static func _line_problem(meta: Dictionary) -> String:
	var count := int((meta["lines"] as Array).size())
	if count == 0:
		return R_NO_LINES
	if count > MAX_LINES:
		return R_TOO_MANY_LINES
	return ""


## ## What a trigger reads
##
## One snapshot of the run, taken once per [method resolve] rather than once per beat:
## `discovered` is the fog as a set of DEF ids, `rooms_by_def` indexes the realized rooms
## by the def they were built from, and `run` is the normalised band ledger. Two reasons:
## a read that re-walked the map per beat would be O(beats x rooms), and — more to the
## point — two beats asking at different moments could see different state, so a story
## could disagree with itself inside one dictionary.
static func _context(actor: Actor) -> Dictionary:
	var discovered := {}
	var rows = DomainApi.discovered(actor)
	if rows is Array:
		for row in rows:
			discovered[_def_id(String(row))] = true
	var by_def := {}
	for room in DomainApi.rooms(actor):
		var fixtures: Array = []
		var entries = room.get("fixtures", [])
		if entries is Array:
			for entry in entries:
				fixtures.append(String((entry as Dictionary).get("fixture_id", "")))
		var realized := {"room_id": String(room.get("room_id", "")), "fixtures": fixtures}
		var def_id := _def_id(String(realized["room_id"]))
		if by_def.has(def_id):
			(by_def[def_id] as Array).append(realized)
		else:
			by_def[def_id] = [realized] as Array
	return {
		"actor": actor,
		"discovered": discovered,
		"rooms_by_def": by_def,
		"run": DomainRun.normalize(actor.get_module_data(DomainRun.MODULE_KEY)),
	}


## The DEF id behind a realized room id. `DomainGenerator._materialize` namespaces a
## reused def as `<def_id>#<n>`, so an author writing `frost_throne` must still match
## `frost_throne#1`. `allow_empty = false` keeps a trailing `#` from yielding `""`.
static func _def_id(room_id: String) -> String:
	var parts := room_id.split("#", false)
	return "" if parts.is_empty() else String(parts[0])


## The whole trigger decision, as `{ok, reason}`. Every branch names itself: there is no
## path out of this function that returns a bare `false`, which is what ADR 0150's "a
## press that quietly does nothing" looks like from a screen's side.
static func _verdict(beat: Dictionary, ctx: Dictionary) -> Dictionary:
	var run: Dictionary = ctx["run"]
	if bool(run.get("abandoned", false)):
		return {"ok": false, "reason": R_ABANDONED}
	var trigger := StringName(beat["trigger"])
	var observed := 0
	var unmet := R_UNKNOWN_TRIGGER
	if trigger == TRIGGER_ROOM_REACHED:
		return _room_reached(beat, ctx)
	if trigger == TRIGGER_FIXTURE:
		return _fixture_met(beat, ctx)
	if trigger == TRIGGER_BAND_CLEARED:
		return _cleared(run)
	if trigger == TRIGGER_BAND_PROGRESS:
		observed = int(run.get("open_index", 0))
		unmet = R_BAND_BELOW
	elif trigger == TRIGGER_DISCOVERED:
		observed = int((ctx["discovered"] as Dictionary).size())
		unmet = R_DISCOVERY_BELOW
	else:
		return {"ok": false, "reason": R_UNKNOWN_TRIGGER}
	return _at_least(observed, int(beat["count"]), unmet)


## A threshold read. `count` is a FLOOR and never a ceiling: "the band has opened at
## least one door" must keep firing after the second one opens, or a progress line would
## vanish the moment it became true.
static func _at_least(observed: int, required: int, unmet: String) -> Dictionary:
	var met := observed >= maxi(0, required)
	return {"ok": met, "reason": "" if met else unmet}


static func _cleared(run: Dictionary) -> Dictionary:
	var met := bool(run.get("cleared", false))
	return {"ok": met, "reason": "" if met else R_BAND_NOT_CLEARED}


## Whether the player has stood in the authored room.
##
## `unknown_room` is separated from `room_not_reached` deliberately: the first is an
## authoring error (this domain never built that room, so the beat is dead content in a
## template a player can walk) and the second is an ordinary answer about a player who
## has not gone there yet. Collapsing them would report "you have not been there yet" for
## a line that can never appear.
static func _room_reached(beat: Dictionary, ctx: Dictionary) -> Dictionary:
	var room_id := String(beat["room_id"])
	if room_id == "":
		return {"ok": false, "reason": R_NO_ROOM_ID}
	if not (ctx["rooms_by_def"] as Dictionary).has(room_id):
		return {"ok": false, "reason": R_UNKNOWN_ROOM}
	var met := (ctx["discovered"] as Dictionary).has(room_id)
	return {"ok": met, "reason": "" if met else R_ROOM_NOT_REACHED}


## Whether a named fixture's ledger row has reached `field`.
##
## `DomainFixtures` owns the ledger, so the row is read through its own public read and
## this file never re-derives what `claimed` means. The MAP is asked separately whether
## the fixture exists at all, because a ledger row reads as a full record even for a
## fixture nobody ever touched — so an absent fixture would otherwise report
## `fixture_below` forever rather than naming itself unresolvable.
static func _fixture_met(beat: Dictionary, ctx: Dictionary) -> Dictionary:
	var room_id := String(beat["room_id"])
	var fixture_id := String(beat["fixture_id"])
	var field := StringName(beat["field"])
	if room_id == "" or fixture_id == "":
		return {"ok": false, "reason": R_NO_FIXTURE_ID}
	if not FIXTURE_FIELDS.has(field):
		return {"ok": false, "reason": R_UNKNOWN_FIELD}
	var actor: Actor = ctx["actor"]
	var known := false
	var met := false
	for realized in _realized_rooms(ctx, room_id):
		var authored_ids: Array = realized["fixtures"]
		if not authored_ids.has(fixture_id):
			continue
		known = true
		var state := DomainFixtures.state_of(
			actor, StringName(realized["room_id"]), StringName(fixture_id)
		)
		if _field_met(state, field, int(beat["count"])):
			met = true
	if not known:
		return {"ok": false, "reason": R_UNKNOWN_FIXTURE}
	return {"ok": met, "reason": "" if met else R_FIXTURE_BELOW}


## The realized rooms built from `def_id`, as the bounded array [method _context] indexed
## — so a beat naming a def fires against every copy of it rather than only the first.
static func _realized_rooms(ctx: Dictionary, def_id: String) -> Array:
	var found = (ctx["rooms_by_def"] as Dictionary).get(def_id, [])
	return found as Array if found is Array else []


## `progress` is an int threshold; the rest are FLAGS, so `count` is spare and a missing
## key reads as `false` — which is the honest answer for a fixture nothing has touched.
static func _field_met(state: Dictionary, field: StringName, count: int) -> bool:
	if field == FIELD_PROGRESS:
		return int(state.get("progress", 0)) >= count
	return int(state.get(String(field), 0)) != 0