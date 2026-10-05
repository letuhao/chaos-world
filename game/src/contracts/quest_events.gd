class_name QuestEvents
extends RefCounted

## Signal contract for the `quest` module (ADR 0266, ADR 0093). Emitted by the module;
## consumed by any observer.
##
## Everything here announces a fact **already written to the ledger**: an acceptance, a paid
## completion, or a named refusal that wrote nothing. A consumer must never treat one as a
## request it can veto — that is the line ADR 0093 draws between an event and a hook.
##
## ## Primitives only, and why that is a rule rather than a style
##
## No `Resource`, no `Actor`, no `Dictionary` of authored content crosses this boundary. A
## quest completion publishes IDS because the thing that happened is a fact about the world's
## ledgers, and every number a consumer could want — what was paid, what was left unspent,
## which grants a quest declares — is already readable from `QuestApi.summary(actor)`.
## Carrying the `QuestDef` instead would let a payload smuggle shared mutable content past
## every boundary the layer rules draw, and would hand a subscriber a live editor handle on
## shipped content. The same reasoning `BeatSink` states for a sink's return payload (ADR
## 0114) and `DamageProposal.is_primitive_effect` enforces by refusing at construction.
##
## ## `shared()` — NOT a fresh instance per subscriber, and the reason is load-bearing
##
## A `RefCounted` cannot emit a signal without an object to emit on, so someone holds the
## instance. There are two house answers: hold it on the module behind a facade accessor
## (`ConflictApi.events()`, `HoldingsApi.events()`), or hold it here as a process-wide static
## (`NpcEvents.shared()`, `AuctionEvents.shared()`). **Quest takes the static, because a mod
## subscriber names the BUS CLASS and nothing else.**
##
## ADR 0242 resolves a subscription's `event_bus` string through `_resolve_events_bus`, and a
## contract-level `shared()` lets that table say `QuestEvents.shared()` with no module edge at
## all — `contracts/` is the leaf layer (`LAYER_DEPS` in `tools/arch/rules.py` is
## `contracts: {contracts}`), so a static here invents no dependency. A facade accessor would
## make `app/`'s factory table name `QuestApi` — a module facade — where it otherwise names
## only contract classes — and would grow a facade that is already over `LINE_BUDGET`.
##
## **The alternative this rejects is fatal to this contract's only purpose.** The other five
## buses in `_resolve_events_bus` are handed out as `SomeEvents.new()`, one fresh object per
## lookup. A subscriber therefore connects to an instance NOTHING holds and NOTHING emits on,
## so the subscription is dead on arrival — and `is_connected` will report it connected
## forever. A registrable System whose entire economy is one quest subscription would pay a
## reward it never receives, with no error anywhere. `shared()` is what makes the difference
## between a bus and a discarded object, and it is why this contract does not take the shape
## the majority of the buses take.
##
## ## What is deliberately NOT here: an "offered" signal
##
## An offer is not a fact. `QuestApi.offered()` RE-DERIVES it on every call from the gate and
## the ledger, and `summary()` reaches it too — so a signal emitted there would fire every time
## a player opened a screen, turning a read into a publisher and putting game logic in the UI
## refresh path. Acceptance is the real door (a `systemic` or `emergent` quest is entered by
## `accept` and never offered at all, per BL-0053), so `quest_accepted` is the announcement.

## A quest was taken on and is now in flight. `source` names where the offer came from
## (`"npc:elder"`, `"event:..."`) and is EMPTY when nothing declared one — a caller that
## reached the module directly has not said, so a consumer must not read empty as "unknown
## origin". This is the one announcement a System can act on before the quest finishes.
signal quest_accepted(actor_id: String, quest_id: StringName, source: String)

## A quest COMPLETED and its grants were PAID, at the ONE place completion is decided
## (`QuestApi._complete`, which both `advance` and `complete` route through). `source` is the
## caller's own provenance string and is empty on the explicit `complete()` path.
##
## **Fires once per quest, never twice.** `QuestState.finish` is the once-guard and it runs
## before any grant is paid, so a repeat call announces nothing and pays nothing — a consumer
## may treat this as "the reward landed" rather than as "a verdict was offered".
signal quest_completed(actor_id: String, quest_id: StringName, source: String)

## A refusal that wrote nothing, carrying the named reason so a panel renders the rule it was
## given rather than inventing one, and so an action failing is observable rather than silent.
##
## **The one signal here that announces something did NOT become true**, and that is the point
## of it rather than an exception to the contract, exactly as `ConflictEvents.conflict_refused`
## and `HoldingsEvents.holding_refused` are. The two are independent facts: the returned
## dictionary carries `ok: false`, and this carries WHICH rule refused and ON WHICH QUEST.
## Emitted from `QuestApi._refuse`, the single place every refusal on that facade is built, so
## no call site can forget to announce. `quest_id` is `&""` when the catalog did not define the
## id, because then there is no quest to name.
signal quest_refused(actor_id: String, quest_id: StringName, reason: String)

## ## The one bus, and why it lives HERE rather than behind `QuestApi.events()`
##
## `contracts/` is the leaf layer (`LAYER_DEPS` in `tools/arch/rules.py`), so a static here is
## a legal home for a shared instance and no dependency is invented to carry it. See the class
## docstring for why the facade accessor was rejected here and a fresh instance is fatal.
static var _shared: QuestEvents = null


## The single bus every quest-event publisher and subscriber shares. Stable across calls, so a
## subscriber that connected once is still connected the next time this is asked for — which is
## the whole difference between a live subscription and a dead one.
static func shared() -> QuestEvents:
	if _shared == null:
		_shared = QuestEvents.new()
	return _shared
