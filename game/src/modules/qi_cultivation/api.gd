class_name QiCultivationApi
extends RefCounted

## Public facade for the `qi_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).
##
## Verbs and one read model, nothing else (ADR 0095). The accessors this module
## used to publish for itself live in `QiAccess`, which is internal: nothing
## outside the module called them, and their place on this facade is what kept
## `attach` from also attaching the dantian.

# Public ids other modules may depend on.
const QI := QiStats.QI

## The training step sizes a UI's Cultivate/Meditate buttons drive. Published so
## a screen reports the facade's numbers instead of hardcoding its own, which is
## what the mind path does (ADR 0043).
const CULTIVATE_STEP := 25.0
const MEDITATE_STEP := 1.0


## Enrol an actor on the qi path: one reservoir, the qi provider, and the
## dantian. The dantian is part of the path, not an optional extra — `cultivate`,
## `recover`, the preview and the breakthrough condition all refuse an actor
## without one — so this single call leaves the actor ready (ADR 0095). The
## meridian network is core state on the Actor and reaches `QiProvider` through
## `StatContext.meridian_network()`, so this module registers no component copy
## of it: a second, divergent source of truth for core state is exactly what
## ADR 0057 removes, and the copy made the wrong read look like a working one.
static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	actor.stats.add_provider(QiProvider.new())
	QiAccess.attach_dantian(actor)
	# BL-0830: the preparation bond's formation depth needs the gate's own numbers
	# (required channels, the refinement they must carry, the deepest the realm below
	# allows) and those live on THIS path's seeds, so the kernel is injected from here
	# for the same reason `DifficultyApi.attach` injects the preparation credit: `core`
	# may not name a path's content. Idempotent — a static seam installed by every
	# attach is one install, not one per body.
	Tribulation.set_gate_requirement(Callable(QiCultivationApi, "tribulation_gate_requirement"))


## The gate kernel `Tribulation.set_gate_requirement` calls: the target realm's required
## channels, the refinement the gate demands of each, and the deepest refinement the realm
## BELOW allows (a channel can only be trained up to the cap its standing realm offers, so
## the pair is what a depth has headroom against). `{}` for a realm the ladder or the
## seeds do not know — an absent kernel entry, never an invented requirement.
static func tribulation_gate_requirement(realm_id: StringName) -> Dictionary:
	var target := QiRealmSeed.for_realm(realm_id)
	if target == null or target.required_meridians.is_empty():
		return {}
	var ladder := RealmDefaults.ladder()
	var index := ladder.index_of(realm_id)
	if index <= 0:
		return {}
	var below := QiRealmSeed.for_realm(ladder.realms()[index - 1].id)
	if below == null:
		return {}
	return {
		"channels": target.required_meridians,
		"required": target.required_channel_refinement,
		"cap": below.channel_refinement_cap,
	}


# --- Read model and actions for the UI program ------------------------------


## Everything a qi panel renders, in one read. Empty when the actor is not on
## the qi path. The dantian contributes only structural state (quality, injury);
## its current/capacity live in the actor's single `qi` ResourcePool.
static func panel_state(actor: Actor) -> Dictionary:
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return {}
	var dantian := QiAccess.dantian(actor)
	var pool := actor.resource(QI)
	var preview := QiBreakthroughTransaction.preview(actor)
	# The channels the gate this actor is trying to ENTER needs, and the state and
	# depth they must reach. Publishing them here means a screen can offer the
	# training action without reaching for the realm seed, which is a module
	# internal (ADR 0043).
	#
	# The gate is the NEXT realm's, because that is the one
	# `QiBreakthroughCondition` enforces (`breakthrough_condition.gd:10-11`) and the
	# one `target`, `can_attempt` and `unmet` in THIS SAME dictionary already
	# describe. It used to read the standing realm's own seed, which made this block
	# the only part of the read model describing a gate nothing checks — and the
	# screen acted on it, skipping every channel the standing realm's state already
	# satisfied. From the first realm whose demand is pure depth the button therefore
	# reported nothing owed while the real gate wanted another elixir, one realm's
	# worth of demand below the truth at every tier (ADR 0158's HANDOFF, closed).
	var required_channels: Array = []
	var required_state := ""
	var required_depth := 0
	var gate := _gate_for_next_realm(state)
	if gate != null:
		required_state = String(gate.required_channel_state)
		required_depth = gate.required_channel_refinement
		for meridian_id in gate.required_meridians:
			required_channels.append(String(meridian_id))
	var channels: Array[String] = []
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null:
			(
				channels
				. append(
					(
						"%s:%s/%d%s"
						% [
							def.id,
							channel.state,
							channel.refinement,
							"!" if channel.is_injured() else "",
						]
					)
				)
			)
	return {
		"realm": String(state.rank_id),
		"target": String(preview.get("target_realm", "")),
		"progress": float(state.progress),
		"qi": 0.0 if pool == null else pool.current,
		"qi_maximum": 0.0 if pool == null else pool.maximum,
		"dantian_quality": 0.0 if dantian == null else dantian.quality,
		"dantian_injured": dantian != null and dantian.injured,
		"channels": channels,
		"required_channels": required_channels,
		"required_channel_state": required_state,
		"required_channel_depth": required_depth,
		# What a training press would refuse, as DATA (ADR 0150): how many channels
		# the gate still wants, and the ROLE of the elixir that pays for them. A
		# screen that counted either had to reassemble `channel_met` out of the
		# ingredients above, which is the ADR 0044 preview/action divergence ADR 0158
		# rejected — and a reassembled gate is how this path lost its depth half
		# once already.
		"owed_channels": _owed_channels(actor, gate),
		"training_price": _training_price(actor, gate),
		# The catalyst's depth step, offered as DATA beside the gate's own price for
		# the same reason: a screen that recomputed either would reassemble the
		# verb's preconditions, which is the ADR 0044/0158 divergence this path has
		# already paid for once (ADR 0201, ADR 0202).
		"deepen_channels": _deepen_candidates(actor, state),
		"deepen_price": _deepen_price(state),
		# The Transcendent ascent, published so a screen can offer the action its
		# gate owes. DATA and not a verb: the walk itself is `WorldAnchor.ascend`, a
		# core entry point `ui/` may call directly (ADR 0041), so nothing here grows
		# the facade — the same split body and mind already publish it under.
		"ascent": _ascent_state(actor, _target_index(preview)),
		"can_attempt": bool(preview.get("can_attempt", false)),
		"chance": float(preview.get("chance", 0.0)),
		"unmet": preview.get("unmet_conditions", []),
		"costs": preview.get("costs", {}),
	}


## The seed of the realm this actor is trying to ENTER, or null at the top of the
## ladder. Every gate reported by `panel_state` reads this one seed, so the state,
## the depth, the channel list, the owed count and the price cannot describe two
## different realms.
static func _gate_for_next_realm(state: PathState) -> QiRealmSeed:
	var next_realm := RealmDefaults.ladder().next(state.rank_id)
	return null if next_realm == null else QiRealmSeed.for_realm(next_realm.id)


## The channels a training press may reach: EXACTLY the ones the gate names, and
## no others.
##
## One candidate list, shared with the verb. `QiTraining.train_next_channel` walks
## `gate.required_meridians` and nothing else, so a second, wider list here made
## `owed_channels` and `training_price` describe work the verb would never attempt:
## the tail it appended was a restatement of `MeridianDefaults.all()`, which
## `training.gd` refuses on purpose — a spare elixir spent deepening a channel the
## gate never asked for is charged at the realm's price for work the gate does not
## want (ADR 0095's rule that a gate must mean what it says).
##
## The two sets coincide at every one of the 29 boundaries today, so this is the
## latent half of BL-0757 closed rather than a behaviour change. It was not
## harmless: the day a seed named fewer channels than the standing realm unlocks,
## the screen would have printed "channel elixir absent; N channel(s) still owed"
## for a press that owes nothing — the one answer ADR 0150 rejects. A bounded
## `for` over the gate's own fixed array appending into a list it does not test the
## size of: no loop here grows its own bound (INC-0002).
static func _training_candidates(gate: QiRealmSeed) -> Array[StringName]:
	var out: Array[StringName] = []
	if gate == null:
		return out
	for meridian_id in gate.required_meridians:
		if not out.has(meridian_id):
			out.append(meridian_id)
	return out


## How many of those channels the gate still wants: state OR depth, read through
## `channel_met` — the one definition of the gate (ADR 0044/0158).
static func _owed_channels(actor: Actor, gate: QiRealmSeed) -> int:
	if gate == null:
		return 0
	var owed := 0
	for meridian_id in _training_candidates(gate):
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel != null and not gate.channel_met(channel):
			owed += 1
	return owed


## Which elixir pays for the first channel still owed, by ROLE and never by id (the
## ids are authored per realm in the seed, a module internal no screen may read).
## `training_item` walks a healthy channel; `recovery_item` closes a burned one,
## because `train_channel` hands a burn to `recover` — so the burn is the
## discriminator (ADR 0141). Empty when nothing is owed.
static func _training_price(actor: Actor, gate: QiRealmSeed) -> StringName:
	if gate == null:
		return &""
	for meridian_id in _training_candidates(gate):
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null or gate.channel_met(channel):
			continue
		return &"recovery_elixir" if channel.is_injured() else &"channel_elixir"
	return &""


## The channels `deepen_past_cap` would accept right now: the gate's own candidate
## list, narrowed by the catalyst step's preconditions. Published so a screen offers
## the action its gate owes instead of leaving a published verb with no caller
## (ADR 0201, ADR 0202).
##
## The CHANNELS come from the next realm's gate seed and the CAP from the STANDING
## realm's, because that is the split `QiTraining.deepen_past_cap` itself reads: it
## prices `QiRealmSeed.for_realm(state.rank_id)` while taking an explicit
## `meridian_id`. Reading one seed for both would offer work the verb refuses.
##
## The four refusals are the verb's, in its order: no catalyst authored for the
## standing realm, a burned channel (which is `recover`'s priced job, ADR 0141), a
## channel that is not yet STRENGTHENED (only one carries depth at all), and a
## channel still BELOW the cap — where the elixir is the price and this verb would be
## a cheaper route to a gate.
##
## `for` over a fixed array appending into a list it does not test the size of, so no
## loop here grows its own bound (INC-0002).
static func _deepen_candidates(actor: Actor, state: PathState) -> Array[StringName]:
	var out: Array[StringName] = []
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.meridian_catalyst == &"":
		return out
	for meridian_id in _training_candidates(_gate_for_next_realm(state)):
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null or channel.is_injured():
			continue
		if channel.state != MeridianState.STRENGTHENED:
			continue
		if channel.refinement < seed.channel_refinement_cap:
			continue
		out.append(meridian_id)
	return out


## The ROLE that pays for the catalyst step, by role and never by id — the ids are
## authored per realm in the seed, a module internal no screen may read (ADR 0043).
## Empty when the standing realm authors no catalyst, which is the answer a screen
## needs: there is nothing to offer, and saying so beats naming a price that is not
## for sale.
static func _deepen_price(state: PathState) -> StringName:
	var seed := QiRealmSeed.for_realm(state.rank_id)
	if seed == null or seed.meridian_catalyst == &"":
		return &""
	return &"meridian_catalyst"


## Ladder index of the realm this actor is trying to enter, or -1 when the ladder
## has none ahead of it. Read off the preview so the ascent report and the unmet
## list can never name two different targets.
static func _target_index(preview: Dictionary) -> int:
	var target := String(preview.get("target_realm", ""))
	if target.is_empty():
		return -1
	return RealmDefaults.ladder().index_of(StringName(target))


## How much of the Transcendent ascent this actor has left to walk, in the shape a
## screen renders a progress bar from. `required` is "is the ascent this actor's
## gate at all", which `ascension_ok` answers — true for every target at or below
## `WorldAnchor.COMMIT_MICRO`, so nothing here is conditional on the tier.
## `outstanding` is `WorldAnchor.ascension_unmet` verbatim (ADR 0034).
static func _ascent_state(actor: Actor, target_index: int) -> Dictionary:
	var remaining := 0
	if actor.ascension != null:
		remaining = actor.ascension.steps_remaining()
	return {
		"required": target_index > 0 and not Breakthrough.ascension_ok(actor, target_index),
		"steps": remaining,
		"steps_total": AscensionState.ASCENT_STEPS,
		"met": Breakthrough.ascension_ok(actor, target_index),
		"outstanding": WorldAnchor.ascension_unmet(actor),
	}


## Fill the qi pool toward the realm's fill requirement. The training verb the
## UI's Cultivate button drives, at a step size the caller supplies.
static func cultivate(actor: Actor, amount: float) -> bool:
	return QiTraining.cultivate(actor, amount)


## Roll the breakthrough attempt. A deviation is recoverable; recover and retry.
##
## **The body answers first (ADR 0109).** A qi path the actor's race closes, or a realm above its
## authored `realm_ceiling`, is refused BEFORE the roll. This facade does NOT ask
## `RaceGate` itself: the refusal lives in `QiBreakthroughTransaction.execute`, the one
## call every qi entry point makes, so `QiAdvancement.try_breakthrough` cannot reach a
## qi realm a caller of this facade could not. The refusal carries `RaceGate`'s own
## `{kind, id, required, actual, label}` entries so the breakthrough screen can name
## the closed path or the ceiling it hit, which is the ADR 0034 rule that a gate and
## its preview must be the same wording. It is a precondition and never a modifier: a
## race can stop a breakthrough, never make one easier.
##
## ## DEF-0106: this is the qi path's SECOND earn site, and it is not optional
##
## `ui/screens/qi_cultivation_screen.gd:275` calls THIS verb, not
## `QiAdvancement.try_breakthrough` — the same shape as `mind_cultivation_ui.gd`
## calling `MindAdvancement` directly, and the same reason the ADR 0109 gate above is
## stated to live in the transaction. So a fate earn living only on `QiAdvancement`
## would leave the player's own Breakthrough button earning nothing, which is the
## UNWIRED failure this entry exists to close rather than a second copy of one.
##
## It calls `QiAdvancement`'s earn rather than restating it, because the fate id and
## its source string are `QiAdvancement`'s to publish (DEF-0105's rule about a source
## naming the system, not the fate, has one home per path) and `earn_fate` is
## exactly-once, so the two sites cannot pay the same breakthrough twice even if a
## caller reaches both.
static func attempt_breakthrough(actor: Actor) -> bool:
	if not QiBreakthroughTransaction.execute(actor, null):
		return false
	QiAdvancement.earn_breakthrough_oath(actor)
	return true


## Raise comprehension. The only route to a realm's `comprehension_required`
## floor, so a qi path cannot advance without it.
static func meditate(actor: Actor, amount: float) -> bool:
	return QiTraining.meditate(actor, amount)


## Train one channel toward the realm's required state and depth. The qi
## breakthrough gate demands specific channels reach `required_channel_state` AND
## `required_channel_refinement`, and `cultivate` never touches meridians, so
## without this a qi actor cannot satisfy its own gate. Spends the realm's
## `training_item`, and refuses without spending it once the channel has nothing
## left to learn at this realm's cap.
static func train_channel(actor: Actor, meridian_id: StringName) -> bool:
	return QiTraining.train_channel(actor, meridian_id)


## One step of depth PAST the standing realm's `channel_refinement_cap`, spending the
## realm's `meridian_catalyst` instead of its channel elixir.
##
## A ninth public method, against a cap of 12. It is a separate verb rather than a mode
## flag on `train_channel` because the two prices are different CURRENCIES for
## different work — an elixir walks the gate, a catalyst buys the one step past the cap
## that no elixir can reach — and one verb with two currencies would make a press's cost
## depend on the channel's depth, which the caller can read, rather than on its own
## intent. ADR 0201, ADR 0202.
static func deepen_past_cap(actor: Actor, meridian_id: StringName) -> bool:
	return QiTraining.deepen_past_cap(actor, meridian_id)


## Train the first channel that still owes the NEXT realm's gate — state or depth
## — and return its id, or `&""` when nothing is owed or no elixir is in hand.
##
## Why this is a verb and not two published predicates: a caller that picked its
## own channel had to reassemble `QiRealmSeed.channel_met` from `panel_state`'s
## ingredients, and a reassembled gate is the ADR 0044 defect — a preview and the
## action it previews disagreeing — which this path already paid for once. A
## screen owns presentation, not which channel is next.
static func train_next_channel(actor: Actor) -> StringName:
	return QiTraining.train_next_channel(actor)


## Close the first wound a recovery item can heal: the dantian scar, then the
## burned channel. Consumes the realm's `recovery_item` (ADR 0031).
static func recover_next(actor: Actor) -> bool:
	var dantian := QiAccess.dantian(actor)
	if dantian != null and dantian.injured:
		for def in MeridianDefaults.all():
			if QiTraining.recover(actor, def.id):
				return true
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null and channel.is_injured() and QiTraining.recover(actor, def.id):
			return true
	return false


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, QiStats.QI, true)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
