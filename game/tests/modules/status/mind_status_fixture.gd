extends TestCase

## Shared fixture for `test_mind_status_no_lock.gd` and `test_mind_status_refill.gd`.
## NOT a suite itself: the runner discovers `test_*.gd` only, so this file is never
## executed on its own.
##
## Split out of the no-lock suite purely for size -- gdlint's `max-file-lines` is
## 1000. Nothing was rewritten, no assertion changed and no case renamed: the fixture
## constants and the catalogue reads both halves walk now live here, which both suites
## `extend`. A test file can only move HELPERS, which is why the moved bodies are
## exactly the ones no `test_` function names.

## Sides of a contest, walked across the sweep. A constant pair read before the loop,
## so the walk's bound is never one of its own values.
const WEAK := 1.0
const OVERPOWERED := 1.0e9

## How much more the TARGET out-invests than the attacker in the `(b)` DIRECTION case
## — a fixture constant, not a balance number. It is the smallest integer ratio for
## which every SHIPPED control reads a refusal above parity.
const OUT_INVESTING := 3.0

## How much more the target out-invests in the `(b)` CEILING case. A SEPARATE constant
## from [constant OUT_INVESTING] because the two make different claims: this one has to
## drive `p_land` to `0.0`, which is a different demand, and `3.0` only reaches it on
## the steep half of the catalogue. It is a fixture number chosen to DOMINATE — the
## margin against the steepest shipped `steepness` is asserted in the walk rather than
## assumed, so this constant cannot go stale without the test saying so.
const CEILING_RATIO := 8.0

## How far a shipped refusal rate must clear the naive coin flip by. `0.2` is the
## design's floor on the margin: a gate that only just cleared `0.5` would be the
## coin flip wearing a rounding error, and the whole point of `floor_resist` is that
## it does not.
const COIN_FLIP_MARGIN := 0.2


## Realms swept for the "no CC is unavoidable at ANY realm" claim. Snapshotted from
## the ladder before the walk and never appended to inside it.
func _realms() -> Array[StringName]:
	var out: Array[StringName] = []
	for realm in RealmDefaults.ladder().realms():
		out.append(realm.id)
	return out


func _actor(
	id: StringName, will: float, clarity: float, rank_id: StringName = &"qi_refining"
) -> Actor:
	var actor := (
		ActorFactory
		. build(
			id,
			{
				Stat.WILL: will,
				MindStats.MENTAL_CLARITY: clarity,
				MindStats.PERCEPTION: clarity,
				Stat.COMPREHENSION: 10.0,
			}
		)
	)
	return ActorFactory.with_mind_cultivation(actor, rank_id)


func _catalog() -> MindStatusCatalog:
	return MindStatusCatalog.instance()


## Every authored control def, in catalogue order. Bounded by the closed catalogue, not
## by a hand list, so a fifth shape authored tomorrow is swept by these tests too.
func _controls() -> Array[MindStatusDef]:
	var out: Array[MindStatusDef] = []
	for status_id in _catalog().ids_of_role(MindVocabulary.ROLE_CONTROL):
		var def := _catalog().definition(status_id)
		if def != null:
			out.append(def)
	return out


func _projections() -> Array[MindStatusDef]:
	var out: Array[MindStatusDef] = []
	for status_id in _catalog().ids_of_role(MindVocabulary.ROLE_EXPRESSION):
		var def := _catalog().definition(status_id)
		if def != null:
			out.append(def)
	return out
