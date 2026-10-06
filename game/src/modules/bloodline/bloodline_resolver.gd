class_name BloodlineResolver
extends RefCounted

## Resolves the bloodline purity map a child is born with (ADR 0063).
##
## **This is the call the birth system makes.** `FertilityApi` asks for one number per
## lineage and gets back a plain `{lineage_id: purity}` dictionary; it never has to
## know how the number is produced, and this class never has to know what a pregnancy
## is. The module boundary is that narrow on purpose.
##
## The function is **pure**: it reads nothing but the two parent actors, it mutates
## nothing, and it draws no random number. Conception is deterministic — the same two
## parents always produce the same ancestry — which is what makes the whole inheritance
## rule headless-testable and reproducible in a save.

## **The mean is load-bearing.** `BloodlineState.inherit` blends from the *mean* of
## both parents, not the maximum, precisely so that a weak partner is a real cost. A
## carrier pairing with someone who carries nothing lands at 0.395 — a viable bloodline
## below `rare` — where blending toward the maximum would have handed over the full
## 0.745 and made every pairing behave identically. That difference is the entire
## marriage-and-alliance layer this system exists to support.


## The `{lineage_id: purity}` map a child of `parent_a` and `parent_b` is born with.
##
## The union of both parents' lineages is blended in a single pass, so a lineage only
## one parent carries still counts — as a dilution, which is the point. A lineage
## neither parent carries is absent from the map rather than present as 0.0, because a
## child has no such ancestry and a consumer should not have to filter noise out.
##
## Purity can never leave `[0, 1]` and can never exceed `0.745` on a first generation,
## which is what keeps every authored threshold inside the reachable band.
##
## ## ADR 0125: divergence is computed once per pairing, not per lineage
##
## `D` is the Jaccard distance over the parents' lineage-id sets (`1 - |A AND B| /
## |A OR B|`): `0.0` same family, `1.0` unrelated. Symmetric, bounded, and reading
## only the lineage sets the ledgers already carry, so no new authored data.
static func resolve(parent_a: Actor, parent_b: Actor) -> Dictionary:
	var out: Dictionary = {}
	var divergence := _divergence(parent_a, parent_b)
	for lineage_id in _union(parent_a, parent_b):
		out[String(lineage_id)] = BloodlineState.inherit(
			BloodlineGate.purity_of(parent_a, lineage_id),
			BloodlineGate.purity_of(parent_b, lineage_id),
			divergence
		)
	return out


## The pair's divergence for ADR 0125's excess term. `0.0` when neither parent
## carries anything (no union to differ over); otherwise one minus the overlap
## share. Bounded by the sets it walks; the body only reads, never writes.
static func _divergence(parent_a: Actor, parent_b: Actor) -> float:
	var a := _lineage_id_set(parent_a)
	var b := _lineage_id_set(parent_b)
	var union_size := a.size() + b.size()
	if union_size == 0:
		return 0.0
	var intersection := 0
	for lineage_id in a:
		if b.has(lineage_id):
			intersection += 1
	var union := union_size - intersection
	if union == 0:
		return 0.0
	return 1.0 - (float(intersection) / float(union))


## Both parents' lineage ids as a set, so overlap is a lookup rather than a scan.
static func _lineage_id_set(actor: Actor) -> Dictionary:
	var out := {}
	for lineage_id in BloodlineGate.lineage_ids(actor):
		out[String(lineage_id)] = true
	return out


## Every lineage either parent names, canonically ordered.
static func _union(parent_a: Actor, parent_b: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for parent in [parent_a, parent_b]:
		for lineage_id in BloodlineGate.lineage_ids(parent):
			if not out.has(lineage_id):
				out.append(lineage_id)
	out.sort()
	return out
