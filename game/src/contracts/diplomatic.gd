class_name Diplomatic
extends InstitutionCapability

## Diplomacy as a SHARED capability: the closed stance set, one canonical row
## per unordered pair, and war through exactly one prize-declaring door
## (ADR 0085, ADR 0922).
##
## A trading guild never needs to hold ground; it still needs to answer "how do
## we stand with them" and, at the extreme, to declare that the standing is war.
## Those two are this capability, and nothing else rides along: no standoff
## store, no verdict counting, no exhaustion. A standoff is a political object
## a sovereign keeps in its own ledger; this contract plans the DECLARATION,
## and the applier writes it. That is the same DECIDES-never-commits split the
## whole family is built on.
##
## ## The set is CLOSED, and it is the sovereign's own words
##
## `rival`, `neutral`, `allied`, `truce`, `embargo`, `war` — the exact six words
## `NationState.VERBS` publishes, in the same spelling. There is deliberately no
## second vocabulary here: a pack inventing `hostile` beside `rival` would fork
## the stance graph the same way a second damage formula forked combat, and the
## parity suite in `test_diplomatic_contract.gd` pins every word so the two lists
## cannot drift. An unknown value refuses as `unknown_verb` and names itself.
##
## ## `war` has exactly one door, and this file is not it
##
## `transition` refuses `war` as `war_requires_a_prize`, so no war can exist
## without a declared prize. `declare` is the only verb that plans one, and its
## plan carries the prize VERBATIM — mode, transfer and the per-side standing
## map, read field for field and never computed. A war whose prize was invented
## at resolution is the scoring function ADR 0085 refuses.
##
## ## A truce has a span, and nothing else here has a price
##
## The D8 cost of each shared behavior, named where it is charged: a truce
## transition refuses `truce_needs_a_span` below one period, because a truce
## with no span is an embargo wearing truce's clothes. The span arrives as an
## explicit `span` from a caller that owns time, never from a clock. Every other
## transition is a free declaration — its cost is that the row is PUBLIC and
## rewritable: one canonical row per pair, so either side's later verb replaces
## the earlier one rather than adding a second. A war's cost is its prize: both
## sides' standing deltas and the transfer at stake, fixed before the first
## verdict. Scarcity throughout is structural — one row per pair, one door to
## war — never a counter this layer would have to keep.
##
## ## Where the sovereign's answer differs, measured rather than assumed
##
## - **A self-declaration refuses `self_dealing`.** The sovereign spells it
##   `unknown_nation`; this contract has no catalog to consult, so an absent id
##   and a self-pair are different faults with different names. The parity suite
##   pins both spellings, so the difference is deliberate vocabulary, not drift.
## - **A truce span has no sovereign counterpart.** `set_stance` writes `truce`
##   with no span; a kind driving this contract must author one. If the sovereign
##   later claims this capability, its truce path needs a span parameter — that
##   edit is REPORTED, not taken.
## - **A malformed prize refuses here.** The sovereign trusts its caller's prize
##   shape; the shared door takes packs nobody vetted, so a non-numeric standing
##   value or a non-map `standing` refuses `malformed` instead of aborting.
##
## ## Context keys this capability reads
##
##   - `institution` — the declaring organization (`String`, family-wide).
##   - `member` — the acting member's id (`String`), recorded on the plan.
##   - `other` — the counterparty's id (`String`). Empty means no counterparty,
##     refused as `no_other`; a self-pair is allowed on `transition` (the
##     sovereign writes one, and its normalizer decides what survives a load)
##     and refused on `declare` (a standoff needs two sides).
##   - `verb` — the requested stance (`String`), one of the closed six.
##   - `current` — the pair's current verb (`String`, `""` for no row). Read by
##     `stance` only; the contract keeps no store, so the applier reports it.
##   - `span` — int: periods a truce holds, authored per declaration. Below 1
##     refuses `truce_needs_a_span`.
##   - `mode` — the standoff mode `declare` plans (`String`, default
##     `contest`, the sovereign's own default). `transfer` — what moves
##     (`String`, `""` for nothing, otherwise one of the three declared shapes).
##     `standing` — the per-side delta map, read verbatim.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111).

## The id this capability is dispatched under.
const ID := &"diplomatic"

## The closed stance set, in the sovereign's spelling. `war` is listed and is
## reachable only through `declare` — `transition` refuses it by name.
const VERBS: Array[StringName] = [&"rival", &"neutral", &"allied", &"truce", &"embargo", &"war"]
## The standoff modes a declared prize may name, in the sovereign's spelling.
const MODES: Array[StringName] = [&"contest", &"siege", &"tribunal"]
## The prize shapes a declaration may move, in the sovereign's spelling. Empty
## means "nothing moves, only standing" and is legal.
const TRANSFERS: Array[StringName] = [&"ownership", &"recognition", &"tribute"]
## The separator joining a pair into its canonical key. A DUPLICATE of the
## sovereign's separator, and documented as one: `contracts/` may not depend on
## `modules/`, so the leaf re-authors the character the same way
## `InstitutionCapability.text` re-authors its pair — and the parity suite
## asserts both joins agree, so a drift fails loudly instead of forking keys.
const PAIR_SEPARATOR := "|"

## No counterparty was named. There is no pair to read or change, so the
## request is incomplete rather than declined.
const R_NO_OTHER := "no_other"
## A standoff was declared against the declarer itself. A war needs two sides,
## and the ledger has only one id to write.
const R_SELF_DEALING := "self_dealing"
## The requested stance is outside the closed six. The refusal names the value,
## so malformed content fails loudly rather than opening a door nobody can read.
const R_UNKNOWN_VERB := "unknown_verb"
## `war` was asked of the transition verb. There is exactly one door to a war
## and this is not it.
const R_WAR_REQUIRES_A_PRIZE := "war_requires_a_prize"
## The declared mode is none of the three. Names itself, like the verb.
const R_UNKNOWN_MODE := "unknown_mode"
## The declared transfer is neither empty nor one of the three shapes. An
## absent key declares nothing moving; an unreadable one is a content bug.
const R_UNKNOWN_TRANSFER := "unknown_transfer"
## A truce was declared with no span. A truce with no end is a permanent
## condition wearing a temporary's name.
const R_TRUCE_NEEDS_A_SPAN := "truce_needs_a_span"


func capability_id() -> StringName:
	return ID


## This capability's own reasons, added to the family's so a caller validating a
## refusal reads a set that cannot drift from the constants above.
func own_reasons() -> Array[String]:
	var out: Array[String] = [
		R_NO_OTHER,
		R_SELF_DEALING,
		R_UNKNOWN_VERB,
		R_WAR_REQUIRES_A_PRIZE,
		R_UNKNOWN_MODE,
		R_UNKNOWN_TRANSFER,
		R_TRUCE_NEEDS_A_SPAN,
	]
	return out


## The canonical key for an unordered pair: the two ids ordered
## lexicographically, joined. Swapping the arguments cannot produce a different
## key, which is the whole structural claim — the sovereign's symmetry, spelled
## in the leaf so any kind can share it.
static func pair_key(a_id: String, b_id: String) -> String:
	return a_id + PAIR_SEPARATOR + b_id if a_id <= b_id else b_id + PAIR_SEPARATOR + a_id


## Both ids of a canonical pair key, as the ordered pair they stand for.
static func split_pair(key: String) -> Array[String]:
	var parts := key.split(PAIR_SEPARATOR, false, 1)
	if parts.size() != 2:
		return []
	return [String(parts[0]), String(parts[1])]


## ## Where the pair stands, as a READ.
##
## `{ok: true, reason: "", institution, other, pair_key, verb}` where `verb` is
## the applier-reported `current`, or `""` for no row. No row is an ANSWER, not
## an error: most pairs have never exchanged a word, and a screen renders that
## as an ordinary absence rather than a refusal.
func stance(ctx: Dictionary) -> Dictionary:
	var other := InstitutionCapability.text(ctx.get("other", ""), "")
	if other == "":
		return InstitutionCapability.refuse(R_NO_OTHER)
	var institution := InstitutionCapability.text(ctx.get("institution", ""), "")
	return (
		InstitutionCapability
		. ok(
			{
				"institution": institution,
				"other": other,
				"pair_key": pair_key(institution, other),
				"verb": InstitutionCapability.text(ctx.get("current", ""), ""),
			}
		)
	)


## ## Plan a stance change, or refuse it.
##
## `{ok: true, reason: "", plan: {institution, member, other, pair_key, verb,
## span, cause}}` — ids and one count, and the applier writes the row.
## Refusal order: counterparty named, declarer known, verb in the closed set,
## not `war`, a truce carrying its span. A refused change writes nothing.
func transition(ctx: Dictionary) -> Dictionary:
	var other := InstitutionCapability.text(ctx.get("other", ""), "")
	if other == "":
		return InstitutionCapability.refuse(R_NO_OTHER)
	var institution := InstitutionCapability.text(ctx.get("institution", ""), "")
	if institution == "":
		return InstitutionCapability.refuse(InstitutionCapability.R_UNKNOWN_INSTITUTION)
	var verb := InstitutionCapability.text(ctx.get("verb", ""), "")
	if not VERBS.has(StringName(verb)):
		return InstitutionCapability.refuse(R_UNKNOWN_VERB, {"verb": verb})
	if verb == "war":
		return InstitutionCapability.refuse(R_WAR_REQUIRES_A_PRIZE, {"verb": verb})
	var fault := _truce_fault(verb, ctx)
	if not fault.is_empty():
		return fault
	return (
		InstitutionCapability
		. ok(
			{
				"plan":
				{
					"institution": institution,
					"member": InstitutionCapability.text(ctx.get("member", ""), ""),
					"other": other,
					"pair_key": pair_key(institution, other),
					"verb": verb,
					"span": _truce_span(verb, ctx),
					"cause": "stance_declared",
				},
			}
		)
	)


## ## Plan a war declaration with its prize fixed up front, or refuse it.
##
## The ONLY path to a `war` stance. `{ok: true, reason: "", plan: {institution,
## member, other, pair_key, verb, mode, transfer, standing, cause}}` where the
## prize rides field by field — mode, transfer and the per-side standing map,
## read VERBATIM and never computed. A declaration both sides can read before
## the first verdict, never a number computed at resolution. The prize is flat
## on the plan rather than nested under one key because the family's
## primitives-only predicate refuses past `MAX_PAYLOAD_DEPTH`, and a third
## level of nesting would make every declaration refuse `unsafe_payload`.
## Refusal order: counterparty named, declarer known, two distinct sides, a
## known mode, a known or empty transfer, a readable standing map.
func declare(ctx: Dictionary) -> Dictionary:
	var other := InstitutionCapability.text(ctx.get("other", ""), "")
	if other == "":
		return InstitutionCapability.refuse(R_NO_OTHER)
	var institution := InstitutionCapability.text(ctx.get("institution", ""), "")
	if institution == "":
		return InstitutionCapability.refuse(InstitutionCapability.R_UNKNOWN_INSTITUTION)
	if institution == other:
		return InstitutionCapability.refuse(R_SELF_DEALING, {"other": other})
	var fault := _declare_fault(ctx)
	if not fault.is_empty():
		return fault
	var plan := {
		"institution": institution,
		"member": InstitutionCapability.text(ctx.get("member", ""), ""),
		"other": other,
		"pair_key": pair_key(institution, other),
		"verb": "war",
		"cause": "war_declared",
	}
	# Disjoint by construction: the plan names the pair, the prize names what is
	# at stake, so neither can overwrite the other.
	plan.merge(_prize_parts(ctx))
	return InstitutionCapability.ok({"plan": plan})


## ## The authored data this capability reads cannot be READ.
##
## A `span` that arrived as text would read as `0`, which is indistinguishable
## from a truce that authors no end. `check` vets what is PRESENT; an absent key
## is the per-verb refusals' business, so the family's bare probe passes.
func check(ctx: Dictionary) -> Dictionary:
	for field in ["institution", "member", "other", "verb", "current", "mode", "transfer"]:
		if ctx.has(field) and not (ctx[field] is String or ctx[field] is StringName):
			return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": field})
	if ctx.has("span") and not (ctx["span"] is int or ctx["span"] is float):
		return InstitutionCapability.refuse(InstitutionCapability.R_MALFORMED, {"field": "span"})
	if ctx.has("standing") and not (ctx["standing"] is Dictionary):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "standing"}
		)
	return {"ok": true, "reason": "", "unmet": []}


## ## The suite this capability's implementations must pass AT REGISTRATION (D3)
##
## The generic half plus this capability's own probes: a transition plans and
## answers identically twice; an unknown verb refuses naming itself; `war` via
## the transition refuses `war_requires_a_prize`; a truce without a span
## refuses and with one plans carrying it; a declaration plans a war with its
## prize verbatim; a self-declaration, an unknown mode, an unknown transfer and
## an unreadable standing map each refuse by name; the pair key is identical
## under a swap; and a refused verb leaves the handed context byte-identical.
func contract_findings() -> Array[String]:
	var found: Array[String] = super()
	var probe := {
		"kind": "contract_probe",
		"institution": "contract_probe",
		"member": "probe_member",
		"other": "probe_rival",
		"verb": "rival",
		"current": "",
		"span": 3,
		"mode": "contest",
		"transfer": "ownership",
		"standing": {"contract_probe": 10, "probe_rival": -5},
	}
	var first := transition(probe.duplicate(true))
	var second := transition(probe.duplicate(true))
	if JSON.stringify(first) != JSON.stringify(second):
		found.append("transition: two identical calls disagreed — the stance is not deterministic")
	_judge(found, "transition", first)
	if bool(first.get("ok", false)):
		var plan = first.get("plan", {})
		if not (plan is Dictionary):
			found.append("transition: a successful plan is not a dictionary")
		elif (
			String((plan as Dictionary).get("pair_key", ""))
			!= pair_key("contract_probe", "probe_rival")
		):
			found.append("transition: the plan does not carry the canonical pair key")
	var unknown := probe.duplicate(true)
	unknown["verb"] = "hostile"
	var refused_verb := transition(unknown)
	expect_refusal(found, "transition", refused_verb, R_UNKNOWN_VERB)
	if String(refused_verb.get("verb", "")) != "hostile":
		found.append("transition: an unknown verb refusal did not name itself")
	var war := probe.duplicate(true)
	war["verb"] = "war"
	expect_refusal(found, "transition", transition(war), R_WAR_REQUIRES_A_PRIZE)
	_probe_purity(found, "transition", probe, probe.duplicate(true))
	var bare := probe.duplicate(true)
	bare["verb"] = "truce"
	bare["span"] = 0
	expect_refusal(found, "transition", transition(bare), R_TRUCE_NEEDS_A_SPAN)
	var spanned := transition(probe.duplicate(true))
	# `probe["verb"]` is `rival`, so the span probe re-asks as a truce: a rival
	# needs no span and must not be asked for one.
	var truce := probe.duplicate(true)
	truce["verb"] = "truce"
	var truce_planned := transition(truce)
	_judge(found, "transition", truce_planned)
	if bool(truce_planned.get("ok", false)):
		if int((truce_planned["plan"] as Dictionary).get("span", 0)) != 3:
			found.append("transition: a truce plan did not carry its span")
	if bool(spanned.get("ok", false)):
		if int((spanned["plan"] as Dictionary).get("span", -1)) != 0:
			found.append("transition: a non-truce plan carried a span it was never given")
	var declared := declare(probe.duplicate(true))
	_judge(found, "declare", declared)
	if bool(declared.get("ok", false)):
		var row: Dictionary = declared.get("plan", {})
		if not (row is Dictionary):
			found.append("declare: a successful plan is not a dictionary")
		elif JSON.stringify(_prize_of(row)) != JSON.stringify(_prize_parts(probe)):
			found.append("declare: the prize was not carried verbatim")
		if String((declared["plan"] as Dictionary).get("verb", "")) != "war":
			found.append("declare: the declaration did not plan a war")
	var itself := probe.duplicate(true)
	itself["other"] = itself["institution"]
	expect_refusal(found, "declare", declare(itself), R_SELF_DEALING)
	var strange_mode := probe.duplicate(true)
	strange_mode["mode"] = "skirmish"
	expect_refusal(found, "declare", declare(strange_mode), R_UNKNOWN_MODE)
	var strange_transfer := probe.duplicate(true)
	strange_transfer["transfer"] = "annexation"
	expect_refusal(found, "declare", declare(strange_transfer), R_UNKNOWN_TRANSFER)
	var broken_prize := probe.duplicate(true)
	broken_prize["standing"] = [1, 2]
	expect_refusal(found, "declare", declare(broken_prize), InstitutionCapability.R_MALFORMED)
	_probe_purity(found, "declare", probe, probe.duplicate(true))
	var read := stance(probe.duplicate(true))
	_judge(found, "stance", read)
	if bool(read.get("ok", false)):
		if String(read.get("pair_key", "")) != pair_key("probe_rival", "contract_probe"):
			found.append("stance: the read is not symmetric under a swap")
	return found


# --- Internals ---------------------------------------------------------------


## Run one own verb against a pristine copy and compare the handed context by
## text afterwards: a refused — and a successful — verb writes nothing
## (ADR 0044). The base probes only the lifecycle verbs, so each capability
## with its own verbs probes them itself.
func _probe_purity(
	found: Array[String], verb: String, pristine: Dictionary, handed: Dictionary
) -> void:
	if verb == &"transition":
		transition(handed)
	else:
		declare(handed)
	if JSON.stringify(handed) != JSON.stringify(pristine):
		found.append("%s: mutated the context it was handed" % verb)


## The truce's span when `verb` is one, else `0`: non-truce rows carry no span
## they were never given, so a panel reads one key without knowing the verb.
func _truce_span(verb: String, ctx: Dictionary) -> int:
	if verb != "truce":
		return 0
	if ctx.get("span", 0) is int or ctx.get("span", 0) is float:
		return maxi(0, int(ctx["span"]))
	return 0


## The refusal a truce without a span reaches, or `{}` when the verb may plan.
## Split out of `transition` so the verb keeps its named refusals while staying
## inside gdlint's `max-returns`: the span is the truce's whole cost, and only
## the truce is asked for it.
func _truce_fault(verb: String, ctx: Dictionary) -> Dictionary:
	if verb != "truce":
		return {}
	var span := InstitutionCapability.count(ctx.get("span", 0), 0)
	if span < 1:
		return InstitutionCapability.refuse(R_TRUCE_NEEDS_A_SPAN, {"span": span})
	return {}


## Whether the declaration's prize reads cleanly, or the refusal it reaches.
## Split out of `declare` for the same `max-returns` reason: mode, transfer
## and the standing map are three checks about the PRIZE, not the pair.
func _declare_fault(ctx: Dictionary) -> Dictionary:
	var mode := InstitutionCapability.text(ctx.get("mode", "contest"), "contest")
	if not MODES.has(StringName(mode)):
		return InstitutionCapability.refuse(R_UNKNOWN_MODE, {"mode": mode})
	var transfer := InstitutionCapability.text(ctx.get("transfer", ""), "")
	if transfer != "" and not TRANSFERS.has(StringName(transfer)):
		return InstitutionCapability.refuse(R_UNKNOWN_TRANSFER, {"transfer": transfer})
	var standing = ctx.get("standing", {})
	if not (standing is Dictionary):
		return InstitutionCapability.refuse(
			InstitutionCapability.R_MALFORMED, {"field": "standing"}
		)
	for side_id in (standing as Dictionary).keys():
		var value = (standing as Dictionary)[side_id]
		if not (value is int or value is float):
			return InstitutionCapability.refuse(
				InstitutionCapability.R_MALFORMED, {"field": "standing"}
			)
	return {}


## The prize a vetted declaration carries, field by field: mode defaulted,
## transfer as declared, standing coerced side by side. Called only after
## `_declare_fault` passed, so every read below is shaped — the ctx is not
## written between the two, and a second read cannot disagree with the first.
func _prize_parts(ctx: Dictionary) -> Dictionary:
	var deltas := {}
	for side_id in (ctx.get("standing", {}) as Dictionary).keys():
		deltas[String(side_id)] = int((ctx["standing"] as Dictionary)[side_id])
	return {
		"mode": InstitutionCapability.text(ctx.get("mode", "contest"), "contest"),
		"transfer": InstitutionCapability.text(ctx.get("transfer", ""), ""),
		"standing": deltas,
	}


## The prize fields of a declaration plan, for the verbatim comparison the
## suite makes: what is at stake, and nothing naming the pair around it.
func _prize_of(plan: Variant) -> Dictionary:
	if not (plan is Dictionary):
		return {}
	var row := plan as Dictionary
	return {
		"mode": String(row.get("mode", "")),
		"transfer": String(row.get("transfer", "")),
		"standing": (row.get("standing", {}) as Dictionary).duplicate(true),
	}
