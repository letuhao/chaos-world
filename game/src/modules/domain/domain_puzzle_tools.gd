class_name DomainPuzzleTools
extends RefCounted

## Puzzle quality-of-life for a domain run: UNDO, HINTS and a SCORE.
##
## A player who cannot read a formation had exactly one way out before this file:
## walk away. There was no undo, no hint and no grade — `DomainFixtures.attempt` answers
## a wrong node with an interruption and a reset to the FIRST node
## (`domain_fixtures.gd:_wrong`), so a player who cannot find the order is never
## stranded against a half-solved formation but is also never told anything they did
## wrong beyond "wrong_node". These three verbs are the other half of that bargain:
## the reset stays EXACTLY as it is, and a player who wants to keep their place asks
## for it explicitly.
##
## ## NOTHING HERE RUNS AUTOMATICALLY
##
## `_wrong`'s reset is deliberate and documented (`domain_fixtures.gd:_wrong`: the
## `progress` it discarded is "deliberately NOT a parameter"). Undo is a SEPARATE,
## OPT-IN verb the caller must reach for. Nothing in this file is wired into
## `attempt`, so a caller that wires none of it gets the fixture behaviour that
## already ships, unchanged — which is the only way to add recovery to a puzzle
## without weakening its gate.
##
## ## THE ADAPTER: ONE SURFACE, TWO PUZZLE KINDS
##
## `record` / `undo` / `hint` / `score` never branch on a puzzle kind. They ask the
## adapter the same four questions of every fixture — [method _total_of],
## [method _done_of], [method _solved] and [method _step_of] — and read the same
## published answer shape. A screen and the headless driver therefore render a hint
## and a score breakdown without naming a kind at all: everything they need is in
## [method read_model].
##
## `ADAPTER_FORMATION` is a shipped `sequence` of node ids, which
## `DomainFixtures.attempt` already plays. `ADAPTER_SPATIAL` is an authored grid with
## a start and a goal, which no shipped fixture plays yet: `domain_grid_puzzle.gd`
## was still uncommitted when this was written and is another session's path, so
## nothing here names it. Its half is written against AUTHORED FIELDS
## (`grid`/`cells`, `width`, `start`, `at`, `goal`) and against the fixture's own
## ledger row as [method DomainFixtures.state_of] publishes it, so the day that
## module writes its cells into that row the spatial adapter starts reading the live
## board with no edit here. **The spatial adapter is the ONE place to extend when a
## new puzzle kind lands**; the four features above it do not change.
##
## ## THE HINT'S PRICE IS A COUNT, AND IT IS PAID IN THE SCORE
##
## Health is out (ADR 0075 forbids a second damage-over-time channel, and
## `DomainFixtures._wrong` already owns this fixture's one body-costing channel — a
## CONTROL gate). Time is out because a module may not own a clock (ADR 0089,
## DEF-0111): a hint priced in seconds needs a per-frame accrual that keeps charging
## while the player walks away from the puzzle. So the price is the fixture's authored
## `hint_budget` (default [constant HINT_BUDGET]), and the price is not merely a
## limiter — it is recorded on the same ledger row the grade reads, so **the currency
## is paid in the ranking, not in the body.** A hint is free in the body and expensive
## in the score, which is the shape ADR 0216 wants: a fixture names what it pays by
## where it sits, and a formation pays insight, so a formation's help is paid for in
## the formation's own record rather than out of a pool.
##
## ## THE GRADE IS TWO AXES, AND BOTH ALREADY EXIST
##
## `wrong` and `hints`. `periods` is ACCEPTED and PUBLISHED but never graded on: no
## caller in the repo owns a clock to pass it, so grading on it would make every
## production grade read `forced` while a test that supplies it looked correct — a
## read model that lies is worse than one that admits a gap. `moves` is declined for
## the same reason from the other side: `_wrong` resets `progress` to 0, so
## `wrong + progress` undercounts and a real `moves` axis would need a new counter
## written by whoever owns the board.
##
## ## STATE, AND WHY IT IS RUN-SCOPED WITHOUT TOUCHING `api.gd`
##
## Everything lives under `DomainApi.MODULE_KEY` / [constant STATE_KEY], primitives
## only, JSON round-trippable, normalised on read through `int()` / `String()` because
## a save has no bools and no int/float distinction. `DomainApi.enter` clears
## `DomainFixtures.STATE_KEY` but not this one, so the stored row carries the RUN it
## belongs to and [method _tools] discards a stack whose run is not the current one.
## That is a fresh run starting with no history, reached without a second clear in a
## file another session holds.

# ── the two authored kinds ───────────────────────────────────────────────────

## An ORDERED list of node ids: what `DomainFixtures.attempt` plays.
const ADAPTER_FORMATION := "formation"
## An authored GRID with a start and a goal. No shipped fixture plays this yet.
const ADAPTER_SPATIAL := "spatial"

## The four directions a spatial hint may name. A hint names ONE of them, never a
## path: a direction is a single step, and the player still has to find the cell.
const DIRECTION_NORTH := "north"
const DIRECTION_SOUTH := "south"
const DIRECTION_EAST := "east"
const DIRECTION_WEST := "west"
const DIRECTION_HERE := "already_there"

# ── state ────────────────────────────────────────────────────────────────────

## Where this file's state sits inside the run. A SIBLING of
## `DomainFixtures.STATE_KEY`, not a nested key under it: the fixture ledger is the
## authored puzzle's own row and this is a different concern that must not be able to
## drop its fields.
const STATE_KEY := "puzzle_tools"

## Bumped when the stored shape changes. Read back through [method _clean_of] so a
## row written by an older shape degrades to the default rather than crashing.
const STATE_VERSION := 1

# ── bounds ───────────────────────────────────────────────────────────────────

## ## How deep an undo stack goes, and why eight
##
## EIGHT, not "however many moves the player made". It is a FIXED constant on
## purpose: a bound read from the stack's own size is the INC-0002 shape (a body that
## grows the container the loop tests never terminates), and an unbounded stack is a
## save that grows without limit as a player mashes a grid. Eight covers the shipped
## five-phase formation end to end plus a few wrong strikes, which is the whole
## recovery need; a deeper stack costs JSON for no authored puzzle in the corpus.
const MAX_UNDO_DEPTH := 8

## The ceiling on the primitives ONE snapshot may hold, across every field. This is
## the allocation guard for a grid: `record` takes a caller-supplied board, and a
## board nobody bounded is the 67 GB shape (INC memory). Exceeding it is refused BY
## NAME and nothing is written.
const MAX_SNAPSHOT_VALUES := 4096

## How many hints a puzzle owes when it authors none. Two of the shipped
## formation's five nodes, so a hint can never hand over the answer.
const HINT_BUDGET := 2

## The ceiling on an AUTHORED `hint_budget`, so a content wave cannot make hints
## free by typing a large number.
const HINT_BUDGET_MAX := 8

## What a hint is PAID in, named so a reader never has to infer it. Not one of ADR
## 0216's currencies: nothing leaves the body and nothing leaves the bag. The cost is
## a slot of the fixture's own budget, and it is spent in the GRADE — which is what
## gives the spend a sink, so a hint is never a free press.
const PAY_HINT := "hint_budget"

# ── grades ───────────────────────────────────────────────────────────────────

const GRADE_FLAWLESS := "flawless"
const GRADE_CLEAN := "clean"
const GRADE_BRACED := "braced"
const GRADE_FORCED := "forced"

## Wrong strikes a solve may carry and still read `braced`. Zero is `flawless` or
## `clean`; three or more is `forced`. Authored here rather than inlined so the two
## graded axes and their edges are one table.
const BRACED_WRONG := 2

# ── answers ──────────────────────────────────────────────────────────────────

const OK_RECORDED := "recorded"
const OK_UNDONE := "undone"
const OK_HINTED := "hinted"
const OK_SCORED := "scored"

# ── reasons. Every refusal has a stable id a reader can show. ────────────────

const ERR_NO_ACTOR := "no_actor"
const ERR_NO_RUN := "no_active_domain"
const ERR_UNKNOWN_FIXTURE := "unknown_fixture"
const ERR_WRONG_KIND := "wrong_kind_for_this_verb"
const ERR_NOTHING_TO_UNDO := "nothing_to_undo"
const ERR_ALREADY_CLAIMED := "already_claimed"
const ERR_ALREADY_SOLVED := "already_solved"
const ERR_NO_HINTS_LEFT := "no_hints_left"
const ERR_NO_NEXT_STEP := "no_next_step"
const ERR_NOT_COMPLETE := "not_complete"
## A board the snapshot guard will not hold. An AUTHORING or CALLER error, and it
## reads as one because the reason says so.
const ERR_SNAPSHOT_TOO_LARGE := "snapshot_too_large"
## A board nested deeper than a grid of rows. Refused rather than stringified,
## because a stringified cell is a silently corrupted board.
const ERR_SNAPSHOT_TOO_DEEP := "snapshot_too_deep"


## Push `state` — the board as it stands BEFORE a move — onto this fixture's undo
## stack. The caller owns the move; this only remembers what the move replaced.
##
## Explicit by construction: nothing calls this for you, so a puzzle that has never
## been wired to it behaves exactly as `DomainFixtures.attempt` already does,
## reset included.
##
## `state` is normalised to PRIMITIVES on the way in, so a `Vector2i` cell or a
## `PackedInt32Array` grid becomes `[x, y]` and a flat array of numbers before it can
## reach a save. That is what makes an undo of a GRID restore the whole grid: the
## snapshot holds every cell, not a reference to one.
static func record(
	actor: Actor, room_id: StringName, fixture_id: StringName, state: Dictionary
) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var about := _about(fixture, room_id)
	if _record_of_fixture(actor, room_id, fixture_id).get("claimed", false):
		return _answer(false, ERR_ALREADY_CLAIMED, about)
	var board := _snapshot_of(state)
	if not bool(board.get("ok", false)):
		return _answer(false, String(board.get("reason", ERR_SNAPSHOT_TOO_LARGE)), about)
	var tools := _ensure_tools(actor)
	var key := String(found["key"])
	var stack: Array = _stacks_of(tools.get("stacks", {})).get(key, [])
	stack.append(board.get("values", {}))
	# FIXED bound, and the loop DRAINS the very container its condition tests
	# (`tests/arch_rules/test_no_unbounded_wait.gd` rule 3). It cannot grow: the only
	# append is the one above it, and this runs on every push, so the stack is never
	# longer than MAX_UNDO_DEPTH after a `record` returns.
	while stack.size() > MAX_UNDO_DEPTH:
		stack.pop_front()
	var stacks := _stacks_of(tools.get("stacks", {}))
	stacks[key] = stack
	tools["stacks"] = stacks
	_store(actor, tools)
	return _answer(
		true,
		OK_RECORDED,
		_merged(
			about,
			{
				"depth": stack.size(),
				"depth_limit": MAX_UNDO_DEPTH,
				"snapshot_values": _snapshot_size(board)
			}
		)
	)


## Pop this fixture's undo stack and answer the board to restore.
##
## EXPLICIT: it pops because it was asked and for no other reason. `attempt`'s wrong
## path resets progress to the first node and still will; undo is the opt-in that
## lets a player keep the place they earned.
##
## The restored board travels in the answer as `state`, and the puzzle owner applies
## it with its own verb. This file does NOT write a board it does not own:
## `DomainFixtures` publishes `state_of` as a read and no public verb writes a raw
## field, so a formation's `progress` is the formation module's to write and a grid's
## cells are the grid module's. A snapshot this file wrote back itself would be a
## SECOND answer to "where is this puzzle", which is worse than a seam with a named
## owner.
static func undo(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var about := _about(fixture, room_id)
	# Claimed before empty on purpose: "you already finished this" is the more
	# fundamental fact, and a puzzle that is both finished and empty would otherwise
	# answer the softer of the two.
	if _record_of_fixture(actor, room_id, fixture_id).get("claimed", false):
		return _answer(false, ERR_ALREADY_CLAIMED, about)
	var tools := _ensure_tools(actor)
	var key := String(found["key"])
	var stacks := _stacks_of(tools.get("stacks", {}))
	var stack: Array = stacks.get(key, [])
	if stack.is_empty():
		return _answer(false, ERR_NOTHING_TO_UNDO, _merged(about, {"depth": 0}))
	var restored: Dictionary = stack.pop_back()
	stacks[key] = stack
	tools["stacks"] = stacks
	_store(actor, tools)
	return _answer(
		true,
		OK_UNDONE,
		_merged(about, {"state": restored, "depth": stack.size(), "depth_limit": MAX_UNDO_DEPTH})
	)


## ONE next correct step, for the price of the fixture's hint budget.
##
## Refuses BY NAME on: no actor, no active domain, an unknown fixture, a fixture
## that is not a puzzle, one already claimed, one already solved, one whose budget is
## spent, and one with no next step to give. The order is the order a player meets
## them in, and each is a different message for a different mistake.
##
## Exactly one step, never the solution: [method _budget_of] clamps the budget to
## `total - 1`, so the last step of any puzzle is unreachable through a hint however
## the fixture authors it. A grid hint is a DIRECTION and never a path.
static func hint(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var about := _about(fixture, room_id)
	var row := _record_of_fixture(actor, room_id, fixture_id)
	if row.get("claimed", false):
		return _answer(false, ERR_ALREADY_CLAIMED, about)
	if _solved(fixture, row):
		return _answer(false, ERR_ALREADY_SOLVED, about)
	var board := _live_board(fixture, row)
	var budget := _budget_of(fixture)
	var tools := _ensure_tools(actor)
	var key := String(found["key"])
	var counts := _counts_of(tools.get("hints", {}))
	var taken := int(counts.get(key, 0))
	var step := _step_of(fixture, board)
	if step.is_empty():
		return _answer(false, ERR_NO_NEXT_STEP, _merged(about, _hint_fields(taken, budget)))
	if taken >= budget:
		return _answer(false, ERR_NO_HINTS_LEFT, _merged(about, _hint_fields(taken, budget)))
	counts[key] = taken + 1
	tools["hints"] = counts
	var revealed := _revealed_of(tools.get("revealed", {}))
	revealed[key] = step
	tools["revealed"] = revealed
	_store(actor, tools)
	return _answer(
		true,
		OK_HINTED,
		_merged(
			about,
			_merged(
				_hint_fields(taken + 1, budget),
				{
					"adapter": _adapter_of(fixture),
					"step": step,
					# The currency, NAMED: a reader renders "this cost you a hint"
					# against "this cost you insight" rather than inferring it.
					"pays": PAY_HINT,
					"steps_done": _done_of(fixture, board),
					"steps_total": _total_of(fixture, board),
				}
			)
		)
	)


## Grade a completed puzzle. A READ: it reads the fixture's own `wrong` counter, this
## file's `hints` counter and the board, and writes NOTHING. A score that spent
## something would make the grade a price rather than a measurement.
##
## `periods` is the caller's clock, taken as a PARAMETER because a module may not own
## one (ADR 0089, DEF-0111). It is published, not graded on — see the class docblock.
## Pass `-1.0` (the default) to say "not timed"; `timed` says which happened.
static func score(
	actor: Actor, room_id: StringName, fixture_id: StringName, periods: float = -1.0
) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var about := _about(fixture, room_id)
	var row := _record_of_fixture(actor, room_id, fixture_id)
	var board := _live_board(fixture, row)
	if not _solved(fixture, row):
		return _answer(false, ERR_NOT_COMPLETE, _merged(about, _board_fields(fixture, board)))
	var tools := _ensure_tools(actor)
	var wrong := maxi(0, int(row.get("wrong", 0)))
	var hints := maxi(0, int(_counts_of(tools.get("hints", {})).get(String(found["key"]), 0)))
	return _answer(
		true,
		OK_SCORED,
		_merged(
			about,
			_merged(
				_grade_fields(wrong, hints, periods),
				_merged(
					_board_fields(fixture, board),
					{"claimed": bool(row.get("claimed", false)), "adapter": _adapter_of(fixture)}
				)
			)
		)
	)


## Everything a screen or the headless driver needs for ONE puzzle, as primitives,
## without naming a domain type: the board's place, what a hint would cost, what the
## last paid-for hint revealed, whether an undo is available, and the score breakdown.
##
## `{}` when no run is in flight, and a NAMED refusal otherwise — the same three-state
## vocabulary every other domain read uses (ADR 0083).
##
## `grade` is `""` on an unsolved puzzle, because ADR 0083's `{}` means "does not
## exist" and a grade nobody has earned is exactly that. `hint` is `{}` when nothing
## has been revealed, and carries the already-PAID-FOR step afterwards: a player who
## bought a hint keeps it, and re-reading it costs nothing more because it is the
## same single step.
static func read_model(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var found := _resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var row := _record_of_fixture(actor, room_id, fixture_id)
	var board := _live_board(fixture, row)
	var tools := _ensure_tools(actor)
	var key := String(found["key"])
	var hints := maxi(0, int(_counts_of(tools.get("hints", {})).get(key, 0)))
	var budget := _budget_of(fixture)
	var depth := int(_stacks_of(tools.get("stacks", {})).get(key, []).size())
	var solved := _solved(fixture, row)
	var wrong := maxi(0, int(row.get("wrong", 0)))
	var fields := _board_fields(fixture, board)
	fields["adapter"] = _adapter_of(fixture)
	fields["solved"] = solved
	fields["claimed"] = bool(row.get("claimed", false))
	fields["complete"] = bool(row.get("complete", false))
	fields["hints"] = hints
	fields["hint_budget"] = budget
	fields["hints_left"] = maxi(0, budget - hints)
	fields["hint"] = _revealed_of(tools.get("revealed", {})).get(key, {})
	fields["hint_price"] = PAY_HINT
	fields["undo_depth"] = depth
	fields["undo_limit"] = MAX_UNDO_DEPTH
	fields["undo_available"] = depth > 0
	# Folded at the top AND nested: a row reads `grade` without descending, and a
	# breakdown panel reads the whole `score` block without re-deriving the axes.
	fields["grade"] = _grade_of(wrong, hints) if solved else ""
	fields["score"] = _grade_fields(wrong, hints, -1.0)
	return _answer(true, "", _merged(_about(fixture, room_id), fields))


# ── resolution ───────────────────────────────────────────────────────────────


## `{fixture, key}` on success, or an ANSWER dictionary on refusal — never a bare
## `{}`, the same contract `DomainFixtures._resolve` publishes. Every verb here is a
## PUZZLE verb, so a trap or a hoard is refused by name rather than half-answered.
static func _resolve(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	if actor == null:
		return _answer(false, ERR_NO_ACTOR, {})
	var room := DomainApi.room(actor, room_id)
	if room.is_empty():
		return _answer(false, ERR_NO_RUN, {"room_id": String(room_id)})
	# Bounded `for` over the room's own authored array.
	for entry in room.get("fixtures", []):
		var fixture: Dictionary = entry
		if String(fixture.get("fixture_id", "")) != String(fixture_id):
			continue
		if String(fixture.get("kind", "")) != String(DomainFixtures.KIND_PUZZLE):
			return _answer(
				false,
				ERR_WRONG_KIND,
				_merged(_about(fixture, room_id), {"asked": String(fixture_id)})
			)
		return {"ok": true, "reason": "", "fixture": fixture, "key": _key(room_id, fixture_id)}
	return _answer(
		false, ERR_UNKNOWN_FIXTURE, {"room_id": String(room_id), "fixture_id": String(fixture_id)}
	)


static func _key(room_id: StringName, fixture_id: StringName) -> String:
	return "%s/%s" % [String(room_id), String(fixture_id)]


## The fixture's own ledger row, through `DomainFixtures`' public read. Normalised by
## that module, so `wrong` / `progress` / `claimed` arrive as ints and bools whether
## they came from a live ledger or out of a save.
static func _record_of_fixture(
	actor: Actor, room_id: StringName, fixture_id: StringName
) -> Dictionary:
	return DomainFixtures.state_of(actor, room_id, fixture_id)


# ── the ADAPTER: the four questions every kind answers ───────────────────────


## Which adapter answers for `fixture`, or `""` when it authors no board at all — an
## AUTHORING error, which every caller turns into a refusal by name.
static func _adapter_of(fixture: Dictionary) -> String:
	if not (fixture.get("sequence", []) as Array).is_empty():
		return ADAPTER_FORMATION
	if not (fixture.get("grid", fixture.get("cells", [])) as Array).is_empty():
		return ADAPTER_SPATIAL
	return ""


## How many steps this puzzle has. A formation's is its authored `sequence`; a grid's
## is whatever it authors as `steps`, and `0` when it authors none — `0` is honest
## ("this kind has no authored step count") rather than an invented Manhattan
## distance, which would be a claim about the puzzle nobody authored.
static func _total_of(fixture: Dictionary, board: Dictionary) -> int:
	match _adapter_of(fixture):
		ADAPTER_FORMATION:
			return maxi(0, (fixture.get("sequence", []) as Array).size())
		ADAPTER_SPATIAL:
			return maxi(0, int(fixture.get("steps", board.get("steps_total", 0))))
	return 0


## How many are done. A formation reads the OWNER's live `progress` — never this
## file's snapshot, which is one move behind by construction, because it holds the
## state BEFORE the last move. A grid reads the board's own authored `steps_done`.
static func _done_of(fixture: Dictionary, board: Dictionary) -> int:
	match _adapter_of(fixture):
		ADAPTER_FORMATION:
			return clampi(int(board.get("progress", 0)), 0, _total_of(fixture, board))
		ADAPTER_SPATIAL:
			return maxi(0, int(board.get("steps_done", 0)))
	return 0


## Whether the board is finished, for EVERY kind — which is why `score` can grade a
## formation and a grid through one gate.
##
## A formation is finished at `progress >= total`, which is the same condition
## `DomainFixtures.attempt` completes on, so a completed formation is never refused
## as unfinished. It is deliberately NOT `claimed`: a puzzle whose board is done and
## whose claim has not been taken is a real state (a grid that reaches its goal
## before it is collected), and grading it is right.
static func _solved(fixture: Dictionary, row: Dictionary) -> bool:
	match _adapter_of(fixture):
		ADAPTER_FORMATION:
			var total := maxi(0, (fixture.get("sequence", []) as Array).size())
			return total > 0 and int(row.get("progress", 0)) >= total
		ADAPTER_SPATIAL:
			var at := _cell_of(row.get("at", fixture.get("at", [])))
			var goal := _cell_of(fixture.get("goal", []))
			return at.size() == 2 and goal.size() == 2 and at == goal
	return false


## ONE next correct step, or `{}` when there is none to give. The published shape is
## the same for both kinds — `{kind, at, value}` — so a panel renders a node id and a
## compass bearing through one row.
##
## NEVER the whole solution. A formation gives `sequence[progress]`, one node. A grid
## gives the ONE axis to move, chosen by the larger remaining delta so the hint is
## never a coin flip between two equally useful directions, and never a path.
static func _step_of(fixture: Dictionary, board: Dictionary) -> Dictionary:
	match _adapter_of(fixture):
		ADAPTER_FORMATION:
			var sequence: Array = fixture.get("sequence", [])
			var at := _done_of(fixture, board)
			if at < 0 or at >= sequence.size():
				return {}
			return {"kind": "node", "at": at, "value": String(sequence[at])}
		ADAPTER_SPATIAL:
			var here := _cell_of(board.get("at", []))
			var bearing := _bearing_of(here, _cell_of(fixture.get("goal", [])))
			if bearing == "":
				return {}
			return {"kind": "direction", "at": here, "value": bearing}
	return {}


## One compass bearing from `from` toward `to`, or `""` when either cell is not a
## cell. `already_there` rather than `""` when the two agree, so a caller can tell a
## puzzle that is solved from one that authored no goal.
static func _bearing_of(from: Array, to: Array) -> String:
	if from.size() < 2 or to.size() < 2:
		return ""
	var dx := int(to[0]) - int(from[0])
	var dy := int(to[1]) - int(from[1])
	if dx == 0 and dy == 0:
		return DIRECTION_HERE
	if absi(dx) >= absi(dy):
		return DIRECTION_EAST if dx > 0 else DIRECTION_WEST
	return DIRECTION_SOUTH if dy > 0 else DIRECTION_NORTH


## The LIVE board, as this adapter reads it. A formation's is the owner's `progress`;
## a grid's is the fixture's authored start, upgraded by the ledger row the moment a
## grid module writes its cell there.
static func _live_board(fixture: Dictionary, row: Dictionary) -> Dictionary:
	match _adapter_of(fixture):
		ADAPTER_FORMATION:
			return {"progress": int(row.get("progress", 0))}
		ADAPTER_SPATIAL:
			return {
				"at": _cell_of(row.get("at", fixture.get("start", []))),
				"steps_done": int(row.get("steps_done", fixture.get("steps_done", 0))),
				"steps_total": int(fixture.get("steps", 0)),
			}
	return {}


## How many hints this fixture owes: its authored `hint_budget`, default
## [constant HINT_BUDGET], ceilinged at [constant HINT_BUDGET_MAX] AND at
## `total - 1`.
##
## That second ceiling is the load-bearing one. It is what makes "a hint reveals ONE
## step, never the whole solution" STRUCTURAL rather than a matter of the default
## being small: a two-step puzzle can owe at most one hint and a one-step puzzle none,
## so no authored budget can ever hand a player the last move.
static func _budget_of(fixture: Dictionary) -> int:
	var authored := clampi(int(fixture.get("hint_budget", HINT_BUDGET)), 0, HINT_BUDGET_MAX)
	var total := maxi(0, (fixture.get("sequence", []) as Array).size())
	if total <= 0:
		return authored
	return mini(authored, total - 1)


## `[x, y]` from an authored cell — an `[x, y]` array, a `Vector2i` or a `Vector2` —
## or `[]` when there is no cell. Never a `Vector2i` in an answer: it would not
## cross into a panel or a save.
static func _cell_of(value: Variant) -> Array:
	if value is Vector2i:
		return [int((value as Vector2i).x), int((value as Vector2i).y)]
	if value is Vector2:
		return [int((value as Vector2).x), int((value as Vector2).y)]
	if value is Array and (value as Array).size() >= 2:
		return [_int_of(value, 0), _int_of(value, 1)]
	return []


static func _int_of(value: Variant, index: int) -> int:
	if not (value is Array) or index >= (value as Array).size():
		return 0
	return int((value as Array)[index])


# ── snapshots: primitives in, primitives out ─────────────────────────────────


## `state` normalised to primitives, or a refusal. Every scalar goes through
## `int()` / `float()` / `String()` because a save has no bools and no int/float
## distinction, and every `Vector2` / nested row becomes flat numbers — which is what
## lets a whole GRID be restored rather than a reference to one.
static func _snapshot_of(state: Dictionary) -> Dictionary:
	var out := {}
	var spent := 0
	for field in state:
		var flat := _flat_of(state[field], MAX_SNAPSHOT_VALUES - spent)
		if not bool(flat.get("ok", false)):
			return {
				"ok": false,
				"reason": String(flat.get("reason", ERR_SNAPSHOT_TOO_LARGE)),
				"values": {}
			}
		var values: Array = flat["values"]
		spent += values.size()
		# A one-element list collapses to the scalar it always meant, so a `progress`
		# reads as a number in the answer rather than as a list holding one.
		out[String(field)] = values[0] if values.size() == 1 else values
	return {"ok": true, "reason": "", "values": out}


## `raw` as a flat list of primitives, bounded by `budget` values. At most TWO levels
## — a grid of rows — and deeper is refused rather than stringified.
##
## ## THE GUARD THAT MAKES THIS TERMINATE
##
## Every path returns the moment `values` passes `budget`, so the walk stops at
## `budget + 1` elements however large the caller's array is. The bound is the FIXED
## [constant MAX_SNAPSHOT_VALUES] minus what earlier fields already spent — never a
## count read from the array being walked.
static func _flat_of(raw: Variant, budget: int) -> Dictionary:
	var values: Array = []
	if raw is Vector2i or raw is Vector2:
		return _fit(values, [int((raw as Vector2).x), int((raw as Vector2).y)], budget)
	if not _is_list_of(raw):
		return _fit(values, [_scalar_of(raw)], budget)
	for entry in raw:
		if entry is Vector2i or entry is Vector2:
			_fit(values, [int((entry as Vector2).x), int((entry as Vector2).y)], budget)
			if values.size() > budget:
				return _over(ERR_SNAPSHOT_TOO_LARGE)
		elif _is_list_of(entry):
			for cell in entry:
				if _is_list_of(cell):
					return _over(ERR_SNAPSHOT_TOO_DEEP)
				values.append(_scalar_of(cell))
				if values.size() > budget:
					return _over(ERR_SNAPSHOT_TOO_LARGE)
		else:
			values.append(_scalar_of(entry))
			if values.size() > budget:
				return _over(ERR_SNAPSHOT_TOO_LARGE)
	return {"ok": true, "reason": "", "values": values}


static func _is_list_of(value: Variant) -> bool:
	return (
		value is Array
		or value is PackedInt32Array
		or value is PackedInt64Array
		or value is PackedFloat32Array
		or value is PackedFloat64Array
	)


static func _fit(values: Array, extra: Array, budget: int) -> Dictionary:
	values.append_array(extra)
	if values.size() > budget:
		return _over(ERR_SNAPSHOT_TOO_LARGE)
	return {"ok": true, "reason": "", "values": values}


static func _over(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "values": []}


## One primitive. A bool becomes an int because a save has no bools; anything this
## file does not recognise becomes a `String`, which at least survives a round trip.
static func _scalar_of(value: Variant) -> Variant:
	if value is bool:
		return int(value)
	if value is int or value is float:
		return value
	return String(value)


static func _snapshot_size(board: Dictionary) -> int:
	var values: Variant = board.get("values", {})
	return (values as Dictionary).size() if values is Dictionary else 0


# ── this file's own state ────────────────────────────────────────────────────


## The stored row, normalised, or `{}` when it belongs to another run.
##
## ## WHY THE RUN ID IS CHECKED HERE
##
## `DomainApi.enter` clears `DomainFixtures.STATE_KEY` and nothing else, so an undo
## stack would otherwise survive into the next run and let a player rewind a puzzle in
## a domain they have not walked yet. The second clear that would fix it belongs in
## `api.gd`, which another session holds, so the row carries the run it was written
## in and a mismatch reads as absent — the same effect, in a file this session owns.
static func _tools(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var raw: Variant = actor.get_module_data(DomainApi.MODULE_KEY).get(STATE_KEY, {})
	if not raw is Dictionary:
		return {}
	var tools: Dictionary = raw
	if String(tools.get("run", "")) != _run_id(actor):
		return {}
	return tools


static func _ensure_tools(actor: Actor) -> Dictionary:
	var tools := _tools(actor)
	if tools.is_empty():
		tools = {
			"version": STATE_VERSION,
			"run": _run_id(actor),
			"stacks": {},
			"hints": {},
			"revealed": {}
		}
	return tools


static func _store(actor: Actor, tools: Dictionary) -> void:
	if actor == null:
		return
	var state := actor.get_module_data(DomainApi.MODULE_KEY)
	if state.is_empty():
		return
	state[STATE_KEY] = _clean_of(tools)
	actor.set_module_data(DomainApi.MODULE_KEY, state)


## The identity of the run in flight: its authored id and the seed the generator
## dealt. `""` outside a run, which is what makes [method _tools] return `{}`.
static func _run_id(actor: Actor) -> String:
	var shape := DomainApi.map_summary(actor)
	if shape.is_empty():
		return ""
	return "%s#%d" % [String(shape.get("domain_id", "")), int(shape.get("seed", 0))]


## The stacks, keyed by fixture and CAPPED ON READ. A hand-edited or older save can
## carry a longer stack, and the cap is what keeps [method undo] from popping a
## snapshot the trim loop never admitted. Bounded by [constant MAX_UNDO_DEPTH] and
## broken out of the walk the moment it is reached, so a save with a thousand entries
## costs a thousand skipped lines and not a thousand copies.
static func _stacks_of(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key in raw:
		var stack: Array = []
		for board in (raw as Dictionary)[key]:
			if board is Dictionary:
				stack.append(board)
			if stack.size() >= MAX_UNDO_DEPTH:
				break
		if not stack.is_empty():
			out[String(key)] = stack
	return out


static func _counts_of(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key in raw:
		out[String(key)] = maxi(0, int((raw as Dictionary)[key]))
	return out


static func _revealed_of(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key in raw:
		var step: Variant = (raw as Dictionary)[key]
		if step is Dictionary:
			out[String(key)] = step
	return out


## What goes into the save: the same three maps, normalised, with the version stamped
## and every stack re-capped. A row this module did not write degrades to `{}` rather
## than crashing a load.
static func _clean_of(tools: Dictionary) -> Dictionary:
	return {
		"version": STATE_VERSION,
		"run": String(tools.get("run", "")),
		"stacks": _stacks_of(tools.get("stacks", {})),
		"hints": _counts_of(tools.get("hints", {})),
		"revealed": _revealed_of(tools.get("revealed", {})),
	}


# ── published fields ─────────────────────────────────────────────────────────


## The board's place, as primitives, for every kind.
static func _board_fields(fixture: Dictionary, board: Dictionary) -> Dictionary:
	return {
		"steps_total": _total_of(fixture, board),
		"steps_done": _done_of(fixture, board),
		"steps_left": maxi(0, _total_of(fixture, board) - _done_of(fixture, board)),
	}


## What a hint costs and what it has cost, with the currency NAMED.
static func _hint_fields(taken: int, budget: int) -> Dictionary:
	return {
		"hints": maxi(0, taken),
		"hint_budget": maxi(0, budget),
		"hints_left": maxi(0, budget - taken),
		"hint_price": PAY_HINT,
	}


## The grade and the primitives that produced it, so a panel renders the breakdown
## rather than the verdict alone.
static func _grade_fields(wrong: int, hints: int, periods: float) -> Dictionary:
	return {
		"grade": _grade_of(wrong, hints),
		"wrong": maxi(0, wrong),
		"hints": maxi(0, hints),
		"periods": maxf(0.0, periods),
		# `timed` rather than a magic number: `-1.0` and a solve that genuinely took
		# no time must not read the same.
		"timed": periods >= 0.0,
	}


## ## The grade, and the two axes it reads
##
## `wrong` and `hints`, and nothing else. Zero of each is `flawless`; zero wrong with
## a hint taken is `clean`; up to [constant BRACED_WRONG] wrong is `braced`; beyond
## that `forced`. `periods` is deliberately absent — see the class docblock for why a
## graded axis with no shipped caller is worse than an unpublished one.
static func _grade_of(wrong: int, hints: int) -> String:
	if wrong <= 0 and hints <= 0:
		return GRADE_FLAWLESS
	if wrong <= 0:
		return GRADE_CLEAN
	if wrong <= BRACED_WRONG:
		return GRADE_BRACED
	return GRADE_FORCED


static func _about(fixture: Dictionary, room_id: StringName) -> Dictionary:
	return {
		"room_id": String(room_id),
		"fixture_id": String(fixture.get("fixture_id", "")),
		"kind": String(fixture.get("kind", "")),
		"reward_item_id": String(fixture.get("reward_item_id", "")),
	}


static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
