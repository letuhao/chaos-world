class_name WorldStageReconcile
extends RefCounted

## ADR 0170's reconcile concern, lifted out of [WorldStage] so the arrival keeps ONE
## OWNER PER JOB. Nothing here is new: every seam, every refusal and every line of
## hazard prose below is code that used to sit on `world_stage.gd`, moved whole.
## `WorldStage.set_reconciler` / `has_reconciler` / `set_epoch_reader` /
## `has_epoch_reader` / `place_state` / `place_epoch` are still THE names a caller
## spells — `item_workbench_app.gd:372-373` installs both seams and
## `tests/app/test_reconcile_reachability.gd` asserts them — so only the file that
## holds them changed.
##
## ## The RECONCILER seam, and the hazard it must not grow a guard in front of
##
## `set_reconciler` is the third injection on the stage and the same inversion again:
## `app/` installs `Callable(WorldPulse, "observe_place")` and this file names no clock
## type at all. It exists because ADR 0170's reconcile had **zero production callers**,
## so a place never aged while you were away — the mechanism was built, exported and
## tested and no player could reach it.
##
## **The arrival IS the observation.** `mount` and `enter` are the only two moments that
## change the stage's place, and ADR 0113 makes the owner of the moment the writer, so
## the reconcile is fired there and nowhere else. It is fired **UNCONDITIONALLY** —
## see [method observe_place]. A seam that is installed but only called when the place
## is already known fresh is the ADR 0173 (c) deadlock with extra steps: nothing errors,
## every elapsed calculation silently reads zero, and the world never moves again.
##
## ## ## Why this is a FILE, and not another 200 lines on the stage
##
## `world_stage.gd` went over `gdlint`'s 1000-line cap and past `tools/arch`'s 400-line
## SRP budget, and the reconcile is what pushed it over. The split is SRP in the plain
## sense — one stage, two reasons to change, a playfield arriving and a world clock
## folding — and it is also the rule `tools/arch/rules.py:239` states about `app/`:
## the composition root WIRES, it does not own state. The folded age per place, kept so
## a read model can report it without re-calling the fold, is state, and state belongs
## beside its concern.
##
## ## A member of the stage, not a global — and the statics are still static
##
## The two seams stay `static` because they are installed ONCE per process by `app/`
## (`item_workbench_app.gd:372-373`, re-pointed on a rebirth at `:721-722`) and every
## stage reads them. The folded answer is per-stage, so it is per-INSTANCE and reaches
## [WorldStage] through [member stand_at] / [member observe_place] / [member forget].
## Two kinds of lifetime on one concern, kept distinct rather than flattened.

## Fold this place's clock when somebody ARRIVES (ADR 0170 trigger (a)). Installed by
## `app/` as `Callable(WorldPulse, "observe_place")`; a null one means the reconcile has
## no owner, which is REPORTED on the arrival rather than guessed around.
static var _reconciler: Callable = Callable()
## Answer which epoch a place is LIVING, without folding anything (ADR 0170's overlay).
## Installed by `app/` as `Callable(WorldPulse, "place_state")`, beside the reconciler and
## deliberately separate: one MUTATES on arrival and one DERIVES on every read.
static var _epoch_reader: Callable = Callable()

## What the LAST reconcile to this place answered, kept for the reason the stage's own
## `_published` is: a place that reconciled and a place whose fold is unwired must not
## answer alike, because "silently stale" is exactly what ADR 0170 refuses to leave
## unreported. A dictionary, not a bool, because the two ways this can fail are different:
## no seam installed is a wiring gap, while a named refusal is the world fold saying
## something in particular about this place.
var _reconciled: Dictionary = {"ok": false, "reason": "not_reconciled"}
## Where this stage stands, and who is standing there — **set by the stage, never by a
## caller and never by a test**, which is why it arrives as arguments to [method stand_at]
## rather than being a second place this file could be told about. `place_state` reads
## `_location_id` precisely so that "this world resolves at the epoch it lived" and "a
## stage that never arrived, asserting its floor about the empty string" cannot be the
## same reading; `test_reconcile_reachability.gd:539` is what pins that difference.
var _location_id: StringName = &""
var _actor: Actor = null


## Install the seam that folds a place's clock when somebody arrives (ADR 0170 (a)).
## `app/` passes `Callable(WorldPulse, "observe_place")`; the callable is
## `func(location_id: StringName) -> Dictionary` answering `{elapsed_periods, ...}`.
##
## **Installed at boot beside `set_location_publisher`, not at the arrival.** A seam
## installed inside `mount` would leave every arrival before the first one unfolded, and
## the arrival is the only place this fires — the same "wired, but only once someone has
## already travelled" hole `set_interaction_handler`'s docstring names for the press.
##
## Passing an empty `Callable` clears it, so a boot that deliberately runs without the
## world fold — a headless probe, a suite asserting the `no_reconciler` refusal —
## uninstalls it deterministically rather than only overwriting it.
static func set_reconciler(reconciler: Callable) -> void:
	_reconciler = reconciler


## Install the seam that answers which epoch a place is LIVING (ADR 0170's overlay).
## `app/` passes `Callable(WorldPulse, "place_state")`; the callable is
## `func(location_id: StringName, occurrences: Array = []) -> Dictionary`.
##
## **A SEPARATE seam from the reconciler, and the reason is the two questions are
## different.** `observe_place` MUTATES — it folds a clock and is a trigger, fired only
## on arrival. `place_state` DERIVES — it computes which of the ledger's occurrences the
## place is currently living and is a READ, answerable at any moment for any place. Firing
## the reader only on arrival is the half-built version of ADR 0170 (c) this file must not
## ship: a panel asking "what is this world NOW" about a place nobody is standing in
## would get nothing at all, which is the deadlock in a read-only costume.
static func set_epoch_reader(reader: Callable) -> void:
	_epoch_reader = reader


## Whether a place's clock has an owner at all. Published on `summary()` so a probe
## can tell the missing seam from a seam that answered.
static func has_reconciler() -> bool:
	return _reconciler.is_valid()


## Whether the epoch overlay has a reader. Published on `summary()` for the same reason
## `has_reconciler` is: "the world resolves to epoch 1 because nothing retired it" and
## "nothing can answer" must not be the same reading.
static func has_epoch_reader() -> bool:
	return _epoch_reader.is_valid()


## The stage records where it stands before it reconciles, so the epoch READ below is
## about a real place. **Arguments, not a setter pair, because the two arrive together** —
## an `enter` assigns the actor and the place on adjacent lines and an epoch read between
## them would be about the previous arrival's place.
func stand_at(location_id: StringName, actor: Actor) -> void:
	_location_id = location_id
	_actor = actor


## The last answer [method observe_place] gave, or [method forget]'s reset, handed back so
## the stage's OWN return dictionaries can read it as fields. A getter rather than a
## published field because the answer is this object's state, and `mount`/`enter` need it
## immediately after the fold they just fired.
func reconciled() -> Dictionary:
	return _reconciled


## ## THE EPOCH READER — what this place IS NOW, not what is standing in it
##
## With no `occurrences` the ledger's own rows are read and each is stamped at
## [constant WorldEpoch.FIRST], because **the ledger records no epoch and never will**:
## `WorldFact` is monotone and a mutable epoch field on it would be the second writer
## ADR 0113 forbids. That is precisely why the overlay exists — the epoch lives beside
## the facts and the reader decides which of them a place is currently living.
##
## **A READ: it folds nothing**, which is the whole reason it is a second seam rather
## than a field on [member _reconciled]'s answer. With no seam installed this answers
## [constant WorldEpoch.FIRST] with nothing applied rather than refusing — a world nobody
## has rebuilt IS epoch one, and a refusal would make "no reader" and "nothing has
## happened" two words for one absence.
func place_state(occurrences: Array = []) -> Dictionary:
	if not _epoch_reader.is_valid():
		return _unreadable()
	var rows := occurrences
	if rows.is_empty() and _actor != null:
		rows = _ledger_occurrences(_actor)
	var answered: Variant = _epoch_reader.call(_location_id, rows)
	if not answered is Dictionary:
		return _unreadable()
	return answered as Dictionary


## The monotone ledger as the overlay's own row shape, `{id, epoch, amount}`, with every
## row at [constant WorldEpoch.FIRST]. A READ of the ledger and no write to it: ADR 0170
## is explicit that "a reconcile READS it and never rewrites it".
func _ledger_occurrences(actor: Actor) -> Array:
	var out: Array = []
	for id in WorldFact.ids(actor):
		out.append(
			{"id": String(id), "epoch": WorldEpoch.FIRST, "amount": WorldFact.count(actor, id)}
		)
	return out


## The epoch this place is living, as a primitive. Separate from [method place_state]
## because "which history is this world living" is answerable without any occurrence, and
## a read model is primitives all the way down (ADR 0038's contract).
func place_epoch() -> int:
	return int(place_state().get("epoch", WorldEpoch.FIRST))


## `place_state`'s two refusals share ONE answer, because they ARE one absence: nothing
## can answer. A missing seam and a seam that answered with something other than a
## dictionary must not be two readings, so both answer epoch one with nothing applied.
func _unreadable() -> Dictionary:
	return {
		"world_id": String(_location_id),
		"epoch": WorldEpoch.FIRST,
		"retired": false,
		"applied": [],
		"deferred": [],
		"counts": {}
	}


## THE RECONCILE. Fold the arriving place's clock against the world fold's own span, and
## report what it became.
##
## ## ## THE HAZARD — there is deliberately no presence guard, and there must never be one
##
## ADR 0173 (c) names it: "an observation-driven clock DEADLOCKS if every advance source
## is itself gated on someone being present. The world freezes forever, every elapsed
## calculation returns zero, and the failure is silent."
##
## So the ONLY thing this method asks before firing is whether a SEAM is installed, which
## is a wiring fact and not a presence fact. **There is no `if visited`, no `if
## knows_place`, and no check of anything the place knows about itself.** An arriving
## player is the trigger; the fold runs whether or not the place has ever been stamped,
## and a place nobody has stood in folds the WHOLE span on its first arrival — that is the
## property `tests/app/test_reconcile_reachability.gd` pins, because it is the one that
## a future "skip the fold we have already done" optimisation would silently remove.
##
## ## It does NOT undo the arrival on a refusal
##
## Same posture the stage's publish takes: the player really did travel and
## `world_spawn`'s ledger is the durable truth. A missing seam is a wiring gap and a
## refused fold is the world fold's own answer, and both are REPORTED on `summary()` so
## neither is silent — a silent reconcile is indistinguishable from a frozen world.
##
## ## Neither is the ACTOR an argument
##
## [method stand_at] has already recorded it, and the fold is keyed by PLACE alone —
## `WorldPulse.observe_place` takes a `location_id` and nothing else, which is what lets
## one fold serve every body that arrives at the same place.
func observe_place(location_id: StringName) -> Dictionary:
	if not _reconciler.is_valid():
		_reconciled = {"ok": false, "reason": "no_reconciler"}
		return _reconciled
	var answered: Variant = _reconciler.call(location_id)
	if not answered is Dictionary:
		_reconciled = {"ok": false, "reason": "reconciler_returned_nothing"}
		return _reconciled
	var out: Dictionary = (answered as Dictionary).duplicate()
	# **The seam's own `ok` is READ, not trusted.** A reconciler that answered without
	# one has said nothing about whether it folded, and a place reporting a clean zero
	# from a seam that never said so is the silent-freeze shape ADR 0173 (c) names — so
	# an absent verdict is `false` and is NAMED, rather than read as a fold that happened.
	out["ok"] = bool(out.get("ok", false))
	out["reason"] = String(out.get("reason", ""))
	# **Kept, not just returned.** `summary()` and the arrival answer both read
	# `_reconciled`, so a method that computed the fold and dropped it left every reader
	# reporting the initial `not_reconciled` — the wiring looked present and the place
	# still read as never folded. The stored answer is the whole point of holding it: "a
	# place that reconciled and a place whose fold is unwired must not answer alike".
	_reconciled = out.duplicate(true)
	return _reconciled


## Drop the answer with the place, and the place itself with it. The stage calls this from
## `leave` and from nowhere else.
##
## **The fold is NOT undone and this asymmetry is the point.** The stamp is monotone and
## `WorldPulse` owns it, so the next arrival reads how far behind the world really is
## rather than folding the same span a second time — a stage that took the answer back
## would make a REBORN hero's fold look like the place it just left. No decrement verb
## appears here and none may: `WorldFact` is monotone (ADR 0113).
func forget() -> void:
	_reconciled = {"ok": false, "reason": "left"}
	_location_id = &""
	_actor = null


## This concern's half of the stage's `summary()` — the seam health, the place's age
## through the fold, and the DERIVED state under the epoch overlay.
##
## ## WHY IT IS A METHOD AND NOT INLINED IN THE STAGE'S OWN `summary()`
##
## One place builds these eight keys, so the read model cannot carry seven of them
## without the eighth, and so a future key lands beside the concern that owns it rather
## than in a dictionary literal two hundred lines from it. ADR 0038's contract is that a
## screen's `summary()` is primitives all the way down, which is why these are FLATTENED
## here rather than returned as one nested dictionary a panel would read as `null`.
func summary() -> Dictionary:
	return {
		"reconciler_installed": _reconciler.is_valid(),
		"epoch_reader_installed": _epoch_reader.is_valid(),
		"reconciled": bool(_reconciled.get("ok", false)),
		"reconciled_reason": String(_reconciled.get("reason", "")),
		"reconciled_periods": int(_reconciled.get("elapsed_periods", 0)),
		"place_periods": int(_reconciled.get("folded_periods", 0)),
		# The place's DERIVED state under the epoch overlay. A retired world's occurrences
		# stay on the monotone ledger; this is what says which of them the place is
		# currently living, and it is DERIVED on every read rather than stored.
		"epoch": place_epoch(),
		"epoch_retired": bool(place_state().get("retired", false)),
	}
