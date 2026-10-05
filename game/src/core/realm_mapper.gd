class_name RealmMapper
extends RefCounted

## Project a cultivation system's OWN ordinal onto the shared standard ladder
## (ADR 0268).
##
## A path keeps its own progression array and is not required to share the standard
## ladder's LENGTH. A partial ladder is already legal at registration —
## `modules/mods/module_registry.gd::_validate_cultivation_seeds` validates the seeds
## it finds and explicitly does not require one per ladder realm. What was missing is
## the correspondence between a path's steps and the ladder's realms, so every caller
## guessed it by index and a path whose array was not 30 long silently misaligned.
##
## It has to live in `core/` and not in a path, because two independent guards refuse
## the per-path version: `CultivationPathContract.validate_provider_source` rejects a
## provider whose code contains `RealmDefaults.ladder()`, and
## `test_realm_rate.gd::test_no_path_provider_computes_a_rate_from_the_ladder_itself`
## rejects the same shape. This is ADR 0116's pattern exactly — one shared curve in
## `core/`, never a per-path copy — and a path that wants the map calls it here rather
## than re-deriving it.
##
## `core` is a LAYER, not a module: `LAYER_DEPS["core"] == {"core", "contracts"}`
## (`tools/arch/rules.py`). Every cultivation module already declares `core`, so
## holding the projection here creates ZERO new edges — the argument
## `core/realm_rate.gd:75-82` makes for the rate.
##
## ## The map
##
## Proportional, with BOTH ends anchored: a path's first step is R1 and its last step
## is the top standard realm, however many steps it has between them. Equal lengths
## make it the identity (`roundi(i * (n - 1) / (n - 1)) == i`), so all five shipped
## paths are bit-for-bit unaffected. A SHORTER path skips standard realms to reach the
## top in its own step count; a LONGER path holds one realm across several of its
## steps rather than running off the end.
##
## A mapped realm INHERITS that standard realm's authored magnitude — `RealmScaling`
## reads the `RealmDef.power` of the realm it maps onto, unchanged — so extending a
## path adds no fourth magnitude table. The only thing a path's own length changes is
## how finely it samples the one shared rate.


## The standard-ladder ordinal a path ordinal maps onto, or -1 for a negative ordinal
## or an empty ladder. Clamped, so a caller that walks one step past its own top lands
## on the top realm instead of off the array.
static func standard_ordinal(path_ordinal: int, path_size: int) -> int:
	var standard_size := RealmDefaults.ladder().size()
	if standard_size <= 0 or path_ordinal < 0:
		return -1
	# A single-step path has no span to spread over; it is the first realm. Without this
	# the division below is by zero and `roundi(INF)` is not an int.
	if path_size <= 1:
		return 0
	var scaled: int = roundi(float(path_ordinal) * float(standard_size - 1) / float(path_size - 1))
	return clampi(scaled, 0, standard_size - 1)


## The standard realm id a path ordinal maps onto, or `&""` when it maps nowhere.
static func standard_realm_id(path_ordinal: int, path_size: int) -> StringName:
	var realms := RealmDefaults.ladder().realms()
	var index := standard_ordinal(path_ordinal, path_size)
	if index < 0 or index >= realms.size():
		return &""
	return realms[index].id


## The rate for a path's own ordinal, off the ONE shared curve. A path never authors
## one: this is `RealmRate.factor` on the realm the step maps onto, so a path with a
## 12-step ladder and a path with a 60-step ladder are both priced by the same number.
static func factor_for_ordinal(path_ordinal: int, path_size: int) -> float:
	var realm_id := standard_realm_id(path_ordinal, path_size)
	if String(realm_id) == "":
		return RealmRate.NEUTRAL
	return RealmRate.factor(realm_id)
