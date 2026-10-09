class_name BodyRefusal
extends RefCounted

## Named refusals for every player-facing body verb (ADR 0150).
##
## A `false` from a body verb used to be one bit the screen turned into one sentence, so
## four distinct refusals read as one: a hero with a torn channel and no recovery elixir was
## told "Nothing damaged to repair" while the same screen's gate line, read from the same
## `panel_state`, said `Damaged channels need repair: lung`. The screen contradicted itself
## on the fail-recoverably leg of the acceptance gate and named the real cause nowhere.
##
## A refusal a player can reach is published as named data on the read model, and the screen
## renders the name. Every entry is `{kind, id, required, actual, label}` — the shape
## `RaceGate.unmet()` already produces, so a panel renders a reason it did not have to invent and
## `RaceGate`'s own entries carry through verbatim.
##
## WHY HERE AND NOT A NEW VERB: `BodyCultivationApi` sits at
## `rules.MAX_FACADE_PUBLIC_METHODS`, and the repo already answered the alternative at
## `app/institution_resolver.gd:100-104` — fold the work into the read model rather than
## widen the surface. WHY NOT FOUR `else` BRANCHES IN THE SCREEN: it is handed a `bool`
## and cannot know which cause fired, and guessing from `unmet` re-derives the truth
## inside the UI program (ADR 0034).
##
## **ONE RULE, TWO READERS.** Nothing here is a second copy of a refusal rule: each report
## asks the same predicates its verb asks, so the read model and the verb cannot disagree.
## What the reports add is only the NAME. They are PURE: `panel_state` calls them on every
## repaint, and a read model that consumed would be an action in disguise.
##

const _ITEMS := preload("res://src/modules/items/api.gd")

## The verbs a refusal is published for: the keys `panel_state` publishes under
## `unavailable`, and the names a screen asks them by.
const VERB_CULTIVATE := "cultivate"
const VERB_RECOVER := "recover"
const VERB_STRENGTHEN := "strengthen"
const VERB_BREAKTHROUGH := "breakthrough"

## Clause kinds. One constant per distinct cause, because a kind a screen cannot tell
## apart is a kind it cannot render: the collapse this file exists to remove was four
## causes sharing one sentence, not two sentences sharing one word.
const KIND_NO_BODY_PATH := "no_body_path"
## `AcupointSet.busy`: a body action is mid-mutation. Defensive today — every window that sets it
## is synchronous — and published anyway, because a report that went silent here is exactly the
## unnamed `false` this file exists to prevent.
const KIND_BUSY := "huyet_set_busy"
## No `AcupointSet` is attached, so the verbs acting on acupoint have nothing to act.
const KIND_NO_HUYETS := "no_huyet_set"
## Every acupoint is jammed: a real player-reachable state, and one `cultivate` refuses on,
## because a deviation jams a acupoint and nothing heals it but the recovery verb.
const KIND_NO_OPEN_HUYETS := "no_open_huyet"
## The realm has no authored `BodyRealmSeed`. A content gap, named as one.
const KIND_NO_REALM_SEED := "realm_seed_unauthored"
## Nothing is damaged, so there is nothing for the recovery elixir to close.
const KIND_NO_DAMAGE := "no_damage"
## The realm authors no `recovery_item` at all — distinct from the elixir being absent from
## the pack, because one is a purchase and the other is a content gap.
const KIND_RECOVERY_ITEM_UNAUTHORED := "recovery_item_unauthored"
## A wound is present and the recovery elixir is not held.
const KIND_NO_RECOVERY_ITEM := "no_recovery_item"
## A channel is trainable and the realm's channel elixir is not held.
const KIND_NO_CHANNEL_ELIXIR := "no_channel_elixir"
## The channel is at this realm's refinement ceiling and its acupoint are trained to target, so
## training it would buy nothing. `id` names the channel.
const KIND_CHANNEL_AT_CAP := "channel_at_cap"
## The seed names a channel no tier has opened. `id` names it.
const KIND_CHANNEL_UNKNOWN := "channel_unknown"
## A durable attempt is already committed, so a second cannot start.
const KIND_ATTEMPT_IN_FLIGHT := "attempt_in_flight"
## The ladder has no realm ahead of this one.
const KIND_NO_REALM_AHEAD := "no_realm_ahead"
## One clause of `preview.unmet`, carried verbatim, so the message line and the gate line
## cannot disagree about why.
const KIND_GATE_UNMET := "gate_unmet"

## The one shared sentence, so a guard can tell "a recovery is in progress" from "the recovery
## verb is unavailable" without matching on prose.
const BUSY_LABEL := "LOC_BODY_CULTIVATION_F951B2AB18"


## Why `cultivate` cannot take a training step right now.
static func cultivate_unavailable(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state := _body_state(actor)
	if state == null:
		return out
	if _busy(actor):
		out.append(_clause(KIND_BUSY, &"", BUSY_LABEL))
		return out
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null:
		out.append(_clause(KIND_NO_HUYETS, &"", "No acupoint set is attached to this body"))
		return out
	if points.open_count() == 0:
		out.append(
			_clause(KIND_NO_OPEN_HUYETS, &"", "Every acupoint is jammed; recover before training")
		)
		return out
	_add_seed_clause(out, state.rank_id)
	return out


## Why `recover_next` cannot repair anything right now.
##
## **THE CONTRACT THIS EXISTS FOR.** A refusal with a wound present has exactly one
## remaining cause — the elixir — because a jam or a tear is a wound the recovery
## elixir exists to close. So `KIND_NO_DAMAGE` and `KIND_NO_RECOVERY_ITEM` are
## DISJOINT BY CONSTRUCTION: the first is published only when
## `recovery_candidates()` is empty, the second only when it is not. Collapsing both
## into "Nothing damaged to repair" is what made the screen deny its own gate line.
static func recover_unavailable(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state := _body_state(actor)
	if state == null:
		return out
	if _busy(actor):
		out.append(_clause(KIND_BUSY, &"", BUSY_LABEL))
		return out
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	if seed == null:
		_add_seed_clause(out, state.rank_id)
		return out
	if seed.recovery_item == &"":
		out.append(
			_clause(
				KIND_RECOVERY_ITEM_UNAUTHORED,
				state.rank_id,
				"This realm authors no recovery elixir"
			)
		)
		return out
	if recovery_candidates(actor).is_empty():
		# The sentence this screen used to print for BOTH causes, now published only
		# where it is true.
		out.append(_clause(KIND_NO_DAMAGE, &"", "Nothing damaged to repair"))
		return out
	if not _ITEMS.has_item(actor, seed.recovery_item):
		out.append(
			_clause(KIND_NO_RECOVERY_ITEM, seed.recovery_item, "No recovery elixir to spend")
		)
	return out


## The meridians `recover_next` would try, in the order it tries them: a blocked
## acupoint's channel first (it names its own channel), then any injured channel.
##
## THE WALK `BodyCultivationApi.recover_next` PERFORMS, in one definition. Were these
## two lists to disagree, the screen would report a cause the verb never hit, which is
## worse than the silence this replaced — so the facade walks THIS list.
##
## Bounded by authored content: `points.points` and `MeridianDefaults.all()` are both
## fixed lists and the loop tests neither. `not out.has()` deduplicates rather than
## growing anything.
static func recovery_candidates(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null:
		return out
	var points: AcupointSet = actor.component(&"acupoints")
	if points != null:
		for point in points.points:
			if not point.blocked:
				continue
			var meridian_id := AcupointDefaults.meridian_of(point.id)
			if meridian_id != &"" and not out.has(meridian_id):
				out.append(meridian_id)
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel != null and channel.is_injured() and not out.has(def.id):
			out.append(def.id)
	return out


## Why `strengthen_next` cannot train a channel right now.
##
## **A UNION, AND THAT IS NOT A WEAKNESS.** `strengthen_next` walks its candidates and
## returns true on the first that trains, so a refusal means EVERY candidate refused —
## and each may have refused for a different reason. The honest answer is every reason,
## deduplicated by `(kind, id)`, which is why two global prices can both appear and why
## a per-channel cap appears once per channel.
##
## The consequence a consumer must know: a NON-EMPTY list does NOT mean the verb will
## refuse. One capped channel and one trainable channel both appear, and the verb
## succeeds on the second. The direction that IS guaranteed — and that ADR 0150 needs
## — is asserted by `tests/modules/body_cultivation/test_refusal_naming.gd`: **a
## `false` always has a name.**
##
## A burn is priced by the realm's RECOVERY elixir (ADR 0141), so an injured candidate
## asks for that item and not the channel elixir. That is why
## `KIND_NO_CHANNEL_ELIXIR` is never emitted for a burn: it used to be the one answer
## that could not be true in the state a torn channel puts a player in.
static func strengthen_unavailable(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state := _body_state(actor)
	if state == null:
		return out
	if _busy(actor):
		out.append(_clause(KIND_BUSY, &"", BUSY_LABEL))
		return out
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null:
		out.append(_clause(KIND_NO_HUYETS, &"", "No acupoint set is attached to this body"))
		return out
	var seed := BodyRealmSeed.for_realm(state.rank_id)
	if seed == null:
		_add_seed_clause(out, state.rank_id)
		return out
	var wants_recovery := false
	var wants_channel := false
	for meridian_id in BodyTraining.strengthen_candidates(actor):
		if not _on_this_body(actor, state.rank_id, meridian_id):
			# `BodyTraining.strengthen` unlocks the realm's channels before looking one
			# up, so this is only reachable when the seed names a channel no tier has
			# opened — an authoring gap, named rather than silently skipped into a "no
			# elixir" the player does not owe.
			_add(
				out,
				KIND_CHANNEL_UNKNOWN,
				meridian_id,
				"No %s channel is on this body" % meridian_id
			)
			continue
		var channel := actor.meridians.get_meridian(meridian_id)
		# `_on_this_body` above proves the SEED names a channel this tier opens, which is
		# a rank claim and not a dictionary one: `Dictionary.get` answers null for an id
		# the network does not hold, so a seed naming a channel no tier materialised
		# reaches `is_injured()` on null. Named rather than skipped, same as KIND_CHANNEL_
		# UNKNOWN above - a missing channel is an authoring gap, not an absent clause.
		if channel == null:
			_add(
				out,
				KIND_CHANNEL_UNKNOWN,
				meridian_id,
				"No %s channel is on this body" % meridian_id
			)
			continue
		if channel.is_injured():
			wants_recovery = true
			continue
		if (
			BodyTraining.at_channel_cap(channel, seed)
			and not BodyTraining.needs_point_training(points, meridian_id, seed.quality_target)
		):
			_add(
				out,
				KIND_CHANNEL_AT_CAP,
				meridian_id,
				"The %s channel is already at this realm's depth" % meridian_id
			)
			continue
		wants_channel = true
	if wants_recovery and not _ITEMS.has_item(actor, seed.recovery_item):
		out.append(
			_clause(KIND_NO_RECOVERY_ITEM, seed.recovery_item, "No recovery elixir to spend")
		)
	if wants_channel and not _ITEMS.has_item(actor, seed.strengthening_item):
		out.append(
			_clause(KIND_NO_CHANNEL_ELIXIR, seed.strengthening_item, "No channel elixir to spend")
		)
	return out


## Why `attempt_breakthrough` cannot COMMIT an attempt right now — every clause in the
## order `BodyAdvancement._start` checks them, and never one it does not check.
##
## ## What is NOT here, and why it matters
##
## The TIER GATES appear in `unmet` and are deliberately absent here.
## `try_breakthrough` commits an attempt first and only then re-checks
## `Breakthrough.tier_gates_met` inside `resolve_attempt`, CANCELLING rather than
## refusing — so a shut tribulation gate is not a cause this press was refused for, and
## publishing it here would blame a player for a gate they had not reached. That
## cancellation is named where it belongs, by the record, in `attempt_outcome`.
##
## ## The one clause `unmet` does not carry
##
## `_start`'s `consume_item` refusal looks like a fifth cause and is not:
## `describe_unmet` already lists "Missing breakthrough pill", so the missing pill is
## refused as `KIND_GATE_UNMET` in the gate's own words, and the consume is reachable
## only if the item vanishes between two synchronous reads.
static func breakthrough_unavailable(actor: Actor, unmet: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# The body answers first (ADR 0109), and `RaceGate` already names itself: its
	# `{kind, id, required, actual, label}` entries are carried through verbatim rather
	# than re-worded, so the screen quotes the same sentence the race gate shows
	# anywhere else.
	out.append_array(RaceGate.path_unmet(actor, PathState.BODY))
	out.append_array(RaceGate.realm_ceiling_unmet(actor))
	if not out.is_empty():
		return out
	var state := _body_state(actor)
	if state == null:
		return out
	if _busy(actor):
		out.append(_clause(KIND_BUSY, &"", BUSY_LABEL))
		return out
	var active := BodyAdvancement.active_attempt(actor)
	if active != null:
		out.append(
			_clause(
				KIND_ATTEMPT_IN_FLIGHT,
				active.attempt_id,
				"An attempt into %s is already committed; resolve it first" % active.target_rank
			)
		)
		return out
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		out.append(_clause(KIND_NO_REALM_AHEAD, &"", "Already at the highest realm"))
		return out
	if BodyRealmSeed.for_realm(target.id) == null:
		out.append(
			_clause(KIND_NO_REALM_SEED, target.id, "No body seed is authored for %s" % target.id)
		)
		return out
	for clause in unmet:
		out.append(_clause(KIND_GATE_UNMET, &"", String(clause)))
	return out


## What the actor's last resolved attempt BECAME, as one named verdict.
##
## The roll is not knowable before it happens, so it cannot live in `unavailable`: a
## breakthrough press either is blocked by a named clause or reaches the roll, and only
## the record can say what the roll produced. This is that verdict, published beside
## the refusal list so a screen can render it instead of assuming "deviated" from a
## `false` — which is what every refusal used to read as.
##
## `reason` is "" whenever the record has not resolved or resolved as a success. A
## consumer finding both the clause list and this empty has a `false` no read model
## names, which is a FINDING to report and never a sentence to invent (ADR 0150).
static func attempt_outcome(actor: Actor) -> Dictionary:
	var record := BodyAdvancement.attempt(actor) if actor != null else null
	if record == null:
		return {"id": "", "status": "", "granted": false, "target": "", "reason": ""}
	return {
		"id": String(record.attempt_id),
		"status": String(record.status),
		"granted": bool(record.outcome_granted),
		"target": String(record.target_rank),
		"reason": _outcome_reason(record),
	}


## The module's own sentence for a record that resolved without an award. Two distinct
## endings, and the difference is one a player acts on: a deviation owes a wound to
## repair, a cancellation owes nothing because nothing was ever rolled.
static func _outcome_reason(record: BodyAttempt) -> String:
	if record == null or record.outcome_granted:
		return ""
	if record.status == BodyAttempt.STATUS_FAILED:
		return (
			"The attempt into %s deviated; repair the wound before trying again"
			% record.target_rank
		)
	if record.status == BodyAttempt.STATUS_CANCELLED:
		return L.t("LOC_BODY_CULTIVATION_477ACEAC8C") % record.target_rank
	return ""


# --- Internals ---------------------------------------------------------------


## The clause shape every entry shares, and the one `RaceGate` already produces.
##
## `required`/`actual` are the house slots. A refusal is always a requirement that does
## not hold, so both are constants here rather than per-clause data: nothing about a
## refusal is a threshold a screen could compare against. The literal carries NO interior
## comment — a comment between two entries of a multi-line dictionary literal is the one
## place a stray token can cost a reader a key without any error, and `label` is the key
## every screen renders.
static func _clause(kind: String, id: StringName, label: String) -> Dictionary:
	var clause := {
		"kind": kind,
		"id": String(id),
		"required": true,
		"actual": false,
		"label": label,
	}
	return clause


static func _add_seed_clause(out: Array[Dictionary], realm_id: StringName) -> void:
	out.append(_clause(KIND_NO_REALM_SEED, realm_id, "No body seed is authored for %s" % realm_id))


## Append unless this `(kind, id)` is already listed, so the union `strengthen` needs
## stays one entry per cause instead of one per candidate.
static func _add(out: Array[Dictionary], kind: String, id: StringName, label: String) -> void:
	for entry in out:
		if String(entry.get("kind", "")) == kind and String(entry.get("id", "")) == String(id):
			return
	out.append(_clause(kind, id, label))


static func _body_state(actor: Actor) -> PathState:
	if actor == null:
		return null
	return actor.path(BodyPath.PATH_ID)


static func _busy(actor: Actor) -> bool:
	var points: AcupointSet = actor.component(&"acupoints")
	return points != null and points.busy


## Whether `meridian_id` is on this body once `BodyTraining.strengthen` has done its own
## unlock — computed WITHOUT unlocking, because a report that mutated would make `panel_state`
## an action. `unlock_for_realm` opens every meridian whose `tier` is at or below the realm's
## ladder index, so that comparison is the rule; `get_meridian` is checked first.
static func _on_this_body(actor: Actor, realm_id: StringName, meridian_id: StringName) -> bool:
	if actor.meridians.get_meridian(meridian_id) != null:
		return true
	var realm_index := RealmDefaults.ladder().index_of(realm_id)
	for def in MeridianDefaults.all():
		if def.id == meridian_id and def.tier <= realm_index:
			return true
	return false
