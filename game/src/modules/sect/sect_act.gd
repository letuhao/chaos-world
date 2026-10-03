class_name SectAct
extends RefCounted

## **What a sect PROPOSES to do this period, and the only verbs it may ever name**
## (BL-0198).
##
## ## Why this is an internal script and not a `SectApi` method
##
## ADR 0084's twelve-method cap is spent: `SectApi` publishes exactly twelve verbs
## and the twelfth is `declare_schism`. Growing a facade past its cap is the ISP
## failure `tools/arch/rules.py` fails the build for, and the repo's own answer to
## "this facade has no room" is to **fold the read into `summary()`** rather than
## widen the surface. So the sect's decision lives here — beside `SectSuccession` and
## `SectTeaching`, which are the same shape: a component holding the rule, reached
## only through the facade or through the resolver `app/` is handed.
##
## ## Propose, never resolve
##
## The institution module **proposes**; `app/` **resolves** (ADR 0114's handler
## shape: a handler never mutates, it returns a proposal, and the director applies).
## Nothing in this file writes a ledger, ages a vacancy or grants a lesson — it names
## the verb and the ids, and `app/institution_resolver.gd` calls the verb that does
## the work. That separation is the whole reason a background tick can run without
## becoming the political layer's author.
##
## ## No `rng`, no `randi`, no `RandomNumberGenerator`, no seed
##
## The choice is a pure function of the ledger: candidates are ordered by
## `(act_priority, institution_id)`, and `institution_id` is a `StringName`, so the
## second key is lexicographic and **total** — two candidates cannot compare equal on
## both keys unless they are the same sect, so ties are impossible BY CONSTRUCTION
## and no tie-break rule and no generator exist. `tests/modules/sect/test_sect_act.gd`
## greps this file for those three names, and runs the identical walk a hundred times
## over fresh actors expecting byte-identical output.
##
## ## The cap is a COUNT read from `InstitutionBudget`, never a multiplier
##
## The tier buys FREQUENCY of action and never SIZE of effect: nothing below scales a
## verb, a lesson or a period by a cap (ADR 0097's refusal, ADR 0050's second-ladder
## rule). The `for` walks a list built once above it and stops on `break`, which is
## the shape `test_no_unbounded_wait.gd` accepts; there is no `while` on this path.

## The closed intent set, in the order a reader should expect them. **These two are
## the only names this file may ever produce**, and `app/` resolves exactly these.
const VERB_WAIT_OFFICE := "wait_office"
const VERB_TEACH := "teach"

const VERBS: Array[StringName] = [VERB_WAIT_OFFICE, VERB_TEACH]

## Why there is no third verb. A sect's per-period business is a vacancy ageing and a
## lesson running — both already implemented, both already taking an explicit
## `periods` from the caller that owns time (`SectApi.advance_succession` and
## `SectApi.teach`). **Nothing here invents a verb the module does not already
## implement**, because a proposal `app/` cannot resolve is a dead branch that reads
## as a capability. The other five institutional verbs belong to `nation`, which owns
## claims, stances and standoffs; ADR 0083 makes the tiers peers, so a sect reaching
## for one would be reaching sideways.


## Whether `verb` is one a sect may propose. An unknown name refuses closed and names
## itself — the `NationState.is_verb` precedent, so malformed content fails loudly
## rather than opening a door nobody can read.
static func is_verb(verb: StringName) -> bool:
	return VERBS.has(verb)


## The vocabularies a decision reads, as primitives. **A refusal is
## `{"ok": false, "reason": ...}` and an empty intent list is `ok: true`** — a sect
## with no walk open and no lesson to run has nothing to do, and that is an ordinary
## outcome rather than a failure (the `do_nothing` state the brief requires be
## representable).
static func empty(periods: int, tier: StringName, cap: int) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"periods": periods,
		"tier": String(tier),
		"acted": 0,
		"intents": [],
		"cap": cap,
	}


## The success shape: `{ok, periods, tier, acted, intents, cap}`.
##
## `acted` is a COUNT so a caller can assert the budget was respected rather than
## trusting it (`SocialApi.tick`'s contract, ADR 0091), and `cap` is carried beside
## it so a caller can check against the bound it was promised without knowing what
## the shipped `InstitutionBudget` says.
static func report(
	periods: int, tier: StringName, cap: int, intents: Array[Dictionary]
) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"periods": periods,
		"tier": String(tier),
		"acted": intents.size(),
		"intents": intents,
		"cap": cap,
	}


## A refusal, and **nothing written** — `app/` may never have called a verb, so a
## refused decision cannot have touched a ledger (ADR 0044).
static func refuse(reason: String, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail, "acted": 0, "intents": []}


## The one intent this sect would act on this period.
##
## **A vacancy ages before a lesson is taught**, and the ordering is authored rather
## than random: ADR 0084 makes "refuses a further step until a period elapses" the
## pacing of a succession, so a walk in progress is the sect's first business and a
## lesson is what it does when no seat is waiting. A sect with an open walk proposes
## exactly one intent and nothing else — which is also what keeps `acted` at or below
## the tier cap by construction rather than by a clamp afterwards.
##
## `def` may be null (a ledger naming a sect the build no longer authors): the answer
## is then `do_nothing`, never an invented institution.
static func intent(ledger: Dictionary, def: SectDef) -> Dictionary:
	if def == null or String(ledger.get("institution", "")) == "":
		return {}
	var sect_id := String(def.id)
	var vacancy := _vacant_office(ledger, def)
	if vacancy != "":
		return {
			"verb": VERB_WAIT_OFFICE,
			"institution_id": sect_id,
			"institution_kind": "sect",
			"target": vacancy,
			"act_priority": def.act_priority,
		}
	# No vacancy open. A lesson needs a teacher this module can actually resolve —
	# an office that may teach and a student admitted to this sect — and both are
	# `SectTeaching`'s business, already gated at `SectApi.teach`. Naming a lesson
	# that `teach` would refuse would be proposing a refusal every period, so the
	# honest default is `do_nothing` and the sect waits for a walk to open.
	return {}


## The lowest-id office whose walk is open and un-finished, or `""` when none is.
##
## **The candidates are collected and SORTED before the walk, never as the walk
## discovers them**, so the bound is the dictionary the caller handed in and the loop
## mutates nothing. `SectState.known_positions` is already a known-content filter, so
## a corrupt save naming an office this build dropped cannot reach `def.position` at
## all — the row is simply not a candidate.
static func _vacant_office(ledger: Dictionary, def: SectDef) -> String:
	var candidates: Array[String] = []
	for office in def.positions:
		if office == null or office.id == &"" or not office.is_walkable_method():
			continue
		var row := SectState.succession(ledger, office.id)
		if row.is_empty() or bool(row.get("complete", false)):
			continue
		if String(row.get("side", "")) != SectDef.SUCCESSION_VACANT:
			continue
		candidates.append(String(office.id))
	# Lexicographic, so two offices waiting at the same authored priority cannot make
	# the outcome depend on the order a `.tres` happened to list them in.
	candidates.sort()
	return "" if candidates.is_empty() else candidates[0]
