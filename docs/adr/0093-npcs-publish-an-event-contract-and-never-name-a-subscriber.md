# 0093 Npcs publish an event contract and never name a subscriber

- Status: Accepted
- Date: 2026-10-03

## Context

The brief: this feature touches almost all gameplay, will take many waves, and future features — quests, reputation, combat, recruitment, teaching, spawning, saves, UI — must wire to it **without editing it**. That is the build-independence requirement, and it is the thing most likely to be got wrong, because the cheapest way to let a quest advance a story npc is for `npc/` to import the quest module and call it.

That inverts the dependency the whole repo is built on. The module boundary exists so the rules that own a rule sit next to it (AGENTS.md, `tools/arch/rules.py`). A feature that reaches sideways into `npc/`'s internals to advance a stage has made the npc module change every time a quest changes, which is exactly the coupling the facade rule forbids.

A second risk is over-building the seam. The design review proposed a contracts-layer `NpcState` value object, a `NpcDecision` pull interface, and a requirement class — three files whose only implementor is the module that defines them.

## Decision

**The seam is one event contract in `contracts/`, a facade accessor, and authored gate requirements. Everything else stays inside the module.**

- `contracts/npc_events.gd` — `NpcEvents`, shaped like `world_events.gd` and `destiny_events.gd`. Signals: `npc_tracked`, `npc_transient`, `stage_advanced(npc_id, stage_id, source)`, `bond_changed`, `presence_changed`, `npc_restored`, `decision_answered`. Primitics only, one fact per signal.
- **Every signal announces what already happened. None is a request and none may be vetoed.** A subscriber reacting to `stage_advanced` cannot stop the stage advancing, which is what keeps story progression out of a vote.
- `NpcApi.events()` is on the facade, because a subscriber in another module must be able to *reach* it. This is the specific failure that makes `DestinyProjection.events()` unusable across a module boundary: the accessor exists but nothing outside the module can get to it.
- **A subscriber connects from its own boot function**, which `app/` calls: `NpcApi.events().stage_advanced.connect(Callable(QuestApi, "_on_npc_stage"))`. The dep is added in `registry.json`; the npc module names no consumer. That is the inversion: the observer registers with the subject, not the reverse.
- **The pull half is an authored `Dictionary` requirement, not an interface.** A consumer asks `SocialApi.gate(actor, {"verb": &"bond_at_least", ...})` or reads `NpcApi.summary(id)`. Combat wanting a stance decision evaluates the requirement itself; it does not need the npc module to call it back.
- `summary()` and `state()` are the read models: primitives only, `{}` when there is no subject, which is the contract a panel tests instead of pixels.

### Refused, with the trigger that would justify each

- **No `NpcState` value object in `contracts/`.** The ledger inside the module is the truth; a contracts-layer copy would be a second source of truth that could disagree with it, and the repo already warns that a `Resource` in `contracts/` is a placement smell. Trigger: a consumer genuinely needs the value object without the facade.
- **No `NpcDecision` pull interface.** It has zero implementors today and combat's need is already served by evaluating a gate requirement — that is ceremony with a future-shaped excuse. Trigger: a second consumer must *ask a question and wait for an answer* rather than evaluate one.
- **No requirement value object in `contracts/`.** The requirement stays a `Dictionary` with a closed verb set, exactly `RaceGate`'s shape. Trigger: a second consumer must *build* a requirement in code rather than deserialize one — a quest editor tool, a fixture builder.
- **No dialogue contract.** Deferred in the repo (`DEF-0014`), and out of scope for a tier system.

## Consequences

- Eight future consumers wire to the npc feature without a single edit to it. The two that already have a shape — `summary()` and `gate()` — need no new plumbing at all.
- A subscriber that connects late is not broken: a signal is not a queue, so the recovery contract is to read `NpcApi.summary(id)` once at wire time. That is stated rather than left to be discovered.
- Adding a seventh consumer costs a facade verb, and the facade is at twelve — so the trigger for a split is explicit rather than discovered as an overgrown file.
- **Cost this ADR accepts:** an event that fires before a subscriber connects is lost. That is accepted because a durable event log is a queue, and a queue in `app/` would be a stateful system in the composition root (`tools/arch/rules.py` flags exactly that shape).
- **Cost this ADR accepts:** `bond_changed` carries a cause id, not a numeric delta, so a consumer that needs the magnitude reads the ledger. That is the anti-farm rule surviving into the event contract — a subscriber cannot recompute the change from a number and re-derive a class that disagrees.