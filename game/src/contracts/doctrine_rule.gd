class_name DoctrineRule
extends RefCounted

## One registrable System (道統): a transmitted body of rules a practitioner opts
## into, farms on its own counter, and spends (ADR 0267).
##
## ## What a System IS, and why its counter is not the ladder
##
## A doctrine is the one progression surface here that is EXTRADIEGETIC — it is the
## player's own transmitted rules, not a fact about the world — which is why its
## counter may run far past the world's thirty realms. So the shape is a flat
## integer COUNTER plus tiers derived from it, and **no method here takes a realm id
## or returns a multiplier**: a doctrine cannot become a second magnitude table
## because there is nowhere in this contract to put one. That is the whole answer to
## the hard question "does a System scale with power", and it is a shape answer
## rather than a rule a reviewer has to remember. If a future System needs a
## magnitude, that is a new power-shaped number and needs its own ADR — ADR 0001
## already makes `core/realm_power_table.tres` the only one.
##
## ## Why `redeem` is the ONLY mutator
##
## `boards` and `price` are reads and must stay reads. A screen renders a board and
## a player reads a price before pressing anything, so a read that wrote would make
## a board unrenderable (it moved under the reader) and a price untrustworthy
## (asking what it costs would cost it). `redeem` being the single write is the
## entire safety story: "where can this System change an actor" has exactly one
## answer, and the contract test can hold it there.
##
## `earn` deliberately does NOT mutate either, which is not the same rule twice. An
## earn is EVENT-driven and two Systems may answer the same occurrence, so the
## arbitration has to sit with the caller that owns the event — ADR 0067's "a
## mechanism returns a proposal" and ADR 0114's `resolve` answering to a director.
## A spend is the opposite: one player press, one row, one self-contained
## transaction, so it needs no arbiter and is applied here.
##
## Rejected: an `apply(actor, row_id, amount)` that AWARDS, splitting the write from
## the spend. It makes a spend with no award reachable and an award with no spend
## reachable, and neither half is a state anybody wanted.
##
## ## Why the currency has an earn AND a sink
##
## `resource_ids()` is what this System earns in and `boards()` is where it goes
## out. A System that declares a pool no row spends is an accumulating debt
## (`AGENTS.md`'s yin-yang rule: a resource generated with no place to spend it), so
## the contract publishes BOTH halves as questions and the contract test asserts the
## pairing. That pairing is checkable here and nowhere else, because the module does
## not exist yet.
##
## What this contract deliberately does NOT catch: a pool id that is not in ANY
## registry anywhere. There is no such list in this repo, so a typo'd id is a silent
## `0.0` and the honest place to fix it is the declaration seam that owns the
## vocabulary — not a check bolted onto an interface that cannot see the vocabulary.
##
## ## Why every return is primitives-only
##
## `ui/` holds only the facade, so a payload carrying a `Resource`, an actor or a
## `Callable` is a second vocabulary reaching a screen through a side door — and
## these payloads are what a module writes through `Actor.set_module_data`, so it
## would be a save-schema bug no gate can see. `DamageProposal.is_primitive_effect`
## (ADR 0067) refuses one at CONSTRUCTION; this contract constructs nothing, so the
## same rule is published as [method is_primitive_payload] for the one boundary that
## has to hold it. Rejected: returning rows as a typed array of an authored
## `Resource` — `contracts/` has no authored content at all
## (`tools/arch/rules.py` `RESOURCE_HOME_UNITS`), and a save schema has no business
## in the leaf layer.
##
## ## Why the actor arrives as `Variant`
##
## `contracts/` is a leaf: `tools/arch/rules.py` `LAYER_DEPS` declares
## `contracts: {contracts}`, so it may depend on nothing and naming `core` is a
## violation the gate reports, not a convention. `BeatSink` and `LocationResolver`
## are the precedents for typing a contract's arguments loosely, and both say so in
## their own docstring rather than leaving the next agent to "fix" it. Rejected
## alternatives, in order of how nearly they worked:
##
## - **Move `Actor` into `contracts/`.** Legal, and it inverts ADR 0001: the actor
##   base is the single source of stats for ALL actors and belongs in the layer
##   everything may reach.
## - **An `ActorLike` interface here.** A second vocabulary for one actor, which
##   would have to redeclare every core method a rule legitimately calls, and would
##   be enforced by nothing.
## - **A `preload` of the actor script.** The arch detector reads a file's RAW text
##   for its path prefix — comments included — so this fails the gate identically
##   while merely looking like a workaround. Hence the wording above avoids the
##   literal outright.
##
## So the actor is `Variant` and every implementation casts it once at the top. Note
## the asymmetry with `StatProvider.contribute(context: StatContext)`: a contract MAY
## type a parameter when the type lives in `contracts/` (see `PathState` in
## `ProgressionModel`). The loose signature here is not a looser style — it is the
## rule.
##
## ## Why this is an abstract class and not a `Dictionary` of callables
##
## Same reason as `BeatSink`: "any script implementing a `contracts/` interface must
## pass the same contract tests" (AGENTS.md's LSP rule) needs a NAME to point at. A
## dictionary of lambdas has none, so the rule becomes unenforceable exactly when a
## second System is added.
##
## ## Why the defaults are no-ops that fail SAFE
##
## Every default below declines rather than guesses. `system_id` is empty, so an
## unnamed System cannot be registered and `data_key` is empty so two of them cannot
## collide on one save slot. `boards` is empty. `progress` is zero. `tier_for` is
## tier 0 of 0, so every row gated above tier 0 stays locked. `earn` claims nothing,
## so the balance never rises. `price` and `redeem` refuse. The consequence is that
## a rule which forgets an override renders a board it cannot pay for — inert, and
## visibly so — instead of one that grants a row for free. A default that returned an
## affordable price would be a stub that lies, and the one failure mode this design
## cannot recover from is a System that hands out its own rewards for nothing.

## The prefix every System's persisted state is keyed under. See [method data_key].
const DATA_KEY_PREFIX := &"doctrine/"

## ## The closed set of refusal reasons
##
## A reason is a NAME, not prose, for the same reason `OwnerRef.UNKNOWN_KIND` is:
## a screen, a test and a log line all have to compare it. `reason` is `""` on
## success and carries one of these otherwise, so "refused" is never the empty
## string and never a re-derivation. Extending the set is an ADR.
const NOT_CLAIMED := "not_claimed"
const TIER_LOCKED := "tier_locked"
const ALREADY_MAXED := "already_maxed"
const UNDECLARED_POOL := "undeclared_pool"
const INSUFFICIENT := "insufficient"

## Every reason above, as one list, so a caller that must VALIDATE a refusal reads
## the set rather than keeping a second copy of it — the decay BL-0619 is about.
##
## There is deliberately NO reason for "no such row". That answer is `{}`, not a
## refusal: a row this System does not sell has not refused anything, and giving it
## a reason string is how a panel ends up rendering a refusal on a row that was never
## there (ADR 0083's three-state vocabulary).
const REASONS: Array[String] = [
	NOT_CLAIMED,
	TIER_LOCKED,
	ALREADY_MAXED,
	UNDECLARED_POOL,
	INSUFFICIENT,
]

## The keys a row on `boards()` carries. Every one, always: a panel draws from this
## and must not have to ask the module what a row might mean.
##
## ## Why the keys are declared and not described
##
## `DamageProposal.is_primitive_effect` is public "because the shape IS the
## contract: a rule nobody can ask about is a rule nobody checks". The same applies
## here one step up: a required-key list in prose is a list the next implementer
## reads once and forgets, and the contract test needs something to iterate to hold
## every default to.
const ROW_KEYS: Array[StringName] = [
	&"row_id",
	&"label",
	&"tier_min",
	&"pool",
	&"amount",
	&"repeatable",
	&"max_count",
]

## The keys `price()` returns. `owned` and `affordable` are LIVE — they come from the
## actor's ledger and balance — which is the reason price is a read and cannot be
## derived by the caller from the row alone.
const PRICE_KEYS: Array[StringName] = [
	&"ok",
	&"reason",
	&"row_id",
	&"pool",
	&"amount",
	&"owned",
	&"affordable",
]

## The keys `redeem()` returns. `granted` carries what the universal grant verb
## answered, which is what lets a caller report the outcome without reaching into
## the actor's status list to rediscover it.
const REDEEM_KEYS: Array[StringName] = [
	&"ok",
	&"reason",
	&"row_id",
	&"pool",
	&"spent",
	&"granted",
]

## The keys `earn()` returns. `amount` is NON-NEGATIVE by contract: a negative "earn"
## is a spend wearing the wrong name, and the caller that applies this proposal owns
## the clamp.
const EARN_KEYS: Array[StringName] = [&"ok", &"reason", &"pool", &"amount"]

## The keys `progress()` returns. `points_max <= 0` means the counter has no
## ceiling, which is legitimate for an extradiegetic counter and is why nothing here
## bounds it: `AGENTS.md` bounds the OUTPUT, never the INPUT.
const PROGRESS_KEYS: Array[StringName] = [&"points", &"points_max"]

## The names a System PERSISTS its counter under, in the dictionary it reaches through
## `Actor.set_module_data` at its own `data_key()`.
##
## These are declared here rather than left to the framework because the framework is
## STRICT about them: the ledger normaliser rebuilds its dictionary from its own key
## list and copies nothing else, so a counter stored under a System's own key name is
## silently erased by the next write. A System has no way to discover that from the
## reads above — `points`, `points_max` and `owned` coincide with `PROGRESS_KEYS` and
## `PRICE_KEYS` by coincidence rather than by declaration, and `version`, `joined`,
## `balance`, `balances`, `earnings` and `redemptions` are published nowhere at all.
##
## That left a mod reaching one module class past this contract to learn which strings
## its own state is keyed by, which is precisely the coupling `contracts/` exists to
## prevent. A System therefore MUST use these names for its own half of the record —
## `points`, `points_max` and `owned` — and MUST NOT assume it may add keys of its own.
const PERSIST_KEYS: Array[StringName] = [
	&"version",
	&"joined",
	&"points",
	&"points_max",
	&"balance",
	&"balances",
	&"owned",
	&"earnings",
	&"redemptions",
]

## The subset a SYSTEM owns, as opposed to the framework half. `DoctrineRule.earn`
## returns a proposal and writes nothing, so the counter is the System's to advance
## inside its own `redeem`; `balance`, `joined`, `earnings` and `redemptions` are the
## framework's to move.
const SYSTEM_OWNED_PERSIST_KEYS: Array[StringName] = [&"points", &"points_max", &"owned"]

const VERSION_KEY := &"version"
const JOINED_KEY := &"joined"
const POINTS_KEY := &"points"
const POINTS_MAX_KEY := &"points_max"
const BALANCE_KEY := &"balance"
const BALANCES_KEY := &"balances"
const OWNED_KEY := &"owned"
const EARNINGS_KEY := &"earnings"
const REDEMPTIONS_KEY := &"redemptions"

## The keys `tier_for()` returns. `tiers` is how many the System has authored, and
## `next_tier_points` is `0` at the top tier — the two together are what a panel
## needs to draw a progress bar without asking a question this contract does not
## answer.
const TIER_KEYS: Array[StringName] = [&"tier", &"tier_name", &"tiers", &"next_tier_points"]

## ## How deep [method is_primitive_payload] will look
##
## The payloads this contract describes are shallow by construction — a dictionary of
## primitives, holding at most an array of primitives or an array of row
## dictionaries. The walk is recursive, and `AGENTS.md` is explicit that recursion
## needs a depth cap a `while` scan cannot see for it, so the cap is a constant here
## rather than a convention. Past the cap the answer is REFUSED: a payload too deep
## to verify is a payload this contract will not vouch for.
const MAX_PAYLOAD_DEPTH := 4


## The id this System is registered under, and the tail of its persisted state key
## (see [method data_key]). Empty by default, which is what makes an unnamed System
## unregistrable rather than silently addressable.
func system_id() -> StringName:
	return &""


## The name a panel prints for this System. Empty by default, and a screen falls back
## to the id — a blank title is a cosmetic defect, never a wrong grant.
func display_name() -> String:
	return ""


## Where this System's state is persisted, as the key it is stored under on an
## actor. Derived from [method system_id] so there is exactly one spelling of it in
## the repo; a hand-written key per System is a save nobody can find again.
##
## EMPTY when the System is unnamed, on purpose: every unnamed System would
## otherwise share one key, and two Systems writing the same dictionary is a save
## that restores one System's board into another's.
func data_key() -> StringName:
	if system_id() == &"":
		return &""
	return StringName("%s%s" % [String(DATA_KEY_PREFIX), String(system_id())])


## The pools this System earns in and spends. These are the SAME ids
## `CultivationPathDef.resource_ids` already creates lazily through
## `ensure_resources(actor)`, read here as a question this contract can ask — not a
## second pool registry, and not a new seam. No validation list exists anywhere in
## this repo, so a pool id this System declares but the game does not know is a
## silent `0.0`; that gap belongs to the declaration seam that owns the vocabulary.
func resource_ids() -> Array[StringName]:
	return []


## This actor's counter for this System. Read-only, and never bounded — see
## [constant PROGRESS_KEYS].
func progress(_actor: Variant) -> Dictionary:
	return {"points": 0, "points_max": 0}


## The tier this actor's counter has reached, DERIVED from [method progress] and from
## nothing else — no realm, no ladder index, no second factor. Read-only.
func tier_for(_actor: Variant) -> Dictionary:
	return {"tier": 0, "tier_name": "", "tiers": 0, "next_tier_points": 0}


## The rows this System sells `actor`, each a primitives-only dictionary carrying
## every key in [constant ROW_KEYS]. Read-only, and it MUST NOT mutate: a screen
## calls this once per frame, so a board that changed while being drawn is a board
## that cannot be drawn.
##
## MAY carry further primitives-only detail keys per row — a `blurb`, a `tags`
## array — for the reason `BeatSink.resolve` may: a panel must not have to re-derive
## a row's meaning from module internals it is forbidden to reach.
func boards(_actor: Variant) -> Array[Dictionary]:
	return [] as Array[Dictionary]


## What `row_id` costs this actor RIGHT NOW, or `{}` when there is no such row.
##
## `{}` for an unknown row and `{"ok": false, "reason": ...}` for a refused one are
## different answers (ADR 0083's three-state vocabulary: does-not-exist vs exists
## and its value is refused), and a panel that collapses them renders a refusal on a
## row that was never there. Read-only, and the reason it is its own method and not a
## field on the row is exactly that: `owned` and `affordable` come from the actor's
## ledger and balance, so the caller cannot derive them from [method boards].
func price(_actor: Variant, _row_id: StringName) -> Dictionary:
	return {}


## The ONE mutator: spend `row_id` for this actor and grant what it says.
##
## Returns `{}` when there is no such row, `{"ok": false, "reason": ...}` when it
## exists and is refused, and every key in [constant REDEEM_KEYS] either way. Writes
## go through the actor's EXISTING universal verbs and nowhere else — the stat grant
## is `Actor.add_status`, which already owns stacking, merging and stat-cache
## invalidation, and the ledger is `Actor.set_module_data`. This contract
## deliberately does not add a grant path, a stat composer or a save key of its own.
##
## MUST be idempotent per press: the caller owns whether a second press is allowed,
## and a rule that charged twice for one press would be undetectable from a screen.
func redeem(_actor: Variant, _row_id: StringName) -> Dictionary:
	return {}


## What this System earns from `event`, as a PROPOSAL the caller applies. Pure — see
## the class docstring for why an earn is arbitrated by the caller and a spend is not.
##
## Returns every key in [constant EARN_KEYS] — including on a refusal, because a
## declining proposal that answers `{"ok": false, "reason": ...}` and nothing else
## gives the caller a second payload shape to parse for the case it cares about.
## Claiming nothing is the correct default rather than a stub that lies: a System
## that never overrides this has no income, so its board is unaffordable and renders
## inert, which is the safe direction. `event` is primitives-only for the same
## reason every other payload here is.
func earn(_actor: Variant, _event: Dictionary) -> Dictionary:
	return {"ok": false, "reason": NOT_CLAIMED, "pool": &"", "amount": 0.0}


## Whether every value reachable inside `value` is a primitive this contract will
## carry. Public because the shape IS the contract — see the docblock on
## [constant ROW_KEYS]. Recursive to [constant MAX_PAYLOAD_DEPTH] and refusing past
## it, so an arbitrarily nested payload cannot turn a check into a walk with no end.
static func is_primitive_payload(value: Variant) -> bool:
	return _is_primitive(value, 0)


## The keys of `required` that `payload` does not carry, so a caller can be told
## which ones are missing rather than discovering a blank field on a screen.
## Non-recursive on purpose: it answers about one dictionary, and
## [method is_primitive_payload] answers about everything inside it.
static func missing_keys(payload: Dictionary, required: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for key in required:
		if not payload.has(key):
			out.append(key)
	return out


static func _is_primitive(value: Variant, depth: int) -> bool:
	if depth >= MAX_PAYLOAD_DEPTH:
		return false
	if value is Dictionary:
		var source := value as Dictionary
		for key in source.keys():
			# A `String`/`StringName` key is the only key this contract will carry;
			# anything else is an object key that no save round trip can restore.
			if not (key is StringName or key is String):
				return false
			if not _is_primitive(source[key], depth + 1):
				return false
		return true
	if value is Array:
		# `size()` is snapshotted by the `for` itself: this walk is over authored
		# payloads and appends nothing, so it cannot outrun its input (INC-0002).
		for entry in value as Array:
			if not _is_primitive(entry, depth + 1):
				return false
		return true
	return value is int or value is float or value is bool or value is StringName or value is String
