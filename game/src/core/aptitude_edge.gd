class_name AptitudeEdge
extends Resource

## One edge of the aptitude matrix (ADR 0881): a CHANNEL names an aptitude SOURCE and
## the coefficient that carries it there. Channels name their source rather than
## aptitudes listing their channels — Keepverse's own rule — so two tables can feed one
## channel without either knowing the other.
##
## ## The read, ported from `AptitudeReadFunctions`
##
## ```
## value = k * share^gamma * span
## ```
##
## where `share` is the source aptitude's share of the actor's own counted points, and
## `span` is the caller's read parameter: the ladder value `P(theta)` for
## [constant Mode.MAGNITUDE] and the contest span for [constant Mode.CONTEST].
##
## Keepverse keeps `k` in per-mille integers and rounds at two separate points, because
## its core is integer-exact; this port is floats end to end (the engine's stat stack is
## floats), so `k` is a plain coefficient and the rounding idiom is deliberately NOT
## carried. The arithmetic is the same.

enum Mode {
	## Ladder-free: a bounded contest point, ready to compare against a defender's
	## same-family number (Keepverse PS-3, "Contest is Theta-free").
	CONTEST,
	## Ladder-scaled: a game MAGNITUDE that keeps climbing as the actor does, and the
	## caller passes the actor's own ladder value.
	MAGNITUDE,
}

## The derived-stat channel this edge feeds, e.g. `CombatStats.SHIELD_CAPACITY`.
@export var channel: StringName = &""
## The aptitude that feeds it; must be one of `Aptitude.all_ids()`. `AptitudeMatrix
## .validate()` names a typo rather than letting it contribute nothing silently.
@export var source: StringName = &""
## The coefficient. Negative is refused by `AptitudeMatrix.validate()`: an aptitude
## point is an advantage, and a negative coefficient would be a trap wearing one.
@export var k: float = 0.0
@export var mode: Mode = Mode.MAGNITUDE
