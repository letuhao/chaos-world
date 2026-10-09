class_name WorldStageInteractionLog
extends RefCounted

## The presses `WorldStage` routed, oldest first, BOUNDED.
##
## Extracted from `WorldStage`, which had grown past the file budget. This is the one
## part of it that is pure storage — an array, a cap and three reads — so it moves whole
## and nothing about a press changes. `WorldStageReconcile` is the sibling extraction
## living beside it, and this follows the same shape.
##
## **The cap is why the array is private to this class.** `interact` records EVERY exit
## including its refusals, so an unbounded log grows with every press of a long session;
## the only way it stays bounded is that no caller can append past `file`.

## The most rows kept. The OLDEST are dropped first, so the log always answers with the
## most recent presses rather than the first ones.
const MAX_ROWS := 8

var _rows: Array[Dictionary] = []


## File one row and hand it straight back, so no caller's exit path can forget to return
## it. Trimmed to [constant MAX_ROWS].
func file(row: Dictionary) -> Dictionary:
	_rows.append(row)
	while _rows.size() > MAX_ROWS:
		_rows.pop_front()
	return row


## The last row, or `{}` when no press has been routed. A COPY: a caller mutating the
## stage's own log would be rewriting a record it never made.
func last() -> Dictionary:
	return {} if _rows.is_empty() else (_rows[-1] as Dictionary).duplicate()


## Every row, oldest first. A copy, for [method last]'s reason.
func all() -> Array[Dictionary]:
	return _rows.duplicate()


## How many rows are filed. A count rather than `all().size()`, which would copy the whole
## log to read a number.
func count() -> int:
	return _rows.size()


## Drop every row. The log belongs to the ACTOR that stood here, so a body swap clears it:
## leaving it would hold a reborn hero's answers against a place it is no longer standing
## in, which is the half-swapped-body failure `WorldStage.adopt_actor` guards one layer up.
func clear() -> void:
	_rows.clear()
