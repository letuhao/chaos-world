class_name RaceResolver
extends RefCounted

## Resolves which single race a child is born (ADR 0062).
##
## **A race is one value, never a blend.** Nothing here averages two body plans or
## merges their numbers: the answer is always exactly one race id, and a child of two
## different races is born one of them, never a mixture.
##
## The function is **pure**: it reads nothing but the two parent actors and the catalog,
## it mutates nothing, and `roll` is a caller-supplied value in `[0, 1)` rather than a
## random draw. That is what makes conception headless-testable and reproducible — the
## same parents and the same roll always name the same race, in the test suite and in a
## save, with no seeded RNG to keep in step.


## The race `parent_a` and `parent_b` produce, for `roll` in `[0, 1)`.
##
## **The algorithm, exactly:**
## 1. Read each parent's race from its ledger. An unknown race, or a parent with none,
##    contributes 0.0 and never participates — an unreadable parent does not get to
##    choose the child's body.
## 2. Group both parents by race. When the two carry the SAME race there is nothing to
##    resolve and `roll` is not consulted at all: that race is the answer.
## 3. A mixed conception is one *round*: each distinct race contests the whole
##    conception, weighted by `roll`. Race A's share is `roll * dominance_A` and race
##    B's is `(1 - roll) * dominance_B`. A race with no share — a roll of 0 hands it
##    nothing — does not manifest, which is what keeps `roll` meaningful for a lopsided
##    pairing rather than making the higher-dominance body always win.
## 4. Among the races that clear their own `manifestation_threshold`, take the highest
##    share. Ties break on the higher `dominance`, then on the catalog's canonical id
##    order, so the outcome is total and never depends on Dictionary iteration order.
## 5. When no race clears its threshold, or when neither parent names one at all, the
##    child is born the catalog's `baseline_race()`.
static func resolve(parent_a: Actor, parent_b: Actor, roll: float) -> StringName:
	var catalog := RaceCatalog.instance()
	var shares := _shares(catalog, parent_a, parent_b, roll)
	var best := StringName("")
	var best_share := -1.0
	var best_dominance := -1.0
	for race_id in _contested_order(shares):
		var share := float(shares[race_id])
		if share <= 0.0:
			continue
		var def := catalog.race_definition(race_id)
		if def == null or share < def.manifestation_threshold:
			continue
		if (
			share > best_share
			or (is_equal_approx(share, best_share) and def.dominance > best_dominance)
		):
			best = race_id
			best_share = share
			best_dominance = def.dominance
	return best if best != &"" else catalog.baseline_race()


## Each contested race's share of this conception.
##
## **Order-independent by construction.** The roll is a property of the *pair*, not of
## which parent happens to be listed first, so the first parent that actually carries a
## contestable race takes the roll and the other takes its complement. Weighting
## parent_a by `roll` and parent_b by `1 - roll` instead let the seat decide the
## outcome: with only one parent holding a race, `(bare, known, 0.0)` answered TIDE
## while `(known, bare, 0.0)` answered the baseline — one conception answering two ways.
static func _shares(
	catalog: RaceCatalog, parent_a: Actor, parent_b: Actor, roll: float
) -> Dictionary:
	var clamped := clampf(roll, 0.0, 1.0)
	var a_weight := clamped
	var b_weight := 1.0 - clamped
	var first := _first_contested(catalog, parent_a, parent_b)
	if first != &"" and not _holds(catalog, parent_a, first):
		# parent_b holds the contested race, so the roll belongs to it.
		a_weight = 1.0 - clamped
		b_weight = clamped
	var shares := {}
	shares = _add(catalog, parent_a, shares, a_weight)
	shares = _add(catalog, parent_b, shares, b_weight)
	# Seed every contested race at zero so an ordering that never manifests is still
	# a key with a value, rather than a missing entry.
	for race_id in _distinct(catalog, parent_a, parent_b):
		if not shares.has(String(race_id)):
			shares[race_id] = 0.0
	return shares


## The race the roll belongs to: whichever the first contesting parent carries.
static func _first_contested(catalog: RaceCatalog, parent_a: Actor, parent_b: Actor) -> StringName:
	for parent in [parent_a, parent_b]:
		var race_id := RaceGate.race_of(parent)
		if race_id != &"" and catalog.race_definition(race_id) != null:
			return race_id
	return &""


## Whether `parent` carries `race_id` — and therefore holds the roll's seat. The catalog is
## not consulted: the caller has already established that `race_id` is a contestable race, so
## the only question left is which seat the parent sits in.
static func _holds(_catalog: RaceCatalog, parent: Actor, race_id: StringName) -> bool:
	if parent == null or race_id == &"":
		return false
	return RaceGate.race_of(parent) == race_id


static func _add(
	catalog: RaceCatalog, parent: Actor, shares: Dictionary, weight: float
) -> Dictionary:
	if parent == null:
		return shares
	var race_id := RaceGate.race_of(parent)
	var def := catalog.race_definition(race_id)
	if def == null:
		return shares
	shares[race_id] = float(shares.get(String(race_id), 0.0)) + weight * maxf(0.0, def.dominance)
	return shares


## Every race either parent names, canonical order. An unknown race is dropped rather
## than carried as a zero: a race id nothing defines cannot manifest.
static func _distinct(catalog: RaceCatalog, parent_a: Actor, parent_b: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for parent in [parent_a, parent_b]:
		if parent == null:
			continue
		var race_id := RaceGate.race_of(parent)
		if race_id == &"" or out.has(race_id):
			continue
		if catalog.race_definition(race_id) == null:
			continue
		out.append(race_id)
	out.sort()
	return out


static func _contested_order(shares: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for key in shares.keys():
		out.append(StringName(key))
	out.sort()
	return out
