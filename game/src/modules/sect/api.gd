class_name SectApi
extends RefCounted

## Public facade for the `sect` module (ADR 0083/0084). Other modules may reference
## ONLY this file (`api.gd`). Concrete implementations live beside this file and are
## wired in `app/`.
##
## ## A sect grants recognition, access and transmission — and never power
##
## That is the whole of what an institution may hand out (ADR 0084), and it is
## why there is no stat verb anywhere below. Standing projects as one bounded
## `PERCENT` through `SectProjection`; everything else this facade does is move a
## number in a ledger or answer whether a door is open. `tools arch` cannot see a
## method that does not exist, so the refusal is pinned structurally instead:
## `test_sect_no_power.gd` reads this file's published method list and fails if a
## power-granting verb ever appears on it.
##
## ## A position is a duty, not a level
##
## `position` is an authored id, `standing` is a continuous earned integer, and
## **neither is ever derived from the other** (ADR 0064, carried forward unchanged
## by ADR 0083). A promotion writes the position and leaves standing alone; a
## standing change moves standing and leaves the position alone. That gap is the
## whole politics layer — collapse it into one number and you have built a
## spreadsheet.
##
## ## Reads fold into `summary()`, and that is deliberate
##
## This facade is capped at twelve public methods and eleven are spoken for by the
## verbs below. Every read a screen or a sibling module needs — which sect, which
## office, who founded it, who is on the roster and how full each office is, the
## walk in progress on a seat, how much standing, what is owed, what the allowlist
## projects, whether a gate opens — is a **key inside `summary()`**, never a
## thirteenth method. The precedent is `DestinyApi`, which folds its catalog reads
## into `summary()` for exactly this reason, and the reason it is the right shape
## rather than a compromise: a panel needs the whole screen in one call anyway, and
## a sibling module that wants one field can read it out of a documented key instead
## of being handed a reason to grow the facade.
##
## ## Every refusal is a named game rule
##
## A mutating verb returns `{"ok": false, "reason": "<named constant>"}` and
## leaves the ledger byte-for-byte as found (ADR 0044). `reason` is an authored
## constant — `not_a_member`, `unknown_sect`, `unknown_position`,
## `standing_below_floor`, `capacity_full`, `seat_occupied` — never free text, so
## a panel renders a reason it did not have to invent. `seat_occupied` and
## `capacity_full` are deliberately distinct (ADR 0084): the first is a succession
## contest, the second is a shut room.

## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := SectState.MODULE_KEY

## The refusal a `leave` gives when there was nothing to leave. **It is the only
## thing `leave` refuses on**: leaving is always permitted and always costs, and
## the cost is standing, never a gate. A player with no exit is in a bad state
## with no out.
const NOT_A_MEMBER := "not_a_member"
## The sect id the catalog does not ship. A sect nothing defines teaches nothing
## and grants nothing, so a claim against one is a content bug rather than a
## player outcome.
const UNKNOWN_SECT := "unknown_sect"
## The office id the sect does not author. Same reasoning as `unknown_sect`.
const UNKNOWN_POSITION := "unknown_position"
## The doctrine id the catalog does not ship. A doctrine nothing defines teaches
## nothing, so a `found` naming one is naming content this build does not have.
const UNKNOWN_DOCTRINE := SectFounding.R_UNKNOWN_DOCTRINE
## The standing bar was not met. **A route, not a wall** — see `_below_floor`.
const STANDING_BELOW_FLOOR := SectDef.STANDING_BELOW_FLOOR
## The office's authored cap is reached. An overflow is a **refused admit**,
## never a silent trim.
const CAPACITY_FULL := SectDef.CAPACITY_FULL
## The office's authored cap is 1 and somebody already holds it. Distinct from
## `capacity_full`; the difference is load-bearing (ADR 0084).
const SEAT_OCCUPIED := SectDef.SEAT_OCCUPIED
## The actor is already sworn to a sect. The three tiers are peers rather than a
## containment tree (ADR 0083), so re-swearing is a `leave` followed by a `join`
## and never a second claim.
const ALREADY_SWORN := "already_sworn"
## The verb asked for a change that could not land — a zero standing delta at the
## cap or at the floor. A refusal like any other: it writes nothing.
const NO_CHANGE := "no_change"
## A `found` named an actor with nothing to found anything for.
const NO_ACTOR := SectFounding.R_NO_ACTOR
## A `found` on a ledger that already names a sect. An actor may found one, and
## founding a second is a `leave` and then a `found` — the tiers are peers.
const ALREADY_FOUNDED := SectFounding.R_ALREADY_FOUNDED
## This sect authors no office a founder could be seated in. Content, not a
## player outcome: every office names an appointment a walk never reaches.
const NO_TOP_POSITION := SectFounding.R_NO_TOP_POSITION
## The authored `founding_cost` is not met. Founding is priced on purpose
## (BL-0174), and a sect whose existence is free is not a sect.
const FOUNDING_COST_UNMET := SectFounding.R_FOUNDING_COST_UNMET
## A walk was asked for on a seat that has no walk open. Opening a vacancy IS a
## step (ADR 0058's `commit` had no counterpart here), so there is nothing to
## advance until a seat is recorded vacant.
const NO_SUCH_WALK := SectSuccession.R_NO_SUCH_WALK
## The seat the walk is on is not vacant, so there is no walk to advance.
const SEAT_NOT_VACANT := SectSuccession.R_NOT_VACANT
## The walk is real and the vacancy has not aged a period yet. This is the whole of
## ADR 0084's "refuses a further step until a period elapses".
const PERIOD_NOT_ELAPSED := SectSuccession.R_PERIOD_NOT_ELAPSED
## The walk is finished — every authored stage has been taken, or the seat was
## never vacant, or the method names a walk this module does not take. Deliberately
## ONE reason for all three: they are the same player-facing sentence, "that
## succession is finished", and a panel should not have to say which.
const WALK_COMPLETE := SectSuccession.R_WALK_COMPLETE
## A teacher may not teach this doctrine at all — their own fit is below its
## authored `affinity_floor`. Distinct from the student's `min_purity` door: a
## teacher who cannot stand on the floor does not get to teach at the floor.
const TEACHER_UNFIT := SectTeaching.R_TEACHER_UNFIT
## The student's BASE comprehension allocation is under the doctrine's authored
## floor. Read from `get_base` and never `derived`, so a grant cannot fund its own
## gate (ADR 0052/0054).
const COMPREHENSION_BELOW_FLOOR := SectTeaching.R_COMPREHENSION_BELOW_FLOOR
## Above the doctrine's authored `comprehension_span`. The far side of the same
## band rather than a floor: a doctrine is practised at an ear, not at every one.
const COMPREHENSION_ABOVE_SPAN := SectTeaching.R_COMPREHENSION_ABOVE_SPAN
## A lesson that would move nothing: no periods asked for, or the student is
## already at `FIT_CAP` for this doctrine. A refusal like any other — it writes
## nothing at all.
const NOTHING_TO_TEACH := SectTeaching.R_NOTHING_TO_TEACH
## A teacher taught themselves. Nothing to do and a real reason for it: the tax
## would be charged and no fit would move.
const SAME_ACTOR := SectTeaching.R_SAME_ACTOR
## The student is sworn to no sect, so no institution is teaching them anything.
const STUDENT_NOT_SWORN := SectTeaching.R_STUDENT_NOT_SWORN


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict`
## carried, normalizes it against the current catalog, and rebuilds the stat
## projection and the membership mirror from the ledger. Idempotent, and safe on an
## actor who has never sworn to anything — an unaffiliated member is the ordinary
## starting state (ADR 0083), not a failure.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := _normalized(actor)
	actor.set_module_data(MODULE_KEY, SectProjection.apply(actor, ledger))


## Swear `actor` to `sect_id`. Returns `{ok: bool, reason: String}`.
##
## A new claim starts at **standing zero holding no office**, which is the whole of
## ADR 0064's two-part split in one line: being a member and being respected are
## different facts, and joining grants the first and not the second.
##
## Refuses — writing nothing at all — for a sect the catalog does not ship, or for
## an actor already sworn to one. The three tiers are peers, not a containment tree
## (ADR 0083), so re-swearing is a `leave` followed by a `join`, and the standing
## the old sect gave is settled before the new claim is opened rather than
## silently carried across.
static func join(actor: Actor, sect_id: StringName) -> Dictionary:
	var read := _claim(actor)
	if SectState.is_affiliated(read):
		return _refuse(ALREADY_SWORN, read)
	var def := SectCatalog.instance().sect_definition(sect_id)
	if def == null:
		return _refuse(UNKNOWN_SECT, read)
	var claim := def.new_claim()
	var ledger := read.duplicate(true)
	ledger["institution"] = String(def.id)
	ledger["position"] = ""
	ledger["standing"] = claim.standing
	ledger["standing_cap"] = claim.standing_cap
	ledger["obligation"] = def.member_obligation_lines()
	_persist(actor, ledger, "join")
	return _ok(ledger)


## ## Founding: the sect comes into being, and the price is authored
##
## `SectApi.found(actor, sect_id, doctrine_id, founder_id)` is the one verb that can
## bring a sect into being (BL-0174). It consumes the authored `founding_cost`, seats
## the founder in the top office, and writes the four founder-owned ledger lines: the
## founder id, the roster, the treasury and the founder's own duty.
##
## ## The founder id is a STRING, never an `Actor`
##
## `founder_id` is recorded as a plain actor id **string**. An `Actor` reference in a
## ledger reaches the save untouched — `Actor.to_dict` copies `module_data` verbatim
## with a hook only for items — and no checker in this repo can see it. The same
## string is the first entry in the roster, which is why the founder is the first
## entry in the sect's own ledger rather than a special case hanging off it.
##
## ## The four refusals, in the order they are asked
##
## `no_actor`, `unknown_sect`, `unknown_doctrine`, `founding_cost_unmet`,
## `already_founded`. Each writes **nothing at all** — not the pool, not the ledger,
## not the trail — so a refused founding leaves the actor byte-for-byte as found
## (ADR 0084). The order matters and is not arbitrary: a cost is never mentioned
## before the sect that charges it, and an existing sect is never re-founded just
## because the price was met.
##
## ## The cost is read, not charged
##
## `SectDef.founding_cost` is authored as `{found, outstanding}` and read against
## `SectFounding.funds(actor)`. This module **records** the cost and never settles
## it: a debt an economy verb has not written yet must not be paid by a sect, and
## `sect` declares no `items` dependency on purpose. What is charged is the funding
## pool — an institution's existence being free would make founding a free action.
static func found(
	actor: Actor, sect_id: StringName, doctrine_id: StringName, founder_id: String
) -> Dictionary:
	if actor == null:
		return _refuse(NO_ACTOR, SectState.empty())
	var catalog := SectCatalog.instance()
	var def := catalog.sect_definition(sect_id)
	if def == null:
		return _refuse(UNKNOWN_SECT, _claim(actor))
	var doctrine := SectDoctrineCatalog.instance().doctrine(doctrine_id)
	if doctrine == null:
		return _refuse(UNKNOWN_DOCTRINE, _claim(actor))
	var read := _claim(actor)
	if SectFounding.founded(read):
		return _refuse(ALREADY_FOUNDED, read)
	var top := def.top_position()
	if top == null:
		return _refuse(NO_TOP_POSITION, read)
	var price := SectFounding.cost(def)
	if SectFounding.funds(actor) < float(price["outstanding"]):
		return _found_unmet(read, def, price)
	SectFounding.draw(actor, float(price["outstanding"]))
	var ledger := SectFounding.write(def, doctrine, founder_id, top)
	_record(ledger, "found", def.id, String(doctrine.id))
	_persist(actor, ledger, "found")
	var bus := SectProjection.events()
	bus.membership_changed.emit(String(actor.id), def.id, true, "")
	bus.claim_changed.emit(String(actor.id), def.id, top.id, "found")
	return _ok(ledger)


## Leave the sect `actor` is sworn to. Returns `{ok: bool, reason: String}`.
##
## **Leaving is always permitted and always costs.** The cost is standing, never a
## gate: the office is released, the claim is closed and the trait mirror is
## dropped, so a member can always get out. `not_a_member` is the only refusal,
## because there is nothing to leave — which is a different statement from "you
## are not allowed to".
##
## The standing the sect gave is settled against it rather than refunded: an
## institution that has been wronged is one that has lost something, and a member
## with nothing left has nothing left to lose, which is the property that makes a
## demotion a real cost (ADR 0064).
static func leave(actor: Actor) -> Dictionary:
	var read := _claim(actor)
	if not SectState.is_affiliated(read):
		return _refuse(NOT_A_MEMBER, read)
	var ledger := read.duplicate(true)
	_record(ledger, "leave", SectState.institution(ledger), "")
	# `SectState.empty()` rather than a hand-cleared dictionary: the skeleton is
	# authored in exactly one place, so a new ledger key cannot be half-written here.
	var cleared := SectState.normalize({})
	cleared["history"] = ledger["history"]
	_persist(actor, cleared, "leave")
	return _ok(cleared)


## Move `actor`'s standing in their sect by `amount`. Returns
## `{ok: bool, reason: String, applied: int}`.
##
## Standing is earned **and can fall** (ADR 0064): a negative `amount` is a
## legitimate call, not an input error. The applied amount is published rather than
## assumed, so a caller learns how much of a requested change actually landed once
## the authored cap clamped it — and a change that lands nothing at all is a
## refused verb writing nothing (ADR 0084).
static func move_standing(actor: Actor, amount: int) -> Dictionary:
	var read := _claim(actor)
	if not SectState.is_affiliated(read):
		return _refuse(NOT_A_MEMBER, read)
	if amount == 0:
		return {"ok": false, "reason": NO_CHANGE, "applied": 0, "ledger": read}
	var ledger := read.duplicate(true)
	var claim := SectState.claim(ledger)
	var applied := claim.move_standing(amount)
	if applied == 0:
		# A refused verb writes nothing: the ledger is byte-for-byte as found.
		return {"ok": false, "reason": NO_CHANGE, "applied": 0, "ledger": read}
	_write_claim(ledger, claim)
	_persist(actor, ledger, "standing", applied)
	# The ledger `_persist` actually wrote, not the one handed in: the projection
	# rewrites the grant record as part of the rebuild, so the pre-write copy would
	# be stale the moment the rebuild ran — which is the same reason `_persist`
	# persists its return value rather than its argument.
	return {
		"ok": true, "reason": "", "applied": applied, "ledger": actor.get_module_data(MODULE_KEY)
	}


## Put `actor` in `position_id` within the sect they are sworn to. Returns
## `{ok: bool, reason: String}`.
##
## **This writes the position and nothing else.** It does not touch standing, does
## not award it, and does not infer it from the office: a member may hold a high
## position on thin standing, and thick standing in no position at all (ADR 0064).
##
## ## `standing_below_floor` is a route, not a wall
##
## The office's authored floor is the ordinary promotion gate and it refuses with
## its name, but `promote` takes `force` so promotion on thin standing **stays
## expressible** — which is what ADR 0064's two-part split is for, and a gate that
## made the exception unreachable would have thrown the politics away. A forced
## promotion says so in the history trail, so a later reader can tell which
## promotions were earned and which were political.
##
## An overflow is a **refused admit**, never a silent trim: the caller may ask, and
## the answer names whether the seat is taken (`seat_occupied`) or the room is full
## (`capacity_full`).
##
## `force` overrules both of those refusals, not just the floor. A council that
## will seat someone it does not have the standing for is overruling the room as
## well, and a flag that opened one route while the other still refused would be a
## verb that cannot do what its name says. `promote_forced` in the trail is how a
## later reader tells the two apart.
##
## ## `held` counts the holders ALREADY in the office
##
## The claim being written below makes the caller one more, so the room is asked
## about **before** the write and `held` is never incremented to compensate — the
## alternative refuses the very first member to arrive at an empty seat and grants
## every room one seat too many. Asking first also keeps a refusal a refusal: it
## writes nothing at all, so the count the caller passed is exactly the count the
## sect was left with (ADR 0084).
static func promote(
	actor: Actor, position_id: StringName, force: bool = false, held: int = 0
) -> Dictionary:
	var read := _claim(actor)
	if not SectState.is_affiliated(read):
		return _refuse(NOT_A_MEMBER, read)
	var sect_id := SectState.institution(read)
	var def := SectCatalog.instance().sect_definition(sect_id)
	if def == null:
		return _refuse(UNKNOWN_SECT, read)
	var office := def.position(position_id)
	if office == null:
		return _refuse(UNKNOWN_POSITION, read)
	if SectState.standing(read) < office.standing_floor and not force:
		return _below_floor(read, office)
	# `force` is the override that opens the route, and it opens BOTH halves of it.
	# A council that will overrule a floor is overruling the room as well: the two
	# refusals are one decision, and honouring one while the other still refuses
	# leaves a verb that cannot do what its name says. The trail records it as
	# `promote_forced`, so a panel reading "in the occupied seat" off a forced
	# admit is reading a true sentence.
	var seat := def.seat_state(office.id, held)
	if not bool(seat["has_room"]) and not force:
		return _refuse(String(seat["reason"]), read)
	var ledger := read.duplicate(true)
	ledger["position"] = String(office.id)
	_record(ledger, "promote" if not force else "promote_forced", office.id, "")
	_persist(actor, ledger, "promote")
	return _ok(ledger)


## ## Succession: WALKED, never rolled (ADR 0084, ADR 0058)
##
## `advance_succession(actor, position_id, action, periods)` takes **exactly one**
## authored stage per call and refuses a further step until a period has elapsed.
## Three actions, and the whole of the walk is three of them at most:
##
##   - `open` — record the seat vacant. Opening a vacancy IS a stage, because
##     ADR 0058's ascension had a `commit` to start it and this module has no such
##     verb; inventing a hidden starter would mean an action that is not a stage.
##   - `step` — take the next authored stage of the open walk.
##   - `wait` — let `periods` pass on a vacancy. **No clock is read**: a period is a
##     count the caller that owns time hands in (DEF-0111), and `wait` is where it
##     lands rather than being silently folded into `step`.
##
## ## `periods` is `open` and `wait`'s argument, never `step`'s
##
## The vacancy clock only ever moves where this module is told to move it — on
## `open` and on `wait`. A `step` reads the periods the seat has already accrued in
## the ledger and refuses otherwise, because a step that could accept its own waiting
## is a step nobody can be made to wait for: `advance_succession(actor, office,
## &"step", 9)` used to satisfy `may_step` outright and take a stage in the same
## breath, which is exactly the pacing ADR 0084 asks this verb for.
##
## ## There is no rng anywhere in this path
##
## No `rng`, no `randi`, no seed. The outcome is a pure function of the ledger, which
## is why `test_sect_succession.gd` can run the identical walk across a hundred fresh
## actors and get byte-identical results — and why that test can also grep this module
## for the three names and fail if one ever appears.
##
## ## One refusal for three finished walks
##
## `walk_complete` covers a walk that has taken every authored stage, a seat that was
## never vacant, and a method this module does not walk at all. They are one sentence
## to a player — "that succession is finished" — and a panel should not have to know
## which of the three produced it. `no_such_walk` is different: nothing has started,
## which is a caller mistake rather than a finished thing.
static func advance_succession(
	actor: Actor, position_id: StringName, action: StringName = &"step", periods: int = 0
) -> Dictionary:
	var read := _claim(actor)
	if not SectState.is_affiliated(read):
		return _refuse(NOT_A_MEMBER, read)
	var def := SectCatalog.instance().sect_definition(SectState.institution(read))
	if def == null:
		return _refuse(UNKNOWN_SECT, read)
	var office := def.position(position_id)
	if office == null:
		return _refuse(UNKNOWN_POSITION, read)
	if not office.is_walkable_method():
		return _refuse(WALK_COMPLETE, read)
	var ledger := read.duplicate(true)
	match String(action):
		"open":
			ledger["succession"] = read["succession"].duplicate(true)
			SectSuccession.open(ledger, office.id, periods)
		"wait":
			SectSuccession.accrue(ledger, office.id, periods)
		_:
			var row := SectSuccession.walk(ledger, office.id)
			if row.is_empty():
				return _refuse(NO_SUCH_WALK, read)
			# A walk is finished when the ledger says so OR when it has already walked
			# the office's authored length. The second half is the honest reading of a
			# hand-edited save: a row claiming stage eight of a three-stage walk is not
			# a walk with five stages left, it is a finished walk wearing a bad number,
			# and `walked_of` clamps it to the authored length precisely so the two agree.
			if (
				bool(row.get("complete", false))
				or String(row["side"]) != SectSuccession.VACANT
				or SectSuccession.walked_of(ledger, office) >= office.walk_length()
			):
				return _refuse(WALK_COMPLETE, read)
			# The vacancy clock is the LEDGER's, never this argument's. `periods`
			# advances that clock on `open` and `wait` and is meaningless on `step`:
			# a step is the thing that WAITS for the clock, so letting the argument
			# stand in for the clock hands the caller the very waiting the step is
			# supposed to be waiting for — `periods=9` satisfied `may_step` outright
			# and skipped ADR 0084's pacing entirely. A step therefore reads only what
			# the seat has actually sat vacant for, and refusing writes nothing.
			var held := int(row.get("held_periods", 0))
			if not SectSuccession.may_step(office, held):
				return _period_not_elapsed(read, office, held)
			SectSuccession.step(ledger, office)
	_record(ledger, "succession_%s" % String(action), office.id, "")
	_persist(actor, ledger, "succession")
	return _ok(ledger)


## ## Teaching: the verb with a real cost on the teacher (BL-0187, BL-0188)
##
## `teach(teacher, student, doctrine_id)` runs `periods` sessions and moves exactly
## one number: the student's **fit** for that doctrine, by the doctrine's authored
## `fit_per_period`, clamped at `SectState.FIT_CAP`.
##
## ## `standing_delta` is 0 on EVERY success, and published
##
## Recognition and transmission are two of the three separate things ADR 0084 lets an
## institution hand out, and they never touch each other: a lesson moves fit and
## leaves standing alone, exactly as a promotion moves position and leaves standing
## alone. The key is published on every success payload so the invariant is
## **observable** rather than merely asserted in a comment — and fit itself projects
## **zero** stat modifiers, so a taught member's sheet is byte-identical before and
## after.
##
## ## Two different fit floors, and they answer different questions
##
## `teacher_unfit` is the doctrine's own `affinity_floor` read on the TEACHER's fit:
## a member below it cannot teach this thing at all. `comprehension_below_floor` is
## the student's BASE comprehension allocation — `get_base`, never `derived`, so a
## standing percent cannot fund the gate that measures the standing (ADR 0052/0054).
## The student's `min_purity` door is the sect's, and is asked separately.
##
## The tax is the office's `teach_tax` plus the doctrine's own, charged out of the
## teacher's `stamina`. It is the whole of BL-0188: teaching that is free and
## unlimited makes disciples a resource faucet.
static func teach(
	teacher: Actor, student: Actor, doctrine_id: StringName, periods: int = 1
) -> Dictionary:
	var t_ledger := _claim(teacher)
	var s_ledger := _claim(student)
	var teacher_id := "" if teacher == null else String(teacher.id)
	var student_id := "" if student == null else String(student.id)
	if teacher_id == "" or student_id == "" or teacher_id == student_id:
		return _refuse(SAME_ACTOR if teacher_id != "" else NO_ACTOR, t_ledger)
	var sect_id := SectState.institution(t_ledger)
	var def := SectCatalog.instance().sect_definition(sect_id)
	if def == null:
		return _refuse(UNKNOWN_SECT, t_ledger)
	var doctrine := SectDoctrineCatalog.instance().doctrine(doctrine_id)
	if doctrine == null:
		return _refuse(UNKNOWN_DOCTRINE, t_ledger)
	if not SectState.is_affiliated(s_ledger):
		return _refuse(STUDENT_NOT_SWORN, t_ledger)
	if not SectTeaching.teacher_fits(t_ledger, doctrine):
		return _refuse(TEACHER_UNFIT, t_ledger)
	if not SectTeaching.student_admitted(def, s_ledger):
		return _refuse(STANDING_BELOW_FLOOR, t_ledger)
	# BASE allocation only. `derived` would let this module's own standing percent
	# fund the gate that decides whether this module may teach (ADR 0052/0054).
	var comprehension := student.stats.get_base(Stat.COMPREHENSION)
	if not doctrine.admits_comprehension(comprehension):
		return _refuse(
			(
				COMPREHENSION_BELOW_FLOOR
				if comprehension < doctrine.comprehension_band().x
				else COMPREHENSION_ABOVE_SPAN
			),
			t_ledger
		)
	var office := def.position(SectState.position(t_ledger))
	var tax := SectTeaching.tax_for(doctrine, office)
	# What this CALL costs, not what one session costs. `tax_for` is the authored price
	# of a session and `periods` is how many the caller asked for, so a three-session
	# lesson that settled one session's price charged the teacher for two sessions they
	# were never given — the cost of a lesson and the value of that lesson were two
	# different numbers, which is the whole of BL-0188 being wrong.
	var cost := tax * float(maxi(1, periods))
	if not SectTeaching.can_pay(teacher, cost):
		return _refuse(NOTHING_TO_TEACH, t_ledger)
	var written := s_ledger.duplicate(true)
	# `fit_per_period`, the RATE — `SectTeaching.apply_fit` multiplies it by `periods`
	# itself. Handing it `SectTeaching.gain(...)`, which has already multiplied by
	# `periods`, counted the same sessions twice: three periods of a three-point
	# doctrine granted twenty-seven points instead of nine, so the payer's cost and the
	# student's gain were two different numbers.
	var gained := SectTeaching.apply_fit(written, doctrine.id, doctrine.fit_per_period, periods)
	if gained <= 0:
		return _refuse(NOTHING_TO_TEACH, t_ledger)
	SectTeaching.charge(teacher, cost)
	# The trail is written on the STUDENT, because the student's ledger is the one
	# that changed: standing, fit, position and the founder's lines are all the
	# student's. The teacher's record of the lesson is that they are still standing.
	written["history"] = (s_ledger["history"] as Array).duplicate(true)
	_record(written, "taught", doctrine.id, "%d periods" % periods)
	_persist(teacher, t_ledger, "teach")
	_persist(student, written, "taught")
	return _taught(written, gained, tax)


## Whether gated content may open for `actor`.
##
## `requirement` is authored data, never code: an empty dictionary is ungated, or
## a `{verb: ..., ...}` map naming exactly one of `SectGate`'s ten verbs. Returns
## `{ok: bool, reason: String, unmet: Array[Dictionary]}` — the same shape
## `SocialApi.gate` and `DestinyApi.gate` produce. An unknown verb refuses closed
## and names itself, because authored content that cannot be read must fail loudly
## rather than open a door.
##
## The actor is handed to `SectGate.evaluate` as its own argument and is NOT copied
## into the requirement first. Injecting it here is what would stop `{}` reading as
## ungated — a probe carrying an actor is no longer an empty requirement — and it is
## exactly the smuggling the gate refuses to allow: content that arrives carrying
## its own actor must not be able to answer for one nobody attached.
static func gate(actor: Actor, requirement: Dictionary) -> Dictionary:
	var verdict := SectGate.evaluate(actor, requirement)
	if not bool(verdict.get("ok", false)) and actor != null:
		SectProjection.events().gate_refused.emit(
			String(actor.id), String(verdict.get("reason", "")), requirement
		)
	return verdict


## The actor's versioned ledger exactly as core persists it. This is the payload a
## save carries, so a caller never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return SectState.empty()
	return _normalized(actor)


## ## The whole read model, in one call
##
## Every read this module owes a screen or a sibling is a key here, folded rather
## than published as its own method — see the class note on why the facade is at
## its cap and why `summary()` is the right shape. `{}` when there is no actor,
## which is the contract a panel tests instead of pixels.
##
## What a caller gets: which sect, who founded it, which office and its authored
## duties and authorities, standing and its share of the cap, what is still owed,
## the treasury's lines, the fit this member has with each doctrine, the bounded
## percent the claim currently projects, **the roster with each office's live seat
## state** — including the `seat_occupied` / `capacity_full` distinction, so a board
## screen renders the difference without re-deriving it — **the walk in progress on
## each seat**, every authored office of the sworn sect, every authored sect for
## comparison, and every authored doctrine.
static func summary(actor: Actor) -> Dictionary:
	var catalog := SectCatalog.instance()
	var out := {
		"has_actor": actor != null,
		"actor_id": "" if actor == null else String(actor.id),
		"is_member": false,
		"founded": false,
		"sect_id": "",
		"sect_name": "",
		"founder_id": "",
		"doctrine_id": "",
		"doctrine_name": "",
		"position_id": "",
		"position_name": "",
		"standing": 0,
		"standing_cap": 0,
		"standing_ratio": 0.0,
		"standing_percent": 0.0,
		"granted_percent": {},
		"min_purity": 0,
		"teaches": false,
		"fit": {},
		"obligations": {},
		"settled": true,
		"treasury": {},
		"roster": {},
		"roster_size": 0,
		"duties": [],
		"authorities": [],
		"can_promote": {},
		"sects": {},
		"doctrines": {},
	}
	var ledger := SectState.empty() if actor == null else _normalized(actor)
	var sect_id := SectState.institution(ledger)
	out["is_member"] = SectState.is_affiliated(ledger)
	out["founded"] = SectFounding.founded(ledger)
	out["sect_id"] = String(sect_id)
	out["founder_id"] = SectState.founder(ledger)
	out["position_id"] = String(SectState.position(ledger))
	out["standing"] = SectState.standing(ledger)
	out["standing_cap"] = int(ledger["standing_cap"])
	out["standing_ratio"] = SectState.claim(ledger).normalized()
	out["standing_percent"] = InstitutionClaim.standing_percent(SectState.standing(ledger))
	out["granted_percent"] = (ledger["granted_percent"] as Dictionary).duplicate()
	out["fit"] = (ledger["fit"] as Dictionary).duplicate()
	out["obligations"] = (ledger["obligation"] as Dictionary).duplicate()
	out["settled"] = SectState.claim(ledger).settled()
	out["treasury"] = (ledger["treasury"] as Dictionary).duplicate()
	out["roster"] = _roster_view(ledger)
	for doctrine_id in (ledger["fit"] as Dictionary).keys():
		var sworn := catalog.sect_definition(sect_id)
		if sworn == null:
			continue
		out["teaches"] = sworn.teaches_at(int((ledger["fit"] as Dictionary)[doctrine_id]))
	var def := catalog.sect_definition(sect_id)
	if def != null:
		out["sect_name"] = def.display_name
		out["doctrine_id"] = String(def.doctrine_id)
		out["min_purity"] = def.min_purity
		var doctrine := SectDoctrineCatalog.instance().doctrine(def.doctrine_id)
		out["doctrine_name"] = "" if doctrine == null else doctrine.display_name
		var office := def.position(SectState.position(ledger))
		if office != null:
			out["position_name"] = office.display_name
			out["duties"] = _strings(office.duties)
			out["authorities"] = _strings(office.authorities)
	# Every authored sect is listed whatever the actor is, so a screen can compare
	# institutions without a second call; `sworn` is the only thing that differs.
	for authored_id in catalog.sect_ids():
		out["sects"][String(authored_id)] = _sect_view(catalog.sect_definition(authored_id))
	for authored in SectDoctrineCatalog.instance().doctrine_ids():
		out["doctrines"][String(authored)] = _doctrine_view(
			SectDoctrineCatalog.instance().doctrine(authored)
		)
	if def == null:
		return out
	for office in def.positions:
		if office == null or office.id == &"":
			continue
		var room := def.position(office.id)
		# `held` is counted from THIS ledger's roster rather than passed in: an
		# argument is a number a caller can be wrong about, and the whole point of
		# BL-0176 is that the count is authored content read against authored
		# content. A member whose ledger holds no roster (anyone who joined rather
		# than founded) reads 0, which is the honest answer for "how many members
		# does MY ledger know about" — and the refusal still names the office.
		var held := SectState.roster_held(ledger, office.id, room)
		out["roster_size"] = int(out["roster_size"]) + held
		var seat := def.seat_state(office.id, held)
		out["can_promote"][String(office.id)] = {
			"id": String(office.id),
			"display_name": office.display_name,
			"capacity": office.capacity,
			"standing_floor": office.standing_floor,
			"below_floor": SectState.standing(ledger) < office.standing_floor,
			"held": held,
			"has_room": bool(seat["has_room"]),
			"reason": String(seat["reason"]),
			# The walk, read from the ledger rather than re-derived: a board screen
			# renders a vacancy without ever learning how the succession advances.
			"succession": _succession_view(ledger, office),
			"teach_tax":
			SectTeaching.tax_for(SectDoctrineCatalog.instance().doctrine(def.doctrine_id), office),
		}
	return out


# --- Internals -------------------------------------------------------------


## ## A refused verb writes nothing
##
## Every mutating verb hands back the ledger it found, so a caller can see that a
## refusal left `actor.module_data` byte-for-byte as it was (ADR 0044) and can
## still render the claim without a second read.
static func _refuse(reason: String, ledger: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "ledger": ledger}


## The success shape. `applied` is present on every verb so a caller can read one
## key without knowing which verb it called — the standing delta is the only one
## that is ever non-zero, and it is non-zero exactly when standing moved.
static func _ok(ledger: Dictionary) -> Dictionary:
	return {"ok": true, "reason": "", "applied": 0, "ledger": ledger}


## Read the ledger for a verb that may write. Normalized against the catalog, so
## the verbs below always operate on a well-formed ledger, and attached first so a
## caller that reaches a verb without `attach` still gets a projected actor.
static func _claim(actor: Actor) -> Dictionary:
	if actor == null:
		return SectState.empty()
	var pending: Dictionary = actor.get_module_data(MODULE_KEY)
	if pending.is_empty():
		attach(actor)
		pending = actor.get_module_data(MODULE_KEY)
	return SectState.normalize(pending)


static func _normalized(actor: Actor) -> Dictionary:
	return SectState.normalize(
		actor.get_module_data(MODULE_KEY), SectCatalog.instance().known_position_ids()
	)


## Append one line to the bounded explanation of how the member got here.
##
## A trail, never an audit log: `SectState.HISTORY_LIMIT` caps it so a save cannot
## grow without limit, and a refused verb never reaches this — it writes nothing at
## all (ADR 0084). `detail` is a string rather than a number so `force` and an
## ordinary promotion stay distinguishable to whoever reads the trail later.
static func _record(ledger: Dictionary, kind: String, id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	if history.size() >= SectState.HISTORY_LIMIT:
		return
	history.append({"kind": kind, "id": String(id), "detail": detail})


static func _write_claim(ledger: Dictionary, claim: InstitutionClaim) -> void:
	var payload := claim.to_dict()
	ledger["position"] = String(payload["position"])
	ledger["standing"] = int(payload["standing"])
	ledger["standing_cap"] = int(payload["standing_cap"])
	ledger["obligation"] = payload["obligation"]


## Persist, rebuild the projection, then announce. The three effects are one
## operation because a half-applied change — stats without a ledger, a ledger
## without stats — is the one state a player cannot recover from.
##
## `standing_delta` is the applied amount and is published so the write is
## observable: a refused verb never reaches here, so a consumer that sees this
## signal knows the ledger moved.
static func _persist(
	actor: Actor, ledger: Dictionary, kind: String, standing_delta: int = 0
) -> void:
	# The return value, never the argument: `SectProjection.apply` rewrites
	# `applied_standing` / `granted_percent` as part of the rebuild, so the ledger
	# handed in is stale the moment the projection runs. Persisting it would leave
	# the save naming a grant the actor is no longer carrying.
	var written := SectProjection.apply(actor, ledger)
	var sect_id := SectState.institution(written)
	var bus := SectProjection.events()
	bus.claim_changed.emit(String(actor.id), sect_id, SectState.position(written), kind)
	match kind:
		"join":
			bus.membership_changed.emit(String(actor.id), sect_id, true, "")
		"leave":
			bus.membership_changed.emit(String(actor.id), sect_id, false, "")
		_:
			if standing_delta != 0:
				bus.standing_changed.emit(
					String(actor.id), sect_id, standing_delta, SectState.standing(written)
				)


static func _below_floor(ledger: Dictionary, office: SectPositionDef) -> Dictionary:
	return {
		"ok": false,
		"reason": STANDING_BELOW_FLOOR,
		"ledger": ledger,
		"required": office.standing_floor,
		"actual": SectState.standing(ledger),
		"force": true,
	}


## `founding_cost_unmet`, with both numbers so a panel can show the shortfall rather
## than only the refusal. `force` is absent on purpose: there is no override for
## founding. BL-0174 prices an institution's existence and an override would make
## the price decorative.
static func _found_unmet(ledger: Dictionary, def: SectDef, price: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"reason": FOUNDING_COST_UNMET,
		"ledger": ledger,
		"required": int(price["outstanding"]),
		"actual": int(SectFounding.cost(def)["found"]),
		"currency": String(def.founding_cost.get("currency", "")),
	}


## `period_not_elapsed`, with both counts. This is ADR 0084's "refuses a further
## step until a period elapses" made legible: a panel can render "the seat has been
## empty 0 of 2 periods" without knowing what a stage is.
static func _period_not_elapsed(
	ledger: Dictionary, office: SectPositionDef, held: int
) -> Dictionary:
	return {
		"ok": false,
		"reason": PERIOD_NOT_ELAPSED,
		"ledger": ledger,
		"required": maxi(0, office.succession_periods),
		"actual": held,
	}


## The teaching success shape.
##
## `standing_delta` is **always 0** and is published rather than omitted, because
## ADR 0064's two-part split is the reason a lesson may not touch standing and a
## consumer has to be able to check that for itself. `fit` and `fit_delta` are the
## only numbers that move; `tax` is what the teacher paid for them.
static func _taught(ledger: Dictionary, gained: int, tax: float) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"applied": 0,
		"standing_delta": 0,
		"fit": (ledger["fit"] as Dictionary).duplicate(),
		"fit_delta": gained,
		"tax": tax,
		"ledger": ledger,
	}


## The roster as a screen reads it: office id to member ids, plus the size.
## `{}` for a member who joined rather than founded — this ledger knows no roster,
## which is ADR 0083's open question rather than an empty institution.
static func _roster_view(ledger: Dictionary) -> Dictionary:
	var out := {}
	var total := 0
	for position_id in SectState.roster(ledger).keys():
		var row = SectState.roster(ledger)[position_id]
		if not (row is Array):
			continue
		var ids: Array = []
		for member_id in row as Array:
			ids.append(String(member_id))
		out[String(position_id)] = ids
		total += ids.size()
	if not out.is_empty():
		out["size"] = total
	return out


## The walk on one office, as a board screen reads it: which side of the walk the
## seat is on, how far through it is, how many authored stages there are, and — for
## an empty seat — `"vacant": true`, which is ADR 0083's middle state spelled out
## rather than inferred from a blank string.
static func _succession_view(ledger: Dictionary, office: SectPositionDef) -> Dictionary:
	var row := SectSuccession.walk(ledger, office.id)
	var vacant := String(row.get("side", "")) == SectSuccession.VACANT
	return {
		"method": String(office.succession_method),
		"walkable": office.is_walkable_method(),
		"stages": office.stages().size(),
		"walked": SectSuccession.walked_of(ledger, office),
		"periods_required": maxi(0, office.succession_periods),
		"periods_held": int(row.get("held_periods", 0)),
		"vacant": vacant,
		"complete": bool(row.get("complete", false)),
	}


static func _doctrine_view(def: SectDoctrineDef) -> Dictionary:
	if def == null:
		return {}
	var band := def.comprehension_band()
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"teachings": _strings(def.teachings),
		"refusals": _strings(def.refusals),
		"comprehension_floor": band.x,
		"comprehension_span": band.y - band.x,
		"affinity_floor": def.floor_fit(),
		"fit_per_period": def.fit_per_period,
		"teach_tax": def.teach_tax,
	}


static func _sect_view(def: SectDef) -> Dictionary:
	if def == null:
		return {}
	var offices: Dictionary = {}
	for office in def.positions:
		if office == null or office.id == &"":
			continue
		offices[String(office.id)] = {
			"id": String(office.id),
			"display_name": office.display_name,
			"capacity": office.capacity,
			"standing_floor": office.standing_floor,
			"succession_method": String(office.succession_method),
			"succession_param": office.succession_param.duplicate(),
			"succession_periods": office.succession_periods,
			"walkable": office.is_walkable_method(),
			"walk_stages": office.stages().size(),
			"duties": _strings(office.duties),
			"authorities": _strings(office.authorities),
			"standing_percent_stats": office.standing_percent_stats.duplicate(),
			"patronage_per_period": office.patronage_per_period,
			"duty_per_period": office.duty_per_period,
			"teach_tax": office.teach_tax,
		}
	var top := def.top_position()
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"doctrine_id": String(def.doctrine_id),
		"top_position_id": "" if top == null else String(top.id),
		"min_purity": def.min_purity,
		"standing_cap": def.standing_cap,
		"founding_cost": def.founding_cost.duplicate(),
		"treasury_lines": SectFounding.treasury_lines(def),
		"positions": offices,
	}


static func _strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
