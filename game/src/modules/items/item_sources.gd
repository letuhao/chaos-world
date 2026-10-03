class_name ItemSources
extends RefCounted

## The one reader of [member ItemDef.sources].
##
## `sources` is an authoring claim on a string field, and until this class existed
## nothing in `game/src` read it: an item could declare `boss:x` or `quest:y`
## forever and no shipping code resolved either. That is why a declared source was
## never evidence of an obtainable item. This class turns the field into a
## validated vocabulary and, when a caller injects content probes, into a
## satisfiability answer.
##
## ## Why a validated string vocabulary and not a typed value object
##
## A `Route` resource in `contracts/` would make a malformed kind impossible to
## author and would cost a boundary change plus its own contract tests. The
## failure this class exists to stop is not a malformed *kind* — it is a kind
## **nobody resolves**. A closed vocabulary checked by one reader stops that
## failure at the only place it can be caught without a new layer, and it keeps
## the field a plain `Array[StringName]` so existing content needs no migration.
## The cost is honest and bounded: [constant KINDS] must be edited when a route is
## added, and `tools data audit` cross-checks it against the content corpus so the
## two cannot drift apart unnoticed.
##
## ## Why the probes are injected
##
## `items` owns recipes, inventory and generation. It cannot see a boss record
## (`world`) or an authored encounter (`loot`) without a facade edge in each
## direction, and an acquisition question that needs both is exactly the question
## neither module can answer alone. So resolution takes the content lookups as
## callables the composition root supplies, and this module owns the vocabulary,
## the refusal, and the reason text. A kind with no probe is reported as
## [constant UNPROBED] rather than assumed satisfiable, which is the direction
## that cannot over-claim.
##
## ## A refusal is inert
##
## Nothing here can mint, deliver or roll anything. [method resolve] answers one
## question about one definition and returns primitives; it holds no inventory, no
## RNG and no content handle. An unsatisfiable route therefore has no path from
## this reader to a delivered item, and the only way to act on a route is to act
## on one this reader marked satisfied.

# --- Reason vocabulary -------------------------------------------------------
# Owned here so the runtime reader and the content audit cannot disagree about
# what "not obtainable" is called. Every value is a stable id a panel may switch
# on; none of them is prose.

const MALFORMED := "malformed_source"
const UNKNOWN_KIND := "unknown_kind"
const MISSING_REF := "missing_ref"
const UNEXPECTED_REF := "unexpected_ref"
const NO_SOURCE := "no_source_declared"
const UNSATISFIED := "route_unsatisfied"
## The kind is in the vocabulary but no shipping code delivers it. A static
## property of the kind, not of any one item: `quest` item grants are recorded
## unspent by `QuestGrants.pay`, which records the grant rather than handing over
## an item.
##
## **`gather` was in this list until the forage route shipped, and the flag moved
## only when there was a verb behind it.** `ForageApi.harvest` works a node the
## actor holds, gated by `ResourceNodeDef.permits`, and settles the accrued units
## into real items through the granter `EconomyBoot.install` binds
## (`app/forage_granary.gd`). A `shipped` flag with no callable verb is a claim
## the audit cannot detect, so the flag follows the code rather than the intention.
const NO_SHIPPED_ROUTE := "no_shipped_route"
## The kind is deliverable in principle but the caller injected no probe for it,
## so satisfiability was not established. Never counted as satisfied.
const UNPROBED := "no_probe"

# --- Route kinds ------------------------------------------------------------

const KIND_CRAFT := &"craft"
const KIND_BOSS := &"boss"
const KIND_DOMAIN := &"domain"
const KIND_QUEST := &"quest"
const KIND_GATHER := &"gather"
const KIND_STARTER := &"starter"

const REF_REQUIRED := "required"
const REF_OPTIONAL := "optional"
const REF_FORBIDDEN := "forbidden"

## The closed vocabulary of `sources` prefixes: what a kind is, whether it must
## carry a reference, and whether shipping code delivers it at all.
##
## `shipped` is a claim about `game/src`, not about content. It is `false` for
## exactly the kinds whose subsystem does not exist or deliberately refuses to
## hand over an item, and `tools data audit` reports any kind in the corpus this
## table does not carry. **`gather` became `true` only once `ForageApi.harvest`
## existed** — see [constant NO_SHIPPED_ROUTE] for why the flag follows the code.
const KINDS: Dictionary = {
	KIND_CRAFT: {"ref": REF_REQUIRED, "shipped": true},
	KIND_BOSS: {"ref": REF_REQUIRED, "shipped": true},
	KIND_DOMAIN: {"ref": REF_REQUIRED, "shipped": true},
	KIND_STARTER: {"ref": REF_FORBIDDEN, "shipped": true},
	KIND_QUEST: {"ref": REF_OPTIONAL, "shipped": false},
	KIND_GATHER: {"ref": REF_FORBIDDEN, "shipped": true},
}


## Every kind this reader knows, in the authored order of [constant KINDS].
static func kind_ids() -> Array[String]:
	var out: Array[String] = []
	for kind in KINDS:
		out.append(String(kind))
	return out


## Whether `kind` is in the vocabulary. The gate every authored prefix must pass.
static func knows(kind: StringName) -> bool:
	return KINDS.has(kind)


## Whether shipping code delivers `kind` at all.
static func is_shipped(kind: StringName) -> bool:
	return bool((KINDS.get(kind, {}) as Dictionary).get("shipped", false))


## Every kind the shipped game cannot deliver. An item resting only on these is
## declared-and-unreachable, which is a content finding and not a parse error.
static func unshipped_kind_ids() -> Array[String]:
	var out: Array[String] = []
	for kind in kind_ids():
		if not is_shipped(StringName(kind)):
			out.append(kind)
	return out


# --- Parsing ----------------------------------------------------------------


## One authored `sources` entry as `{kind, ref, ok, reason}`.
##
## The reason is [constant MALFORMED] for an entry with no prefix,
## [constant UNKNOWN_KIND] for a prefix outside [constant KINDS],
## [constant MISSING_REF] for a kind that must name a target and does not, and
## [constant UNEXPECTED_REF] for one that must not. `ok` is false in every one of
## those cases, so a caller cannot read a route it could not have satisfied.
static func parse(entry: StringName) -> Dictionary:
	var text := String(entry).strip_edges()
	if text.is_empty():
		return _route(&"", "", false, MALFORMED)
	var separator := text.find(":")
	var kind_text := text if separator < 0 else text.substr(0, separator)
	var ref := "" if separator < 0 else text.substr(separator + 1).strip_edges()
	var kind := StringName(kind_text)
	if not KINDS.has(kind):
		return _route(kind, ref, false, UNKNOWN_KIND)
	var policy := String((KINDS[kind] as Dictionary).get("ref", REF_REQUIRED))
	match policy:
		REF_REQUIRED:
			if ref.is_empty():
				return _route(kind, "", false, MISSING_REF)
		REF_FORBIDDEN:
			if not ref.is_empty():
				return _route(kind, ref, false, UNEXPECTED_REF)
		_:
			pass
	return _route(kind, ref, true, "")


## Every route `def` declares, normalized, in authored order, one per distinct
## `kind`/`ref` pair.
##
## A def with no `sources` is not an error here: it reports no route at all, and
## [method resolve] turns that into [constant NO_SOURCE]. A numeraire declares
## nothing on purpose (ADR 0099), so an empty list is a legitimate answer.
static func routes(def: ItemDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	var seen: Dictionary = {}
	for entry in def.sources:
		var route := parse(StringName(entry))
		var key := "%s|%s" % [String(route["kind"]), String(route["ref"])]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(route)
	return out


# --- Resolution -------------------------------------------------------------


## Whether any route `def` declares can actually deliver it, and why not when it
## cannot. `probe` maps a route kind to a `Callable(kind_ref: String) -> bool`
## answering "can shipping code deliver this target". A kind absent from `probe`,
## or one this reader knows no route for, is [constant UNPROBED] — never
## satisfied.
##
## The answer is primitives only, so a panel can render it without reaching into
## a Resource, and nested under `routes` so one refused route among several does
## not hide the ones that do work.
static func resolve(def: ItemDef, probe: Dictionary = {}) -> Dictionary:
	var declared := routes(def)
	var out: Array[Dictionary] = []
	var satisfied := 0
	var reason := ""
	for route in declared:
		var resolved := _satisfy(route, probe)
		if bool(resolved["satisfied"]):
			satisfied += 1
		elif reason.is_empty():
			reason = String(resolved["reason"])
		out.append(resolved)
	if declared.is_empty():
		reason = NO_SOURCE
	elif satisfied > 0:
		reason = ""
	return {
		"item_id": String(def.id) if def != null else "",
		"obtainable": satisfied > 0,
		"reason": reason,
		"satisfied": satisfied,
		"total": declared.size(),
		"routes": out,
	}


## The first route a caller could act on, or `{}` when none can. `{}` is not a
## route: it carries no kind, so a caller that skips the emptiness check has
## nothing to hand to anything.
static func first_satisfied(def: ItemDef, probe: Dictionary = {}) -> Dictionary:
	for route in resolve(def, probe)["routes"]:
		if bool(route["satisfied"]):
			return route
	return {}


## Whether `def` has at least one route shipping code can close. The single
## boolean the acceptance question needs; [method resolve] is the same answer
## with the evidence attached.
static func obtainable(def: ItemDef, probe: Dictionary = {}) -> bool:
	return bool(resolve(def, probe)["obtainable"])


# --- Internals --------------------------------------------------------------


static func _route(kind: StringName, ref: String, ok: bool, reason: String) -> Dictionary:
	return {"kind": kind, "ref": ref, "ok": ok, "reason": reason, "satisfied": false}


static func _satisfy(route: Dictionary, probe: Dictionary) -> Dictionary:
	var out := route.duplicate()
	if not bool(route["ok"]):
		return out
	var kind := StringName(route["kind"])
	var ref := String(route["ref"])
	if not is_shipped(kind):
		out["reason"] = NO_SHIPPED_ROUTE
		return out
	var check = probe.get(kind)
	if not check is Callable:
		out["reason"] = UNPROBED
		return out
	if not bool(check.call(ref)):
		out["reason"] = UNSATISFIED
		out["reason"] = UNSATISFIED
		return out
	out["satisfied"] = true
	out["reason"] = ""
	return out
