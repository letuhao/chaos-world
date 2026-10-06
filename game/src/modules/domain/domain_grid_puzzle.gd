class_name DomainGridPuzzle
extends RefCounted

## The SPATIAL variant of a `puzzle` fixture, played on an AUTHORED GRID (ADR 0269).
##
## `DomainFixtures.attempt` strikes nodes in an authored ORDER: where a node sits on the
## board is decoration and the sequence is the whole puzzle. This file is the other axis —
## POSITION is the whole puzzle and there is no order to remember. The player issues MOVES
## (`up`/`down`/`left`/`right`) and the grid resolves move, push, block.
##
## ## IT IS A PUZZLE VARIANT, NOT A FOURTH FIXTURE KIND
##
## `kind` stays `puzzle`, so a spatial board is IN the one `DomainFixtures` ledger, pays
## through the one `_grant` delivery path, records the one LORE row, and clears with the
## run. `DomainFixtures.KINDS` is closed at three (ADR 0073) and `test_domain_content.gd`
## closes the set too; a fourth KIND would fork the ledger to buy a spelling. The
## discriminant is an authored `variant` over a closed two-value set — the pattern ADR 0218
## used to stop a hand-applied tag being read as a fact about a fixture.
##
## ## THE GRID IS THE FIXTURE'S OWN FOOTPRINT
##
## No new room-tile coordinate is authored. The grid's size is the fixture's existing
## `bounds.size` and its placement in the room is that `bounds`' own position, both already
## published as `[x, y, w, h]` by `DomainFixtures.telegraph` — so there is exactly ONE
## description of where the board sits (ADR 0170: "a stored coordinate is a second
## description of a place that can disagree with the first"), and `DomainPaths.layout()`
## stays the one rule that lays a room out. Every NEW key here is GRID-LOCAL and
## primitive — `[x, y]` arrays, never a `Vector2i` — because `RoomDef.to_dict` duplicates
## `fixtures` into the run state a save carries.
##
## ## AND THE PAIRING
##
## A grid puzzle's advantage is that position matters; its counterpart is that the board is
## SOLVABLE and a move it cannot make is refused rather than punished. The content suite
## asserts every authored board is well-formed, this file refuses `push_into_wall` and
## `push_into_piece` BY NAME rather than nudging the piece, and the reward is gated on the
## solve — so a board a player cannot finish costs a turn and never health, which is the
## rule ADR 0075's formation half already holds.
##
## ## NO `while` IN THIS FILE, AND THAT IS THE LOOP GUARD
##
## A grid move is ONE tile. There is no sliding, no cascade and no search to iterate, so
## every walk here is a bounded `for`: over an authored array, over the board's own tile
## count snapshotted out of the authored footprint BEFORE the fill, or over a piece list
## that is never grown. Nothing waits on a condition it cannot prove, and a caller that
## cannot reach the goal is REFUSED by name, never spun.

# ── the variant, and the authored key that carries it ──────────────────────────

## The authored default: `nodes` plus the `sequence` they must be struck in. What every
## puzzle fixture before this file means, and what an EMPTY `variant` still means, so no
## shipped formation had to be edited to carry a field that says what it already was.
const VARIANT_SEQUENCE := &"sequence"

## A grid of `grid_walls`/`grid_start`/`grid_pieces`/`grid_targets` played with moves.
## THE discriminant is `variant`; the `grid_` keys are the payload and never the
## discriminant, so a mistyped `variant` is a refusal rather than a half-working board.
const VARIANT_SPATIAL := &"spatial"

## CLOSED, for the reason `DomainFixtures.KINDS` is closed: an unrecognised variant is a
## loud refusal rather than a board the game silently cannot play.
const VARIANTS: Array[StringName] = [VARIANT_SEQUENCE, VARIANT_SPATIAL]

# ── the four moves ────────────────────────────────────────────────────────────

const UP := &"up"
const DOWN := &"down"
const LEFT := &"left"
const RIGHT := &"right"

## CLOSED, for the reason [constant VARIANTS] is closed. An unknown direction is a caller
## error refused by name, never a move read as a no-op that still burns the turn.
const DIRECTIONS: Array[StringName] = [UP, DOWN, LEFT, RIGHT]

# ── the published cell vocabulary ─────────────────────────────────────────────

## A cell a screen draws. CLOSED so a renderer switches over a set rather than over
## whatever the simulation left in an array: an unlisted cell renders as nothing, and a
## player cannot tell open floor from a missing piece.
const CELL_OPEN := "open"
const CELL_WALL := "wall"
const CELL_TARGET := "target"
const CELL_PIECE := "piece"
const CELL_CURSOR := "cursor"

## A piece standing on its target: the ONE cell that is two facts at once, and the reason
## the drawn vocabulary cannot be derived from "is there a wall, is there a piece".
const CELL_PIECE_ON_TARGET := "piece_on_target"

# ── reasons. Every refusal has a stable id a reader can show. ─────────────────

const OK_MOVED := "moved"
const OK_PUSHED := "pushed"
const OK_SOLVED := "solved"

## `no_active_domain` and `unknown_fixture` are NOT restated here: they arrive from
## `DomainFixtures.resolve`, because the run is this module's ledger and there must not be
## a second way of asking whether there is one.
const ERR_BLOCKED_BY_WALL := "blocked_by_wall"

## The board has no token HERE to move: the start tile is unauthored or off the grid, or a
## ledger cursor is. A desynced cursor is REFUSED rather than re-seeded from the authored
## start, because re-seeding would let an edited save teleport a player.
const ERR_NO_PIECE_HERE := "no_piece_here"

const ERR_PUSH_INTO_WALL := "push_into_wall"

## A piece may not be pushed into ANOTHER piece. Named apart from
## [constant ERR_PUSH_INTO_WALL] because the remedy differs: a wall is a property of the
## board, another piece is a property of the turn.
const ERR_PUSH_INTO_PIECE := "push_into_piece"

const ERR_OFF_GRID := "off_grid"

## Already solved and already paid. Distinct from `already_claimed` because this answer
## still carries the board: a caller can DRAW the finished grid while being told the move
## means nothing.
const ERR_ALREADY_SOLVED := "already_solved"

const ERR_UNKNOWN_DIRECTION := "unknown_direction"
const ERR_UNKNOWN_VARIANT := "unknown_puzzle_variant"

## The fixture authors no board a move can be resolved on: no footprint, no target, or no
## pushable piece. An AUTHORING error, refused loudly rather than answered as an empty grid
## a player can walk around forever.
const ERR_NO_GRID := "authors_no_grid"

## The authored footprint names more tiles than this module will simulate. A cap on an
## INPUT is normally the wrong kind per ADR 0200 — but a grid is authored CONTENT, not a
## rate that must scale with the ladder, and a board nobody can finish is not a bigger
## puzzle. Named rather than clamped so the author sees the board they wrote.
const ERR_GRID_TOO_LARGE := "grid_too_large"

## The simulation ceiling, in TILES. Far above any authored board (`ash_arena_spatial` is
## 30) so it can never change an answer, and it names what it refused.
const MAX_GRID_TILES := 1024


## The authored variant of `fixture`, defaulting to the sequence shape.
##
## A non-empty value outside [constant VARIANTS] is returned AS AUTHORED rather than
## coerced: the caller refuses it by name, because guessing would turn a typo into a board
## that half works.
static func variant_of(fixture: Dictionary) -> StringName:
	var authored := StringName(fixture.get("variant", ""))
	return VARIANT_SEQUENCE if authored == &"" else authored


## One `[x, y]` cell as ints, or `[]` for anything that is not a two-element array.
##
## PUBLIC because `DomainFixtures._record_of` normalises the grid's own ledger fields
## through it: the CELL shape has one owner, and a second cast inside the ledger would be
## a copy of this one.
static func cell_of(value: Variant) -> Array:
	if value is Array and (value as Array).size() >= 2:
		return [int((value as Array)[0]), int((value as Array)[1])]
	return []


## A list of cells, each normalised through [method cell_of] and the malformed ones DROPPED.
## Read straight back out of a save: JSON has no int/float distinction, so a round-tripped
## `grid_pieces` arrives as nested float arrays.
static func cells_of(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for entry in value as Array:
		var cell := cell_of(entry)
		if not cell.is_empty():
			out.append(cell)
	return out


## Move `actor`'s token ONE tile `direction` and resolve the whole grid: move, push, or a
## named refusal. Never a partial move — the board is written whole or not at all.
##
## ## THE PAYOUT IS THE LAST THING THAT HAPPENS
##
## A solve pays and only writes the ledger row when the delivery succeeded, exactly as
## `attempt` does. So a full bag on the final push costs the push rather than eating a
## solved board the player cannot be paid for — the one silent loss this module shares with
## every other fixture.
static func step(
	actor: Actor, room_id: StringName, fixture_id: StringName, direction: StringName
) -> Dictionary:
	var found := DomainFixtures.resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var about := DomainFixtures.about(fixture, room_id)
	var gate := _verb_gate(fixture, about)
	if not gate.is_empty():
		return gate
	if not DIRECTIONS.has(direction):
		return _answer(false, ERR_UNKNOWN_DIRECTION, _merged(about, {"direction": String(direction)}))
	var size := _grid_size(fixture)
	var missing := _grid_problem(fixture, size)
	if not missing.is_empty():
		# Named, not swallowed: a board that cannot be played is an AUTHORING error, and
		# the detail is what lets the author fix it without reading this file.
		push_error(
			"DomainGridPuzzle: fixture '%s' authors an unplayable board — %s"
			% [String(fixture.get("fixture_id", "")), String(missing.get("detail", ""))]
		)
		return _answer(false, String(missing["reason"]), _merged(about, missing))
	var row := DomainFixtures.state_of(actor, room_id, fixture_id)
	var board := _board_for(fixture, size, row)
	if not bool(board["placed"]):
		return _answer(
			false,
			ERR_NO_PIECE_HERE,
			_merged(about, _published(board, {"cursor": (board["cursor"] as Array).duplicate()}))
		)
	if int(row.get("grid_solved", false)):
		return _answer(false, ERR_ALREADY_SOLVED, _merged(about, _published(board, {})))
	var moved := _resolve_move(board, direction)
	if not bool(moved["ok"]):
		return _answer(false, String(moved["reason"]), _merged(about, _moved_fields(board, moved)))
	var solved := _on_every_target(board["targets"] as Array, board["pieces"] as Array)
	var fields := _fields_of(board, row, int(moved["pushes_made"]), solved)
	if not solved:
		DomainFixtures.progress(actor, room_id, fixture_id, fields)
		return _moved_answer(String(moved["reason"]), about, board, fields, false)
	var payout := DomainFixtures.payout(actor, room_id, fixture_id)
	if not bool(payout.get("ok", false)):
		return payout
	DomainFixtures.progress(actor, room_id, fixture_id, fields)
	return _moved_answer(OK_SOLVED, about, board, fields, true, payout)


## The board as primitives WITHOUT touching it — the free, non-mutating read a screen
## draws before the first move. Reads the ledger and writes nothing, so looking at a board
## is free rather than a mistake, which is the reason `inspect` is a verb at all.
static func view(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	var found := DomainFixtures.resolve(actor, room_id, fixture_id)
	if not bool(found.get("ok", false)):
		return found
	var fixture: Dictionary = found["fixture"]
	var about := DomainFixtures.about(fixture, room_id)
	var gate := _verb_gate(fixture, about)
	if not gate.is_empty():
		return gate
	var size := _grid_size(fixture)
	var missing := _grid_problem(fixture, size)
	if not missing.is_empty():
		return _answer(false, String(missing["reason"]), _merged(about, missing))
	var board := _board_for(fixture, size, DomainFixtures.state_of(actor, room_id, fixture_id))
	var placed := _published(board, {})
	if not bool(board["placed"]):
		return _answer(false, ERR_NO_PIECE_HERE, _merged(about, placed))
	var solved := _on_every_target(board["targets"] as Array, board["pieces"] as Array)
	placed["solved"] = solved
	if solved:
		placed["reason"] = ERR_ALREADY_SOLVED
		placed["ok"] = false
	return _answer(bool(placed.get("ok", true)), String(placed.get("reason", "")), _merged(about, placed))


# ── the two gates ─────────────────────────────────────────────────────────────


## `wrong_kind_for_this_verb` for BOTH wrong shapes, because they are one fact: this
## fixture's shape does not answer this verb. A treasure answered by `step`, a formation
## answered by `step`, and a spatial board answered by `attempt` are the same mistake with
## different nouns, and one named refusal beats a vocabulary that grows a word per pair.
static func _verb_gate(fixture: Dictionary, about: Dictionary) -> Dictionary:
	if StringName(fixture.get("kind", "")) != DomainFixtures.KIND_PUZZLE:
		var wrong := {"kind": String(fixture.get("kind", ""))}
		return _answer(false, DomainFixtures.ERR_WRONG_KIND, _merged(about, wrong))
	var variant := variant_of(fixture)
	if not VARIANTS.has(variant):
		return _answer(false, ERR_UNKNOWN_VARIANT, _merged(about, {"variant": String(variant)}))
	if variant != VARIANT_SPATIAL:
		return _answer(
			false, DomainFixtures.ERR_WRONG_KIND, _merged(about, {"variant": String(variant)})
		)
	return {}


## `{}` when the board is playable, else the named refusal and the numbers behind it.
##
## Every check reads AUTHORED content, so the whole walk is a bounded `for` over four
## authored arrays — there is no loop whose bound is a container the body is filling.
static func _grid_problem(fixture: Dictionary, size: Vector2i) -> Dictionary:
	if size.x <= 0 or size.y <= 0:
		return {"reason": ERR_NO_GRID, "detail": "the authored footprint has no tiles"}
	var tiles := size.x * size.y
	if tiles > MAX_GRID_TILES:
		return {
			"reason": ERR_GRID_TOO_LARGE,
			"tiles": tiles,
			"cap": MAX_GRID_TILES,
			"detail": "the authored footprint is %d tiles against a %d tile ceiling"
			% [tiles, MAX_GRID_TILES],
		}
	if cells_of(fixture.get("grid_targets", [])).is_empty():
		return {"reason": ERR_NO_GRID, "detail": "the board authors no target"}
	if cells_of(fixture.get("grid_pieces", [])).is_empty():
		return {"reason": ERR_NO_GRID, "detail": "the board authors no pushable piece"}
	return {}


## The board's footprint in TILES: the fixture's own `bounds`, already published by
## `telegraph` and laid out by `DomainPaths`. A missing `bounds` is `Rect2i()`, which
## [method _grid_problem] refuses by name rather than simulating.
static func _grid_size(fixture: Dictionary) -> Vector2i:
	var box: Rect2i = fixture.get("bounds", Rect2i())
	return Vector2i(maxi(0, box.size.x), maxi(0, box.size.y))


# ── the board ─────────────────────────────────────────────────────────────────


## The whole board: authored walls and targets, with the LEDGER's token and pieces laid
## over them. Every cell resolves from an index set rather than by scanning the tile list,
## so the tile fill is O(1) per cell against a bound snapshotted before it.
##
## The AUTHORED start and pieces are the default and the ledger overrides them, so a first
## move never has to ask whether there was a previous one. `placed` is false when the
## token or any piece sits off the grid, which is what `no_piece_here` names.
static func _board_for(fixture: Dictionary, size: Vector2i, row: Dictionary) -> Dictionary:
	var cursor := cell_of(row.get("grid_cursor", []))
	if cursor.is_empty():
		cursor = cell_of(fixture.get("grid_start", []))
	var pieces := cells_of(row.get("grid_pieces", []))
	if pieces.is_empty():
		pieces = cells_of(fixture.get("grid_pieces", []))
	var placed := _inside(size, cursor)
	for piece in pieces:
		if not _inside(size, piece):
			placed = false
	return {
		"size": size,
		"walls": cells_of(fixture.get("grid_walls", [])),
		"targets": cells_of(fixture.get("grid_targets", [])),
		"cursor": cursor,
		"pieces": pieces,
		"placed": placed,
	}


## Tiles as `[row-major index] -> true`, so membership is a dictionary hit rather than a
## scan of every authored cell. An off-grid cell is DROPPED here and surfaced by
## [method _board_for]'s `placed` flag instead of crashing an index lookup.
static func _index_set(cells: Array, size: Vector2i) -> Dictionary:
	var out := {}
	for cell in cells:
		if _inside(size, cell):
			out[_flat(cell, size.x)] = true
	return out


## One move, resolved whole. Reads no ledger and writes none: a refused move leaves the
## board exactly as it was, which is what makes every refusal safe to retry.
static func _resolve_move(board: Dictionary, direction: StringName) -> Dictionary:
	var size: Vector2i = board["size"]
	var delta := _delta(direction)
	var here := board["cursor"] as Array
	var next := _shift(here, delta)
	if not _inside(size, next):
		return _refused(ERR_OFF_GRID, here, next, delta, board)
	var index := _index_of(board["pieces"] as Array, next)
	if index < 0:
		board["cursor"] = next
		return {"ok": true, "reason": OK_MOVED, "pushes_made": 0}
	var beyond := _shift(next, delta)
	if not _inside(size, beyond):
		return _refused(ERR_OFF_GRID, here, next, delta, board)
	if _index_of(board["walls"] as Array, beyond) >= 0:
		return _refused(ERR_PUSH_INTO_WALL, here, next, delta, board)
	if _index_of(board["pieces"] as Array, beyond) >= 0:
		return _refused(ERR_PUSH_INTO_PIECE, here, next, delta, board)
	var pieces: Array = (board["pieces"] as Array).duplicate()
	pieces[index] = beyond
	board["pieces"] = pieces
	board["cursor"] = next
	return {"ok": true, "reason": OK_PUSHED, "pushes_made": 1}


## A refusal carries the two tiles that produced it, because "the push failed" is a
## question a player answers by looking at where they stand and where the piece is.
static func _refused(reason: String, here: Array, into: Array, delta: Vector2i, board: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"moved": false,
		"cursor": here.duplicate(),
		"into": into.duplicate(),
		"delta": [delta.x, delta.y],
		"pushes_made": 0,
	}


## Whether every authored target now holds a piece. A conjunction over a FIXED authored
## list rather than a loop over the board: a board with more pieces than targets is not
## solved by filling every tile.
static func _on_every_target(targets: Array, pieces: Array) -> bool:
	if targets.is_empty():
		return false
	for target in targets:
		if _index_of(pieces, target) < 0:
			return false
	return true


## The four ledger fields, primitives only. `grid_solved` is what `already_solved` and a
## re-solve's double payout are refused on, so it is written WITH the board rather than
## re-derived from the cursor on read.
##
## Piece ORDER is preserved rather than sorted: authored order is already stable and
## canonical, and sorting would make the ledger's order disagree with the order an author
## read in their own `.tres` — a worse lie than stability.
static func _fields_of(board: Dictionary, row: Dictionary, pushed: int, solved: bool) -> Dictionary:
	return {
		"grid_cursor": (board["cursor"] as Array).duplicate(),
		"grid_pieces": (board["pieces"] as Array).duplicate(),
		"grid_pushes": maxi(0, int(row.get("grid_pushes", 0))) + pushed,
		"grid_solved": solved,
	}


# ── answers ───────────────────────────────────────────────────────────────────


## One answer, in the shape every verb in this module answers in: the shared header, the
## board as primitives, and whatever the reward reported when one was paid.
static func _moved_answer(
	reason: String,
	about: Dictionary,
	board: Dictionary,
	fields: Dictionary,
	solved: bool,
	payout: Dictionary = {}
) -> Dictionary:
	var out := _merged(about, _published(board, fields))
	out["ok"] = true
	out["reason"] = reason
	out["solved"] = solved
	if not payout.is_empty():
		out.merge(payout, true)
	return out


## The fields of a REFUSED move, published over the UNCHANGED board: a player who cannot
## push needs the board they still have, not an empty answer. `ok` and `reason` are
## dropped rather than merged so the answer's own verdict cannot be overwritten by the
## move's.
static func _moved_fields(board: Dictionary, moved: Dictionary) -> Dictionary:
	var published := _published(board, {})
	for drop in ["ok", "reason"]:
		published.erase(drop)
	published.merge(moved, true)
	return published


## The board as a screen draws it. `grid_cells` is row-major and exactly
## `grid_width * grid_height` long — the product taken from the authored footprint BEFORE
## the fill — so a renderer can index it without asking how wide the board is twice.
static func _published(board: Dictionary, extra: Dictionary) -> Dictionary:
	var size: Vector2i = board["size"]
	var width := maxi(1, size.x)
	var wall_at := _index_set(board["walls"] as Array, size)
	var target_at := _index_set(board["targets"] as Array, size)
	var piece_at := _index_set(board["pieces"] as Array, size)
	var cursor := board["cursor"] as Array
	var cells: Array = []
	# Bounded `for` over the board's OWN tile count, taken from the authored footprint
	# before the loop; the body appends exactly one entry per pass and never reads
	# `cells.size()`, so the bound cannot grow in lockstep with what it produces.
	for y in size.y:
		for x in size.x:
			var flat := y * width + x
			var name := CELL_OPEN
			if wall_at.has(flat):
				name = CELL_WALL
			elif piece_at.has(flat):
				name = CELL_PIECE_ON_TARGET if target_at.has(flat) else CELL_PIECE
			elif _is_cursor(cursor, x, y):
				name = CELL_CURSOR
			elif target_at.has(flat):
				name = CELL_TARGET
			cells.append(name)
	var out := {
		"grid_width": size.x,
		"grid_height": size.y,
		"grid_cells": cells,
		"grid_walls": _cells_from_set(wall_at, size),
		"grid_targets": _cells_from_set(target_at, size),
		"grid_cursor": cursor.duplicate(),
		"grid_pieces": (board["pieces"] as Array).duplicate(),
	}
	out.merge(extra, true)
	return out


## The inverse of [method _index_set], so the published walls/targets are `[x, y]` in
## row-major order whatever order an author wrote them in — which is what makes the
## determinism claim a real one rather than an artefact of authored order.
static func _cells_from_set(indexes: Dictionary, size: Vector2i) -> Array:
	var out: Array = []
	var width := maxi(1, size.x)
	# Bounded `for` over the same snapshotted tile product; the body FILTERS, so it never
	# decides the bound it is walking.
	for flat in range(maxi(0, size.x * size.y)):
		if indexes.has(flat):
			out.append([flat % width, flat / width])
	return out


# ── geometry ──────────────────────────────────────────────────────────────────


static func _delta(direction: StringName) -> Vector2i:
	match direction:
		UP:
			return Vector2i(0, -1)
		DOWN:
			return Vector2i(0, 1)
		LEFT:
			return Vector2i(-1, 0)
		RIGHT:
			return Vector2i(1, 0)
	return Vector2i.ZERO


static func _shift(cell: Array, delta: Vector2i) -> Array:
	if cell.size() < 2:
		return []
	return [int(cell[0]) + delta.x, int(cell[1]) + delta.y]


static func _inside(size: Vector2i, cell: Array) -> bool:
	if cell.size() < 2:
		return false
	var x := int(cell[0])
	var y := int(cell[1])
	return x >= 0 and y >= 0 and x < size.x and y < size.y


static func _is_cursor(cursor: Array, x: int, y: int) -> bool:
	return cursor.size() >= 2 and int(cursor[0]) == x and int(cursor[1]) == y


## Row-major index. `width` is the authored footprint's own width, so two boards of
## different sizes never collide on one key.
static func _flat(cell: Array, width: int) -> int:
	if cell.size() < 2:
		return -1
	return int(cell[1]) * maxi(1, width) + int(cell[0])


## Where `cell` sits in `cells`, or -1. A bounded `for` over a snapshot of the authored /
## ledger piece count: the body returns early and the array is never grown, so there is
## nothing for the bound to chase.
static func _index_of(cells: Array, cell: Array) -> int:
	var found := 0
	for entry in cells:
		if entry == cell:
			return found
		found += 1
	return -1


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out


## NOT `base.merge(extra, true)`: Godot's `Dictionary.merge` returns `void` and merges IN
## PLACE, so a chained call is a parse error. The copy is what keeps the caller's
## dictionary from being rewritten under it — `DomainFixtures._merged`, restated here
## because this file must not reach into another file's private helper.
static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out