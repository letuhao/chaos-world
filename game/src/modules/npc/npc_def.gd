class_name NpcDef
extends Resource

## An authored INDIVIDUAL (ADR 0077). `WorldInhabitantDef` is the species — a bear; this
## is Bearcutter Lao, the smith who owes you a debt and will remember it.
##
## The split matters: a species is spawnable population and is owned by `world`, while an
## individual is a cast member with a tier, a stage ladder and a roster entry. One def for
## both would force a species to carry a stage ladder it has no use for.
##
## **Tiers are data, not behaviour.** `tier` answers only "is this one remembered"; what
## it does in a room is read from `stages` and `tags`, never from an `if tier == major`.

## The stable identity across saves. The roster keys on this, never on a display name.
@export var npc_id: StringName = &""

@export var display_name: String = ""

## The species this individual is built from. The module never names `WorldInhabitantDef`
## (that is `world`'s type); it records the id and `app/` resolves it, so `npc` never
## declares a dependency on `world`.
@export var inhabitant_id: StringName = &""

## The authored tier. An untracked def has no roster entry and leaves no trace.
@export var tier: StringName = NpcTier.DEFAULT

@export var faction: StringName = &""
@export var tags: Array[StringName] = []

## The realm the individual starts at, so a rival cultivator is a rival *cultivator* and
## not a mob with a name. Authored, exactly as a boss seed authors its realm (ADR 0074).
@export var realm_id: StringName = &""

## Base attributes for this individual, before any realm or stage scale. An empty map
## falls back to the species'.
@export var base: Dictionary = {}

## The stage ladder, authored in order.
@export var stages: Array[NpcStageDef] = []

## Where this individual starts. Must be a stage this def declares, or the first one.
@export var initial_stage: StringName = &""

## ## The alive layer's four authored halves (ADR 0253)
##
## All four are optional, and ALL FOUR are read through the tier policy rather than
## branched on in a mechanism: a tracked def that authors none still spawns, still has a
## stage ladder and still remembers the player. The alive layer is an ADDITION to ADR
## 0092's tier question, not a replacement for it.
##
## **A `minor`/`transient` def that authors any of these pays for it with a per-npc
## asset loaded while nobody is looking at that npc**, which is what the lazy principle
## forbids — so the untracked tiers are composed by `NpcMinorComposer` instead, and
## `tests/modules/npc/test_npc_alive.gd` is what keeps an author from quietly paying that
## bill on a tier whose whole promise is that it costs nothing.

## ## THE AUTHORED SUITOR CANDIDATE (ADR 0256)
##
## A pursuit feature with no cast member to pursue is a mechanism, and the owner's headline
## — "an NPC pursues the player because she is a beautiful fairy, or has a special body, or
## her clan is rich" — is only true of somebody who actually exists. So the pursuit ships
## ONE tracked suitor, authored at the `major` rung so he persists and can therefore be
## courted, refused and answered over a real career rather than a single conversation.
##
## ### Why `major` and not `story`
##
## A `story` tier is the property of narrative beats, and that suitor has none yet. He is
## the standing candidate: present, remembered, and reachable by a player who builds a bond
## with him. `NpcTier.TRACKED` is what `PursuitStance.PERSISTENT_TIERS` names, so authoring
## him `major` is what makes a claim on him legal at all.
##
## ### The tag the content guard reads
##
## `courts` is the marker. Nothing in the mechanism branches on it — the pursuit path reads
## the tier and the ledger, never a tag — so an author can add a suitor by adding this one
## tag, and a content audit can walk `game/data/npc/cast/` for it without reading code.
## `game/data/npc/cast/courting_elder_bo.tres` is the authored suitor this paragraph is
## about; it carries that tag on `tags` and on every one of its three stages.

## ## (1) THE DAILY ROUND — where they are when you are not looking
##
## Authored slots, resolved against the LAZY clock: nothing here moves until somebody
## reads, and the read is the trigger (ADR 0173(c)).
##
## A round that only happens in public has no private beats, so a def that wants to be
## courted alone authors places that can be APPROACHED: two of a suitor's three slots are
## locations he occupies alone rather than a room he is found in.
@export var daily_round: Array[NpcRoundDef] = []

## ## (2) WHAT THEY BELIEVE — including about other npcs
##
## An opinion is authored, and it may be about ANOTHER npc, which is the point: two people
## in the same sect may hold opposite positions about the man who teaches both of them, and
## the closed half of a row is the STANCE rather than the subject. See `elder_wei.tres`.
@export var opinions: Array[NpcOpinionDef] = []

## ## (3) WHAT THEY REMEMBER — authored prose keyed to the real cause id
##
## `NpcRecallDef.cause_id` is the source of truth and the prose renders it. There is no
## number here at all.
##
## A row is reachable only because its `cause_id` is genuinely ON the bond, so a player who
## spared somebody never sees that recall fire and should not: the ledger stays the only
## record and the prose is a rendering of it (ADR 0091 / ADR 0253).
@export var recalls: Array[NpcRecallDef] = []

## ## (4) THE BODY — what they do on approach
##
## Tells key on the bond CLASS — a word — rather than on an impression value: a tell whose
## `matches` were an impression number would be that number wearing a costume, and the
## player's view is a word plus behavioural tells, never a bare score (ADR 0256 decision 3).
## The impression reaches the player only as the word `PursuitStance.read` publishes.
##
## A ladder is authored as one tell per rung of the SAME relationship — the plain nod, then
## a reason to keep talking, then the rung where the performance stops — and `priority` is
## authored so the ordering is content rather than array order.
@export var tells: Array[NpcTellDef] = []

## ## The authored SOCIAL GATE this npc's behaviour consults (ADR 0264)
##
## **A plain `Dictionary`, never a `Resource` and never a number.** Two reasons, both
## load-bearing:
##
##   1. **It is a requirement, not a stat.** ADR 0076: "a gate reads the ledger, never a
##      derived stat" — a stat can be satisfied by a pill or an item, so a gate that reads one
##      is a gate the player can buy. So this names a *threshold* against `social`'s own
##      ledger and `npc/` never interprets a verb.
##   2. **A dictionary serializes inside a placement without a value object** (ADR 0076's own
##      sentence), and an unknown verb **refuses closed and names itself** rather than quietly
##      unlocking content — a typo in an authored `.tres` fails loudly.
##
## The vocabulary is `SocialGate.VERBS` exactly, and the reader is injected
## (`NpcGates.set_social_gate`), so `npc/` gains no dependency on `social/` for this.
##
## **Empty means ungated**, and an ungated def is the overwhelmingly common case: the gate is
## evaluated nowhere and the behaviour is byte-identical to today's. That is why the
## counterpart `NpcGates.WARMTH_NEUTRAL` is the default rather than a value this file
## computes.
@export var social_gate: Dictionary = {}

## The tuned magnitude a composed MINOR persona is built at, 0..100. **Read only for the
## tiers that compose** (`minor`, `transient`): a tracked def's `base` is the authored
## scale and this is never consulted for it, so this cannot become a second magnitude
## ladder (ADR 0050). See `NpcMinorComposer`.
@export_range(0.0, 100.0, 0.1) var minor_power_scale: float = 0.0


## The four authored halves as a digest, so a content guard can walk the cast without
## reaching into five arrays. One place, so a missing round and a missing opinion list
## cannot disagree about being empty.
func alive_digest() -> Dictionary:
	return {
		"tier": String(normalized_tier()),
		"round_slots": daily_round.size(),
		"opinions": opinions.size(),
		"recalls": recalls.size(),
		"tells": tells.size(),
		"power_scale": minor_power_scale,
	}


## ## The custody term this individual may be TAKEN on (ADR 0247)
##
## An empty `capture_term` means **this individual is not capturable at all** — not "capturable
## with a default". So capturability is CONTENT, and a cast that authors no term ships a custody
## page whose primary verb has nothing to press rather than a free grab with no cause.
##
## It is a TERM and a COUNT OF PERIODS, exactly as ADR 0104 defines a custody claim, and never a
## price: there is no `RARITY_WEIGHT` on a person and no realm scaling behind these two fields.
## Mechanical and clinical, like every other field on this def.
@export var capture_term: StringName = &""

## The periods this individual is owed when taken. Zero falls back to a single authored period
## at the seam, so a half-authored term is a one-period claim and fails as `no_terms` rather than
## as a capture with no term at all.
@export var capture_periods: int = 0

## ## The daily round's lookups — by AUTHORED INDEX, resolved by an elapsed span
##
## There is deliberately **no `round_slot_of_period(period)`**. A slot is addressed by its
## authored `index` and the caller converts an elapsed span with `TimeLadder`, which then
## divides by `round_slot_ratio_periods` (ADR 0173(a)). Keeping the conversion on the clock
## side is why no slot carries a duration: ADR 0178 says a daypart carries no ratio, and a
## local copy of one is the exact duplication ADR 0173's source-reading guard names.

## The authored ratio of one whole slot in periods, for this def's round. The caller
## authors a ratio because a per-npc day length is CONTENT; the conversion itself is
## `TimeLadder`'s. Zero means this def ships no round at all, which is a real state and
## not an error.
@export var round_slot_ratio_periods: int = 0


## Whether this individual may be taken at all: a def authors a custody term, or it is not
## capturable. One question, one conjunction, so nothing can be capturable by accident.
func capturable() -> bool:
	return capture_term != &""


## This def's capture beat as primitives, or `{}` when it is not capturable. The shape is
## `{term_id, periods}` and nothing else — no prose field, because ADR 0104's rule that a custody
## record carries no `description`, `flavor` or `display_name` holds on the AUTHORED side too.
func capture_term_row() -> Dictionary:
	if not capturable():
		return {}
	return {"term_id": String(capture_term), "periods": maxi(1, capture_periods)}


func tracked() -> bool:
	return NpcTier.is_tracked(NpcTier.normalize(tier))


func normalized_tier() -> StringName:
	return NpcTier.normalize(tier)


## The stage def for `stage_id`, or null. Null rather than a guess: a gate that silently
## fell through to the first stage would let a half-authored def open everything.
func stage(stage_id: StringName) -> NpcStageDef:
	for stage_def in stages:
		if stage_def.stage_id == stage_id:
			return stage_def
	return null


func stage_index_of(stage_id: StringName) -> int:
	for stage_def in stages:
		if stage_def.stage_id == stage_id:
			return stage_def.index
	return -1


## The stage this individual is born at, resolving an unset `initial_stage` to the first
## authored stage.
func starting_stage_id() -> StringName:
	if initial_stage != &"" and stage(initial_stage) != null:
		return initial_stage
	if stages.is_empty():
		return &""
	return stages[0].stage_id


## The stage that follows `stage_id`, or an empty id when this is the end of the ladder.
## One step, never a loop: a caller walks the ladder or stops.
func next_stage_id(stage_id: StringName) -> StringName:
	var current := stage_index_of(stage_id)
	if current < 0:
		return starting_stage_id()
	for stage_def in stages:
		if stage_def.index > current:
			return stage_def.stage_id
	return &""


func stage_count() -> int:
	return stages.size()


## ## The slot whose authored `index` contains `period` within the round, or null. **One
## division and one scan of the authored slots** — `O(slots)`, and `slots` is an authored
## row count rather than anything the span can grow (ADR 0173(b)).
func round_slot_of(period: int) -> NpcRoundDef:
	if round_slot_ratio_periods <= 0 or daily_round.is_empty():
		return null
	if period < 0:
		return null
	var slot := (period / round_slot_ratio_periods) % daily_round.size()
	for round_def in daily_round:
		if round_def.index == slot:
			return round_def
	return null


## The authored slots of this def's round, newest-index last. The read returns them in
## AUTHORED order so a caller reading the whole round twice gets the same list.
func round_slots() -> Array[NpcRoundDef]:
	var out: Array[NpcRoundDef] = []
	for round_def in daily_round:
		out.append(round_def)
	return out


## The first authored recall whose `cause_id` is `cause_id`, or null. The lookup every
## read goes through, so "the incident" is one answer rather than a scan a caller repeats.
func recall_for_cause(cause_id: StringName) -> NpcRecallDef:
	for recall_def in recalls:
		if recall_def.cause_id == cause_id:
			return recall_def
	return null
