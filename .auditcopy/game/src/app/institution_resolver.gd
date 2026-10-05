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
##
## ## These three are CONTENT CADENCE in the SSOT's own unit, and they stay authored
##
## **A count of periods cannot drift from a ratio of seconds-per-period**: converting one
## to the other needs seconds, and the unit is already spent. They are divisors, not
## ratios — `_every(periods, NEAR_PERIODS)` is how often a tier reaches a count someone
## else decided elapsed (ADR 0145, `InstitutionBudget`'s "the tier buys FREQUENCY, never
## SIZE"), and no ladder magnitude is 4 or 16 either.
##
## `near` IS the base — every period is `TimeLadder.ratio_for(BASE)` — and **GDScript will
## not let a `const` say so**: `ratio_for` reads the shipped `.tres`, so it is not a
## constant expression and the compiler refuses outright ("Assigned value for constant
## `NEAR_PERIODS` isn't a constant expression"). `TimeLadder.PERIOD_SECONDS` and
## `TimeLadder.BASE` ARE constant expressions; anything behind a `static func` is not.
## So it is written as the base it is and the base row is checked against it at runtime
## (`_check_base_row`) rather than by the compiler.
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
## ## The SSOT's magnitudes arrive here as the SPAN, not as a second calendar
##
## `crossed` is [code]TimeLadder.magnitudes_crossed[/code] over the periods that were
## PAID, handed down by the caller that owns time. It is what an action's declared cost
## becomes in the clock's own authored units (ADR 0173), and it reaches a consumer that
## already exists: the tier cadence below is a frequency folded out of a period count,
## which is exactly what `_every` does. **So the coarse magnitudes are folded through
## the same helper, never a second cadence function of its own** — a ladder walked twice
## by two helpers is the drift ADR 0066 exists to refuse, and `InstitutionResolver`
## already states that no ladder magnitude is 4 or 16 (`institution_resolver.gd:49-55`).
##
## A missing `crossed` is not an error: it reads as the base row only, so a caller that
## settles a plain count — every advance in the tree except the retreat — settles on the
## cadence it always did and the fold of magnitudes is a no-op rather than a change of
## rate nobody authored.
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
static func settle(actor: Actor, periods: int, crossed: Dictionary = {}) -> Dictionary:
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
	_check_base_row()
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
	# ## The coarse magnitudes REACH a cadence, on the STRATEGIC rung
	#
	# `distant` and `strategic` are authored divisors — a content decision nobody asked
	# the ladder about, which is why they stay constants. The coarse rows are not: they
	# are the SSOT's own answer to "how much time passed", handed down by the caller that
	# owns it, and a strategic act is the one tier whose cadence is meant to name a
	# political AGE rather than a number of ticks.
	#
	# So the period count reaching this tier is the span in the ladder's own base units
	# **plus every coarser magnitude that span covers** — one year of periods counts as
	# one year's worth here, not as however many period-sized steps it happened to be cut
	# into. `crossed` arrives already folded by division per row, so this is a sum over
	# the AUTHORED rows and the loop bound is the ladder's row count, never the span
	# (`TimeLadder.magnitudes_crossed`, `core/time_ladder.gd:199-208`).
	#
	# The floor is the count the authored divisor already reaches, so an ordinary advance
	# is untouched: the magnitudes only ever ADD to a coarse act, never replace a per-
	# period one.
	_apply_tier(
		actor,
		_every(periods, STRATEGIC_PERIODS) + _magnitude_periods(crossed),
		STRATEGIC_TIER,
		out["strategic"]
	)
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


## How many BASE-periods `crossed` says elapsed, once each coarser magnitude is restated in
## the base the tiers above are counted in. **Zero on an ordinary advance**, so this is
## invisible until a caller declares a coarse cost.
##
## ## What it deliberately does NOT do
##
## It does not replay the finer steps inside a coarser bucket, and it does not bank a
## surplus: `TimeLadder.magnitudes_crossed` already truncated each row independently
## (`core/time_ladder.gd:181-208`), so what is summed here is what the ladder DROPPED the
## remainder of. Two half-months are not one month, and neither is one month and a half
## (`time_ladder.gd:48-52`).
##
## The base row is excluded because it is `periods` itself, which the tier cadence above
## already counts — counting it twice would hand a verb four periods because two elapsed,
## the rule this file's own `settle` docstring is about.
##
## The `for` walks the SSOT's authored row array (`TimeLadder.magnitudes()`, a fixed set
## of keys, not a count anybody hands in), so the bound is the ladder's own length and
## never the elapsed span: the shape `tests/arch_rules/test_no_unbounded_wait.gd`
## accepts and the shape the 67 GB incident was not.
static func _magnitude_periods(crossed: Dictionary) -> int:
	if crossed.is_empty():
		return 0
	var base := TimeLadder.ratio_for(TimeLadder.BASE)
	var total := 0
	for row in TimeLadder.magnitudes():
		var magnitude := StringName(str(row.get("name", "")))
		var ratio := int(row.get("ratio_periods", 0))
		# A row the caller named but this table does not author, a row whose ratio is
		# not a positive count, and the base itself all contribute zero rather than
		# being guessed at — the same "0 rather than 1" discipline `ratio_for` keeps.
		if magnitude == StringName() or magnitude == TimeLadder.BASE or ratio < 1:
			continue
		total += maxi(0, int(crossed.get(magnitude, 0))) * ratio
	return total


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


## The base cadence against the ladder's own base row, checked rather than asserted.
##
## `NEAR_PERIODS` is `1` because "every period" IS the base, and `ratio_for` reads the
## shipped `.tres` so the compiler cannot prove it (`const` above). **The claim is only
## true if the base row still says 1**, and a `.tres` retune that moved it would leave a
## constant that is silently wrong — the `RealmProfile` copy that stayed green under
## every value assertion (ADR 0116). So the conformance is MACHINE-CHECKED here, at the
## one place a period count is already being handed down, and it fails loudly.
##
## Only the BASE row is compared: `distant`/`strategic` are content divisors with no row
## to check them against, which is the whole of the difference between them and this.
static func _check_base_row() -> void:
	var base := TimeLadder.ratio_for(TimeLadder.BASE)
	if base != NEAR_PERIODS:
		push_error(
			(
				(
					"InstitutionResolver: NEAR_PERIODS is %d but the ladder's base row is %d — "
					+ "a cadence that no longer reaches every period. Refusing rather than "
					+ "settling a wrong frequency (ADR 0173)."
				)
				% [NEAR_PERIODS, base]
			)
		)


## Whether `actor` lives under a polity of the given tier. Read through the facades
## rather than off `module_data`, so this file never holds a ledger. A sect and a
## nation are PEERS (ADR 0083), so the nation is asked first only because the shipped
## roster never holds both at once — not because one contains the other.
static func _found(actor: Actor, tier: StringName) -> bool:
	if tier == &"nation":
		return bool(NationApi.summary(actor).get("founded", false))
	return bool(SectApi.summary(actor).get("is_member", false))
