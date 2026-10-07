class_name WorldmapRng
extends RefCounted

## Deterministic hash RNG: the same (seed, stream, position) answers the same
## value on every run, on every machine. Generation never holds rolling state
## across passes — each draw names its stream — so reordering passes, or
## regenerating one chunk of a world, cannot shift any other draw.
##
## 32-bit FNV-1a plus a xorshift finalizer. Every constant fits a signed
## 64-bit literal with room to spare: nothing here depends on overflow width,
## only on determinism.

const _BASIS := 2166136261
const _PRIME := 16777619
const _MASK := 0xFFFFFFFF


## A unit draw in [0, 1) for `stream` at integer position (`a`, `b`, `c`).
static func unit(seed: int, stream: String, a: int, b: int = 0, c: int = 0) -> float:
	var h := _BASIS
	h = _mix(h, seed)
	for index in stream.length():
		h = _mix(h, stream.unicode_at(index))
	h = _mix(h, a)
	h = _mix(h, b)
	h = _mix(h, c)
	h = _final(h)
	return float(h & 0xFFFFFF) / 16777216.0


## An int draw in [lo, hi).
static func range_i(seed: int, stream: String, a: int, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(unit(seed, stream, a) * float(hi - lo))


## Pick one entry of a non-empty array, deterministically.
static func pick(seed: int, stream: String, a: int, entries: Array):
	if entries.is_empty():
		return null
	return entries[range_i(seed, stream, a, 0, entries.size())]


static func _mix(h: int, value: int) -> int:
	return ((h ^ (value & _MASK)) * _PRIME) & _MASK


static func _final(h: int) -> int:
	var x := h & _MASK
	x = (x ^ (x >> 13)) & _MASK
	x = (x * 0x5BD1E995) & _MASK
	x = (x ^ (x >> 15)) & _MASK
	return x
