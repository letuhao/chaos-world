class_name RowBudget
extends RefCounted

## A ceiling on how many rows a screen may build at runtime.
##
## UI screens pool their rows and grow them to fit whatever the data says: the
## number of offices, claims, fates, techniques. That count is bounded by authored
## content today, but nothing about the loop enforces it — `while rows.size() <
## needed` is accepted by `test_no_unbounded_wait.gd` precisely because `needed`
## is a fixed number *as far as the scan can see*, and a data-derived one makes
## that a claim rather than a guarantee.
##
## So the bound is stated once, here, and every grow loop clamps through it. A
## screen that would exceed the cap renders what fits; the count it reports still
## comes from the data, so a truncated screen says it is showing N of M rather
## than silently pretending the list ended.
##
## One shared helper rather than six local constants, because the value only means
## something as a single number: six independently-chosen caps would drift, and
## the one that matters is the smallest.

## Rows one screen may build. Comfortably above every authored pool today, and
## low enough that even an accidental runaway is a truncated list rather than a
## machine that stops responding.
const MAX_ROWS := 256


## `needed`, clamped to `MAX_ROWS`. The only function a grow loop should use to
## decide how far to build.
static func cap(needed: int) -> int:
	return clampi(needed, 0, MAX_ROWS)


## Whether `shown` rows out of `total` means the screen dropped some, so a caller
## can say so instead of showing a list that appears to end.
static func truncated(shown: int, total: int) -> bool:
	return total > shown
