class_name ElementTraining
extends RefCounted

## The elemental MASTERY loop (ADR 0004's second half): `element_mastery_<e>` is the
## channel the provider turns into power (`affinity * (1 + rate * mastery)`) and crit,
## and until this file existed NOTHING in the game could move it — the stat was
## published on every actor and writable by no verb, no item and no status, so the
## whole "master an element to grow stronger" fantasy had no door.
##
## ## The rate is the SHARED one, and the rank is the actor's own climb
##
## A sitting's gain is `amount * RealmRate.factor(rank)` — the same rate curve every
## cultivation path reads (ADR 0116/0268: one shared rate, never a per-path copy) — so
## elemental practice speeds up exactly as fast as qi, body and mind do. `rank` is the
## ELEMENTAL path's own standing when it is enrolled, and the actor's highest realm
## otherwise: a body that has never opened the elemental path still trains at the pace
## its cultivation has earned.
##
## ## The SPARK gate, and why elixirs are the other door
##
## A sitting requires `affinity > 0.0` for the element: a body practises what its
## constitution can sense, so the races' authored affinities ARE the training set
## (emberblood: fire; tidecaller: water and ice; commonborn: all five base). The
## advanced elements most races never touch are opened by `ElementsApi.awaken` — a
## rare resource raises the AFFINITY itself — and then by the master pool's
## `element_mastery_<e>` options. That is the novel shape: the spark decides the cheap
## path, a rare resource buys the other.
##
## The verb NEVER refuses for a full bar: mastery has no cap, because the channel it
## feeds is a magnitude the provider multiplies (ADR 0200's rule — the OUTPUT is what
## is bounded, never the input).


## Whether `actor` may practise `element_id`: the element must exist in the rules and
## the body must carry a SPARK for it (`affinity > 0.0`).
static func can_practise(actor: Actor, element_id: StringName, rules: ElementRules = null) -> bool:
	if actor == null:
		return false
	var resolved := rules if rules != null else ElementsApi.default_rules()
	if resolved == null or resolved.element(element_id) == null:
		return false
	return actor.affinities.get_value(element_id) > 0.0


## One sitting on `element_id`: raises `element_mastery_<e>` by
## `amount * RealmRate.factor(rank)`.
static func practise(actor: Actor, element_id: StringName, amount: float) -> bool:
	if actor == null or amount <= 0.0 or not is_finite(amount):
		return false
	if not can_practise(actor, element_id):
		return false
	var rank := _rank_of(actor)
	_set_mastery(actor, element_id, mastery_of(actor, element_id) + amount * RealmRate.factor(rank))
	return true


## The mastery this actor has earned on `element_id`, from the BASE layer the provider
## reads.
static func mastery_of(actor: Actor, element_id: StringName) -> float:
	if actor == null or actor.stats == null:
		return 0.0
	return maxf(0.0, actor.stats.get_base(ElementStats.mastery_id(element_id)))


## Raise the actor's AFFINITY for `element_id` — the innate channel, opened by a rare
## resource rather than by birth. The affinity map publishes its own `changed` signal
## (`StatsInvalidator` is connected to it), so the derived stats rebuild without a
## second dirty call here.
static func awaken(actor: Actor, element_id: StringName, amount: float) -> bool:
	if actor == null or amount <= 0.0 or not is_finite(amount):
		return false
	var rules := ElementsApi.default_rules()
	if rules == null or rules.element(element_id) == null:
		return false
	actor.set_affinity(element_id, actor.affinities.get_value(element_id) + amount)
	return true


## The rank a sitting is priced at: the elemental path's own standing when the actor
## has enrolled it, the highest realm across its paths otherwise, and the first rung
## when it has no path at all.
static func _rank_of(actor: Actor) -> StringName:
	var state := actor.path(ElementMastery.PATH_ID)
	if state != null:
		return state.rank_id
	var realm := RealmScaling.highest_realm(actor)
	if realm != null:
		return realm.id
	return RealmDefaults.ladder().realms()[0].id


static func _set_mastery(actor: Actor, element_id: StringName, value: float) -> void:
	actor.stats.set_base(ElementStats.mastery_id(element_id), maxf(0.0, value))
	actor.mark_stats_dirty()
