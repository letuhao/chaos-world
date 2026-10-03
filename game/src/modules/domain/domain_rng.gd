class_name DomainRng
extends RefCounted

## Deterministic, independent random streams for domain generation.
##
## A generator that draws the graph and the room kit from ONE stream is unreviewable:
## adding one decor roll re-rolls every wall. Four streams — `graph`, `rooms`, `decor`
## and `spawns` — mean a change to how many furniture picks a room makes cannot move
## the layout, which is what lets a map be regenerated months later and still mean
## the same thing.
##
## ## Why the mixer is written here
##
## The stream seeds come from [method mix_seed], a splitmix64-shaped xor-shift
## multiply written in GDScript, and from NOTHING else. `hash()`, `String.hash()` and
## the global `randi()`/`randf()` family are deliberately not used:
##
## - `hash()` is documented as unspecified for the engine and free to change between
##   releases, so a byte-identical claim resting on it is not a claim at all.
## - the global generators are process-state. Reading them makes a map depend on
##   everything that touched the RNG before the generator ran.
##
## Every shift here is 30, 27 or 31 bits and every product is masked back to 64 bits,
## so no intermediate leaves the signed 64-bit range a GDScript int occupies.
##
## ## What IS the engine's
##
## `RandomNumberGenerator` is seeded with the mixed value and then supplies the
## distribution (`randf_range`, `randi_range`, `shuffle`). The claim this file backs
## is therefore "the same seed draws the same numbers from the same streams in the
## same order", which is a property of the call sequence — and the call sequence is
## asserted byte-for-byte by `test_domain_generator.gd`.

## One stream's domain tag. A per-stream tag, not the raw seed, is what goes through
## the mixer: two streams of the same seed cannot collide even though they are drawn
## from the same integer.
const STREAM_TAGS: Array[StringName] = [&"graph", &"rooms", &"decor", &"spawns"]

const STREAM_GRAPH := &"graph"
const STREAM_ROOMS := &"rooms"
const STREAM_DECOR := &"decor"
const STREAM_SPAWNS := &"spawns"

## splitmix64 finalizer constants, as signed 64-bit literals: GDScript ints are signed
## and an out-of-range literal is a parse error, so these are written the way the
## engine has to read them. See `_mix` for what they are.
const GOLDEN_GAMMA := -7046029254386353131
const MIX_A := -4658895280553007687
const MIX_B := -7723592293110705685


## The four streams for `seed_value`, keyed by `STREAM_TAGS`.
##
## Returns `{}` for an out-of-range seed rather than a half-built set: a caller that
## checked `graph` and then read `rooms` would be reading null off a live dictionary.
static func streams(seed_value: int) -> Dictionary:
	var out: Dictionary = {}
	if not is_valid_seed(seed_value):
		return out
	for tag in STREAM_TAGS:
		out[tag] = _generator(seed_value, tag)
	return out


## The engine's own seed domain. `RandomNumberGenerator.seed` is a 64-bit word and a
## GDScript int cannot hold every one of them, so an out-of-range integer is a value
## nothing can reproduce — it fails here instead of silently aliasing a valid seed.
static func is_valid_seed(seed_value: int) -> bool:
	return seed_value >= -9223372036854775808 and seed_value <= 9223372036854775807


## splitmix64's `next`, as a pure function of its argument.
##
## `z = x + GOLDEN_GAMMA`, then two xor-shift-multiply rounds, then a final xor-shift.
## The point of writing it out is that it is a function of INTEGER ARITHMETIC alone:
## the same three operations produce the same word on any engine version, which is a
## claim `hash()` cannot make.
static func mix_seed(seed_value: int, salt: int = 0) -> int:
	return _mix(seed_value + _mix(salt))


## The seed of one stream. Exposed so a test can assert that two streams of the same
## seed are genuinely different rather than accidentally equal.
static func stream_seed(seed_value: int, stream: StringName) -> int:
	return mix_seed(seed_value, _salt_for(stream))


static func _generator(seed_value: int, stream: StringName) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = stream_seed(seed_value, stream)
	generator.state = generator.seed
	return generator


## A stable per-stream salt. Derived from the tag's bytes, never from `hash()`.
static func _salt_for(stream: StringName) -> int:
	var value := 0
	for index in stream.length():
		value = _mix(value ^ (stream.unicode_at(index) + index))
	return value


static func _mix(value: int) -> int:
	var z := value + GOLDEN_GAMMA
	z = (z ^ (z >> 30)) * MIX_A
	z = (z ^ (z >> 27)) * MIX_B
	return z ^ (z >> 31)
