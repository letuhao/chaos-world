class_name NationApi
extends RefCounted

## Public facade for the `nation` module. Other modules may reference ONLY this
## file (`api.gd`).
##
## ## A nation is the third tier: offices that may be VACANT, and claims over land
##
## ADR 0083's three-state vocabulary is the contract every caller reads:
##   - `{}` — this does not exist. A spare row in a pool. Hidden, not counted.
##   - `"vacant": true` — this EXISTS and its value is absent. An office with no
##     holder. **Visible**, with its own tone, because a succession that renders an
##     unfilled seat as `0` has destroyed the design that made the vacancy legible.
##   - `{"ok": false, "reason": "<named>"}` — this action EXISTS and is refused.
##     `reason` is an authored constant on `NationState`, never a UI string.
##
## ## A conflict is a declaration of sides and a prize, never a formula
##
## `declare_war` writes a standoff with its PRIZE fixed up front; `resolve_conflict`
## counts a verdict already decided elsewhere. This module never calls combat,
## never reads a combat stat, and owns no `rng` (ADR 0085). Its only arithmetic is
## `tally + transfer`.
##
## ## There is no world tick
##
## Nothing here reads `Time`, and every accrual takes an explicit `periods` count
## from a caller that owns time (DEF-0111). A module that invented a timer would be
## a second source of truth for when a save happened.
##
## ## Who the ids in this ledger are
##
## `nation_id`, every `holder_id` and every standoff side is the POLITY's id, and
## the ledger is keyed under one actor's `module_data` because that is the only
## persistence root the repo has (ADR 0083 records the disclosed gap and requires
## the ledger be JSON-safe, which it is). **Every other identifier crossing this
## facade is a plain `StringName` id** — a sect, a clan, a place — and never a
## class, because the tier reads only DOWNWARD and always as ids.
##
## ## Reading `sect`: the edge `tools arch` cannot see
##
## A nation's offices are filled FROM sects, never because a nation contains them
## (ADR 0083). `BARE_REF_UNITS` excludes `modules/*`, so a bare `SectApi`
## reference out of `modules/nation/` reports ZERO violations and a cycle written
## that way is invisible to the gate — ADR 0083 says so in its own Consequences.
## `sect` therefore names `clan`, and the ONLY sanctioned seam is the `preload`
## below: one `res://` edge to a facade, which the resolver DOES read. Every other
## sect identifier is a plain id string, and `test_nation_sect_edge.gd` greps this
## module for a bare `Sect[A-Z]` class name outside that line so the invisible cycle
## cannot be written quietly.
const SECT_FACADE := preload("res://src/modules/sect/api.gd")
## ## And the one sanctioned edge to `social`, for the same reason
##
## A nation's founding, its seats and its wars are public acts, and they move the
## same institutional `regard` a sect's do (BL-0200). `social` is reached exactly as
## `sect` is: one `preload`, which is the only shape the resolver reads, because
## `BARE_REF_UNITS` excludes `modules/*` and a bare `SocialApi` reference out of
## `modules/nation/` would report ZERO violations (ADR 0083).
const SOCIAL_FACADE := preload("res://src/modules/social/api.gd")

## The actor component holding the live projection state.
const STATE_COMPONENT := &"nation_state"
## `actor.module_data` key the versioned ledger is persisted under (ADR 0027).
const MODULE_KEY := NationState.MODULE_KEY
## How far into a standoff a verdict must be, by mode (ADR 0085). A mode changes
## the quota and the prize shape only, never how a verdict is produced.
const QUOTAS := {NationState.CONTEST: 3, NationState.SIEGE: 5, NationState.TRIBUNAL: 1}

## ## The decision verbs (BL-0198)
##
## `act` **PROPOSES**; the composition root RESOLVES. That split is ADR 0085's shape
## applied one layer up — "the conflict module never calls combat, never reads a
## combat stat, and never owns an `rng`" — and ADR 0114's handler shape: a handler
## never mutates, it returns a proposal, and the director applies. So nothing below
## writes a ledger, moves a claim or declares a war; it names what the polity WOULD
## do, and `app/` calls the verb that does it.
##
## **The set is CLOSED, and it is the whole of what `act` may ever return.** Two of
## the seven institutional verbs live here — `claim_territory` and
## `accrue_territory`, the module's only per-period income and the only verb a
## background tick may propose without inventing a number. `set_stance`,
## `declare_war` and `resolve_conflict` are reachable only from a caller that has an
## opinion to state and a prize to declare: a clock may not choose a war (ADR 0085 —
## a conflict is a DECLARATION of sides and a prize, and nothing here declares one).
##
## Every `target` is an id the ledger or the catalog already holds; nothing in this
## path invents a number. Membership is `ACT_VERBS.has(verb)`, which is why this is
## a const rather than a thirteenth method on a facade that has one slot left.
const VERB_ACCRUE := "accrue_territory"
const VERB_CLAIM := "claim_territory"

## The whole closed set this module may propose, in one place, so a test asserts
## membership against the constant rather than restating the list in a fourth file.
const ACT_VERBS: Array[StringName] = [VERB_ACCRUE, VERB_CLAIM]

## ## The authored causes a nation's acts move `regard` BY
##
## Ids in `social`'s catalog, reached as plain strings through the `preload` above.
## The pairing with `sect` is deliberate: both tiers ask the same module to record
## the same kind of fact, which is what makes "regard toward an institution" ONE
## number rather than three (ADR 0083's answer to the ADR 0066 failure mode).
const CAUSE_LIVED := &"lived_under_nation"
const CAUSE_LEFT := &"left_a_nation"
const CAUSE_EXPELLED := &"expelled_from_nation"
const CAUSE_HELD_OFFICE := &"held_nation_office"
const CAUSE_FOUGHT := &"fought_for_a_nation"


## Attach the module to `actor`. Restores any ledger a prior `Actor.from_dict`
## carried, normalizes it against the current catalog, and rebuilds the bounded
## PERCENT recognition from the ledger. Idempotent, and safe before the actor lives
## under any nation at all — which is the normal starting state (ADR 0083).
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := _ledger(actor)
	actor.set_module_data(MODULE_KEY, ledger)
	_mirror(actor, ledger)
	_project(actor, ledger)


## Found the nation `actor` lives under, and seat its authored board. Founding a
## nation the actor already lives under returns that same ledger with nothing
## written, so a caller may call this on story entry without asking first.
##
## `founder_id` names who established it, as a plain actor id **string**, never an
## `Actor`: an `Actor` in a ledger reaches the save untouched and no checker in this
## repo can see it.
static func found(actor: Actor, nation_id: StringName, founder_id: String = "") -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var def := _catalog().nation_definition(nation_id)
	if def == null:
		return NationState.refuse(NationState.R_UNKNOWN_NATION, {"nation_id": String(nation_id)})
	var ledger := _ledger(actor)
	if NationState.founded(ledger):
		return ledger
	var claim := def.own_claim()
	ledger["nation_id"] = String(nation_id)
	ledger["standing_cap"] = maxi(1, claim.standing_cap)
	ledger["standing"] = clampi(claim.standing, 0, int(ledger["standing_cap"]))
	var board := def.board()
	for office_id in board.keys():
		(ledger["offices"] as Dictionary)[String(office_id)] = String(board[office_id])
	_advance(ledger)
	_record(ledger, "founded", nation_id, founder_id)
	# Living under a polity is a public act and moves the institutional `regard` the
	# other tiers move (BL-0200) — through `social`, so this module keeps no second
	# copy of it. It does NOT move `standing`: that is what the nation thinks of
	# the polity, and founding is a beginning rather than an earned reputation.
	_regard(actor, nation_id, CAUSE_LIVED)
	_persist(actor, ledger)
	var bus := NationProjection.events()
	bus.nation_founded.emit(String(actor.id), nation_id, founder_id)
	for office_id in def.vacant_office_ids():
		bus.office_vacated.emit(String(actor.id), office_id, nation_id)
	return ledger


## Take or contest a claim over places (ADR 0085).
##
## WHICH of the two happens is read from the ledger, never passed in: ground
## nobody holds is a take, ground somebody else holds is a challenge. A caller
## that named the outcome could contradict the ledger and open a take over held
## ground, so there is no parameter to contradict it with.
##
## **A claim on held ground never moves ground**: a challenge writes a
## challenger and opens exactly ONE standoff, and `holder_id` is byte-identical
## before and after. Only `resolve_conflict` paying an `ownership` prize transfers
## the claim, and it transfers the whole row rather than merging two holders'.
static func claim_territory(actor: Actor, territory_id: StringName) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var catalog := _catalog()
	var def := catalog.territory_definition(territory_id)
	if def == null:
		return NationState.refuse(
			NationState.R_UNKNOWN_TERRITORY, {"territory_id": String(territory_id)}
		)
	var ledger := _ledger(actor)
	if not NationState.founded(ledger):
		return NationState.refuse(NationState.R_UNKNOWN_NATION, {"nation_id": ""})
	var entry: Dictionary = (ledger["claims"] as Dictionary).get(String(territory_id), {})
	var holder := String(entry.get("holder_id", ""))
	var self_id := String(NationState.nation_id(ledger))
	if holder == self_id and holder != "":
		return NationState.refuse(
			NationState.R_ALREADY_HELD, {"territory_id": String(territory_id)}
		)
	var floor := catalog.tuning().claim_floor_for(def.tier_index)
	var standing := int(ledger["standing"])
	if standing < floor:
		return NationState.refuse(NationState.R_CLAIM_FLOOR, {"standing": standing, "floor": floor})
	if holder == "":
		_take(ledger, territory_id, def)
		_advance(ledger)
		_record(ledger, "claimed", territory_id, "")
		_persist(actor, ledger)
		NationProjection.events().territory_claimed.emit(String(actor.id), territory_id, self_id)
		return _ok(ledger, {"territory_id": String(territory_id), "holder_id": self_id})
	# Ground somebody holds: write a challenger, open one standoff, and leave
	# `holder_id` byte-for-byte as it was found.
	entry["challenger_id"] = self_id
	(ledger["claims"] as Dictionary)[String(territory_id)] = entry
	var id := _declare(ledger, self_id, holder, territory_id, NationState.CONTEST)
	_declare_prize(ledger, id, _contested_prize(self_id, holder))
	_advance(ledger)
	_record(ledger, "challenged", territory_id, holder)
	_persist(actor, ledger)
	NationProjection.events().war_declared.emit(
		String(actor.id), id, StringName(holder), String(NationState.CONTEST)
	)
	return _ok(
		ledger,
		{"territory_id": String(territory_id), "challenger_id": self_id, "holder_id": holder}
	)


## Give up a claim, in full. Leaving is always permitted and always costs (ADR
## 0083), so this refuses on nothing but "you do not hold it".
static func release_territory(actor: Actor, territory_id: StringName) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var ledger := _ledger(actor)
	var entry = (ledger["claims"] as Dictionary).get(String(territory_id), null)
	if not (entry is Dictionary):
		return NationState.refuse(NationState.R_NOT_HELD, {"territory_id": String(territory_id)})
	var holder := String((entry as Dictionary).get("holder_id", ""))
	(ledger["claims"] as Dictionary).erase(String(territory_id))
	_advance(ledger)
	_record(ledger, "released", territory_id, holder)
	_persist(actor, ledger)
	NationProjection.events().territory_released.emit(String(actor.id), territory_id, holder)
	return _ok(ledger, {"territory_id": String(territory_id)})


## Settle `periods` of yield and upkeep against every claim this polity holds.
##
## ## The caller owns time, and this verb owns none
##
## `periods` arrives as an explicit argument because **there is no clock in this
## repo** (DEF-0111). Nothing here reads `Time`, declares a process callback or
## reaches for the tree, and a module that invented a timer would be a second
## source of truth for when a save happened. A caller that owns time — the only
## place a period can come from — decides how many elapsed and asks for exactly
## that many to be settled.
##
## Every amount is read from `NationTuning` rather than from a literal here, so a
## rebalance is a `.tres` edit. Yield and upkeep are both **rates** (a rate answers
## "what is one unit worth", never "how strong is a thing"), and both net into the
## same standing the projection reads, so a claim that costs more than it pays is a
## balance mistake an author can read off the tier row rather than discover in play.
##
## `periods` at or below zero settles nothing and writes nothing: a settlement is
## not a negative accrual.
static func accrue_territory(actor: Actor, periods: int) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	if periods <= 0:
		return _ok(_ledger(actor), {"periods": 0, "settled": 0, "yielded": 0, "upkeep": 0})
	var ledger := _ledger(actor)
	var tuning := _tuning()
	var claims: Dictionary = ledger["claims"]
	var net := 0.0
	var settled := 0
	for territory_id in claims.keys():
		var entry: Dictionary = claims[territory_id]
		# A claim this polity does not HOLD pays nothing. A row written by a take
		# this actor does not speak for is not this actor's income.
		if String(entry.get("holder_id", "")) != String(ledger.get("nation_id", "")):
			continue
		var tier := int(entry.get("tier_index", 0))
		net += tuning.yield_for(tier) - tuning.upkeep_for(tier)
		entry["yield_accrued"] = (
			int(entry.get("yield_accrued", 0)) + int(roundf(tuning.yield_for(tier)))
		)
		claims[territory_id] = entry
		settled += 1
	if settled == 0:
		return _ok(ledger, {"periods": periods, "settled": 0, "yielded": 0, "upkeep": 0})
	var before := int(ledger["standing"])
	# Multiply by `periods` BEFORE rounding. Rounding the per-period net and then
	# scaling it makes two periods worth something other than twice one, so a board
	# whose net is 0.6 pays 1 for two periods where two periods should pay 1 — and
	# the same call at 5 periods pays the same 1. A claim is a per-period RATE and
	# the ledger keeps whole units, so the product is taken once, at the end.
	ledger["standing"] = clampi(
		before + int(roundf(net * float(periods))), 0, int(ledger["standing_cap"])
	)
	var moved := int(ledger["standing"]) - before
	_advance(ledger)
	_record(ledger, "accrued", StringName(ledger["nation_id"]), "%d periods" % periods)
	_persist(actor, ledger)
	NationProjection.events().territory_accrued.emit(
		String(actor.id), settled, periods, int(ledger["standing"])
	)
	return _ok(
		ledger,
		{
			"periods": periods,
			"settled": settled,
			"standing_moved": moved,
			"net_rate": net,
		}
	)


## Write the ONE canonical stance row for an unordered pair (ADR 0047 as extended by
## ADR 0085). The row is keyed by the two ids ordered lexicographically, so reading
## it back with the ids swapped returns the identical dictionary and a one-sided
## opinion is structurally impossible.
##
## The verb set is CLOSED: `rival`, `neutral`, `allied`, `truce`, `embargo`, `war`.
## An unknown value refuses as `unknown_verb` and **names itself** in the detail, so
## malformed content fails loudly rather than opening a door nobody can read.
## `war` is in the set but is reachable ONLY through `declare_war`: it is refused
## here as `war_requires_a_prize`, so no war can exist without a declared prize.
static func set_stance(actor: Actor, other_id: StringName, verb: StringName) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var text := String(verb)
	if not NationState.is_verb(text):
		return NationState.refuse(NationState.R_UNKNOWN_VERB, {"verb": text})
	if text == "war":
		return NationState.refuse(NationState.R_WAR_REQUIRES_A_PRIZE, {"verb": text})
	if String(other_id) == "":
		return NationState.refuse(NationState.R_UNKNOWN_NATION, {"nation_id": ""})
	var ledger := _ledger(actor)
	var self_id := String(actor.id)
	var key := NationState.pair_key(StringName(self_id), other_id)
	_advance(ledger)
	(ledger["stances"] as Dictionary)[key] = {
		"verb": text,
		"other_id": String(other_id),
		"sequence": int(ledger["sequence"]),
	}
	_record(ledger, "stance", other_id, text)
	_persist(actor, ledger)
	NationProjection.events().stance_changed.emit(self_id, key, other_id, text)
	return _ok(ledger, {"pair_key": key, "verb": text})


## Declare a standoff over a territory, with its PRIZE fixed up front.
##
## `prize` is `{mode, transfer, standing}` where `transfer` is `ownership`,
## `recognition` or `tribute`, and `standing` is a per-nation-id delta map read
## **verbatim at resolution**. Declaring it now is what makes a conflict a political
## object rather than a scoring function: both sides know what is at stake before
## the first verdict.
##
## This is the ONLY path to a `war` stance, and it is why `set_stance` refuses that
## verb (ADR 0085).
static func declare_war(
	actor: Actor, other_id: StringName, territory_id: StringName, prize: Dictionary
) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var self_id := String(actor.id)
	if String(other_id) == "" or self_id == String(other_id):
		return NationState.refuse(NationState.R_UNKNOWN_NATION, {"other_id": String(other_id)})
	var mode := String(prize.get("mode", NationState.CONTEST))
	if not NationState.is_mode(mode):
		return NationState.refuse(NationState.R_UNKNOWN_MODE, {"mode": mode})
	var transfer := String(prize.get("transfer", ""))
	# An EMPTY transfer is legal and means "nothing moves, only standing" — a
	# tribunal decides who is owed what, not who holds the ground. What is refused
	# is a transfer that is neither empty nor one of the three declared shapes: that
	# is a content bug, and the one thing ADR 0085 forbids is quietly resolving it
	# to `ownership`. An absent key therefore declares nothing moving rather than
	# inventing the strongest prize on the list.
	if transfer != "" and not NationState.TRANSFERS.has(StringName(transfer)):
		return NationState.refuse(NationState.R_UNKNOWN_TRANSFER, {"transfer": transfer})
	var ledger := _ledger(actor)
	if not NationState.founded(ledger):
		return NationState.refuse(NationState.R_UNKNOWN_NATION, {"nation_id": ""})
	var id := _declare(ledger, self_id, String(other_id), territory_id, StringName(mode))
	_declare_prize(ledger, id, prize)
	_advance(ledger)
	_record(ledger, "declared", StringName(id), transfer)
	_persist(actor, ledger)
	NationProjection.events().war_declared.emit(self_id, id, other_id, mode)
	return _ok(ledger, {"standoff_id": id, "mode": mode, "quota": int(QUOTAS.get(mode, 3))})


## Record a verdict already decided elsewhere — a `CombatApi.exchange` the caller
## ran, a tournament result, a tribunal's ruling — and pay the DECLARED prize once
## the quota is met. **Never a fight**: no damage, no stat, no `rng` (ADR 0085).
##
## Exhaustion decides whether a side may KEEP FIGHTING, never who owns ground: a
## side whose losses reach `war_break` is refused further verdicts, and a forced
## `withdrawal` pays the declared standing costs and **moves no territory**.
static func resolve_conflict(
	actor: Actor, standoff_id: StringName, winner_id: StringName, close_outcome: String = ""
) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var ledger := _ledger(actor)
	var entry = (ledger["standoffs"] as Dictionary).get(String(standoff_id), null)
	if not (entry is Dictionary):
		return NationState.refuse(
			NationState.R_UNKNOWN_STANDOFF, {"standoff_id": String(standoff_id)}
		)
	var standoff: Dictionary = (entry as Dictionary).duplicate(true)
	if bool(standoff.get("closed", false)):
		return _ok(ledger, {"standoff_id": String(standoff_id), "closed": true})
	var winner := String(winner_id)
	var sides: Dictionary = standoff["sides"]
	if not sides.has(winner):
		return NationState.refuse(
			NationState.R_UNKNOWN_WINNER, {"winner_id": winner, "standoff_id": String(standoff_id)}
		)
	var loser := ""
	for side_id in sides.keys():
		if String(side_id) != winner:
			loser = String(side_id)
	var winner_side: Dictionary = (sides[winner] as Dictionary).duplicate(true)
	var loser_side: Dictionary = (sides[loser] as Dictionary).duplicate(true)
	winner_side["won"] = int(winner_side.get("won", 0)) + 1
	loser_side["lost"] = int(loser_side.get("lost", 0)) + 1
	loser_side["exhaustion"] = maxf(
		0.0, float(loser_side.get("exhaustion", 0.0)) + _tuning().exhaustion_per_loss
	)
	sides[winner] = winner_side
	sides[loser] = loser_side
	standoff["sides"] = sides
	# One verdict is ONE exchange, and both sides' counters are two VIEWS of that one
	# event: the winner's `won` and the loser's `lost` always move together. Adding
	# them counts every verdict twice, which halves the effective quota — a siege
	# authored at five closes on the third call. The tally is the loser's `lost`
	# because every exchange has exactly one loser, so that counter is the count.
	var total := int(loser_side["lost"])
	if total < int(standoff.get("quota", 1)):
		(ledger["standoffs"] as Dictionary)[String(standoff_id)] = standoff
		_persist(actor, ledger)
		return _ok(ledger, {"standoff_id": String(standoff_id), "verdicts": total, "closed": false})
	return _close(actor, ledger, standoff_id, standoff, winner, loser, close_outcome)


## The actor's versioned ledger exactly as core persists it. This is the payload a
## save carries, so a caller never reaches into `actor.module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return NationState.empty()
	return _ledger(actor)


## A read-only, primitive-only snapshot built for a screen: the board of offices,
## the claims held, the stances and the standoffs, in ONE call.
##
## Every read a screen needs folds in here rather than becoming a facade method:
## nine facades already sit at the twelve-method cap, so "add a method" is not a
## free move in this program.
##
## **Vacancies are visible rows.** An authored seat with no holder appears under
## `offices` with `"vacant": true` and `"holder_id": ""` — never as `0`, never as
## `"-"`, never omitted, because the succession design exists to make an unfilled
## seat legible.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {"has_actor": false, "offices": {}, "vacant_offices": 0}
	var catalog := _catalog()
	var ledger := _ledger(actor)
	var nation_id := NationState.nation_id(ledger)
	var def := catalog.nation_definition(nation_id)
	var out := {
		"has_actor": true,
		"actor_id": String(actor.id),
		"nation_id": String(nation_id),
		"nation_name": "" if def == null else String(def.display_name),
		"founded": NationState.founded(ledger),
		"standing": int(ledger["standing"]),
		"standing_cap": int(ledger["standing_cap"]),
		"standing_normalized": NationState.normalized_standing(ledger),
		"recognized_percent": InstitutionClaim.standing_percent(int(ledger["standing"])),
		"sequence": int(ledger["sequence"]),
		"offices": {},
		"vacant_offices": 0,
		"filled_offices": 0,
		"claims": {},
		"stances": {},
		"standoffs": {},
		"open_standoffs": 0,
	}
	var office_defs := catalog.office_definitions(nation_id)
	var board: Dictionary = ledger["offices"]
	for office_id in board.keys():
		var holder := String(board[office_id])
		var office = office_defs.get(String(office_id), null)
		var vacant := holder == ""
		if vacant:
			out["vacant_offices"] = int(out["vacant_offices"]) + 1
		else:
			out["filled_offices"] = int(out["filled_offices"]) + 1
		out["offices"][String(office_id)] = {
			"office_id": String(office_id),
			"display_name": "" if office == null else String(office.display_name),
			"succession_method": "" if office == null else String(office.succession_method),
			"capacity": 0 if office == null else office.capacity,
			# ADR 0083's middle state, spelled out rather than inferred from a blank
			# string: the seat EXISTS and its value is absent.
			"vacant": vacant,
			"holder_id": holder,
			"powers": [] if office == null else _string_list(office.powers),
		}
	for territory_id in (ledger["claims"] as Dictionary).keys():
		out["claims"][String(territory_id)] = _claim_view(ledger, StringName(territory_id), catalog)
	for key in (ledger["stances"] as Dictionary).keys():
		out["stances"][String(key)] = _stance_view(ledger, String(key))
	for standoff_id in (ledger["standoffs"] as Dictionary).keys():
		var standoff: Dictionary = (ledger["standoffs"] as Dictionary)[standoff_id]
		out["standoffs"][String(standoff_id)] = _standoff_view(standoff)
		if not bool(standoff.get("closed", false)):
			out["open_standoffs"] = int(out["open_standoffs"]) + 1
	return out


# --- Internals ---------------------------------------------------------------


## ## The ONE place this module moves `regard`, and it moves nothing else
##
## Identical in shape to `sect`'s counterpart and for the same reason: a nation keeps
## no regard number, no regard ledger and no increment. It asks `social` to apply an
## AUTHORED cause to the bond between this actor and the POLITY's id (ADR 0091), and
## `social` owns the arithmetic, the cause ledger and the projection. Two tiers
## recording the same kind of fact through one module is what stops the three
## institutions growing a second copy of one number (ADR 0066).
##
## **The partner is the POLITY id, not the actor id.** A nation outlives any one
## member (ADR 0083's disclosed gap), so an actor id here would write an opinion the
## world would forget with the person. The same string is the ledger's `nation_id`.
##
## ## Silence is a refusal, and every call site is past its own
##
## `apply_cause` refuses an unknown cause rather than moving nothing quietly. It can
## only refuse here if the shipped catalog lacks this id, and a test asserts it does
## not — so the silent path is a failed test rather than an invisible one.
static func _regard(actor: Actor, nation_id: StringName, cause_id: StringName) -> void:
	if actor == null or nation_id == &"":
		return
	SOCIAL_FACADE.apply_cause(actor, nation_id, cause_id)


## Leave a nation, or be cast out of one. The two are deliberately different verbs
## with different causes rather than one verb with a flag: ADR 0083 makes leaving
## always permitted and always costs, while an expulsion is the polity's verdict and
## must cost more — a single "depart" would have to pick one number for both.
##
## Underscore-prefixed, so neither counts against the twelve-method cap. `NationApi`
## has two free slots today, but a verb whose only caller is another module is not a
## reason to spend one: the component-id reach is the `TechniquesApi.CASTING_COMPONENT`
## precedent (ADR 0083 folds reads into `summary()` and keeps the surface small).
static func _leave(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	if not NationState.founded(ledger):
		return NationState.refuse(NationState.R_NO_NATION)
	_regard(actor, NationState.nation_id(ledger), CAUSE_LEFT)
	var cleared := NationState.normalize({})
	cleared["history"] = (ledger["history"] as Array).duplicate(true)
	_persist(actor, cleared)
	return _ok(cleared)


static func _expel(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	if not NationState.founded(ledger):
		return NationState.refuse(NationState.R_NO_NATION)
	_regard(actor, NationState.nation_id(ledger), CAUSE_EXPELLED)
	var cleared := NationState.normalize({})
	cleared["history"] = (ledger["history"] as Array).duplicate(true)
	_persist(actor, cleared)
	return _ok(cleared)


## Seat `actor` in one of their own nation's offices, and let the world hear it.
## Holding a seat is public recognition and is exactly the fact ADR 0083 separates
## from `standing` inside the institution — a member may hold a seat on thin
## standing, and the regard the world extends is the same either way.
static func _hold_office(actor: Actor, office_id: StringName, holder_id: String) -> Dictionary:
	var ledger := _ledger(actor)
	if not NationState.founded(ledger):
		return NationState.refuse(NationState.R_NO_NATION)
	if String(holder_id) != String(actor.id):
		return NationState.refuse(NationState.R_NOT_A_PARTY)
	if office_id == &"":
		return NationState.refuse(NationState.R_NO_SEATS)
	var catalog := _catalog()
	if not catalog.known_ids().has(String(office_id)):
		return NationState.refuse(NationState.R_UNKNOWN_OFFICE)
	var board: Dictionary = ledger["offices"]
	var seat := String(board.get(String(office_id), ""))
	var def: Variant = catalog.office_definitions(NationState.nation_id(ledger)).get(
		String(office_id), null
	)
	if seat != "" and (def == null or def.capacity <= 1):
		return NationState.refuse(NationState.R_SEAT_OCCUPIED)
	if seat != "" and def != null:
		# A room above one: count the holders already in it, bounded by the office's
		# own capacity so a corrupt save cannot ask this loop for more seats than the
		# room has. Snapshot the bound before the walk — a loop whose bound it is
		# itself growing does not terminate.
		var held := 0
		for other_id in board.keys():
			if String(board[other_id]) == String(holder_id):
				held += 1
		if held >= def.capacity:
			return NationState.refuse(NationState.R_CAPACITY_FULL)
	board[String(office_id)] = String(holder_id)
	_advance(ledger)
	_record(ledger, "seated", office_id, holder_id)
	_regard(actor, NationState.nation_id(ledger), CAUSE_HELD_OFFICE)
	_persist(actor, ledger)
	var bus := NationProjection.events()
	bus.office_filled.emit(
		String(actor.id), office_id, String(holder_id), NationState.nation_id(ledger)
	)
	return _ok(ledger, {"office_id": String(office_id), "holder_id": String(holder_id)})


static func _catalog() -> NationCatalog:
	return NationCatalog.instance()


static func _tuning() -> NationTuning:
	return _catalog().tuning()


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return NationState.empty()
	return NationState.normalize(actor.get_module_data(MODULE_KEY), _catalog().known_ids())


static func _ok(ledger: Dictionary, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "nation_id": String(ledger.get("nation_id", ""))}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out


## Write an unheld claim. `held_since` is the ledger's OWN sequence, never a clock
## read: a claim whose age depended on when the file happened to be saved would
## make the ledger's history depend on the save (DEF-0111).
static func _take(ledger: Dictionary, territory_id: StringName, def: NationTerritoryDef) -> void:
	var tier := def.tier_index
	(ledger["claims"] as Dictionary)[String(territory_id)] = {
		"territory_id": String(territory_id),
		"holder_id": String(ledger.get("nation_id", "")),
		"held_since": int(ledger.get("sequence", 0)),
		"tier_index": tier,
		"challenger_id": "",
		"yield_accrued": maxi(1, int(roundf(_tuning().yield_for(tier)))),
	}


## Write a standoff shell: two sides, a quota read from the MODE, an exhaustion
## counter, and the pair's ONE canonical `war` stance row. Returns the standoff id.
## The prize is attached separately so it is stored exactly as declared.
static func _declare(
	ledger: Dictionary, side_a: String, side_b: String, territory_id: StringName, mode: StringName
) -> String:
	var key := NationState.pair_key(StringName(side_a), StringName(side_b))
	var sequence := NationState.next_sequence(ledger)
	var id := "%s@%d" % [key, sequence]
	var blank := {"won": 0, "lost": 0, "exhaustion": 0.0}
	(ledger["standoffs"] as Dictionary)[id] = {
		"standoff_id": id,
		"other_id": side_b,
		"territory_id": String(territory_id),
		"mode": String(mode),
		"quota": int(QUOTAS.get(mode, 3)),
		"winner_id": "",
		"outcome": "",
		"closed": false,
		"declared_sequence": sequence,
		"sides": {side_a: blank.duplicate(true), side_b: blank.duplicate(true)},
		"tributes": {},
		"prize": {},
	}
	# The ONE canonical `war` row for this pair. Declaring is the only door to it,
	# which is why `set_stance` refuses that verb.
	(ledger["stances"] as Dictionary)[key] = {
		"verb": "war",
		"other_id": side_b,
		"sequence": sequence,
	}
	return id


## Attach a declared prize to a standoff, field by field, with `String` keys and
## integer values throughout. A prize nobody declared in the declared shape is
## DROPPED, never defaulted: a war without a prize must not be able to invent one.
static func _declare_prize(ledger: Dictionary, standoff_id: String, prize: Dictionary) -> void:
	var standoff: Dictionary = (ledger["standoffs"] as Dictionary).get(standoff_id, {})
	if standoff.is_empty():
		return
	var deltas := {}
	var standing = prize.get("standing", {})
	if standing is Dictionary:
		for side_id in (standing as Dictionary).keys():
			deltas[String(side_id)] = int((standing as Dictionary)[side_id])
	standoff["prize"] = {
		"mode": String(prize.get("mode", standoff.get("mode", NationState.CONTEST))),
		"transfer": String(prize.get("transfer", "")),
		"standing": deltas,
	}
	(ledger["standoffs"] as Dictionary)[standoff_id] = standoff


## The prize a contested-claim standoff declares: ownership of the claim, plus the
## authored standing for each side. Read from the TUNING, so the module owns no
## balance literal — a rebalance is a `.tres` edit (ADR 0067).
static func _contested_prize(challenger: String, holder: String) -> Dictionary:
	var tuning := _tuning()
	return {
		"mode": String(NationState.CONTEST),
		"transfer": String(NationState.OWNERSHIP),
		"standing":
		{
			challenger: int(tuning.standing_on_win),
			holder: -int(tuning.standing_on_loss),
		},
	}


## Close a standoff and pay its DECLARED prize. The only arithmetic here is
## `tally + transfer` (ADR 0085): a withdrawal moves NO territory, so the
## declaration and the counter cannot decide a war between them.
static func _close(
	actor: Actor,
	ledger: Dictionary,
	standoff_id: StringName,
	standoff: Dictionary,
	winner: String,
	loser: String,
	forced: String
) -> Dictionary:
	var tuning := _tuning()
	var deltas: Dictionary = (standoff["prize"] as Dictionary).get("standing", {})
	var loser_side: Dictionary = (standoff["sides"] as Dictionary)[loser]
	var winner_gain := int(deltas.get(winner, int(tuning.standing_on_win)))
	var loser_cost := absi(int(deltas.get(loser, -int(tuning.standing_on_loss))))
	var outcome := "resolved"
	if forced != "":
		outcome = forced
	elif float(loser_side.get("exhaustion", 0.0)) >= tuning.war_break:
		# Exhaustion decides whether a side may KEEP FIGHTING, never who owns
		# ground. A broken side pays and moves nothing.
		outcome = "withdrawal"
	if outcome != "resolved":
		winner_gain = int(deltas.get(winner, 0))
		loser_cost = absi(int(deltas.get(loser, int(tuning.standing_on_surrender))))
	var gained := _pay(ledger, winner, winner_gain)
	var lost := _pay(ledger, loser, -loser_cost)
	var transferred := ""
	if (
		outcome == "resolved"
		and (
			String((standoff["prize"] as Dictionary).get("transfer", ""))
			== String(NationState.OWNERSHIP)
		)
	):
		transferred = _transfer(ledger, standoff, winner)
	standoff["winner_id"] = winner
	standoff["outcome"] = outcome
	standoff["closed"] = true
	(ledger["standoffs"] as Dictionary)[String(standoff_id)] = standoff
	_advance(ledger)
	_record(ledger, outcome, StringName(winner), loser)
	# A closed war is the one deed a nation records publicly about its own people, and
	# it is what `fought_for_a_nation` is authored for. **Only the standing side gets
	# it**: a war fought and lost is not a credential, and a cause applied to both
	# sides would make the prize a participation trophy. A withdrawal is excluded too
	# — the polity did not fight, it ran.
	if outcome == "resolved" and winner == String(ledger.get("nation_id", "")):
		_regard(actor, NationState.nation_id(ledger), CAUSE_FOUGHT)
	_persist(actor, ledger)
	NationProjection.events().conflict_resolved.emit(
		String(actor.id), String(standoff_id), winner, outcome
	)
	return _ok(
		ledger,
		{
			"standoff_id": String(standoff_id),
			"outcome": outcome,
			"winner_id": winner,
			"loser_id": loser,
			"standing_gained": gained,
			"standing_lost": lost,
			"territory_transferred": transferred,
		}
	)


## Move a whole claim to `winner` and return the territory id, or `""` when there
## was nothing to transfer. The claim row MOVES rather than merging: a territory
## has exactly one holder, and two polities' rows for the same ground would be the
## one-sided ownership a single canonical row exists to prevent.
static func _transfer(ledger: Dictionary, standoff: Dictionary, winner: String) -> String:
	var territory_id := String(standoff.get("territory_id", ""))
	var entry = (ledger["claims"] as Dictionary).get(territory_id, null)
	if territory_id == "" or not (entry is Dictionary):
		return ""
	var moved: Dictionary = (entry as Dictionary).duplicate(true)
	moved["holder_id"] = winner
	moved["held_since"] = int(ledger.get("sequence", 0))
	moved["challenger_id"] = ""
	(ledger["claims"] as Dictionary)[territory_id] = moved
	return territory_id


## Move one side's standing and return the amount that actually landed, clamped at
## zero. A defeat lowers a number and never dissolves an institution (ADR 0085), and
## a polity this actor does not speak for pays nothing.
static func _pay(ledger: Dictionary, nation_id: String, delta: int) -> int:
	if nation_id == "" or String(ledger.get("nation_id", "")) != nation_id:
		return 0
	var before := int(ledger["standing"])
	ledger["standing"] = clampi(before + delta, 0, int(ledger["standing_cap"]))
	return int(ledger["standing"]) - before


static func _advance(ledger: Dictionary) -> void:
	ledger["sequence"] = NationState.next_sequence(ledger)


static func _record(ledger: Dictionary, kind: String, id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	if history.size() >= NationState.HISTORY_LIMIT:
		return
	history.append(
		{"kind": kind, "id": String(id), "detail": detail, "sequence": int(ledger["sequence"])}
	)


## Persist, rebuild the bounded PERCENT recognition, and keep the component in
## step. The three effects are one operation because a ledger without a projection
## is the one state a player cannot recover from.
static func _persist(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(MODULE_KEY, ledger)
	_mirror(actor, ledger)
	_project(actor, ledger)


## Keep the `actor.components` mirror in step with the persisted payload.
##
## The mirror is a `RefCounted` holder rather than the dictionary itself because
## `Actor.set_component` takes a `RefCounted` and the ledger is a plain
## `Dictionary`. The ledger in `module_data` stays the single source of truth —
## core persists it verbatim and never names a nation type — so the mirror is
## only what a caller reads without going through the facade.
static func _mirror(actor: Actor, ledger: Dictionary) -> void:
	var mirror := actor.component(STATE_COMPONENT) as NationStateComponent
	if mirror == null:
		mirror = NationStateComponent.new()
		actor.set_component(STATE_COMPONENT, mirror)
	mirror.write(ledger)


static func _project(actor: Actor, ledger: Dictionary) -> void:
	var catalog := _catalog()
	var nation_id := NationState.nation_id(ledger)
	var granted := NationProjection.apply(
		actor, ledger, catalog.office_definitions(nation_id), nation_id
	)
	var next := NationState.normalize(ledger, catalog.known_ids())
	next["applied_percent"] = granted
	actor.set_module_data(MODULE_KEY, next)
	_mirror(actor, next)


static func _string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## One claim row as a screen reads it: who holds it, since when, at what tier, what
## it has accrued, and who is contesting it. A claim with no challenger says so with
## `""` — ADR 0083's first state — rather than omitting the key.
static func _claim_view(
	ledger: Dictionary, territory_id: StringName, catalog: NationCatalog
) -> Dictionary:
	var entry: Dictionary = (ledger["claims"] as Dictionary).get(String(territory_id), {})
	var def := catalog.territory_definition(territory_id)
	var tier := int(entry.get("tier_index", 0))
	return {
		"territory_id": String(territory_id),
		"display_name": "" if def == null else String(def.display_name),
		"holder_id": String(entry.get("holder_id", "")),
		"held_since": int(entry.get("held_since", 0)),
		"tier_index": tier,
		"challenger_id": String(entry.get("challenger_id", "")),
		"yield_accrued": int(entry.get("yield_accrued", 0)),
		"location_count": 0 if def == null else def.location_ids.size(),
		"has_seat": def != null and def.has_seat(),
		"upkeep": catalog.tuning().upkeep_for(tier),
	}


static func _stance_view(ledger: Dictionary, key: String) -> Dictionary:
	var entry: Dictionary = (ledger["stances"] as Dictionary).get(key, {})
	var pair := NationState.split_pair_key(key)
	return {
		"pair_key": key,
		"a_id": "" if pair.is_empty() else String(pair[0]),
		"b_id": "" if pair.size() < 2 else String(pair[1]),
		"verb": String(entry.get("verb", "")),
		"other_id": String(entry.get("other_id", "")),
		"sequence": int(entry.get("sequence", 0)),
	}


static func _standoff_view(standoff: Dictionary) -> Dictionary:
	var sides := {}
	var stored: Dictionary = standoff.get("sides", {}) as Dictionary
	for side_id in stored.keys():
		var side: Dictionary = stored[side_id]
		sides[String(side_id)] = {
			"won": int(side.get("won", 0)),
			"lost": int(side.get("lost", 0)),
			"exhaustion": float(side.get("exhaustion", 0.0)),
		}
	return {
		"standoff_id": String(standoff.get("standoff_id", "")),
		"other_id": String(standoff.get("other_id", "")),
		"territory_id": String(standoff.get("territory_id", "")),
		"mode": String(standoff.get("mode", "")),
		"quota": int(standoff.get("quota", 1)),
		"closed": bool(standoff.get("closed", false)),
		"outcome": String(standoff.get("outcome", "")),
		"winner_id": String(standoff.get("winner_id", "")),
		"sides": sides,
		"tributes": (standoff.get("tributes", {}) as Dictionary).duplicate(true),
		# The DECLARED prize, verbatim. Never recomputed for display.
		"prize": (standoff.get("prize", {}) as Dictionary).duplicate(true),
	}
