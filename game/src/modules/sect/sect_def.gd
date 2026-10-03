class_name SectDef
extends Resource

## One authored sect: a school of teaching, a doctrine, and the offices its
## members may hold (ADR 0083).
##
## A sect is **sworn to, not born into**. ADR 0083 put the three institutional
## tiers on a strict acyclic chain — race, bloodline, clan, sect, nation — and a
## sect is the first tier on it you can *leave*, which is why `standing` can fall
## here as it cannot in a clan. It grants exactly three things and no more
## (ADR 0084): recognition, access, and transmission. Transmission is `doctrine_id`
## plus fit, and fit is a gate that projects **zero** modifiers.
##
## `doctrine_id` is content, not a hierarchy. Nothing in this module ranks one
## sect against another; "which sect teaches what" is a `.tres` question, the
## same way authority is.
##
## Adding a sect is authoring a `.tres` under `res://data/sect/`, never code.

## The refusal reason an office reaches when its authored cap is 1 and somebody
## already holds it. Distinct from `capacity_full` on purpose (ADR 0084): a seat
## produces a succession contest and a room produces a queue, and a panel that
## renders one string for both has destroyed the difference between them.
const SEAT_OCCUPIED := "seat_occupied"
## The refusal reason an office reaches when its authored cap is above 1 and it is
## full. Still a refused admit, never a silent trim.
const CAPACITY_FULL := "capacity_full"
## The refusal reason a `promote` gives on thin standing. **A route, not a wall**
## (ADR 0084): promotion on thin standing stays expressible, which is what
## ADR 0064's two-part split is for.
const STANDING_BELOW_FLOOR := "standing_below_floor"

## Periods of `duty_<sect_id>` a membership opens against an ordinary member, holding
## no office at all. **A constant rather than a field because this is a duty of
## membership, not of an office** — `SectPositionDef.duty_per_period` is the
## authored per-office rate, and a member who holds none of them still owes the sect
## something, or ADR 0083's question for this tier ("who taught me, and what am I
## obliged to do?") has no answer in the ordinary case.
const MEMBER_DUTY_PERIODS := 1
## The side of a seat's `succession_method` a holder is standing on. A vacancy is
## the OTHER side, which is why `SectState` keeps it as its own key rather than as
## a stage number with a sentinel.
const SUCCESSION_SEATED := "seated"
const SUCCESSION_VACANT := "vacant"

## The pool id a treasury publishes under. Authored here rather than in a screen so
## the sect's money and the player's money are two visibly different currencies and
## a treasury can never be mistaken for an inventory (BL-0191).
const TREASURY_POOL := &"sect_treasury"

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice: what is taught here and what
## the house asks of its members (AGENTS.md).
@export var description: String = ""

## The doctrine this sect teaches. A sect's teaching is its reason to exist and
## is distinct from its politics, which is what `positions` is.
@export var doctrine_id: StringName = &""

## The offices this sect ships. Discretely authored, keyed by `id`, never a
## ladder: `position` is an id and never an index (ADR 0083).
@export var positions: Array[SectPositionDef] = []

## Fit below this is refused a teaching. Fit is **transmission**, one of the three
## things an institution grants, and it is a gate and nothing else — it projects
## no modifier at all (ADR 0084), which is precisely what keeps it from becoming
## a second currency for comprehension.
@export var min_purity: int = 0

## The ceiling this sect's standing clamps to. Authored per institution so the
## political range is content rather than a constant buried in a ledger.
@export var standing_cap: int = 100

## What founding one costs. Content, so an institution's existence is priced by
## the game rather than by whatever code happened to gate it. This module records
## it and never charges it: charging is an economy verb and `sect` declares no
## `items` dependency, which is the whole point of the boundary. It is read at
## founding as `{funds, outstanding}` — **how much the founder has in the treasury
## pool against what the sect charges to exist**.
@export var founding_cost: Dictionary = {}

## The places this sect claims, by id. **Ids, never sub-resources**, and a
## schism's per-territory charge is counted against this list rather than against
## whatever the caller happened to pass — a bill a caller can shrink is a bill
## nobody has to pay (BL-0197, ADR 0085).
##
## A claim on ground confers nothing: no combat bonus, no yield, no upkeep. What
## it decides is who MAY fight and where, and that is the whole of ADR 0085's
## territory rule. `""` means this sect authors no claims at all, which makes a
## split of it cost the declared price and nothing more — not a zero price,
## because the per-territory charge is an addition and never a substitute.
@export var territory_ids: Array[StringName] = []

## The office a founder is seated in, by id. `""` means the highest office this
## sect authors that a SUCCESSION can actually reach, which is what a founder is:
## they hold the top the sect has, and the top is decided by content rather than by
## an array index (ADR 0083 — a position is an id, never a ladder position).
@export var top_position_id: StringName = &""

## Who this sect acts FIRST among the institutions competing for one period's budget
## (BL-0198). **An integer, because the tie-break is structural and there is no
## generator anywhere in the decision**: candidates sort by `(act_priority,
## institution_id)` and `institution_id` is a `StringName`, so the second key is
## lexicographic and total — ties are impossible by construction, so no seed has to
## be saved and a test can run the identical walk a hundred times and get identical
## output. Higher acts sooner; it is an ORDER, never a magnitude, and it is never
## multiplied by anything.
@export var act_priority: int = 0


## Whether this sect authors an office under `position_id`.
func has_position(position_id: StringName) -> bool:
	return position(position_id) != null


## The office a founder takes, or null when this sect authors none.
##
## An authored `top_position_id` wins when it names an office that exists and can be
## reached by succession. Otherwise the top is the **highest-standing-floored office
## whose method names a walk**, so `{"steward": 60, "reader": 20}` finds `steward`
## without the author writing the id down — and a sect whose only office is a
## `named` or `inherited` seat finds nothing, because seating a founder there is not
## a thing its culture does.
##
## Ties are impossible rather than broken arbitrarily: two offices sharing a floor is
## a content mistake, and refusing to guess about it is the same rule `position()`
## follows when two `.tres` answer to one id.
func top_position() -> SectPositionDef:
	if top_position_id != &"":
		var authored := position(top_position_id)
		if authored != null and authored.succeeds_by_walk():
			return authored
	var best: SectPositionDef = null
	for def in positions:
		if def == null or def.id == &"" or not def.succeeds_by_walk():
			continue
		if best == null or def.standing_floor > best.standing_floor:
			best = def
	return best


## Whether this sect has an office a founder could be seated in. The refusal
## `no_top_position` reads off this rather than being written per caller.
func has_top_position() -> bool:
	return top_position() != null


## The office under `position_id`, or null. Null rather than a guess: an office
## nothing defines grants nothing, gates nothing, and cannot be filled, so
## inventing one would hide a content bug behind a working-looking promotion.
func position(position_id: StringName) -> SectPositionDef:
	if position_id == &"":
		return null
	for def in positions:
		if def != null and def.id == position_id:
			return def
	return null


## Whether an office under `position_id` may exercise `authority_id`. Both halves
## are authored: the office must exist and its `authorities` must name the verb.
func has_authority(position_id: StringName, authority_id: StringName) -> bool:
	var def := position(position_id)
	return def != null and def.grants(authority_id)


## Every office id this sect authors, canonically ordered. The known-content
## filter `SectState.normalize` is handed, so a save from a wider content build
## cannot smuggle in a seat this build does not ship.
func position_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in positions:
		if def != null and def.id != &"":
			out.append(def.id)
	out.sort()
	return out


## Whether `fit` is enough for this sect to teach. The boundary is inclusive: a
## gate reading strictly above would make a `min_purity` unreachable by exactly
## the number the content author wrote down.
func teaches_at(fit: int) -> bool:
	return fit >= min_purity


## ## Why `seat_occupied` and `capacity_full` are two different strings
##
## `held` is how many members the caller already counted in this office. The
## answer is `{has_room: bool, reason: String}`:
##
##   - `has_room` false with reason `seat_occupied` — the authored cap is **1**.
##     The seat exists and is taken. That is a succession question: somebody has
##     to leave, die or be expelled, and each of those is a political event the
##     player can watch. Rendering it as "full" would hide all three.
##   - `has_room` false with reason `capacity_full` — the authored cap is **above
##     1** and every slot is filled. Nobody is blocking anybody; the room is shut
##     until a period passes.
##
## The distinction is load-bearing per ADR 0084, so it lives on the authored
## definition rather than in the facade: the answer is a property of the content,
## and two callers asking about the same office must never disagree about which
## word it produced.
##
## `has_room` true always reports an empty `reason`: a room with space in it has
## no refusal to name.
func seat_state(position_id: StringName, held: int) -> Dictionary:
	var def := position(position_id)
	if def == null:
		# An office this sect does not author cannot admit anybody. The reason is
		# the full one, not the seat one: there is no seat here at all.
		return {"has_room": false, "reason": CAPACITY_FULL}
	if def.has_room(held):
		return {"has_room": true, "reason": ""}
	return {
		"has_room": false,
		"reason": SEAT_OCCUPIED if def.capacity == 1 else CAPACITY_FULL,
	}


## The claim a new member of this sect starts on: standing at zero, the authored
## cap, and no position. `SectorDef` never mints a position on its own — ADR
## 0083's two-part split means thick standing and a held office are separate
## facts, and a fresh member legitimately has the first without the second.
func new_claim() -> InstitutionClaim:
	var claim := InstitutionClaim.new()
	claim.standing_cap = maxi(1, standing_cap)
	return claim


## The obligation lines a member of this sect owes while they hold no office at
## all. Ids and counts only, so a save never carries an authored amount.
##
## Both kinds of line are here and neither is optional. `instruction_<sect>` is the
## price of being taught at all; `duty_<sect>` is what the sect asks of anybody it
## counts among its own, and it is the only line a `duty_owed` gate can be asked
## about before an office exists — a gate naming a line no membership ever opened
## reads every member's debt as zero, which is a gate answering `yes` to everyone
## rather than one that refuses.
func member_obligation_lines() -> Dictionary:
	var out := {"duty_%s" % String(id): MEMBER_DUTY_PERIODS}
	if min_purity > 0:
		out["instruction_%s" % String(id)] = mini(min_purity, SectState.FIT_CAP)
	return out
