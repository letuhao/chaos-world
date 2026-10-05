class_name SectDoctrineDef
extends Resource

## One authored school of thought: what a sect exists to TEACH, and what it
## refuses (BL-0186).
##
## ## Doctrine is content, never a hierarchy
##
## Nothing here ranks one doctrine against another. "Which sect teaches what" is a
## `.tres` question exactly as authority is (ADR 0084), and two sects sharing a
## doctrine are rivals rather than duplicates — so the id is the identity, not the
## sect that happens to point at it.
##
## ## Affinity and comprehension are two different gates
##
## `affinity_floor` is **fit**: the fit between this member and this doctrine, read
## as a plain integer off the ledger (`SectState.fit`), never off a derived stat. It
## is a gate and nothing else — a stat can be satisfied by an item, and "may I be
## taught this here" becoming something a grinder can buy is the failure ADR 0076
## measured. A teacher below the floor cannot teach at all.
##
## `comprehension_floor` / `comprehension_span` are a band on `Stat.COMPREHENSION`
## read from **BASE ALLOCATION ONLY** (`actor.stats.get_base(...)`, never
## `derived`). ADR 0052/0054 pinned that deliberately: *"a technique can never
## satisfy its own requirement with the stats it grants."* Reading `derived` would
## let a standing percent — a grant this module itself projects — fund its own gate,
## which is precisely the smuggling `set_base` was rejected for.
##
## ## Teaching may be refused by name
##
## `refusals` is a closed, authored list of named verdicts a teacher may hand back
## (`unready`, `contradicts`, `already_known`). The facade publishes the reason
## string it was given rather than inventing one, so the vocabulary lives in
## content and a panel never has to invent a wording (ADR 0084).
##
## ## Fit projects ZERO modifiers
##
## Affinity is transmission, one of the three things an institution grants, and
## `SectProjection` grants nothing from it: recognition is `standing_percent` on an
## authored allowlist and nothing else (ADR 0084). A cap on a number that is a gate
## is what stops it becoming a currency — comprehension is the one thing this repo
## says cannot be bought.
##
## Adding a doctrine is authoring a `.tres` under `res://data/sect/doctrines/`,
## never code.

## One session of instruction, in fit points. A pure rate: it is multiplied by the
## number of periods asked for and never rolled, because a lesson that might not
## land is a gate that can satisfy itself (ADR 0084).
const TEACH_FIT_PER_PERIOD := 3
## A teaching session takes this much of the teacher's own life. A real cost is the
## whole point (BL-0188): teaching that is free and unlimited makes disciples a
## resource faucet. Defaults to nothing so an author opts IN to a cost.
const TEACH_TAX_DEFAULT := 0.0
## How much one call may teach. A ceiling rather than a `while`: ADR 0058's
## ascension is walked one stage per call, and the same bound applies here.
const MAX_TEACH_PERIODS := 8

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice: what is practised here and
## what the house will not do (AGENTS.md).
@export var description: String = ""

## What this doctrine teaches, as authored verb ids. Counted and rendered, never
## executed: this module owns no technique verbs, and a technique the sect may
## teach is gated through `contracts/` rather than granted from here (ADR 0083).
@export var teachings: Array[StringName] = []
## The named verdicts a teacher may hand back. Closed and authored: the facade
## publishes one of these rather than composing free text.
@export var refusals: Array[StringName] = []

## The comprehension band this doctrine is practised at. Read from base allocation
## only — see the class note on why `derived` would let a grant fund its own gate.
@export var comprehension_floor: float = 0.0
@export var comprehension_span: float = 0.0
## The fit below which this doctrine cannot be taught at all. A member under it can
## still hold standing, hold an office and owe duties; they simply cannot be taught
## this thing, which is a route rather than a wall.
@export var affinity_floor: int = 0
## One session of instruction, in fit points.
@export var fit_per_period: int = TEACH_FIT_PER_PERIOD
## What one session costs the teacher, over and above their office's `teach_tax`.
@export var teach_tax: float = TEACH_TAX_DEFAULT


## The fit needed before this doctrine may be taught. Never negative: an
## unshipped floor of `-1` would be a lower bar than no bar at all.
func floor_fit() -> int:
	return maxi(0, affinity_floor)


## The fit `point` points sits above the floor by — a pure readout of a pure
## comparison, and the only way a panel can say "so far above the bar" without
## re-deriving it. Written in points of 100 because `comprehension` in this repo
## is a 0-100 sheet.
func fit_margin(point: int) -> int:
	return clampi((point - floor_fit()) * 100 / maxi(1, SectState.FIT_CAP), 0, 100)


## Whether `point` points of fit clears this doctrine's floor.
func teaches_at(point: int) -> bool:
	return point >= floor_fit()


## Whether this office's office-level `teach_tax` plus this doctrine's own tax is
## the price of one session. Summed here so the two authored numbers add up in one
## place rather than in every caller's head — the price of a lesson is the doctrine's
## tax plus the office's, and a screen has to render one number.
func tax_for(position: SectPositionDef) -> float:
	var office_tax := 0.0 if position == null else position.teach_tax
	return maxf(0.0, office_tax + teach_tax)


## The comprehension band this doctrine admits, as `[floor, floor + span]`. The
## high end is an equality bound, never an exclusive one: a band whose upper edge
## has to be beaten rather than reached is a band an author cannot author by writing
## down the number they meant.
func comprehension_band() -> Vector2:
	var low := maxf(0.0, comprehension_floor)
	return Vector2(low, low + maxf(0.0, comprehension_span))


## Whether `allocation` — a BASE comprehension value, never a derived one — sits
## inside this doctrine's band.
func admits_comprehension(allocation: float) -> bool:
	var band := comprehension_band()
	return allocation >= band.x and allocation <= band.y
