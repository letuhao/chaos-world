class_name CombatRng
extends RefCounted

## Contract: a source of one bounded draw. Anything that answers
## `randf() -> float` satisfies it, which is what makes a draw countable.
##
## Why this is named and not typed. `RandomNumberGenerator` is a concrete native class,
## and `randf()` on it is native too, so it cannot be overridden. That makes a counting
## subclass impossible, and a resolver that promises "this costs exactly one draw"
## therefore had no way to be checked by anything. Declaring the parameter as this
## contract inverts the dependency: the resolver depends on "something that draws", and
## the engine's own `RandomNumberGenerator` becomes one implementation among several
## rather than the only admissible one.
##
## GDScript has no `interface` keyword, so the runtime half is a `Variant` parameter
## documented at each seam -- `CombatBand.roll` is the lowest one and states the rule
## once. Implementations must be deterministic for a given seed or given value list:
## a resolve that cannot be replayed cannot be diagnosed from a bug report.
##
## ADR 0067 is the reason an injected draw is worth having at all; this is the seam
## that makes the injection testable.
