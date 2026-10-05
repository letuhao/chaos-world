class_name SectFounding
extends RefCounted

## The one place a sect comes into being: it assembles the PROFILE the generic
## `InstitutionFounding.found` consumes and hands it over. **This module writes no
## ledger.** The skeleton, the treasury, the obligation merge and the refusal order
## all live in `core/institution_founding.gd` and were deleted from here, so a guild
## and a sect cannot disagree about what founding a school IS (ADR 0271 decision 2).
##
## ## What stayed here, and why each stayed
##
##   - **Profile assembly.** `core/` may not name a `SectDef`, so the authored cost,
##     the standing cap, the treasury prefixes and the founding fit grant are read
##     from sect content here and handed in as primitives.
##   - **The fit GRANT.** `FOUNDER_FIT_POINTS` is capped by a doctrine's own
##     `affinity_floor`, and a doctrine is `sect` content. The tier owns the points;
##     `core/` only carries whatever the profile hands it.
##   - **The funding pool name.** `sect_founding_funds` is a SAVE-SPACE name, not a
##     second funding rule: a pool id is written into every actor's save, so renaming
##     it would strand every fund. See `FUNDING_POOL`.
##   - **The refusal NAMES.** Aliased below, never restated: a panel renders a string
##     it did not invent, so the strings must not change because the writer moved.
##
## ## A sect is a SIGNAL, not a pile of items
##
## Founding is the only verb that opens a treasury, and a treasury in this repo is
## **a ledger of obligation lines on ids**, never a pile of items (BL-0191). A line is
## an id and a count, so retuning a rate never rewrites a save.
##
## ## The generic writer's opening line is named `_all`, and this module no longer
## ## authors one of its own
##
## `InstitutionFounding` opens `<prefix>all` for the institution itself. `sect` used
## to open `<prefix>hall` as well, and the two were the SAME line under two names —
## two sources of truth for one fact, which is the failure this consolidation exists to
## remove. `treasury_lines` is now the AUTHORED office rates only, and the opening line
## belongs to the generic writer. **This is the one observable change the migration
## makes** and it is a line id: a save written before it carries `..._hall`, which
## `SectState.normalize` still keeps (it filters on the `treasury_<id>_` prefix), and
## a newly founded sect carries `..._all`. Nothing settles a treasury line — `SectDuty`
## settles `claim.obligation`, a different map — so no debt moves.
##
## ## Nothing here reads a clock
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (ADR 0083, DEF-0111): a ledger
## whose contents depended on when the save was written would not be a ledger.

## The registry id a sect is REGISTERED under (ADR 0271). **Not a container**: a sect
## is a peer kind and a clan or a nation is not a thing this one holds.
const KIND := &"sect"

## What a SECT may do, as the registry's closed capability flags. Declared HERE because
## `core/` may not name `sect` and the row is the only place the answer is written.
##
##   - `teaches` — a sect HAS a fit axis, so a founded ledger carries one. Without it
##     `InstitutionFounding.write` writes NO `fit` key at all, and `SectState`'s
##     whole teaching ladder would read as "this kind has no transmission".
##   - `has_offices` — a sect authors positions and a founder is seated in the top one,
##     so a profile naming none is refused `no_top_position`.
##   - `has_territory` — `SectDef.territory_ids` exists and `SectSchism.unassigned`
##     counts against it (ADR 0085), so a sect does claim ground.
##
## Absent deliberately: `is_born_to`. A sect is SWORN TO, which is the whole reason it
## can be founded at all, and `is_born_to` is the only place the foundable answer is
## written (ADR 0064, ADR 0271).
const CAPABILITIES: Array[StringName] = [
	InstitutionRegistry.CAP_HAS_OFFICES,
	InstitutionRegistry.CAP_HAS_TERRITORY,
	InstitutionRegistry.CAP_TEACHES,
]

## The def class a `sect` kind's registry row names. Loaded HERE, in the module that
## owns the def, because `core/` may not resolve a path into `modules/`
## (`InstitutionRegistry` states the same rule).
const DEF_SCRIPT := preload("res://src/modules/sect/sect_def.gd")
## The `class_name` that script declares — a label a panel prints and a save may carry.
const DEF_TYPE := "SectDef"

## The pool a founder funds a sect from, and **deliberately NOT
## `InstitutionFounding.DEFAULT_FUNDING_POOL`.** The pool id is written into every
## actor's save, so it is a namespace a rename would break rather than a rule worth
## sharing — the same reasoning `InstitutionLedger` gives for `SOURCE_PREFIX`. The
## profile NAMES it and the generic path reads the name, so the funding RULE is shared
## and only the currency is the sect's own.
const FUNDING_POOL := &"sect_founding_funds"

## What founding starts a sect's treasury with, in periods. **Aliased from the generic
## writer**, which owns the line and the number: a second copy would be a cap two files
## could disagree about (ADR 0066), and this slice's whole subject is that founding is
## one path.
const TREASURY_OPENING_PERIODS := InstitutionFounding.TREASURY_OPENING_PERIODS

## ## The FIRST RUNG: a founding member is RECOGNISED by their own school
##
## `teach` is the only verb that writes `fit` (`sect_teaching.gd:79`), it refuses a
## teacher below the doctrine's `affinity_floor`, and fit starts at 0 — so the ladder
## had no rung a player could stand on: a fresh founder held fit 0, every shippable
## doctrine authors a floor above 0, and `teacher_unfit` was the only reachable
## verdict. The gate itself is load-bearing and STAYS (ADR 0084: fit is a gate that
## projects no stat). What was missing is the state the gate reads.
##
## ## Why a grant, and not a lower floor or an exemption
##
## The three options weighed were a doctrine-level floor of 0 for a school's own
## doctrine, a first-teacher exemption, and an authored grant at founding. The floor
## of 0 is rejected because it is exactly "weaken a gate to make this pass": it makes
## EVERY member of the house teachable with no transmission at all, not just the one
## who made the school. The first-teacher exemption is rejected because it hands the
## floor to whoever happens to hold the top office, which is a vacancy a succession
## walks — so the exemption would follow a SEAT, not a person, and `declare_schism`
## would let a rival house promote somebody into it.
##
## The grant is the one that is about the FOUNDING ACT rather than about a seat or a
## doctrine's number: founding a school is authoring a curriculum, and the person who
## authored it is recognised as the one who can first deliver it. It is capped at the
## doctrine's own floor, so it never buys a teaching post above the bar and never
## projects a stat (ADR 0084).
const FOUNDER_FIT_POINTS := 35
## The cap the grant stops at. **The doctrine's own `affinity_floor`, never a number of
## its own** — applied in [method founder_fit], not here, so `FOUNDER_FIT_CAP` stays a
## DERIVATION of the points rather than a second number that could disagree with them.
const FOUNDER_FIT_CAP := FOUNDER_FIT_POINTS

## A standing value a member is REFUNDED by founding their own sect: they paid for it,
## so charging them again would make the price of existing an infinite regress. Not a
## percent and not a multiplier — a floor would make founding a demotion and a
## multiple would make it a grant, and ADR 0064's split says it is neither. The clamp
## against the sect's own cap is applied in [method _founder_standing], so this stays
## the one authored number.
const FOUNDER_REFUND_STANDING := SectState.FOUNDER_REFUND_STANDING

## ## The refusal NAMES, ALIASED from the shared vocabulary rather than restated
##
## A writer that moved is still the same game rule, so a caller writing
## `SectFounding.R_ALREADY_FOUNDED` and a caller writing
## `InstitutionLedger.R_ALREADY_FOUNDED` are holding one value. `sect_founding.gd`
## used to write all six strings out again, which is the ADR 0066 failure mode inside
## the file that exists to stop it — and the strings have since crossed the facade, so
## a panel that renders a reason it did not invent would break the moment one side was
## renamed.
##
## **`R_UNKNOWN_SECT` is the one name that is NOT an alias, and it cannot be.** The
## generic vocabulary says `unknown_institution` because `core/` may not know that a
## sect is a thing; `SectApi.UNKNOWN_SECT` has always said `unknown_sect` and a save's
## history record and a screen's copy both quote it. The sect's own refusals still fire
## before the generic path is reached, so the generic's spelling is never the one a
## player sees.
const R_NO_ACTOR := InstitutionLedger.R_NO_ACTOR
const R_UNKNOWN_SECT := "unknown_sect"
const R_UNKNOWN_DOCTRINE := "unknown_doctrine"
const R_ALREADY_FOUNDED := InstitutionLedger.R_ALREADY_FOUNDED
const R_NO_TOP_POSITION := InstitutionLedger.R_NO_TOP_POSITION
const R_FOUNDING_COST_UNMET := InstitutionLedger.R_FOUNDING_COST_UNMET

## The sect's six reasons keyed by the name each is written with. A **SUPERSET** of the
## shared table rather than a second copy of it: `unknown_sect` and `unknown_doctrine`
## are this tier's own, so a lookup by name has to find them here. Every shared reason
## holds the shared value, which `test_sect_migration.gd` asserts rather than assumes.
const REASONS := {
	R_NO_ACTOR: InstitutionLedger.R_NO_ACTOR,
	R_UNKNOWN_SECT: R_UNKNOWN_SECT,
	R_UNKNOWN_DOCTRINE: R_UNKNOWN_DOCTRINE,
	R_ALREADY_FOUNDED: InstitutionLedger.R_ALREADY_FOUNDED,
	R_NO_TOP_POSITION: InstitutionLedger.R_NO_TOP_POSITION,
	R_FOUNDING_COST_UNMET: InstitutionLedger.R_FOUNDING_COST_UNMET,
}


## ## The registry a sect's founding is resolved against, and why sect registers it
##
## `InstitutionFounding.found` takes a registry as an ARGUMENT rather than reaching
## for a global, because "which kinds exist" is a fact about one boot. **Nothing ships
## the `sect` row**: `InstitutionBoot.install()` discovers `.tres` under
## `res://data/institutions/`, and sect content lives at `res://data/sect/` on its own
## def class, so the boot cannot see it — and `install()` itself has no production
## caller yet (ADR 0271's Consequences, DEF-0326). A tier that cannot answer its own
## capability question would have to be refused `unknown_kind` on every founding, which
## is the invented default the registry exists to refuse.
##
## So the module that OWNS the declaration registers it, **into the shared instance and
## only when the row is absent**: whoever gets there first wins, there is exactly one
## `sect` row per process, and a `clear()` by a suite leaves the next call to
## re-register rather than to fail. A later wiring of the boot needs no change here.
static func registry() -> InstitutionRegistry:
	var shared := InstitutionRegistry.instance()
	if not shared.knows(KIND):
		shared.register(KIND, DEF_TYPE, CAPABILITIES, DEF_SCRIPT)
	return shared


## Whether this ledger already names an institution. A delegate, never a second
## definition of "founded": `found` is the only verb that may write one, and an actor
## may found exactly one sect because the tiers are peers, not a containment tree
## (ADR 0083). `SectState.is_affiliated` and `InstitutionFounding.founded` ask the same
## question and must answer it the same way, so this is one call.
static func founded(ledger: Dictionary) -> bool:
	return InstitutionFounding.founded(ledger)


## ## The PROFILE the generic founding consumes — the whole seam
##
## A plain `Dictionary` of primitives assembled here and nowhere else, because `core/`
## may not name a `SectDef`. **Every key below is one `found` or `write` actually
## reads**, and there is no key nothing reads.
##
## ## `founding_cost` is TRANSLATED HERE, and that is the decision
##
## `SectDef.founding_cost` is authored `{currency, amount, found, outstanding}` — four
## keys, one of them a coin a panel renders — while `InstitutionFounding.cost` reads a
## NUMBER off the profile. Handing the dictionary over unchanged does not fail: the
## cost reader explicitly coerces a non-numeric value to `0`, so **every sect would
## found for free**, silently, and founding is priced on purpose (BL-0174). So the
## tier translates.
##
## The alternative — teaching `core/` to accept the dictionary — was rejected for two
## reasons, both measured. `InstitutionDef.founding_cost` is an `int` and its own
## `founding_profile()` passes it straight through, so a dictionary in `core/` would
## make the generic def's own authored shape the second one. And `currency` is a
## display concept with no other use anywhere in `core/`, which is the same mistake
## `InstitutionLedger` refuses one layer down by not knowing its own save slot. The
## profile is documented as "a plain dictionary of primitives the tier assembles from
## its own defs"; translating an authored shape into that contract is the tier's job.
static func profile(def: SectDef, doctrine: SectDoctrineDef) -> Dictionary:
	var top := def.top_position()
	var office_lines := {} if top == null else top.obligation_lines()
	var points := founder_fit(doctrine)
	return {
		"kind": String(KIND),
		"institution_id": String(def.id),
		"top_position": "" if top == null else String(top.id),
		"standing_cap": maxi(1, def.standing_cap),
		"founder_standing": _founder_standing(def),
		"founding_cost": int(cost(def)["outstanding"]),
		"funding_pool": String(FUNDING_POOL),
		"treasury": treasury_lines(def),
		"obligation": def.member_obligation_lines(),
		"office_obligation": office_lines,
		"fit": {} if points <= 0 else {String(doctrine.id): points},
	}


## The treasury lines founding opens: one per office this sect authors that carries an
## authored rate. **No opening line of our own** — `InstitutionFounding` opens
## `<prefix>all` for the institution itself, and two names for one line is the ADR 0066
## failure mode; see the class note.
##
## Every line is namespaced `treasury_<sect_id>_<what>` because the ledger belongs to
## a person, not to an institution: two sects may both owe the same actor's save, and
## a line one of them cannot see is a line it cannot accidentally settle.
##
## A `for` over the AUTHORED offices writing into a NEW dictionary: the body never
## grows the array being walked, so the bound is the content's own length and there is
## no shape here for a loop to grow in lockstep with its own bound
## (`tests/arch_rules/test_no_unbounded_wait.gd`).
static func treasury_lines(def: SectDef) -> Dictionary:
	var prefix := "treasury_%s_" % String(def.id)
	var out := {}
	for office in def.positions:
		if office == null or office.id == &"":
			continue
		if office.patronage_per_period > 0:
			out["%spatronage_%s" % [prefix, String(office.id)]] = office.patronage_per_period
		if office.duty_per_period > 0:
			out["%sduty_%s" % [prefix, String(office.id)]] = office.duty_per_period
	return out


## What this sect charges to exist: `{found, outstanding}`, read off the AUTHORED
## dictionary. This is the one place `SectDef.founding_cost`'s shape is known, and the
## profile hands the generic writer the number [method profile] derives from it.
##
## `found` and `outstanding` are both the authored `outstanding` (falling back to
## `amount`), and both keys are kept because `SectPayloads.found_unmet` publishes them
## as the shortfall a panel renders. A negative authored cost is clamped to zero, so a
## hand-edited `.tres` cannot make a price pay its holder.
static func cost(def: SectDef) -> Dictionary:
	var authored = def.founding_cost.get("outstanding", def.founding_cost.get("amount", 0))
	var amount := 0 if not (authored is int or authored is float) else maxi(0, int(authored))
	return {"found": amount, "outstanding": amount}


## What this actor has put into the sect's founding pool. A delegate to the shared read
## with the sect's own pool named, so the BALANCE is one rule and the CURRENCY is
## this tier's. Zero for an actor who funded nothing, which is the ordinary case and
## never an error — "this member has no founding fund" and "this member spent it all"
## are the same answer.
static func funds(actor: Actor) -> float:
	return InstitutionFounding.funds(actor, FUNDING_POOL)


## Take `amount` off the sect's founding pool. A delegate for the same reason as
## [method funds], and with the same no-op semantics: a settlement is never a negative
## accrual, and an actor with no pool has nothing to take.
static func draw(actor: Actor, amount: float) -> void:
	InstitutionFounding.draw(actor, FUNDING_POOL, amount)


## The points the founding grant writes for `doctrine`, and never more than the floor.
##
## Capped at `min(FOUNDER_FIT_CAP, doctrine.floor_fit())` for two reasons, and the
## second is the one that keeps ADR 0084 honest. A floor of 0 would hand the grant
## nothing (there is no rung to stand on in a school that authors no floor — refusing
## is then the correct answer), and a floor of 35 gets exactly 35: the founder may
## teach the school they founded and may teach nothing else they have not been taught.
##
## **It also may never exceed `SectState.FIT_CAP`**, which is asserted rather than
## assumed: `FOUNDER_FIT_POINTS` is 35 against a fit ceiling of 100, and a retune that
## pushed the grant past the ceiling would hand a founder a fit the rest of the module
## clamps away on read — a grant that reads as smaller than it was.
static func founder_fit(doctrine: SectDoctrineDef) -> int:
	if doctrine == null:
		return 0
	return clampi(FOUNDER_FIT_POINTS, 0, mini(FOUNDER_FIT_CAP, doctrine.floor_fit()))


## ## The standing a founder starts on: the refund, clamped into the sect's own cap
##
## Written here rather than in `core/` so the CLAMP is the tier's, against the tier's
## authored cap, and `InstitutionFounding` keeps its one job of clamping whatever the
## profile says. A floor would make founding a demotion and a multiple a grant; ADR
## 0064's split says it is neither.
static func _founder_standing(def: SectDef) -> int:
	return mini(FOUNDER_REFUND_STANDING, maxi(1, def.standing_cap))
