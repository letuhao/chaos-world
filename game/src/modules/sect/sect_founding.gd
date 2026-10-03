class_name SectFounding
extends RefCounted

## The one place a sect comes into being: it consumes the authored
## `founding_cost`, seats the founder in the top office, and opens the four
## founder-owned lines of the ledger (BL-0174, BL-0190, BL-0191).
##
## ## A sect is a SIGNAL, not a pile of items
##
## Founding is the only verb that opens a treasury, and a treasury in this repo is
## **a ledger of obligation lines on ids**, never a pile of items — a treasury that
## duplicated the `items` module's inventory would be two sources of truth for what
## an institution owns (BL-0191, ADR 0064). A line is an id and a count, so
## retuning a rate never rewrites a save.
##
## ## The founder is the first entry in the sect's own ledger, not a special case
##
## The roster holds plain actor-id strings and the founder is simply the first of
## them. A `Resource` or an `Actor` in either place would reach the save untouched
## and no checker in this repo can see it.
##
## ## What founding cannot do
##
## It cannot be cheap. An authored `founding_cost` is read as `{funds, outstanding}`
## — how much is in the treasury pool against what the sect charges to exist — and
## the shortfall is `founding_cost_unmet`. **This module never charges an inventory
## and never settles a debt**: it moves `found` off the funding pool, because an
## institution's existence being free would make founding a free action and BL-0174
## prices it on purpose. Anything past that price belongs to the economy verb that
## will own it.
##
## Nothing here reads a clock. `Actor` has no tick, `core/` owns no time, and a
## ledger that counted periods from `Time.get_ticks*` would make a save's contents
## depend on when it was written (ADR 0083, DEF-0111).

## The pool a founder funds a sect from. Namespaced under `sect:` so it is visibly
## the sect's own money and can never be confused with `health`, `stamina` or any
## inventory an item granted.
const FUNDING_POOL := &"sect_founding_funds"
## What founding starts a sect's treasury with, in periods. An opening balance is a
## starting state rather than a grant: the sect owes the world nothing on day one
## and everybody in it something from the day they walk in.
const TREASURY_OPENING_PERIODS := 1

## The named reason each refusal of `found` uses. Declared once and reused verbatim
## by the facade's constants, so the vocabulary is authored in one file and a panel
## renders a reason it did not have to invent (ADR 0084).
##
## Strings and not an `enum`, because every one of these is a value that crosses the
## facade as a `String` and is written into a ledger, a signal and a history record.
## An enum ordinal in any of those places would be a number that changes meaning the
## moment somebody reorders this file.
const R_NO_ACTOR := "no_actor"
const R_UNKNOWN_SECT := "unknown_sect"
const R_UNKNOWN_DOCTRINE := "unknown_doctrine"
const R_ALREADY_FOUNDED := "already_founded"
const R_NO_TOP_POSITION := "no_top_position"
const R_FOUNDING_COST_UNMET := "founding_cost_unmet"

## The same six, keyed by the name each refusal is written with, so a caller can
## look a reason up without holding the constant. `SectState.refuse` is the
## counterpart on the ledger side.
const REASONS := {
	R_NO_ACTOR: R_NO_ACTOR,
	R_UNKNOWN_SECT: R_UNKNOWN_SECT,
	R_UNKNOWN_DOCTRINE: R_UNKNOWN_DOCTRINE,
	R_ALREADY_FOUNDED: R_ALREADY_FOUNDED,
	R_NO_TOP_POSITION: R_NO_TOP_POSITION,
	R_FOUNDING_COST_UNMET: R_FOUNDING_COST_UNMET,
}


## Whether this ledger already names an institution. `found` is the only verb that
## may write it, and an actor may found exactly one sect: the tiers are peers, not a
## containment tree (ADR 0083), so founding twice is a `leave` and then a `found`.
static func founded(ledger: Dictionary) -> bool:
	return SectState.is_affiliated(ledger)


## The treasury lines founding opens, keyed by line id. One line per office the sect
## authors that carries an authored rate, plus one line for the institution itself.
##
## Every line is namespaced `treasury_<sect_id>_<what>` because the ledger belongs to
## a person, not to an institution: two sects may both owe the same actor's save, and
## a line one of them cannot see is a line it cannot accidentally settle.
static func treasury_lines(def: SectDef) -> Dictionary:
	var prefix := "treasury_%s_" % String(def.id)
	var out := {"%shall" % prefix: TREASURY_OPENING_PERIODS}
	for office in def.positions:
		if office == null or office.id == &"":
			continue
		if office.patronage_per_period > 0:
			out["%spatronage_%s" % [prefix, String(office.id)]] = office.patronage_per_period
		if office.duty_per_period > 0:
			out["%sduty_%s" % [prefix, String(office.id)]] = office.duty_per_period
	return out


## What this sect charges to exist: `{found, outstanding}`. An authored cost with no
## `outstanding` is a cost nothing has to pay, which is a deliberate way to author a
## free sect rather than an accident the module has to guess about.
static func cost(def: SectDef) -> Dictionary:
	var authored = def.founding_cost.get("outstanding", def.founding_cost.get("amount", 0))
	return {"found": maxi(0, int(authored)), "outstanding": maxi(0, int(authored))}


## What this actor has put into the founding pool, read as a plain pool balance. Zero
## for an actor who has funded nothing, which is the ordinary case and never an
## error — "this member has no founding fund" and "this member spent it all" are the
## same answer.
static func funds(actor: Actor) -> float:
	if actor == null:
		return 0.0
	var pool := actor.resource(FUNDING_POOL)
	return 0.0 if pool == null else pool.current


## Take `amount` off the founding pool. Zero-or-less takes nothing, so a settlement is
## never a negative accrual. No-op rather than an error for an actor with no pool at
## all: a member who never funded anything has nothing to take.
static func draw(actor: Actor, amount: float) -> void:
	if actor == null or amount <= 0.0:
		return
	var pool := actor.resource(FUNDING_POOL)
	if pool == null:
		return
	pool.change(-amount)


## The ledger a founding writes, built from a blank skeleton rather than from the
## caller's. A found sect is a NEW claim: nothing about the caller survives into it,
## because a founder who carried a rival house's office into their own house would
## be seated in two institutions at once.
##
## `standing` is `FOUNDER_REFUND_STANDING` rather than zero, and the reason is the
## one ADR 0064's split makes obvious: founding PRICES a sect, and charging the
## founder again for standing inside their own sect would make the price of existing
## an infinite regress. It is a named constant rather than a percent or a multiple
## because a floor would make founding a demotion and a multiple would make it a
## grant, and neither is what happened.
static func write(
	def: SectDef, doctrine: SectDoctrineDef, founder_id: String, top: SectPositionDef
) -> Dictionary:
	var ledger := SectState.normalize({})
	ledger["institution"] = String(def.id)
	ledger["doctrine"] = String(doctrine.id)
	ledger["standing"] = mini(SectState.FOUNDER_REFUND_STANDING, maxi(1, def.standing_cap))
	ledger["standing_cap"] = maxi(1, def.standing_cap)
	ledger["position"] = String(top.id)
	ledger[SectState.FOUNDER_KEY] = String(founder_id)
	ledger["roster"] = {String(top.id): [String(founder_id)]}
	ledger["treasury"] = treasury_lines(def)
	# A founding obligation is what the FOUNDER owes to hold the top office, which is
	# the office's own rate stacked on the membership rate — not a fresh invention.
	var duties := def.member_obligation_lines()
	var office_lines := top.obligation_lines()
	for term_id in office_lines.keys():
		duties[String(term_id)] = maxi(
			int(duties.get(String(term_id), 0)), int(office_lines[term_id])
		)
	ledger["obligation"] = duties
	return ledger
