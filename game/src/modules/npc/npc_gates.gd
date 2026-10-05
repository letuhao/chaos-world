class_name NpcGates
extends RefCounted

## The SOCIAL GATE an authored NPC behaviour consults (ADR 0264).
##
## ## ## What this file is, and what it is deliberately NOT
##
## DEF-0123 asked for NPC behaviour to react to a social gate. The alive layer (ADR 0253)
## already reacts to the **bond class** — and a bond class is a pure function of `standing`
## and `trust` — so the teaching axis was an input to behaviour already, transitively and with
## no second evaluator. What did NOT exist is `regard`: the **institutional** axis that
## `clan`, `sect` and `nation` all write and that `SocialGate`'s `regard_at_least` verb exists
## for. Nothing in `npc/` read it.
##
## **This file does not evaluate a gate.** It passes an authored `Dictionary` through to an
## injected reader, untouched, and reports the verdict. There is no second evaluator here,
## which is the whole of ADR 0076's rule: one answer to "is this gate satisfied" in the repo.
##
## ## ## Why a `Callable` and not a `SocialApi` preload
##
## The shape is `MarketFavour.set_reputation_reader` and `CustodyApi.set_resolver` verbatim.
## `SocialApi.gate(actor, requirement) -> Dictionary` already *is* this signature, so
## `app/npc_boot.gd` binds it as a bare static-function reference with no adapter and no copy
## of the axis. `tools/arch/registry.json` is unchanged — a `Callable` carries the edge, so
## this module adds no dependency at all.
##
## ## ## The default is EXACTLY today's behaviour
##
## No reader bound, a dead reader, a null player, an empty authored gate, or a reader
## answering anything that is not a `Dictionary` all read `gate_open: true`, `gate_reason: ""`
## and `warmth: 0` — **byte-identical to the row as it shipped**. That is what makes the
## existing `test_npc_alive.gd` assertions the regression guard for this file rather than
## something they have to be taught about.

## ## Warmth is a SIGN, which is the counterpart (AGENTS.md's yin-yang rule)
##
## An advantage needs a counterpart, and a gate that only ever *opens* is pure upside with no
## cost — the strict-best-response defect the rule names. So warmth is read from the sign of
## the **same** single gate result rather than from a second axis:
##
##   gate passes  -> `WARMTH_OPEN   +1`   the world holds this player at the bar; the NPC opens
##   gate fails   -> `WARMTH_CLOSED -1`   it does not; the NPC is colder, not merely silent
##   no gate      -> `WARMTH_NEUTRAL  0`   the shipped shape, and the overwhelmingly common one
##
## One axis, two signs, no second mechanic and no second rate — the same pair ADR 0250 shipped
## for the buyer-dependent price. `0` is the default, so landing this changes nothing for any
## def that authors no gate.
##
## **A failure is negative only when a gate was actually authored.** A missing reader is not
## a refusal; it is the absence of an opinion, and treating it as one would make an un-booted
## world look like a world that despises the player.

## The player is inside the author's favour.
const WARMTH_OPEN := 1
## The player is outside it. The counterpart: the same gate, the other sign.
const WARMTH_CLOSED := -1
## No gate authored, or no reader bound. **The shipped default.**
const WARMTH_NEUTRAL := 0

## The reason published when there is nothing to say about the gate.
const REASON_NONE := ""

## The injected reader: `Callable(player: Actor, requirement: Dictionary) -> Dictionary`,
## which is `SocialApi.gate` verbatim. A `static var` because the seam is process-wide exactly
## as `MarketFavour._reader` and `MarketApi.set_store`'s are, and `static var` is excluded
## from the app-state heuristics by construction (the `ShopCounter._counters` shape).
static var _reader: Callable = Callable()


## Install the reader that answers whether `player` satisfies an authored `requirement`.
## Anything that is not a live `Callable` is stored as none, so a dead binding degrades to the
## neutral default rather than raising at the first read.
static func set_social_gate(reader: Callable) -> void:
	_reader = reader if reader.is_valid() else Callable()


## Whether a reader is installed, so a caller can tell "no gate opinion" from "the gate says
## no" — two different sentences, and only one of them is a fact about a person.
static func has_social_gate() -> bool:
	return _reader.is_valid()


## Drop the seam. A test harness only: the reader is process-wide and the runner shares one
## process across every suite, so a reader left installed would silently re-gate every later
## npc suite — the same hazard `MarketFavour`'s teardown exists for.
static func reset() -> void:
	_reader = Callable()


## The verdict on `requirement` for `player`, as `{gate_open, gate_reason, warmth}`.
##
## ## EVERY path out of here is the shipped shape except one
##
## The type gate is `TYPE_DICTIONARY` rather than a cast, because the reader is a `Callable`
## and may answer anything at all — and a malformed answer must degrade to "no opinion", never
## to a refusal, or a bug in an unrelated module would close every gate in the world.
##
## ## And it answers NOTHING when the def authors no gate
##
## An empty requirement is ungated and always open (ADR 0076: "an empty requirement is
## ungated and always open"), so no reader is called at all for an unauthored def. That is the
## O(1) property: a cast of four hundred un-gated NPCs costs zero evaluations.
static func evaluate(player: Actor, requirement: Dictionary) -> Dictionary:
	if requirement.is_empty() or not _reader.is_valid() or player == null:
		return _open()
	var answered: Variant = _reader.call(player, requirement)
	if typeof(answered) != TYPE_DICTIONARY:
		return _open()
	var row := answered as Dictionary
	# `SocialGate` publishes `{ok, reason, unmet}`. Anything else is a reader that did not
	# answer the question it was handed, and an unanswered question is not a refusal.
	if not row.has("ok"):
		return _open()
	if bool(row["ok"]):
		return {
			"gate_open": true,
			"gate_reason": REASON_NONE,
			"warmth": WARMTH_OPEN,
			"gated": true,
		}
	return {
		"gate_open": false,
		# NAMED, never a bare `false` (ADR 0150): a panel must be able to say WHY without
		# inventing a reason, and `SocialGate` already publishes one.
		"gate_reason": String(row.get("reason", "gate_unmet")),
		"warmth": WARMTH_CLOSED,
		"gated": true,
	}


static func _open() -> Dictionary:
	return {"gate_open": true, "gate_reason": REASON_NONE, "warmth": WARMTH_NEUTRAL, "gated": false}


## The clamp and the warm answers as primitives, so a read model and a test state the
## invariant from one place rather than restating three integers.
static func view() -> Dictionary:
	return {
		"reader_installed": has_social_gate(),
		"warmth_open": WARMTH_OPEN,
		"warmth_closed": WARMTH_CLOSED,
		"warmth_neutral": WARMTH_NEUTRAL,
	}
