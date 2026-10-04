class_name InstitutionResolver
extends RefCounted

## The composition root's institution resolver (BL-0198). Wiring, not rules: `app/`
## asks each institution module what it PROPOSES, and this turns each proposal into
## the facade call that does it.
##
## ## Why the split exists at all
##
## ADR 0085 is the shape, applied one layer up: *"the conflict module never calls
## combat, never reads a combat stat, and never owns an `rng`. It counts verdicts and
## pays the declared prize when the quota is met."* The same reasoning applies to a
## background tick — **a module that both decided and executed would be the political
## layer deciding its own outcomes**, and the only thing keeping that honest is a
## caller that resolves a proposal against a verb the module already implements.
## ADR 0114's handler shape says the same thing: a handler never mutates, it returns
## a proposal, and the director applies.
##
## ## This file calls the modules. It never owns one of their rules.
##
## Every verb below is a facade call with an explicit `periods` — the whole contract
## ADR 0085 asks for. `app/` never reaches into a ledger, never reads
## `actor.module_data`, and never holds a roster: it reads a proposal, dispatches on
## the CLOSED verb set, and counts. The rules that own the data are next to the
## feature, in the module, which is exactly what `app_state_warnings` in
## `tools/arch/enforce.py` asks `app/` to be.
##
## ## Zero new frame drivers
##
## Nothing here declares `_process`, reads `Time.get_ticks*` or reaches for
## `get_tree()`. The one `_process` in the game
## (`app/item_workbench_app.gd`) hands `delta` to `WorldPulse.pull`, which converts
## seconds into whole PERIODS and hands that integer down. `test_status_clock.gd`
## pins the tree to exactly three frame drivers, and this file is not a fourth.

## ## How often each tier reaches `periods`, and what that buys
##
## **The cadence is the PERIODS HANDED DOWN, and it is the only effect a tier has** —
## which is `InstitutionBudget`'s own rule ("the tier buys FREQUENCY of action, never
## SIZE of effect", `institution_budget.gd:37-42`) and ADR 0145's shape of the one
## institution verb that consumes a period count rather than merely ageing something.
##
## `near` is every period. `distant` is every fourth and `strategic` every sixteenth:
## both numbers are the shipped cadence this file has always published, and with the
## shipped `.tres` the whole budget is exactly those three divisors, so **a sect's duty
## is served `near + distant + strategic` periods per real period** and the three
## constants are one series rather than three folklore numbers.
const NEAR_PERIODS := 1
const DISTANT_PERIODS := 4
const STRATEGIC_PERIODS := 16
## Which of the three tiers `distant` actually authors — resolved at runtime rather
## than named as a literal, because the three tiers are `InstitutionBudget.TIERS` and
## an ordinal that drifts out of step with that array would silently invent a fourth
## name this file then has no period count for.
const DISTANT_TIER := InstitutionBudget.TIERS[1]
## Likewise `strategic`.
const STRATEGIC_TIER := InstitutionBudget.TIERS[2]


## Resolve whatever `sect` and `nation` propose for one whole period, and return what
## actually landed.
##
## `periods` is the count `WorldPulse` converted elapsed seconds into, and it is
## handed to every verb verbatim: a module accrues exactly the periods the caller
## says elapsed and none that it decided for itself (DEF-0111). How often each TIER
## reaches that count is the tier's own business — see the cadence note below and the
## budget it is bounded by.
##
## The return is primitives-only and carries the per-tier counts, so a caller can
## assert the budget was respected rather than trusting it — `SocialApi.tick`'s
## contract applied to an institution budget instead of a decay. The two headline
## counts, `acted` and `refused`, are the SUM of those per-tier rows: a verb that
## dispatched and was refused is counted once either way, and an actor no institution
## proposed anything for reads zero on both.
##
## ## Every verb is wrapped, because a proposal is not a guarantee
##
## The proposal is what the module WOULD do; the verb may still refuse — a seat the
## walk finished, a student who moved out of the band, a claim somebody else took
## first. A refusal is counted and reported, never thrown: a background tick that
## raised on one institution's refusal would take the whole frame with it, and the
## refusal is an ordinary outcome of a political world (ADR 0083's third state).
##
## ## `periods` is the count that ELAPSED, and every tier spends it on itself
##
## The caller owns time (DEF-0111), so this file may divide that count and must never
## multiply it: handing a verb `periods` twice would accrue four periods because two
## elapsed.
##
## Every tier is handed the **whole** count, which is what the `settle` contract above
## says and is the only reading under which a period of elapsed time is settled rather
## than silently dropped. It is also what bounds the work: `near + distant + strategic`
## is three dispatches against caps of `4 + 2 + 1`, so one real period costs at most
## seven actions however large `periods` grows — ADR 0085's two-transfer-passes rule is
## upheld by the shipped budget rather than by a clamp that was never needed.
static func settle(actor: Actor, periods: int) -> Dictionary:
	var out := {
		"ok": actor != null,
		"periods": periods,
		"near": {"proposed": 0, "acted": 0, "refused": 0},
		"distant": {"proposed": 0, "acted": 0, "refused": 0},
		"strategic": {"proposed": 0, "acted": 0, "refused": 0},
		"acted": 0,
		"refused": 0,
	}
	if actor == null or periods <= 0:
		# A period in which nothing elapsed is a frame in which the world did not
		# move, not a refusal — the same reading `WorldPulse.pull` gives a zero delta.
		out["ok"] = true
		return out
	_apply_tier(actor, _every(periods, NEAR_PERIODS), InstitutionBudget.TIERS[0], out["near"])
	# ## Why one period is paid THREE times, by design
	#
	# `wait_office` only ever ages a vacancy, so handing it the whole count twice would
	# age it identically twice and change nothing a caller could see. `serve_duty` is the
	# one verb here that CONSUMES a period count (`SectDuty.serve` pays `periods` down on
	# every open line), which is exactly why the ladder needs a third rung: with the
	# shipped `.tres`, a member is served `NEAR_PERIODS + DISTANT_PERIODS +
	# STRATEGIC_PERIODS` periods per elapsed period instead of `periods`.
	#
	# So the cadence above is REAL and it is a deliberate reading of ADR 0097's second
	# ladder: nothing scales a **rate** by a period count, and a payment is the scale of
	# an action. A different tier split — and this file's `match` is what a future one
	# would change — would move those three constants and nothing else.
	#
	# The three dispatches are separate `break`-bounded `for`s, never a merged list, so
	# each tier is still re-checked against its own cap before every dispatch and
	# `tests/arch_rules/test_no_unbounded_wait.gd` has nothing new to refuse.
	_apply_tier(actor, _every(periods, DISTANT_PERIODS), DISTANT_TIER, out["distant"])
	_apply_tier(actor, _every(periods, STRATEGIC_PERIODS), STRATEGIC_TIER, out["strategic"])
	# ## The two headline counts are SUMMED, never left at their initial zeros
	#
	# `acted` and `refused` are the only figures `WorldPulse` keeps
	# (`world_pulse.gd:385-386`), so they are the whole public account of whether the
	# world moved. They were literal zeros in the literal above and nothing ever wrote
	# them: `_apply_tier` mutates its own `row` in place and the loop bodies accumulate
	# into the per-tier halves. So `settle` reported "nothing happened" for every actor
	# in the game, every period, however many institutions acted — and every caller
	# reading those two keys was reading a constant.
	#
	# They are folded here, over the SHIPPED tier list rather than over the three
	# literal keys above, so a tier added to `InstitutionBudget.TIERS` and settled here
	# is counted rather than silently omitted from the total.
	for tier in InstitutionBudget.TIERS:
		var row = out.get(String(tier), null)
		if row is Dictionary:
			out["acted"] = int(out["acted"]) + int(row["acted"])
			out["refused"] = int(out["refused"]) + int(row["refused"])
	return out


## Every `step`-th period of the `total` that elapsed, counting from the first: three
## elapsed over a cadence of four is still one.
##
## **Integer arithmetic only, never a float**, because a cadence is an authored divisor
## and the count of periods must be exact: a `%` on a `float` would hand a verb `2.0`
## periods and round it somewhere nobody pinned. `step < 2` is the whole count, so `near`
## is unaffected by this helper and a hand-edited cadence cannot starve a tier.
static func _every(total: int, step: int) -> int:
	if step < 2 or total <= 0:
		return total
	return int(total / step)


## Ask one tier what it proposes, then dispatch each intent through the closed verb
## set. `row` is this tier's half of `settle`'s report, mutated in place.
##
## ## The budget is enforced by the `break`, not by a clamp afterwards
##
## `act` returns `acted <= cap` by construction, and the loop below re-checks it
## against the same shipped budget before each dispatch. The `for` walks an array
## sized by a bounded `act`, and the body breaks rather than continuing — the shape
## `tests/arch_rules/test_no_unbounded_wait.gd` accepts. **No `while` appears on this
## path, and no loop bound is a count another body mutates.**
static func _apply_tier(actor: Actor, periods: int, tier: StringName, row: Dictionary) -> void:
	var budget := InstitutionBudget.shipped()
	var cap := 0 if budget == null else budget.cap_for(tier)
	var sect := SectAct.empty(periods, tier, cap)
	if _found(actor, &"nation"):
		sect = NationApi.act(actor, periods, tier)
	elif _found(actor, &"sect"):
		# `SectApi` has no `act`: its facade is at the twelve-method cap ADR 0084 set
		# and the twelfth verb is `declare_schism` (see `sect_act.gd`). The decision
		# therefore lives beside `SectSuccession` and `SectTeaching`, which is the
		# repo's own answer to a full facade — fold the work into a component rather
		# than widen the surface `tools arch` fails the build for.
		sect = _sect_proposal(actor, periods, tier, cap)
	if not bool(sect.get("ok", false)):
		row["refused"] = int(row["refused"]) + 1
		return
	var intents: Array = sect.get("intents", []) as Array
	for intent in intents:
		if int(row["acted"]) >= cap:
			break
		var entry := intent as Dictionary
		row["proposed"] = int(row["proposed"]) + 1
		if _resolve(actor, periods, entry):
			row["acted"] = int(row["acted"]) + 1
		else:
			row["refused"] = int(row["refused"]) + 1


## The sect's proposal, read through the internal component. The actor's ledger is
## read through `SectApi.state` — a facade read — so this file never touches
## `actor.module_data` (the `APP_STATE_MARKERS` rule: `app/` wires and never holds a
## ledger).
static func _sect_proposal(actor: Actor, periods: int, tier: StringName, cap: int) -> Dictionary:
	var ledger := SectApi.state(actor)
	if not SectState.is_affiliated(ledger):
		return SectAct.empty(periods, tier, cap)
	var def := SectCatalog.instance().sect_definition(SectState.institution(ledger))
	var intent := SectAct.intent(ledger, def)
	if intent.is_empty():
		return SectAct.empty(periods, tier, cap)
	return SectAct.report(periods, tier, cap, [intent])


## Dispatch one intent. **The verb set is CLOSED and this `match` is the whole of
## it** — an intent naming anything else is refused by name rather than defaulted,
## because a default branch here would silently execute the wrong verb.
##
## `wait_office` ages a vacancy and nothing else: it never pays a grant, because ADR
## 0084's pacing is the point and a lesson granted for free makes disciples a faucet
## (BL-0188). `accrue_territory` settles exactly the periods asked for, which the
## module clamps to its own `standing_cap`.
static func _resolve(actor: Actor, periods: int, intent: Dictionary) -> bool:
	var verb := StringName(String(intent.get("verb", "")))
	match verb:
		&"wait_office":
			return bool(
				(
					SectApi
					. advance_succession(
						actor, StringName(String(intent.get("target", ""))), &"wait", periods
					)
					. get("ok", false)
				)
			)
		&"accrue_territory":
			return bool(NationApi.accrue_territory(actor, periods).get("ok", false))
		&"serve_duty":
			# Pay every open obligation line, one term at a time (ADR 0145). `SectDuty`
			# rather than a `SectApi` verb because the facade is at its twelve-method cap
			# and `institution_resolver.gd:100-104` records the repo's own answer to a
			# full facade: fold the work into a component, do not widen the surface.
			# `periods` is a count of periods to serve, so a long unpaid term pays down
			# over several ticks instead of in one.
			return bool(SectDuty.serve(actor, periods).get("ok", false))
		_:
			# Unknown verb: refused closed and NOT executed. `tests/arch_rules` and
			# `test_nation_act.gd` both read this line, so a fourth verb cannot be
			# added without somebody deciding what it resolves to.
			push_warning("InstitutionResolver: no verb '%s' -- refused closed" % String(verb))
			return false


## Whether `actor` lives under a polity of the given tier. Read through the facades
## rather than off `module_data`, so this file never holds a ledger. A sect and a
## nation are PEERS (ADR 0083), so the nation is asked first only because the shipped
## roster never holds both at once — not because one contains the other.
static func _found(actor: Actor, tier: StringName) -> bool:
	if tier == &"nation":
		return bool(NationApi.summary(actor).get("founded", false))
	return bool(SectApi.summary(actor).get("is_member", false))
