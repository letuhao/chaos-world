class_name Progressive
extends InstitutionCapability

## Organization PROGRESSION: a flat integer counter the organization earns from
## its own activity, and AUTHORED milestones derived from it (D11, ADR 0922).
##
## ## What growth COSTS, and what it BUYS that is not power (the D8 gate)
##
## The counter accrues from the organization's OWN ACTIVITY and from nothing
## else: `served` — duty periods members actually settled through
## `Dutiable.serve` — and `admitted` — people brought in. **Time is not a
## source**: an idle organization earns nothing, so the counter is a record of
## work rather than a clock (DEF-0111; `accrue` reads no `periods` at all). The
## cost is member effort and people: every duty line is OPENED by admission or
## by office and is paid down out of the member's own periods, and admission is
## gated by the authored office capacity and immediately opens MORE duty on the
## joiner. It cannot be farmed for free because there is no idle path to a
## point — no periods, and no dues paid by nobody.
##
## What a milestone may UNLOCK is ACCESS and CAPACITY, and the set is CLOSED:
## positions (authored office ids the organization may now fill), capabilities
## (contracts the organization may now exercise) and member_capacity (how many
## members it may hold). **Never a stat** (ADR 0084).
##
## ## Why a `standing_cap` raise is REFUSED, and the measurement that refuses it
##
## The one candidate that looks like access and is not: raising the
## organization's `standing_cap`. ADR 0084's whole stat surface is
## `standing_percent(standing) = min(STANDING_PERCENT_CAP, STANDING_RATE *
## standing)` with `STANDING_RATE = 0.001` and `STANDING_PERCENT_CAP = 0.10`. For
## any cap below 100, raising the cap raises the ceiling a member's recognition
## can reach — POWER, by ADR 0084's own formula. At or above 100 the percent is
## already saturated, so a raise buys nothing and only dilutes `normalized()`
## (the ratio a gate reads gets harder). **Power or nothing, never access**, so a
## milestone carrying `standing_cap` — or any key this contract does not name —
## is refused [constant R_UNKNOWN_UNLOCK] BY NAME, and the suite plants exactly
## that row. The refusal is structural: growth cannot smuggle a stat surface
## through the authored table without a new ADR.
##
## ## What was REJECTED, and why
##
## - **A stat grant, a multiplier, or anything realm-shaped.** No method here
##   takes a realm id and no answer returns a multiplier — the `DoctrineRule`
##   shape answer: the contract has nowhere to put a magnitude, so it cannot
##   become a second magnitude table. ADR 0084 allows exactly three grants
##   (recognition, access, transmission), and a fourth is a new ADR.
## - **A treasury, a currency, or a spend verb.** The counter IS the cost
##   record; a second balance beside it would be the ADR 0066 failure mode
##   inside one organization's growth.
## - **Rolling a milestone.** Walked, never rolled (ADR 0058/0084): a milestone
##   is crossed by a comparison, so the outcome is a pure function of the
##   counter and a test needs no seeded generator.
## - **Counting `periods` elapsed.** Time passes whether or not anybody works,
##   so a period-sourced counter is the free farm this design exists to refuse.
##
## ## Bound the OUTPUT, never the INPUT
##
## The counter itself is UNBOUNDED — a cap on a growth rate dies because the
## rate must scale with the organization's size. What is bounded is what the
## counter BUYS: milestones are AUTHORED and FINITE, so the union of everything
## growth can ever unlock is the authored table and nothing else.
## [constant MAX_MILESTONES] is a corrupt-table guard (the
## `Successive.MAX_WALK_LENGTH` precedent), never the D8 bound.
##
## ## Context keys this capability reads
##
##   - `points` — int: the organization's current counter, clamped to `[0, …]`.
##   - `milestones` — Array of authored rows, each `{at: int, name: String,
##     opens: {positions: [...], capabilities: [...], member_capacity: int}}`.
##     Strictly increasing in `at`, or refused `milestones_not_increasing`: the
##     order decides `tier_name` and `next_points`, and a table with two
##     readings has two answers. Keys outside the closed sets are refused
##     `unknown_unlock`, naming the key.
##   - `base_capacity` — int: the organization's authored base member
##     allowance, read by the answer and never written.
##   - `served` (accrue only) — int: duty periods actually settled since the
##     last accrual; the caller reads it off `Dutiable.serve`'s `settled`.
##   - `admitted` (accrue only) — int: members admitted since the last accrual.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111). Every
## accrual takes explicit activity counts from a caller that owns both the
## clock and the ledger.

## The id this capability is dispatched under.
const ID := &"progressive"

## The keys a milestone row may carry. Every one is read below and NOTHING else
## is: a row outside this set is refused [constant R_UNKNOWN_UNLOCK] — see the
## class note for why `standing_cap` is the key that must never be read.
const MILESTONE_KEYS: Array[StringName] = [&"at", &"name", &"opens"]

## The keys a milestone's `opens` map may carry. The closed set of what growth
## BUYS: access and capacity, never a stat.
const UNLOCK_KEYS: Array[StringName] = [&"capabilities", &"member_capacity", &"positions"]

## The longest authored milestone table this contract will read. A corrupt-table
## guard (the `Successive.MAX_WALK_LENGTH` precedent), never the D8 bound: the
## D8 bound is that milestones are authored and finite.
const MAX_MILESTONES := 64

## The accrual moved nothing: no duty was served and nobody was admitted.
## Refused rather than answered with a zero — a settlement that moved nothing is
## indistinguishable from one that never ran (the `Dutiable.nothing_owed` rule),
## and this is what makes an idle organization unable to farm its own growth.
const R_NOTHING_EARNED := "nothing_earned"
## The organization authors no milestone at all, so an accrual would feed a
## number no reader consults. `progress` still READS that state (tier 0 of 0);
## only the write is refused.
const R_NO_MILESTONES_AUTHORED := "no_milestones_authored"
## The authored table is not strictly increasing in `at`. The order decides
## `tier_name` and `next_points`, so a table with two readings has two answers.
const R_MILESTONES_NOT_INCREASING := "milestones_not_increasing"
## The table is longer than [constant MAX_MILESTONES].
const R_TOO_MANY_MILESTONES := "too_many_milestones"
## A milestone row, or its `opens` map, carries a key this contract does not
## name. The refusal names the key: growth can only buy what this contract can
## read, and `standing_cap` is the key that would smuggle a stat surface.
const R_UNKNOWN_UNLOCK := "unknown_unlock"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [
		R_NOTHING_EARNED,
		R_NO_MILESTONES_AUTHORED,
		R_MILESTONES_NOT_INCREASING,
		R_TOO_MANY_MILESTONES,
		R_UNKNOWN_UNLOCK,
	]
	return out


## ## Where the organization stands, as a READ.
##
## `{ok: true, reason: "", points, tier, tier_name, tiers, next_points,
## opened_positions, opened_capabilities, member_capacity}` — every number
## derived from `points` and the authored table, and nothing else. A table
## nobody authored is a legitimate state (tier 0 of 0), never a refusal: a read
## that refused would make a screen unable to show the bar, the same split
## `Successive.walk` keeps.
func progress(ctx: Dictionary) -> Dictionary:
	var fault := _table_fault(ctx)
	if not fault.is_empty():
		return fault
	return InstitutionCapability.ok(
		_state(_count(ctx.get("points", 0)), _table(ctx), _count(ctx.get("base_capacity", 0)))
	)


## ## The ONE mutator: plan the organization's growth by the activity it earned.
##
## `{ok: true, reason: "", plan: {points, gained, served, admitted, tier,
## tier_name, tiers, next_points, opened_positions, opened_capabilities,
## member_capacity, cause}}` — a plan the applier writes, exactly as every
## capability in this family decides and never commits (ADR 0922).
##
## `gained` is `served + admitted`, so the counter moves by exactly the work
## done and by nothing else. Refusal order: table readable, milestones authored,
## something actually earned. Every refusal returns above the plan, so a refused
## accrual writes nothing (ADR 0044).
func accrue(ctx: Dictionary) -> Dictionary:
	var fault := _table_fault(ctx)
	if not fault.is_empty():
		return fault
	var milestones := _table(ctx)
	if milestones.is_empty():
		return InstitutionCapability.refuse(R_NO_MILESTONES_AUTHORED)
	var served := _count(ctx.get("served", 0))
	var admitted := _count(ctx.get("admitted", 0))
	var gained := served + admitted
	if gained < 1:
		return InstitutionCapability.refuse(R_NOTHING_EARNED)
	var plan := {
		"points": _count(ctx.get("points", 0)) + gained,
		"gained": gained,
		"served": served,
		"admitted": admitted,
		"cause": "organization_grew",
	}
	plan.merge(_state(int(plan["points"]), milestones, _count(ctx.get("base_capacity", 0))))
	return InstitutionCapability.ok({"plan": plan})


## ## The authored data this capability reads cannot be READ.
##
## The type checks `Successive.check` keeps, plus the milestone table itself: a
## table this contract cannot read is refused where the kind is vetted, so a
## corrupt row never reaches a verb. `check` vets what is PRESENT; an absent key
## is the per-verb refusals' business.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["points", "base_capacity", "served", "admitted"]:
		if ctx.has(field) and not (ctx[field] is int or ctx[field] is float):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	if ctx.has("milestones"):
		var fault := _table_fault(ctx)
		if not fault.is_empty():
			return fault
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: two identical calls
## answer by TEXT (determinism — no roll can hide in a comparison), the counter
## moves by exactly `served + admitted`, a crossing milestone opens its access
## and its capacity while an unreached one opens neither, an idle organization
## refuses `nothing_earned` EVEN WITH `periods` PRESENT (time is not a source), a
## `standing_cap` row and an `opens` map outside the closed set refuse
## `unknown_unlock`, an out-of-order table refuses `milestones_not_increasing`, a
## table past [constant MAX_MILESTONES] refuses, a table nobody authored refuses
## the write while the read still answers, and both verbs leave the handed
## context byte-identical.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"points": 2,
		"base_capacity": 3,
		"served": 2,
		"admitted": 1,
		"milestones":
		[
			{"at": 3, "name": "chartered", "opens": {"positions": ["probe_office"]}},
			{
				"at": 6,
				"name": "established",
				"opens": {"capabilities": ["probe_contract"], "member_capacity": 4},
			},
		],
	}
	var first := accrue(probe.duplicate(true))
	var second := accrue(probe.duplicate(true))
	if JSON.stringify(first) != JSON.stringify(second):
		found.append("accrue: two identical calls disagreed — the growth is not deterministic")
	_judge(found, "accrue", first)
	var gained := int(probe["served"]) + int(probe["admitted"])
	if bool(first.get("ok", false)):
		var plan = first.get("plan", {})
		if not (plan is Dictionary):
			found.append("accrue: a successful plan is not a dictionary")
		else:
			var row := plan as Dictionary
			if int(row.get("gained", -1)) != gained:
				found.append("accrue: gained is not served plus admitted")
			if int(row.get("points", -1)) != int(probe["points"]) + gained:
				found.append("accrue: the counter did not move by exactly the activity")
			if int(row.get("tier", -1)) != 1:
				found.append("accrue: the crossing milestone did not raise the tier")
			if not _contains(row.get("opened_positions"), "probe_office"):
				found.append("accrue: a reached milestone's position was not opened")
			if _contains(row.get("opened_capabilities"), "probe_contract"):
				found.append("accrue: an unreached milestone's capability was opened")
			if int(row.get("next_points", -1)) != 6:
				found.append("accrue: next_points does not name the next milestone")
			if int(row.get("member_capacity", -1)) != int(probe["base_capacity"]):
				found.append("accrue: an unreached milestone's capacity was added")
	# The second milestone crossed: its capability opens and its capacity lands.
	var crossed := probe.duplicate(true)
	crossed["served"] = 4
	var landed := accrue(crossed)
	_judge(found, "accrue", landed)
	if bool(landed.get("ok", false)):
		var row: Dictionary = landed["plan"]
		if not _contains(row.get("opened_capabilities"), "probe_contract"):
			found.append("accrue: the crossing milestone's capability was not opened")
		if int(row.get("member_capacity", -1)) != int(probe["base_capacity"]) + 4:
			found.append("accrue: the crossing milestone's capacity did not land")
		if int(row.get("next_points", -1)) != 0:
			found.append("accrue: a fully grown table still names a next milestone")
	# Time is NOT a source: an idle organization earns nothing even with periods
	# present, which is what makes the counter a record of work rather than a clock.
	var idle := probe.duplicate(true)
	idle["served"] = 0
	idle["admitted"] = 0
	idle["periods"] = 99
	expect_refusal(found, "accrue", accrue(idle), R_NOTHING_EARNED)
	# The power-smuggling row: `standing_cap` is outside the closed set and the
	# refusal NAMES the key, so a milestone that would raise the stat ceiling
	# fails loudly (ADR 0084 — see the class note for the measurement).
	var smuggled := probe.duplicate(true)
	smuggled["milestones"] = [{"at": 3, "standing_cap": 200}]
	var refused_row := accrue(smuggled)
	expect_refusal(found, "accrue", refused_row, R_UNKNOWN_UNLOCK)
	if String(refused_row.get("key", "")) != "standing_cap":
		found.append("accrue: an unknown unlock refusal did not name the key")
	expect_refusal(found, "progress", progress(smuggled), R_UNKNOWN_UNLOCK)
	var smuggled_opens := probe.duplicate(true)
	smuggled_opens["milestones"] = [{"at": 3, "opens": {"stats": ["poise"]}}]
	expect_refusal(found, "accrue", accrue(smuggled_opens), R_UNKNOWN_UNLOCK)
	var out_of_order := probe.duplicate(true)
	out_of_order["milestones"] = [{"at": 5}, {"at": 2}]
	expect_refusal(found, "accrue", accrue(out_of_order), R_MILESTONES_NOT_INCREASING)
	var unreadable := probe.duplicate(true)
	unreadable["milestones"] = [{"at": "soon"}]
	expect_refusal(found, "accrue", accrue(unreadable), InstitutionCapability.R_MALFORMED)
	var bare := probe.duplicate(true)
	bare["milestones"] = []
	expect_refusal(found, "accrue", accrue(bare), R_NO_MILESTONES_AUTHORED)
	_judge(found, "progress", progress(bare))
	var stood := progress(probe.duplicate(true))
	_judge(found, "progress", stood)
	if bool(stood.get("ok", false)):
		if int(stood.get("tier", -1)) != 0:
			found.append("progress: a counter below the first milestone is not tier zero")
		if int(stood.get("next_points", -1)) != 3:
			found.append("progress: next_points does not name the first milestone")
		if int(stood.get("tiers", -1)) != 2:
			found.append("progress: the authored table length is not published")
	# Purity: a read and a write leave the handed context byte-identical (ADR 0044).
	var handed_read := probe.duplicate(true)
	progress(handed_read)
	if JSON.stringify(handed_read) != JSON.stringify(probe):
		found.append("progress: mutated the context it was handed")
	var handed_write := probe.duplicate(true)
	accrue(handed_write)
	if JSON.stringify(handed_write) != JSON.stringify(probe):
		found.append("accrue: mutated the context it was handed")
	# The corrupt-table guard: a table past MAX_MILESTONES refuses by name. The
	# fill is toward a FIXED count with an unconditional append — the accepted
	# shape `test_no_unbounded_wait.gd` recognises.
	var too_many: Array = []
	for index in range(MAX_MILESTONES + 1):
		too_many.append({"at": index})
	var crowded := probe.duplicate(true)
	crowded["milestones"] = too_many
	expect_refusal(found, "accrue", accrue(crowded), R_TOO_MANY_MILESTONES)
	return found


# --- Internals ---------------------------------------------------------------


## The table `ctx` carries, as an Array. Validated by [method _table_fault]
## BEFORE this is read; a value that is not an array reads as empty here rather
## than aborting the walk.
func _table(ctx: Dictionary) -> Array:
	var listed = ctx.get("milestones", [])
	return listed as Array if listed is Array else []


## ## Everything wrong with the authored table, or `{}` when it reads cleanly
##
## A `for` over the caller's own array, reading only: the body never writes to
## `milestones`, so the bound is the authored row count and nothing here grows
## the container its bound is read from.
func _table_fault(ctx: Dictionary) -> Dictionary:
	if not ctx.has("milestones"):
		return {}
	var listed = ctx["milestones"]
	if not (listed is Array):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "milestones"}
		)
	var rows := listed as Array
	if rows.size() > MAX_MILESTONES:
		return InstitutionCapability.refuse(
			R_TOO_MANY_MILESTONES, {"count": rows.size(), "max": MAX_MILESTONES}
		)
	var previous := -1
	for row in rows:
		var fault := _row_fault(row, previous)
		if not fault.is_empty():
			return fault
		previous = int(InstitutionCapability.entry(row as Dictionary, &"at"))
	return {}


## One milestone row's faults: closed keys, a readable `at`, strict order, and a
## readable `opens` map. `previous` is the last accepted threshold, so the order
## check is `at > previous` and the first row is unbounded below by `-1` while
## `at` itself is refused negative.
func _row_fault(row: Variant, previous: int) -> Dictionary:
	if not (row is Dictionary):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "milestones"}
		)
	var entry := row as Dictionary
	for key in entry.keys():
		if not MILESTONE_KEYS.has(StringName(str(key))):
			return InstitutionCapability.refuse(R_UNKNOWN_UNLOCK, {"key": str(key)})
	var at = InstitutionCapability.entry(entry, &"at")
	if not (at is int or at is float) or int(at) < 0:
		return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": "at"})
	if int(at) <= previous:
		return InstitutionCapability.refuse(R_MILESTONES_NOT_INCREASING, {"at": int(at)})
	var opened = InstitutionCapability.entry(entry, &"opens")
	return {} if opened == null else _opens_fault(opened)


## One `opens` map's faults: closed keys, readable id lists, a non-negative
## capacity. The key check runs FIRST, so a `standing_cap` or a `stats` key is
## refused by name before anything tries to read it.
func _opens_fault(opened: Variant) -> Dictionary:
	if not (opened is Dictionary):
		return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": "opens"})
	var map := opened as Dictionary
	for key in map.keys():
		if not UNLOCK_KEYS.has(StringName(str(key))):
			return InstitutionCapability.refuse(R_UNKNOWN_UNLOCK, {"key": str(key)})
	for key in [&"positions", &"capabilities"]:
		var listed = InstitutionCapability.entry(map, key)
		if listed != null and not _text_list(listed):
			return InstitutionCapability.refuse(
				InstitutionCapability.R_MALFORMED, {"field": String(key)}
			)
	var held = InstitutionCapability.entry(map, &"member_capacity")
	if held != null and (not (held is int or held is float) or int(held) < 0):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "member_capacity"}
		)
	return {}


## Whether `value` is an array of readable ids. An empty array is legal (a
## milestone that opens nothing on one axis states exactly that); an entry that
## is not text is a content fault, not an id this contract will carry.
func _text_list(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in value as Array:
		if InstitutionCapability.text(item, "") == "":
			return false
	return true


## ## The whole derived state, from `points` and the authored table and NOTHING
## ## else
##
## The `DoctrineRule` shape answer: every number below is a comparison against
## the counter or a read off the authored row — there is no realm, no ladder
## index and no second factor anywhere in it, so there is nowhere for a
## magnitude to enter. A `for` over the validated table reading only, so the
## bound is the authored row count.
func _state(points: int, milestones: Array, base_capacity: int) -> Dictionary:
	var tier := 0
	var tier_name := ""
	var next_points := 0
	var positions: Array[String] = []
	var capabilities: Array[String] = []
	var capacity := base_capacity
	for row in milestones:
		var entry := row as Dictionary
		var at := int(InstitutionCapability.entry(entry, &"at"))
		if at <= points:
			tier += 1
			tier_name = InstitutionCapability.text(InstitutionCapability.entry(entry, &"name"), "")
			var opened = InstitutionCapability.entry(entry, &"opens")
			if opened is Dictionary:
				capacity += _capacity_of(opened as Dictionary)
				_gather(opened as Dictionary, &"positions", positions)
				_gather(opened as Dictionary, &"capabilities", capabilities)
			continue
		if next_points == 0:
			next_points = at
	return {
		"points": points,
		"tier": tier,
		"tier_name": tier_name,
		"tiers": milestones.size(),
		"next_points": next_points,
		"opened_positions": _canonical(positions),
		"opened_capabilities": _canonical(capabilities),
		"member_capacity": capacity,
	}


## Append every readable id under `key` of one `opens` map. Textual lookup
## through the family's `entry`, because an authored map is keyed by whatever
## the authoring layer produced.
func _gather(opened: Dictionary, key: StringName, into: Array[String]) -> void:
	var listed = InstitutionCapability.entry(opened, key)
	if not (listed is Array):
		return
	for item in listed as Array:
		var id := InstitutionCapability.text(item, "")
		if id != "":
			into.append(id)


## One `opens` map's member capacity, clamped at zero. The validation above has
## already refused anything unreadable, so this is a coercion and never a check.
func _capacity_of(opened: Dictionary) -> int:
	var held = InstitutionCapability.entry(opened, &"member_capacity")
	if not (held is int or held is float):
		return 0
	return maxi(0, int(held))


## The ids of `values`, deduplicated and canonically ordered by STRING value.
## Sorted on `Array[String]` for the reason `InstitutionDef.position_ids`
## states: interned ids do not order by their string value, so a list whose
## order is load-bearing must not depend on which id loaded first.
func _canonical(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		if not out.has(value):
			out.append(value)
	out.sort()
	return out


## `value` as a non-negative integer count, `0` otherwise. A raw `int()` on a
## string RAISES in GDScript, so a hand-edited context would abort a verb
## instead of reading as absent — an explicit type test that falls back is
## refusal, not coincidence.
func _count(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	return maxi(0, int(value))


## Whether `listed` really is an array carrying `id`. The suite's own read, so a
## malformed list answers `false` rather than aborting the probe that checks it.
func _contains(listed: Variant, id: String) -> bool:
	if not (listed is Array):
		return false
	return (listed as Array).has(id)
