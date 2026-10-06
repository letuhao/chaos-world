class_name AptitudeMatrix
extends RefCounted

## The pure resolver of the aptitude layer (ADR 0881): POINTS per aptitude -> SHARES ->
## flat contributions per channel, through a table of [AptitudeEdge]s. Ported from
## Keepverse's `AptitudeResolver` + `AptitudeReadFunctions`.
##
## Pure and stateless, one call in and one Dictionary out: the caller owns the edge table
## (data), the points (resolved by the three majors from what an actor has built) and the
## ladder value. Nothing here reads an actor, a file or a global, so the arithmetic is
## testable with nothing configured.


## `id -> share` over the actor's own counted points. Points at or below zero are not
## counted: they grant nothing and they do not dilute anyone else's share. A key that is
## not an aptitude id is invisible — it neither grants nor dilutes, because a stray key
## must not be a denominator.
static func shares(points: Dictionary) -> Dictionary:
	var total := 0.0
	for id in points.keys():
		if not Aptitude.is_id(StringName(id)):
			continue
		total += _counted(points[id])
	if total <= 0.0:
		return {}
	var out := {}
	for id in points.keys():
		var name := StringName(id)
		if not Aptitude.is_id(name):
			continue
		var value := _counted(points[id])
		if value > 0.0:
			out[name] = value / total
	return out


## Resolve `edges` against `points`: channel id -> summed flat contribution.
##
## One channel can be fed by several edges and the values SUM (Keepverse composes an
## aptitude contribution as a FLAT modifier); a channel no edge reaches is ABSENT, never
## a zero. An empty or zeroed allocation resolves to NOTHING AT ALL — not to zero-valued
## contributions — so "no build" has no footprint on any channel.
static func resolve(
	edges: Array[AptitudeEdge],
	points: Dictionary,
	share_exponent: float = 1.0,
	contest_span: float = 1.0,
	ladder: float = 1.0
) -> Dictionary:
	var share_of := shares(points)
	if share_of.is_empty():
		return {}
	var gamma := share_exponent if is_finite(share_exponent) else 1.0
	var out := {}
	for edge in edges:
		if edge == null:
			continue
		var share := float(share_of.get(edge.source, 0.0))
		if share <= 0.0:
			continue
		var value := read_value(edge, share, gamma, contest_span, ladder)
		if value <= 0.0:
			continue
		out[edge.channel] = float(out.get(edge.channel, 0.0)) + value
	return out


## One edge's term, exposed because a preview or a test may want it without a full
## resolve: `k * share^gamma * span`, the one formula (Keepverse PS-3). Never negative,
## never non-finite: a malformed input reads `0.0` rather than poisoning a stat.
static func read_value(
	edge: AptitudeEdge, share: float, gamma: float, contest_span: float, ladder: float
) -> float:
	if edge == null:
		return 0.0
	var bounded := clampf(share, 0.0, 1.0)
	var curve := pow(bounded, gamma if gamma > 0.0 else 1.0)
	var span := contest_span if edge.mode == AptitudeEdge.Mode.CONTEST else ladder
	if not is_finite(span):
		return 0.0
	var candidate := float(edge.k) * curve * span
	return candidate if is_finite(candidate) and candidate > 0.0 else 0.0


## Every way an edge can be malformed, as messages — empty means the table is sound.
## The shipped table's own test calls this: a typo'd `source` would otherwise contribute
## NOTHING at every resolve, the silently-dead edge class Keepverse's tuning reader
## catches at load, carried over rather than re-learned.
static func validate(edges: Array[AptitudeEdge]) -> Array[String]:
	var problems: Array[String] = []
	for index in range(edges.size()):
		var edge := edges[index]
		if edge == null:
			problems.append("edge %d is null" % index)
			continue
		if edge.channel == &"":
			problems.append("edge %d has no channel" % index)
		if not Aptitude.is_id(edge.source):
			problems.append("edge %d names unknown aptitude '%s'" % [index, String(edge.source)])
		if not is_finite(edge.k) or edge.k < 0.0:
			problems.append("edge %d has a non-finite or negative k" % index)
	return problems


static func _counted(value: Variant) -> float:
	if not (value is float or value is int):
		return 0.0
	var number := float(value)
	return number if is_finite(number) and number > 0.0 else 0.0
