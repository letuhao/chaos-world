class_name ItemWorkbenchPlay
extends Control

## The composition root's PLAY half: the actor it holds and the four clocks that
## answer for it — the world period, the anchor repair, the death poll and the
## autosave.
##
## ## Why this is a base script and not a `ItemWorkbenchApp` method
##
## Extracted from `item_workbench_app.gd` because that file passed the thousand-line
## ceiling and the twenty-public-method cap, and because these are not the SHELL's
## job. The shell's job is mounting a screen and answering "where is the player" —
## [method ItemWorkbenchApp.navigate_to], [method ItemWorkbenchApp.summary] and the
## route table. This half is what a body IS: who it is, what period it has advanced
## to, what it costs to stand next to a hearth, and what happens when it dies. Two
## reasons to change, so two files (AGENTS.md, "one module = one reason to change").
##
## ## Why inheritance and not delegation
##
## **The public surface is the contract, and it does not move.** Every verb below is
## called on the mounted root by a screen, a probe or a suite — `advance_world`,
## `poll_death`, `actor()`, `raise_anchor` — so moving one to another object would
## leave a caller naming a method that is not there. A base class keeps all of them
## ON the same instance: `ItemWorkbenchApp` still answers every one of them, and
## `get_script_method_list()` on it reports the inherited declarations too, so
## `tests/app/test_screen_reachability.gd` still sees the whole door surface.
##
## ## What the split is NOT allowed to break
##
## Two suites read `item_workbench_app.gd` as TEXT and would go red for the right
## reason if the wiring they check moved here:
##
##   - `tests/app/test_status_clock.gd` requires `StatusLoop.new(` and `func _process(`
##     to appear in `item_workbench_app.gd` and NOWHERE ELSE under `res://src`, because
##     one tick caller is ADR 0106's whole claim. Neither is below.
##   - `tests/modules/save/test_cultivation_boot_round_trip.gd` slices that same file
##     between `func restore_actor` and `func restored_from_save`, so both stay in it.
##
## `_ready`, `_process`, `restore_actor`, `_build_actor` and `adopt_actor` therefore
## all stayed in the shell. What moved is what they call, and nothing they call calls
## back into the shell — so there is no cycle for a reader to follow in either
## direction.
##
## ## No clock of its own, and no `while`
##
## Every accrual here takes the elapsed time or the period count from the caller that
## owns it (DEF-0111); nothing reads `Time.get_ticks_*`, which is what
## `tests/app/test_status_clock.gd` asserts. There is no loop in this file at all, so
## `tests/arch_rules/test_no_unbounded_wait.gd` has nothing to rule on.
##
## The autosave takes PERIODS, not seconds (ADR 0179): it is an accrual verb like every
## other one here, so it rides the same explicit count as the world fold rather than a
## frame delta of its own.

var _actor: Actor = null
## What [code]NpcBoot.populate_room[/code] answered at boot: how many bodies stood up
## and who they are. Held so a probe can read the cast without reaching past `app/` —
## the live instances themselves stay in `npc`'s own registry, which is where ADR 0092
## says a room's occupants live.
var _npc_settlement: Dictionary = {}
## The world's clock and the ONE place a beat reaches a sink (ADR 0117, DEF-0111).
## A director with no production instance is the same defect as a facade with no
## callers: `add_sink` / `offer` were tested and a player could never reach them.
var _world: WorldPulse = null
## The death resolver (ADR 0130). Polled from [method ItemWorkbenchApp._process] like
## every other clock here, because a module may not declare its own frame driver
## (DEF-0111) and a FOURTH `_process` fails `tests/app/test_status_clock.gd`.
var _death: SoulDeath = null
## The actor id the death poll is currently watching. Armed on adoption and re-armed on a body
## swap, so a poll never fires twice for the same body and never fires for a replaced one.
var _death_armed: String = ""
## The last resolved death, as primitives, so `summary()` can report what happened without a
## screen re-deriving it.
var _last_death: Dictionary = {}
## The world fold's running period total as of the last [method advance_world], so the autosave
## is told what MOVED rather than what was asked for (ADR 0179).
##
## **Reset by [method adopt_world], and that reset is load-bearing.** `adopt_actor` builds a
## fresh `WorldPulse` whose total starts at zero, so without the reset the first
## `AUTOSAVE_PERIODS` world-moving periods after a rebirth read `maxi(0, total - _periods_seen)`
## as `maxi(0, small - large)` = **0** — the autosave schedule silently under-counts for
## that many periods and no player is told. The delta is only meaningful within ONE fold.
var _periods_seen: int = 0


## Advance the world by exactly `periods` whole periods, with no elapsed time — the
## player-facing half of the tick. `EventApi.advance` refuses `periods <= 0` by
## design (ADR 0085), so nothing accrues without a caller saying how much.
##
## ## The autosave rides the SAME count, on the SAME path
##
## The save must be told what the WORLD actually advanced rather than what was asked for.
## The report's `periods` is the world fold's own running TOTAL, so the delta against the
## last one seen is exactly what moved — which is how a chunked long skip (ADR 0173) reports
## the whole span it paid for rather than one ceiling's worth of it.
##
## **Every advance this file makes passes through here**, including the chunked ones, so a
## caller never has to ask which of the two shapes it is about to drive.
func advance_world(periods: int) -> Dictionary:
	if _world == null:
		return {"ok": false, "reason": "no_world"}
	var outcome := _world.advance_periods(periods) as Dictionary
	poll_save(_advanced_by(outcome))
	return outcome


## ## The retreat verb: a SEASON-SCALE action that costs world time (ADR 0167)
##
## **The chosen length IS the cost.** `periods` is what the player asked to sit for, and
## it is paid through [method advance_world], which chunk-plans it against the fold's own
## `MAX_PERIODS_PER_PULL` and REFUSES a span the plan cannot cover. Nothing here truncates:
## a refused plan returns `{"ok": false}` with the fold's own reason and `paid == 0`, which
## is the loud half of ADR 0173's "It never truncates" (`AGENTS.md:56`).
##
## **Gain is proportional to periods PAID, not periods DECLARED** — the ADR 0167 half that
## makes a meditation interruptible. `paid` comes from the fold's own `moved`, read
## against the total before this call, so it is a measurement and not a restatement of
## the ask; `unpaid` is therefore `declared - paid`, and a fully-paid retreat reports zero
## of it. A caller that previews a cost and then pays a different one can read both.
##
## **No `periods` reaches a module facade here.** ADR 0167 decides that a cultivation verb's
## `amount` stays a qi amount (`modules/qi_cultivation/training.gd:42`) and this file is
## the caller that owns time, so a retreat's per-period work is whatever the caller asks
## for once per PAID period — not an argument this method grows to pass.
##
## `magnitudes` is [code]TimeLadder.magnitudes_crossed[/code] read over the PAID span, so
## a coarser cost is reported in the clock's own authored units rather than in a second
## set of numbers invented here (ADR 0173: the ladder is the one calendar).
func retreat(periods: int) -> Dictionary:
	var before := 0 if _world == null else int(_world.summary().get("periods", 0))
	var outcome := advance_world(periods) as Dictionary
	var paid := _advanced_by_reading(outcome, before)
	return (
		outcome
		. duplicate(true)
		. merged(
			{
				"declared": maxi(0, periods),
				"paid": paid,
				"unpaid": maxi(0, maxi(0, periods) - paid),
				"magnitudes": TimeLadder.magnitudes_crossed(paid),
			}
		)
	)


## How many whole periods `outcome` moved the fold by, measured against the total read
## BEFORE the call.
##
## ## Why not the report's `periods`
##
## That key is the fold's running TOTAL, and [method advance_world] already consumes that
## delta for the autosave (ADR 0179) — reading it a second time here would see
## `_periods_seen` already advanced and report zero. So the pre-call total is captured by
## the caller and this is the difference between the two, which is the same measurement
## [method _advanced_by] makes, taken from the other side.
func _advanced_by_reading(outcome: Dictionary, before: int) -> int:
	if not bool(outcome.get("ok", false)):
		return 0
	return maxi(0, int(outcome.get("periods", 0)) - before)


## How many whole periods this advance moved the world by, read from the report the world fold
## returns. A report whose total did not RISE moved nothing.
##
## **The clamp is gone from this method's reasoning, because the clamp is gone from the
## fold.** It used to sit here as the reason the delta existed at all; now the fold pays a
## declared span in full through its chunk plan (`world_pulse.gd:255-271`), so the delta
## measures a real movement rather than a shortfall against a ceiling.
func _advanced_by(outcome: Dictionary) -> int:
	var total := int(outcome.get("periods", 0))
	var moved := maxi(0, total - _periods_seen)
	_periods_seen = total
	return moved


## Point this root at a new world fold and reset the delta with it.
##
## **One door, so a body swap cannot forget the reset.** `adopt_actor` builds a fresh
## `WorldPulse` whose running total starts at zero; a `_periods_seen` left on the old
## body's total would swallow the next `AUTOSAVE_PERIODS` world-moving periods into a
## `maxi(0, total - _periods_seen)` of zero — a silent under-count of the schedule
## (ADR 0179), with nothing anywhere reporting that periods went unrecorded.
func adopt_world(world: WorldPulse) -> void:
	_world = world
	_periods_seen = 0


## Advance the world by exactly ONE period. **The verb a screen's "wait a season"
## button and a headless probe both call**, so neither has to know the cadence or
## pass an argument a driver would hand over as a string.
##
## ## An anchor repairs HERE, because this is the period boundary
##
## `AnchorApi.repair` takes explicit `periods` precisely because nothing may own a clock
## (DEF-0111), and this is the caller that owns one. **Wiring it anywhere else would leave the
## building feature a set of headless verbs**: the hearth would exist, be raisable, and never
## heal anybody in play. The repair is REPORTED rather than swallowed, because a player who
## waits a season at a hearth and sees nothing happen cannot tell a bug from a feature that
## never fired.
func advance_one_period() -> Dictionary:
	var outcome := advance_world(1)
	outcome["anchor_repair"] = _repair_at_anchor()
	return outcome


## Raise `anchor_id` where this actor stands, and report what it cost.
##
## **The door a construction screen and a probe both call**, so neither has to know the
## authored cost shape. Refusals are the module's own (`cannot_afford`, `already_raised`,
## `realm_floor`), passed through verbatim rather than re-worded.
func raise_anchor(anchor_id: StringName) -> Dictionary:
	return AnchorApi.raise_anchor(_actor, anchor_id, String(_actor.id))


## Select the difficulty this run is played under, and report the scalars it now answers with.
##
## **The door a settings screen and a probe both call.** Persisting the id rather than the
## resolved numbers is what keeps an old save meaningful after a retune (ADR 0129).
func select_difficulty(difficulty_id: StringName) -> Dictionary:
	var outcome := DifficultyApi.select(_actor, difficulty_id)
	if not bool(outcome["ok"]):
		return outcome
	return {
		"ok": true,
		"reason": "",
		"difficulty_id": String(difficulty_id),
		"scalars": DifficultyApi.scalars(_actor),
	}


## Repair the soul from whatever raised anchor stands, for `periods` whole periods.
func _repair_at_anchor(periods: int = 1) -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor", "restored": 0}
	return AnchorApi.repair(_actor, periods)


## The world's own view of itself, published beside [method ItemWorkbenchApp.summary] so a
## probe can tell a dead director from a quiet one without reaching into the pulse.
func world_summary() -> Dictionary:
	return {} if _world == null else _world.summary()


## Resolve a death for the current body, once.
##
## **Armed on the actor id, so one body dies once.** A poll that fired on every frame would
## charge the soul repeatedly for a single wound, and re-arming after a body swap is the only
## reason a rebirth can happen at all. Called from [method ItemWorkbenchApp._process] and
## directly by tests and probes, so the rule is testable without driving frames.
##
## A body with no lives left stays in place rather than being swapped for null: there is nowhere
## to swap TO, and a null actor would take every screen with it.
func poll_death() -> Dictionary:
	if _death == null or _actor == null:
		return {}
	# ## Armed on a body that has ALREADY been watched once, never on a body whose first
	# ## watch this is
	#
	# The once-rule used to arm HERE, on the first poll after an adoption: `_ready` and
	# `adopt_actor` both set `_death_armed = ""`, so the first `poll_death` of every body
	# only recorded the id and returned `{}`. The game survived it because `_process`
	# polls every frame and arms on frame one; a caller that kills a body and polls ONCE
	# got the arming frame instead of the death — `test_creation_play_wiring.gd::poll_death`
	# and its `_rebody()` helper were exactly that caller, and 20 cases failed on it.
	#
	# So arming is keyed on the id having been WATCHED, not on it being the current one:
	# the first poll of a body asks `is_dead` and fires on it. A poll that finds a live
	# body re-arms, so the once-rule still holds and a guardian heal (which leaves the
	# body standing) cannot make the same wound fire twice.
	if _death_armed != String(_actor.id) and not _death_armed.is_empty():
		_death_armed = String(_actor.id)
		return {}
	if not _death.is_dead(_actor):
		_death_armed = String(_actor.id)
		return {}
	_last_death = _death.resolve(_actor)
	# Re-arm whatever stands now, so a guardian death does not re-fire next frame and a rebirth
	# arms the NEW body rather than the one that fell.
	_death_armed = String(_actor.id)
	# A death is a thing that happened to the world, so it is saved immediately rather than
	# waiting for the next boundary: the run state that matters most is the state at death.
	SaveApi.persist(_actor, String(DifficultyApi.current_id(_actor)))
	return _last_death


## The last resolved death, as primitives. `{}` before anything has died.
func last_death() -> Dictionary:
	return _last_death.duplicate(true)


## Write the save if the clock says one is due.
##
## **The player never decides when this happens.** The clock counts whole periods and the save
## lands on a boundary they never see, which is the requirement rather than a limitation
## (ADR 0128).
##
## **`periods` is a COUNT handed down, never seconds** (ADR 0179). The engine's frame delta is
## not an input here: the autosave was the last wall-clock holdout among the accrual verbs, and
## it is gone. A sub-period delta cannot fire the schedule because the schedule has no idea how
## long a period is — only how many have passed.
func poll_save(periods: int) -> Dictionary:
	if not SaveApi.clock.advance(periods):
		return {}
	return SaveApi.persist(_actor, String(DifficultyApi.current_id(_actor)))


## Mint a fresh body for `arrival_id` — the composition root's half of a rebirth.
##
## The body is built through the SAME arrival table character creation uses, so a returning
## soul arrives the way a first one does and there is one rule for "how does a hero arrive"
## rather than two. Refuses an arrival the catalog does not define rather than minting a hero
## nothing can explain.
func mint_body(arrival_id: String, incarnation: int) -> Dictionary:
	var arrival := StringName(arrival_id)
	if SoulCatalog.instance().arrival_definition(arrival) == null:
		return {"ok": false, "reason": "unknown_arrival"}
	return CharacterCreationFlow.build_forced(arrival, incarnation)


## The actor this root is currently holding, or null before boot builds one.
##
## **Public because a rebirth makes the actor MOVE.** A screen bound to the body that fell is
## reading a dead hero, and the only way for it to follow is to ask the root rather than cache
## what it was handed. The alternative — every screen re-reading on a signal — is a second
## mechanism for the one fact the root already owns.
func actor() -> Actor:
	return _actor


## The save's own condition, as primitives, so a status line can report that saving happened
## without asking permission and without naming the backup.
func save_summary() -> Dictionary:
	return SaveApi.summary()


## The soul, the difficulty, the anchors and the save, as primitives, so a probe can assert the
## wiring without reaching into a module.
func soul_summary() -> Dictionary:
	return {
		"soul": SoulApi.soul(_actor),
		"difficulty": String(DifficultyApi.current_id(_actor)),
		"anchors": AnchorApi.summary(_actor),
		"last_death": _last_death,
		"save": SaveApi.summary(),
	}


## ## The CURRENT-room roster, and why it is not the payload below
##
## [method npc_presence] is a BOOT-TIME settlement — minted once by
## [code]NpcBoot.populate_room[/code] into `mortal_plains` and deliberately NOT restocked
## on a rebirth, because `STARTING_CAST` is a fact about the settlement the slice opens
## on rather than a property of a body. It stays published for the probe that wants to
## read what boot did.
##
## **A player-facing roster must NOT key on it.** It is minted once and never moves, so a
## screen painting it shows the same four people for the whole session, in a room the
## player may have walked out of, with nothing on screen to tell the reader. That is the
## defect DEF-0261 recorded, and it is why the panel keys on [method npc_roster_bridge]'s
## location instead. Nothing here feeds the panel.
##
## This door exists because `ui/` may reach `npc` and `world_spawn` through NEITHER
## facade (neither is in `rules.UI_MODULES`) and may not name `app/` at all — the same
## shape as `_loot_bridge` and `_world_bridge`, for the same reason.
func npc_roster_bridge() -> NpcRosterBridge:
	return NpcRosterBridge.shared()


## Who is standing in the settlement this root stocked at boot (BL-0626).
##
## Published for the same reason `routes()` is: a probe or a test must be able to
## READ what the boot did without reaching into `npc`'s registry or re-deriving the
## cast list. The answer is `populate_room`'s own dictionary verbatim — a count, the
## location id, and one read-model row per npc — so nothing here can disagree with
## what was actually minted.
func npc_presence() -> Dictionary:
	return _npc_settlement.duplicate(true)
