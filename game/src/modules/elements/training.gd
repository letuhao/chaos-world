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
## ## The cap, and why the verb CAN refuse now
##
## BL-0938's ruling bounded the channel at both ends: the provider's output saturates,
## and the INPUT is capped per element by the tier the body is preparing for
## (`ElementMastery.cap_for`). So a sitting that would cross the cap lands exactly ON it
## — every point paid still pays, nothing is silently truncated away beyond the cap —
## and a sitting at the cap refuses with the named `mastery_capped` reason rather than
## taking the player's time for nothing. The one condition a player must change to keep
## growing is named by the refusal: rise a realm tier.

## The items facade, for the elixir door's ONE spend (`has_item` + `consume_item`).
## A facade preload rather than a bare class reference, the same shape every other
## module edge in this tree uses.
const _ITEMS := preload("res://src/modules/items/api.gd")

## The mastery an elixir of an element's TIER is worth, keyed by tier and never by the
## element: the family is three tiers of one item kind, and a per-element table would be
## thirteen numbers to keep in step with a three-row one.
##
## Tier 1 pays four practise sittings and tier 2 nine-plus — `PRACTICE_STEP` is `25.0`
## and an R1 sitting is exactly `25.0` at `RealmRate`'s factor of `1.0`, so `100.0` is
## four sittings by construction — and tier 3 (ADR 0921's triad) pays twenty-four, the
## same roughly 2.4x step per tier. The elixir does NOT ride the realm rate the way a
## sitting does: a sitting is labour and scales with the cultivator, an elixir is a
## RESOURCE and grants what it says, which is what makes one worth carrying to depth
## rather than a rounding error there. A tier the table does not name reads the tier-1
## figure rather than failing, because a missing row must not make an elixir un-drinkable.
const ELIXIR_GAIN_BY_TIER := {1: 100.0, 2: 240.0, 3: 600.0}


## Whether `actor` may practise `element_id`: the element must exist in the rules and
## the body must carry a SPARK for it (`affinity > 0.0`).
static func can_practise(actor: Actor, element_id: StringName, rules: ElementRules = null) -> bool:
	if actor == null:
		return false
	var resolved := rules if rules != null else ElementDefaults.rules()
	if resolved == null or resolved.element(element_id) == null:
		return false
	return actor.affinities.get_value(element_id) > 0.0


## One sitting on `element_id`: raises `element_mastery_<e>` by
## `amount * RealmRate.factor(rank)`, clamped to the element's cap. Named refusals, the
## module's usual shape: `no_actor`, `bad_amount`, `unknown_element`, `no_spark` (the
## practice gate's own rule), `mastery_capped` (the element is at the cap its realm tier
## allows).
static func practise(actor: Actor, element_id: StringName, amount: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if amount <= 0.0 or not is_finite(amount):
		return {"ok": false, "reason": "bad_amount"}
	var rules := ElementDefaults.rules()
	if rules == null or rules.element(element_id) == null:
		return {"ok": false, "reason": "unknown_element"}
	if not can_practise(actor, element_id, rules):
		return {"ok": false, "reason": "no_spark"}
	var cap := ElementMastery.cap_for(actor)
	var current := ElementMastery.mastery_of(actor, element_id)
	if current >= cap:
		return {"ok": false, "reason": "mastery_capped", "cap": cap}
	var gain := minf(amount * RealmRate.factor(ElementMastery.rank_of(actor)), cap - current)
	_set_mastery(actor, element_id, current + gain)
	return {"ok": true, "gain": gain, "cap": cap}


# --- the elixir door (ADR 0917) -------------------------------------------------


## What one elixir of `element_id` grants, from the element's authored tier.
static func elixir_gain(element_id: StringName) -> float:
	var entry := ElementDefaults.rules().element(element_id)
	if entry == null:
		return 0.0
	return float(ELIXIR_GAIN_BY_TIER.get(maxi(1, entry.tier), ELIXIR_GAIN_BY_TIER[1]))


## Drink the element's authored mastery elixir: consume ONE from the pack and raise
## `element_mastery_<e>` by [method elixir_gain]. The price is content — the id is
## [method ElementStats.mastery_elixir_id] and nothing here invents an item the corpus
## does not ship.
##
## Refusals are named dictionaries, the module's usual shape: `unknown_element`,
## `no_spark` (the practice gate's own rule — a body refines what it can sense),
## `mastery_capped` (BL-0938: the element sits at the cap its realm tier allows, so
## nothing could move), `no_elixir` (the pack holds none), `refused` (the inventory
## would not spend it). Nothing is consumed unless the mastery moved, and a drink that
## would cross the cap lands ON it and reports the gain it actually applied.
static func use_elixir(actor: Actor, element_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	var rules := ElementDefaults.rules()
	if rules == null or rules.element(element_id) == null:
		return {"ok": false, "reason": "unknown_element"}
	if not can_practise(actor, element_id):
		return {"ok": false, "reason": "no_spark"}
	var cap := ElementMastery.cap_for(actor)
	var current := ElementMastery.mastery_of(actor, element_id)
	if current >= cap:
		return {"ok": false, "reason": "mastery_capped", "cap": cap}
	var elixir := ElementStats.mastery_elixir_id(element_id)
	if not _ITEMS.has_item(actor, elixir):
		return {"ok": false, "reason": "no_elixir", "item": String(elixir)}
	if not _ITEMS.consume_item(actor, elixir):
		return {"ok": false, "reason": "refused", "item": String(elixir)}
	var gain := minf(elixir_gain(element_id), cap - current)
	_set_mastery(actor, element_id, current + gain)
	return {"ok": true, "gain": gain, "item": String(elixir)}


## Raise the actor's AFFINITY for `element_id` — the innate channel, opened by a rare
## resource rather than by birth. The affinity map publishes its own `changed` signal
## (`StatsInvalidator` is connected to it), so the derived stats rebuild without a
## second dirty call here.
static func awaken(actor: Actor, element_id: StringName, amount: float) -> bool:
	if actor == null or amount <= 0.0 or not is_finite(amount):
		return false
	var rules := ElementDefaults.rules()
	if rules == null or rules.element(element_id) == null:
		return false
	actor.set_affinity(element_id, actor.affinities.get_value(element_id) + amount)
	return true


static func _set_mastery(actor: Actor, element_id: StringName, value: float) -> void:
	actor.stats.set_base(ElementStats.mastery_id(element_id), maxf(0.0, value))
	actor.mark_stats_dirty()
