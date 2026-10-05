class_name NpcAliveness
extends RefCounted

## THE ALIVE LAYER's four capabilities, read through the lazy clock (ADR 0253).
##
## ## ## The shape of this file, and why it is a collaborator and not a thirteenth verb
##
## `NpcApi` sits at exactly twelve public methods (`rules.MAX_FACADE_PUBLIC_METHODS`,
## and `tools arch` FAILS at thirteen), so the alive layer lives here and `NpcApi` carries
## ONE underscore-prefixed delegate. Four capabilities cannot be four verbs.
##
## ## ## THE CLOCK (1): NOTHING TICKS WHILE NOBODY IS THERE
##
## The daily round is `O(1)` against a stored stamp, exactly as ADR 0173(c) describes a
## place's advance, and **the read IS the advance** — `sync` is called FIRST and the
## answer is read from what it left behind. There is no `if someone_is_here: advance()`
## anywhere in this file, and that is the deadlock hazard ADR 0173(c) names: a clock whose
## every trigger is gated on an observer freezes silently, returning zero forever.
##
## ## ## THE COST COUNTERS ARE THE POINT OF THE FILE
##
## `composes` and `round_syncs` are not instrumentation. They are the MEASUREMENT the
## design claims, and they are what a test asserts rather than a comment: **an unobserved
## minor npc costs 0 and an unobserved major costs a constant, not O(cast)**. A design that
## says "cheap" and cannot be asked what it cost has not made the claim.

## The `npc` facade, preloaded. Reached for exactly two verbs — `state` and `summary` —
## because the bond ledger is `social`'s to publish and the roster is ours
## (ADR 0091's anti-farm rule stays: nothing here writes a cause).
const SOCIAL_FACADE := preload("res://src/modules/social/api.gd")

## ## How much of a bond's authored prose one read may render.
##
## An npc who has met the player forty times has forty causes and no more than
## [constant MAX_MEMORY_ROWS] sentences about them, because a panel is not a diary and a
## save is not a log. The surplus is REPORTED (`dropped`), never silently swallowed —
## and it is not a truncation of a *world event*, so "N of M" is the honest shape here in
## the way `RowBudget` uses it, rather than ADR 0173(b)'s refusal (that rule is about
## events a ledger cannot un-record; a rendered line can be asked for again).
const MAX_MEMORY_ROWS := 4

## ## How many npcs one gossip pass may reach.
##
## **This is the named constant ADR 0173(b) is the precedent for**, and it bounds the
## work of ONE advance: a hop count, not a loop over the cast, so a settlement of four
## hundred tracked npcs costs this many and not four hundred. News dies at the bound
## rather than being delivered to everybody, which is what makes it gossip.
const MAX_GOSSIP_NPCS := 8

## ## How many periods one sync may convert at all.
##
## `TimeLadder` truncates per magnitude and DROPS the surplus (ADR 0173(a)), so the
## conversion is already bounded; this is the second belt on the same property, and it
## exists so a caller cannot pass a span large enough to make anything downstream
## `O(elapsed)`. A span past it is CLAMPED and the clamp is reported — this is a
## presentation round, not a world event, so refusing it would refuse the player a look.
const MAX_SYNC_SPAN_PERIODS := 4380

## The most opinions one read renders, for a panel and not a diary. Separate from
## [constant MAX_MEMORY_ROWS] because an opinion is a STANDING VIEW rather than an event,
## and a cast member plausibly holds more views than grievances.
const MAX_OPINION_ROWS := 4

## The body an npc wears when no authored tell fires. A real reaction, never an empty row:
## an npc with no opinion of you still nods, and refusing to answer would make an
## unauthored cast look broken rather than neutral.
const DEFAULT_TELL_VERB := &"nods_once"
const DEFAULT_TELL_BODY := "nods once and goes back to what they were doing"
const DEFAULT_TELL_CONSEQUENCE := &"neutral"

## The `last_synced` stamps, keyed by npc id. A `static var` because the clock is
## process-wide (`NpcEvents.shared()` is too) and a per-instance sink would have to be
## kept alive by somebody to be worth anything.
static var _last_synced: Dictionary = {}

## How many times each npc's round has been advanced, keyed by npc id. See
## `_last_synced` for why this is static.
static var _round_syncs: Dictionary = {}

## ## The compose counter — THE named measurement of what an unobserved minor npc costs.
##
## **Nothing but `NpcMinorComposer` composition increments it**, which is the claim made
## concrete: a settlement of unobserved minor npcs composes nobody, because composition
## happens at the interaction and not before it. `tests/modules/npc/test_npc_alive.gd`
## asserts this stays at its floor across a full cast read.
static var composes: int = 0

## ## The gossip counter — one per DELIVERED piece of news, not one per pass.
##
## Bounded per pass by [constant MAX_GOSSIP_NPCS], so a pass is `O(constant)` whatever the
## cast is.
static var gossip_deliveries: int = 0


## ## (1) THE DAILY ROUND — `O(1)` against a stamp, advanced BY the read
##
## `period` is the coarse world period, already converted by the caller with `TimeLadder`
## (ADR 0173: this module never reads a wall clock, and never divides a span itself —
## `def.round_slot_of` does one division against the def's authored slot ratio).
##
## Returns the slot the npc is in, or `{}` when they author no round or are untracked (an
## untracked npc has no day — that is the tier policy).
static func round(def: NpcDef, npc_id: StringName, period: int) -> Dictionary:
	if def == null or period < 0:
		return {}
	if not def.tracked():
		# A minor npc has no authored day to be somewhere-else in. Composing one would be
		# inventing a schedule for a person the world does not remember.
		return {}
	# `_last_synced` is an untyped Dictionary, so `.get()` answers Variant and a `:=`
	# would infer Variant — which this project treats as a hard error. Annotate both.
	var last: int = int(_last_synced.get(npc_id, -1))
	var span: int = period - last
	# The read ADVANCES, then reads. There is no branch here that asks whether anybody is
	# looking — the arrival of this call IS the observation (ADR 0173(c)).
	_last_synced[npc_id] = period
	_round_syncs[npc_id] = int(_round_syncs.get(npc_id, 0)) + 1
	if span < 0:
		span = 0
	var clamped := mini(span, MAX_SYNC_SPAN_PERIODS)
	var slot := def.round_slot_of(period)
	if slot == null:
		return {}
	return {
		"slot_id": String(slot.slot_id),
		"activity": slot.activity,
		"location_id": String(slot.location_id),
		"tell_id": String(slot.tell_id),
		"period": period,
		"elapsed_periods": span,
		"clamped": clamped != span,
	}


## Whether this npc's round has been read since the last advance, which is what a test
## asserts about "costs nothing while unobserved". **A read, not a tick** — there is no
## timer and nothing polls this.
static func is_synced(npc_id: StringName) -> bool:
	return _last_synced.has(npc_id)


## How many times this npc's round has been advanced. **Flat in the cast**: the whole
## claim `tests/modules/npc/test_npc_alive.gd` makes about an unobserved major is that
## this never moves while nobody reads, and it never has to consult the roster to prove it.
static func round_syncs(npc_id: StringName) -> int:
	return int(_round_syncs.get(npc_id, 0))


## Drop every stamp and every counter. A test harness only: this state is process-wide, so
## a suite that advanced an elder would otherwise leave its stamp for the next npc suite.
static func reset() -> void:
	_last_synced.clear()
	_round_syncs.clear()
	composes = 0
	gossip_deliveries = 0


## ## (3) INCIDENT MEMORY — the SPECIFIC thing you did, keyed to the real cause id
##
## Returns `{count, dropped, rows}` where each row is
## `{cause_id, prose, brief, anchors, times}` — **no standing, no trust, no class**, for
## the reason ADR 0091 gives: a number here would be the second writer of a bond.
##
## ## **The cause id is the source of truth and this is a RENDERING of it**
##
## Two rules keep prose from drifting away from the ledger, and both live in this
## function rather than in a docstring:
##
##   1. **A cause the ledger does not carry produces NO row.** The loop walks
##      `bond.causes`, never `def.recalls` — so an authored recall nothing ever happened
##      cannot be rendered, which is the whole of "prose is not a second record".
##   2. **The order is the ledger's own.** `bond.causes` is keyed by cause id; the rows
##      come back sorted by cause id, so the read is deterministic across a save round
##      trip rather than depending on dictionary iteration order.
##
## `player` is the actor whose bond is being read — the hero. A bond the player does not
## hold is `{}` rather than an invented stranger.
static func memory(player: Actor, def: NpcDef, npc_id: StringName) -> Dictionary:
	if def == null or npc_id == &"":
		return {"count": 0, "dropped": 0, "rows": []}
	var bond := SOCIAL_FACADE.social_state(player).bond(npc_id) if player != null else null
	if bond == null:
		return {"count": 0, "dropped": 0, "rows": []}
	# `def.recalls` is the authored index, read ONCE and bounded by its own named cap, so
	# the inner loop never walks an authored array a caller could have grown.
	var authored: Array[NpcRecallDef] = []
	for recall_def in def.recalls:
		if recall_def.cause_id == &"":
			continue
		if authored.size() >= NpcRecallDef.MAX_RECALLS:
			break
		authored.append(recall_def)
	var rows: Array = []
	var carried := 0
	for cause_id in bond.causes.keys():
		carried += 1
		var recall := _recall_for(authored, StringName(cause_id))
		if recall == null:
			# The ledger holds a cause this def authors no prose for. That is a REAL state
			# — an act nobody wrote a sentence for — and it is counted, not dropped: the
			# cause id is reported with empty prose so the fact survives even though the
			# prose does not.
			(
				rows
				. append(
					{
						"cause_id": String(cause_id),
						"prose": "",
						"brief": "",
						"anchors": [],
						"times": int(bond.causes[cause_id]),
						"authored": false,
					}
				)
			)
			continue
		(
			rows
			. append(
				{
					"cause_id": String(recall.cause_id),
					"prose": recall.prose,
					"brief": recall.brief(),
					"anchors": recall.anchors.duplicate(),
					"times": int(bond.causes[cause_id]),
					"authored": true,
				}
			)
		)
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("cause_id", "")) < String(b.get("cause_id", ""))
	)
	var total := rows.size()
	var dropped := 0
	if total > MAX_MEMORY_ROWS:
		dropped = total - MAX_MEMORY_ROWS
		rows = rows.slice(0, MAX_MEMORY_ROWS)
	return {"count": rows.size(), "dropped": dropped, "carried": carried, "rows": rows}


## The one lookup, so "the incident for this cause" is a single answer rather than a scan
## each caller repeats.
static func _recall_for(rows: Array[NpcRecallDef], cause_id: StringName) -> NpcRecallDef:
	for recall_def in rows:
		if recall_def.cause_id == cause_id:
			return recall_def
	return null


## ## (4) REACTION TELLS — the body, answered to ON APPROACH
##
## ## **A verb is never a menu.** The match is made against REAL state here — the cause
## ledger, the derived bond class, the day's slot, or "no history at all" — and what comes
## back is an authored body the presentation can play. A reaction list the player clicks
## from could be authored in a tenth of the time and would say nothing about the world.
##
## Highest authored `priority` wins among the matches, with the array order breaking an
## exact tie, so the answer is deterministic and the ordering is CONTENT. The scan is
## bounded by `def.tells`, which is an authored row count.
##
## With no matching tell the answer is the CONSTANT body below — a real reaction, never
## `{}`. An npc with no opinion of you still nods; refusing to answer would make an
## unauthored cast look broken rather than neutral.
static func tell(
	_player: Actor, def: NpcDef, bond_class: StringName, slot_id: StringName, has_history: bool
) -> Dictionary:
	var empty := {
		"verb": String(DEFAULT_TELL_VERB),
		"body": DEFAULT_TELL_BODY,
		"consequence": String(DEFAULT_TELL_CONSEQUENCE),
		"trigger": "",
		"matches": "",
	}
	if def == null or def.tells.is_empty():
		return empty
	var best: NpcTellDef = null
	for candidate in def.tells:
		if not candidate.valid():
			continue
		if not _tell_fires(candidate, bond_class, slot_id, has_history):
			continue
		if best == null or candidate.priority > best.priority:
			best = candidate
	if best == null:
		return empty
	return {
		"verb": String(best.verb),
		"body": best.body,
		"consequence": String(best.consequence),
		"trigger": String(best.trigger),
		"matches": String(best.matches),
	}


## Whether one authored tell's trigger fires against the state this read was handed. The
## CAUSE trigger is deliberately NOT matched here: which cause an npc resents is a
## question only the MEMORY read can answer, and a body that fired on "any cause you have
## on file" would be the same body for the worst thing and the best.
static func _tell_fires(
	tell_def: NpcTellDef, bond_class: StringName, slot_id: StringName, has_history: bool
) -> bool:
	match tell_def.trigger:
		NpcTellDef.TRIGGER_CAUSE_ID:
			return false
		NpcTellDef.TRIGGER_BOND_CLASS:
			return String(bond_class) == String(tell_def.matches)
		NpcTellDef.TRIGGER_SLOT:
			return slot_id != &"" and String(slot_id) == String(tell_def.matches)
		NpcTellDef.TRIGGER_NEW_FACE:
			return not has_history
	return false


## ## (2) OPINIONS, and GOSSIP THAT ACTUALLY TRAVELS
##
## `opinions` is a read: the authored rows, primitives out, capped by
## [constant MAX_OPINION_ROWS]. Open subject vocabulary, so two npcs may hold opposite
## positions about a third and nothing in this module has to be taught what a sect is.
##
## `spread` is the mechanism that makes gossip gossip: it moves news **npc to npc**, along
## `edges`, bounded by [constant MAX_GOSSIP_NPCS] recipients. Without it, "gossip" is the
## player being told the same thing twice — which is the failure the owner named, and the
## reason this is a graph walk rather than a broadcast.
static func opinions(def: NpcDef) -> Dictionary:
	var rows: Array = []
	if def == null:
		return {"count": 0, "truncated": false, "rows": rows}
	for opinion_def in def.opinions:
		if not opinion_def.valid():
			continue
		if rows.size() >= MAX_OPINION_ROWS:
			return {"count": rows.size(), "truncated": true, "rows": rows}
		(
			rows
			. append(
				{
					"subject_id": String(opinion_def.subject_id),
					"stance": String(opinion_def.normalized_stance()),
					"prose": opinion_def.prose,
				}
			)
		)
	return {"count": rows.size(), "truncated": false, "rows": rows}


## Deliver `news` from `from_id` along `edges`, to at most [constant MAX_GOSSIP_NPCS]
## recipients. Returns `{ok, delivered, hops, dropped, reasons}`.
##
## ## **The bound is the feature, not a truncation**
##
## An edge list longer than the constant is REFUSED with `too_many_edges` rather than
## sliced, and news that reaches the cap stops — it does not wrap around to the sender.
## A town square where one rumour reaches everybody within the hour is a broadcast, and a
## broadcast is the thing this exists to avoid.
##
## `edges` is `[{from, to}]`. A single hop is one edge; a recipient is reached at most
## once per pass because `delivered` is a SET, so a cycle in the edge list cannot spin —
## which is the bounded-walk property `tests/arch_rules/test_no_unbounded_wait.gd` cannot
## infer from a shape.
static func spread(from_id: StringName, news: Array[StringName], edges: Array) -> Dictionary:
	var delivered: Array[String] = []
	if from_id == &"" or news.is_empty():
		return _gossip_result(0, 0, 0, [])
	if edges.size() > MAX_GOSSIP_NPCS:
		push_error(
			(
				(
					"NpcAliveness: one gossip pass was offered %d edges and the cap is %d. "
					+ "Refusing rather than slicing a route list (ADR 0173(b))."
				)
				% [edges.size(), MAX_GOSSIP_NPCS]
			)
		)
		return _gossip_result(0, 0, 0, ["too_many_edges"])
	var reached := {String(from_id): true}
	for edge in edges:
		var row := edge as Dictionary
		var tail := StringName(String(row.get("from", "")))
		var head := StringName(String(row.get("to", "")))
		if not reached.has(String(tail)) or head == &"":
			continue
		if reached.has(String(head)):
			# Already told. A cycle in the edge list therefore terminates at the first
			# repeat rather than walking it, and the news does not go back to its source.
			continue
		reached[String(head)] = true
		delivered.append(String(head))
		if delivered.size() >= MAX_GOSSIP_NPCS:
			break
	gossip_deliveries += delivered.size()
	return _gossip_result(delivered.size(), 1, maxi(0, edges.size() - delivered.size()), [])


static func _gossip_result(delivered: int, hops: int, dropped: int, reasons: Array) -> Dictionary:
	var out := {"delivered": delivered, "hops": hops, "dropped": dropped, "reasons": reasons}
	for key in reasons:
		out[String(key)] = false
	return out
