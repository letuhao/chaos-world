class_name WorldBeat
extends RefCounted

## The CLAIM that something happened, and never the record of it (ADR 0114).
##
## ## Why a value object and not a dictionary
##
## A beat carries `id`, `fact`, `amount` and `source`, and a bare dictionary is
## exactly how ADR 0067 refused to model a damage payload — four subsystems
## passing four spellings of the same claim is how they drift. This file is
## beside `WorldFact` in `core/` because both are reachable as shared foundation
## data: `core` is a LAYER, not a module, so the cross-module facade rule never
## applied to it and the two files add zero new edges.
##
## ## Recording is NOT dispatching
##
## A beat changes nothing. Constructing one, offering it to a sink and having a
## sink claim it all leave `WorldFact`'s ledger untouched until the OWNER OF THE
## MOMENT calls `WorldFact.record`. That is the whole distinction ADR 0114 draws:
## a fact that happened is true whether or not any handler cared, so an unclaimed
## beat is still recorded — and recording it is a separate act from asking about
## it. Rejected: a `commit(actor)` method here, which would make the beat the
## writer and give every subsystem a second way to move the ledger (ADR 0067's
## "a mechanism returns a proposal, the spine applies").
##
## ## What this deliberately does NOT carry
##
## No reward, no effect reference, no handler list. A beat is a proposal, and a
## proposal that could grant something would be a second accrual path beside the
## one monotone verb ADR 0113 defines. `source` is an audit trail — `"combat"`,
## `"quest:<id>"`, `"event:<id>"`, the same string `DestinyApi.earn_fate`
## already accepts — not a dispatch key, so nothing routes on it.
##
## ## Once is a property of the LEDGER, not of the beat
##
## `WorldFact.record` is monotone, so "did this already fire" is answerable only
## by COUNTING, and a `&"killed_boar"` beat with `amount == 1` that has fired is
## indistinguishable from one that has not. Therefore **a beat's `id` MUST be
## unique per occurrence**: the caller that owns the moment mints
## `&"killed_boar@3"` for the third boar. That is the honest cost of "once"
## without keeping a second dispatch ledger — the caller names the occurrence,
## not the dispatcher. [method is_valid] cannot check this (an id carries no
## memory of what fired), so it checks only that both ids are non-empty and
## `occurrence_key` is the id a caller-derived map or gate would key on.

## How many times this occurrence contributes to the fact. Always at least 1:
## a beat is a proposal that something HAPPENED, and a zero or negative claim is
## a caller bug that `WorldFact.record` refuses with `non_positive` anyway.
## Clamped here too so no beat exists in a shape the ledger would reject.
var amount: int = 1
## The fact this occurrence accrues to, in `WorldFact`'s flat namespace.
var fact: StringName = &""
## Unique per occurrence. `&"killed_boar@3"`, not `&"killed_boar"` — see the
## class docstring for why ADR 0114 makes the CALLER own this.
var id: StringName = &""
## The audit trail: `"combat"`, `"quest:<id>"`, `"event:<id>"`. Free text on
## purpose, because `contracts/` and `core/` may not name a module's ids and a
## closed enum of sources would need editing every time a caller is added.
var source: String = ""


## A beat for one occurrence. A named factory rather than a constructor with four
## positional arguments, because two adjacent `StringName` parameters are
## transposable at the call site and a beat whose id and fact are swapped is a
## claim that is silently about the wrong thing.
static func make(
	id: StringName, fact: StringName, amount: int = 1, source: String = ""
) -> WorldBeat:
	var beat := WorldBeat.new()
	beat.id = id
	beat.fact = fact
	beat.amount = maxi(1, amount)
	beat.source = source
	return beat


## Whether this beat names something a sink can be asked about: both ids are
## non-empty and the amount is positive.
##
## Refuse-with-cause rather than repair: a beat naming no fact has no honest
## reading, and [method make] returning one anyway would push the diagnosis to
## whoever records it. See `DestinyGate`'s malformed-requirement refusal for the
## same house rule.
func is_valid() -> bool:
	return id != &"" and fact != &"" and amount >= 1


## The string a caller-derived map, a gate or a test keys this occurrence on.
##
## This is `String(id)` and nothing more, deliberately: it is NOT a count, a
## dispatch registry or a once-check. The ledger's count is the only record of
## multiplicity, so an id that repeats is a caller bug and shows up as a count of
## two rather than as a distinct event.
func occurrence_key() -> String:
	return String(id)


## The JSON-safe payload a beat travels as. `String` keys throughout and no
## `StringName`, for the same reason `InstitutionClaim.to_dict` states: these
## travel into save blobs and UI summaries, where an interned name is not a
## value.
func to_dict() -> Dictionary:
	return {"id": String(id), "fact": String(fact), "amount": amount, "source": source}


## A beat from [method to_dict], every field coerced. An absent key means its
## default rather than a refusal: a restored beat that came back invalid reports
## itself through [method is_valid] instead of failing the load, so one malformed
## claim in a save cannot refuse every other one.
static func from_dict(data: Dictionary) -> WorldBeat:
	return make(
		StringName(data.get("id", "")),
		StringName(data.get("fact", "")),
		int(data.get("amount", 1)),
		String(data.get("source", ""))
	)
