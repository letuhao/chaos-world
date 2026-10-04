class_name QuestApi
extends RefCounted

## Public facade for the `quest` module. Other modules may reference ONLY this
## file (`api.gd`).
##
## Concrete implementations live beside this file and are wired in `app/`.
##
## ## One shape, three kinds (BL-0053)
##
## BL-0053 names three kinds of quest — authored, systemic, emergent — and this
## module gives all three **one** shape. `QuestDef.kind` selects where a quest
## came from; it never selects a different rule. A kind that needed its own class
## would be three vocabularies for one idea, and the reader would be written
## three times.
##
## ## A quest READS the world's memory. It never counts its own progress.
##
## This is the whole point of ADR 0113. A step is satisfied by
## `WorldFactLedger.has(actor, step.fact, step.need)` — the one shared ledger a
## combat kill, an npc tally, a world event and a quest step all write. There is
## no per-quest progress counter anywhere in this module, so a save carries
## exactly one copy of "the player did X" and it is not ours. `advance()` reads
## that ledger; the world's other systems are what write to it.
##
## ## Completion is decided once, and the once-guard is not the caller's job
##
## `complete()` pays grants exactly once and `advance()` pays them exactly once.
## A second call answers `{ok: false, reason: "already_completed"}` and pays
## nothing (ADR 0061's precedent: a reward is decided in one place, and that
## place refuses the second decision).
##
## ## Gates are DATA (ADR 0065/0066)
##
## A requirement is a dictionary read through `DestinyApi.gate` — the six-verb
## evaluator — never GDScript. Adding a gated quest is a content edit.
##
## ## DEF-0107, closed
##
## Fate is earned from the ONE place a quest is marked complete, with the source
## string `"quest:<quest_id>"`, and fate keeps its own catalog: a fate id is never
## authored as `quest:*`. That rule is enforced in `QuestGrants`.

## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := QuestState.MODULE_KEY

## The three kinds BL-0053 names, re-exported so a caller naming a kind does not
## have to reach into `quest_def.gd` — the facade rule means this file is the
## only thing another module may reference.
const KIND_AUTHORED := QuestDef.KIND_AUTHORED
const KIND_SYSTEMIC := QuestDef.KIND_SYSTEMIC
const KIND_EMERGENT := QuestDef.KIND_EMERGENT

## The `source` string a fate grant carries, exactly as DEF-0107 prescribes it.
## DEF-0105 uses a bare `"combat"`, DEF-0108 uses `"event:<id>"`; the namespace
## is what makes a ledger's history explain WHERE a fate came from.
const FATE_SOURCE_PREFIX := "quest:"


## Attach the module to `actor`: normalize an empty ledger, drop entries naming
## content the catalog no longer ships, and leave the actor ready to be offered
## quests. Idempotent, and safe to call before anything has been accepted — the
## same contract `DestinyApi.attach` publishes.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(
		MODULE_KEY, QuestState.normalize(actor.get_module_data(MODULE_KEY), _known())
	)


## The authored catalog, as `{quest_id: QuestDef}`. A direct view of content, so
## a caller that wants a quest's authored text reads it here instead of reaching
## for the catalog singleton.
static func catalog() -> Dictionary:
	var out: Dictionary = {}
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def != null:
			out[String(quest_id)] = def
	return out


## Every quest whose `requirement` passes `DestinyApi.gate` for `actor` and which
## the actor has neither accepted nor completed, as primitive dicts.
##
## An already-accepted quest is NOT re-offered: `offered` is the first screen a
## player sees, and a quest they are already running on it is noise. A completed
## one never returns, which is what makes the once-guard visible from outside.
##
## ## `kind` is the OFFER rule, and this is where it is read
##
## This is the one place `QuestDef.kind` decides anything, and until it existed the
## field was the ADR 0065 lie in its purest form: a three-valued label with three
## call sites and **zero** readers, which read as a working reference and granted
## nothing. BL-0053 names three origins, so the three origins get three offers:
##
##   `authored`  — a person wrote this one, somebody HANDS it to you. Offered on
##                  its gate, exactly as before.
##   `systemic`  — "the simulation generated it; its steps are the facts the world
##                  already records, so it completes by living rather than by being
##                  handed out" (that docstring's own words). Nobody hands you a
##                  record of what already happened, so it is NOT offered here.
##   `emergent`  — "it appears from interacting systems" — the same shape: it is
##                  entered by [method advance] as its facts arrive, not listed on
##                  an offer board.
##
## The exclusion is the only asymmetry and it is deliberately narrow: a non-`authored`
## quest still ACCEPTS, still advances, still completes and still pays. It simply is
## not a thing an NPC puts in front of the player, which is what makes `kind` a fact
## about origin rather than a second name for `requirement`.
static func offered(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ledger := _ledger(actor)
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		if def.kind != KIND_AUTHORED:
			continue
		if QuestState.is_tracked(ledger, quest_id):
			continue
		if not bool(DestinyApi.gate(actor, def.requirement).get("ok", false)):
			continue
		out.append(_quest_view(def))
	return out


## Take `quest_id` on. Refuses rather than half-applying:
##   `unknown_quest`      — the catalog does not define it (a content bug).
##   `already_active`     — already accepted and not finished.
##   `already_completed`  — already paid; completion is decided once.
##   `gate_unmet`         — `DestinyApi.gate` refused, with `unmet` carried
##                           through verbatim so a panel renders the reason the
##                           gate itself produced rather than re-deriving it.
##
## `source` names where the offer came from (`"npc:elder"`, `"event:...``) and is
## recorded on the entry.
static func accept(actor: Actor, quest_id: StringName, source: String = "") -> Dictionary:
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null:
		return _refuse("unknown_quest")
	var ledger := _ledger(actor)
	if QuestState.is_completed(ledger, quest_id):
		return _refuse("already_completed")
	if QuestState.is_tracked(ledger, quest_id):
		return _refuse("already_active")
	var verdict := DestinyApi.gate(actor, def.requirement)
	if not bool(verdict.get("ok", false)):
		return _refuse("gate_unmet", verdict)
	if not QuestState.begin(ledger, quest_id, 0):
		# `begin` is the once-guard's own authority. Reaching here would mean two
		# readers of the same ledger disagreed, so the write is refused rather
		# than forced.
		return _refuse("already_active")
	_persist(actor, ledger)
	var out := {"ok": true, "reason": "", "unmet": []}
	out["quest_id"] = String(quest_id)
	out["source"] = source
	return out


## Every quest in flight: accepted, not yet completed, not yet failed. Primitive
## dicts, one per quest, carrying the live step tally so a panel does not have to
## call `steps()` per row.
static func active(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ledger := _ledger(actor)
	for quest_id in QuestState.active_ids(ledger):
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		var view := _quest_view(def)
		var steps := _steps_for(actor, def)
		var done := 0
		var required := 0
		for step in steps:
			required += 1
			if bool(step["done"]):
				done += 1
		view["steps_done"] = done
		view["steps_total"] = required
		view["ready"] = required > 0 and done >= required
		out.append(view)
	return out


## Every step of `quest_id` as `{step_id, fact, need, have, done, optional, label}`,
## read from the shared ledger. `have` is the ledger's count and `done` is that
## count against `need` — a step has no progress of its own to read.
static func steps(actor: Actor, quest_id: StringName) -> Array[Dictionary]:
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null:
		return []
	return _steps_for(actor, def)


## Recompute every ACTIVE quest's steps from the ledger and complete any whose
## REQUIRED steps all read done. Idempotent: calling it five times with no new
## facts completes nothing extra, because the second call finds every quest
## already completed and the once-guard refuses to pay again.
##
## This is the verb ADR 0114's director hands a beat to, and the one place an
## emergent quest chain advances: a world's interaction records a fact, the
## director offers the beat, this recomputes, and whatever crossed the line is
## completed here.
##
## `source` is recorded on each completion's grant ledger. Returns
## `{"ok": true, "completed": [quest_id, ...], "paid": [...], "unspent": [...]}`.
static func advance(actor: Actor, source: String = "") -> Dictionary:
	var ledger := _ledger(actor)
	var completed: Array[String] = []
	var paid: Array[Dictionary] = []
	var unspent: Array[Dictionary] = []
	for quest_id in QuestState.active_ids(ledger):
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		if not _required_steps_met(actor, def):
			continue
		var outcome := _complete(actor, ledger, quest_id, def, source)
		if bool(outcome["ok"]):
			completed.append(String(quest_id))
			for entry in outcome["paid"] as Array:
				paid.append(entry)
			for entry in outcome["unspent"] as Array:
				unspent.append(entry)
	return {"ok": true, "completed": completed, "paid": paid, "unspent": unspent}


## Mark `quest_id` complete explicitly, refusing when a REQUIRED step is unmet.
##
## The auto-path in `advance()` is the normal way a quest finishes; this is the
## hand-off for a caller that owns the moment — a dialogue that ran its course, a
## npc stage that reached its end (DEF-0122), a scripted ending — and wants the
## completion decided by the story rather than by a ledger tally.
##
## Refuses `unknown_quest`, `not_active` (never accepted), `already_completed`,
## and `steps_unmet` carrying the outstanding steps.
static func complete(actor: Actor, quest_id: StringName) -> Dictionary:
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null:
		return _refuse("unknown_quest")
	var ledger := _ledger(actor)
	if QuestState.is_completed(ledger, quest_id):
		return _refuse("already_completed")
	if not QuestState.is_tracked(ledger, quest_id):
		return _refuse("not_active")
	var outstanding := _outstanding_steps(actor, def)
	if not outstanding.is_empty():
		return _refuse("steps_unmet", {"unmet": outstanding})
	return _complete(actor, ledger, quest_id, def, "")


## The whole quest state as primitives, for a UI that wants one read.
##
## `quests` is `{quest_id: view}` over everything tracked, so a codex can render
## finished and in-flight rows without three facade calls; `active`/`completed`
## are id lists. No Resource and no `Actor` crosses this boundary.
static func summary(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	var quests: Dictionary = {}
	for quest_id in QuestState.active_ids(ledger):
		var def := QuestCatalog.instance().definition(quest_id)
		if def != null:
			quests[String(quest_id)] = _quest_view(def)
	for quest_id in QuestState.completed_ids(ledger):
		var def := QuestCatalog.instance().definition(quest_id)
		if def != null:
			quests[String(quest_id)] = _quest_view(def)
	var active_ids: Array[String] = []
	for quest_id in QuestState.active_ids(ledger):
		active_ids.append(String(quest_id))
	var completed_ids: Array[String] = []
	for quest_id in QuestState.completed_ids(ledger):
		completed_ids.append(String(quest_id))
	return {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"quests": quests,
		"active": active_ids,
		"completed": completed_ids,
		"offered": _offered_ids(actor),
		"ledger_available": QuestFactReader.available(actor),
	}


## The `{verb, id}` requirements `quest_id` declares, so a panel can say what is
## holding a quest back without re-deriving the six-verb grammar. Empty for an
## ungated quest; `{"known": false}` for an id the catalog does not define.
##
## Folded into the facade rather than given its own method on the catalog: the
## facade is under the twelve-method cap and "what is this waiting on" is a
## question every quest screen asks — the same reason `DestinyApi.summary` carries
## its own `blocked_by` rather than exposing `DestinyGate` to a UI.
static func gates_for(actor: Actor, quest_id: StringName) -> Dictionary:
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null:
		return {"known": false, "requirements": [], "unmet": []}
	var verdict := DestinyApi.gate(actor, def.requirement)
	var out: Array[Dictionary] = []
	for id in def.required_gate_ids():
		out.append({"id": String(id)})
	return {
		"known": true,
		"quest_id": String(quest_id),
		"ok": bool(verdict.get("ok", false)),
		"requirements": out,
		"unmet": verdict.get("unmet", []),
	}


# --- Internals -------------------------------------------------------------


## The actor's ledger, normalized, exactly as core persists it.
static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return QuestState.empty()
	return QuestState.normalize(actor.get_module_data(MODULE_KEY), _known())


static func _persist(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(MODULE_KEY, ledger)


static func _known() -> Dictionary:
	var out: Dictionary = {}
	for quest_id in QuestCatalog.instance().quest_ids():
		out[String(quest_id)] = true
	return out


## One quest as primitives: authored text plus the ids a panel needs. No Resource
## crosses the facade, because a UI may only hold this module's `api.gd`.
static func _quest_view(def: QuestDef) -> Dictionary:
	var steps: Array[Dictionary] = []
	for step in def.steps:
		if step == null:
			continue
		(
			steps
			. append(
				{
					"step_id": String(step.step_id),
					"fact": String(step.fact),
					"need": step.required_count(),
					"optional": step.optional,
					"label": String(step.display_name),
				}
			)
		)
	var grants: Array[Dictionary] = []
	for grant in QuestGrants.owed(def):
		grants.append(
			{
				"kind": String(grant["kind"]),
				"id": String(grant["id"]),
				"amount": int(grant["amount"])
			}
		)
	return {
		"id": String(def.id),
		"display_name": String(def.display_name),
		"description": String(def.description),
		"kind": String(def.kind),
		"tier": def.tier,
		"gated": not def.requirement.is_empty(),
		"steps": steps,
		"grants": grants,
	}


## Every step of `def` read against the shared ledger.
static func _steps_for(actor: Actor, def: QuestDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for step in def.steps:
		if step == null:
			continue
		var have := QuestFactReader.count(actor, step.fact)
		(
			out
			. append(
				{
					"step_id": String(step.step_id),
					"fact": String(step.fact),
					"need": step.required_count(),
					"have": have,
					"done": have >= step.required_count(),
					"optional": step.optional,
					"label": String(step.display_name),
				}
			)
		)
	return out


## Every REQUIRED step that is not yet done. An optional step is never
## outstanding: it is flavour the player may never do, and letting it block
## completion would make `optional` a lie.
static func _outstanding_steps(actor: Actor, def: QuestDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for step in _steps_for(actor, def):
		if bool(step["optional"]) or bool(step["done"]):
			continue
		out.append(step)
	return out


static func _required_steps_met(actor: Actor, def: QuestDef) -> bool:
	return _outstanding_steps(actor, def).is_empty()


## **The one place a quest is marked complete.** Both `advance()` and `complete()`
## route through here, which is what makes DEF-0107's "the one place" literally
## true rather than a convention two call sites could drift from.
##
## The once-guard is `QuestState.finish`: it returns false and writes nothing when
## the quest is already completed, and this function pays nothing on that path.
## Ordering matters — the guard runs BEFORE any grant is paid, so a repeat call
## cannot pay even the grants that have no once-guard of their own.
static func _complete(
	actor: Actor, ledger: Dictionary, quest_id: StringName, def: QuestDef, source: String
) -> Dictionary:
	if not QuestState.finish(ledger, quest_id):
		return {"ok": false, "reason": "already_completed", "paid": [], "unspent": []}
	# DEF-0107, verbatim: `earn_fate(actor, fate_id, "quest:<quest_id>")`. An
	# explicit `source` from the caller is appended so an ADR 0114 beat still
	# leaves an audit trail naming the moment, not just the quest.
	var payout := QuestGrants.pay(actor, def, quest_id)
	_persist(actor, ledger)
	return {
		"ok": true,
		"reason": "",
		"quest_id": String(quest_id),
		"source": source,
		"paid": payout["paid"],
		"unspent": payout["unspent"],
	}


static func _offered_ids(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for view in offered(actor):
		out.append(String(view["id"]))
	return out


## A refusal, optionally carrying another verdict's payload verbatim.
##
## `extra` is copied last and may add or overwrite detail keys, but never
## `reason` and never `ok`: those two are what the refusal IS. `accept` hands
## this the whole `DestinyApi.gate` verdict, which carries its own `reason`
## (`"unmet"`), so an unguarded copy silently replaced `gate_unmet` with
## `unmet` — a caller reading the documented reason got a word from another
## module's vocabulary instead. Detail (`unmet`) still crosses untouched, which
## is the whole point of passing the verdict through.
static func _refuse(reason: String, extra: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": reason, "unmet": []}
	for key in extra.keys():
		var name := String(key)
		if name == "reason" or name == "ok":
			continue
		out[key] = extra[key]
	return out
