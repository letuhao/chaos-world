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

### Correction (2026-10-04, audit F2 / BL-0793) — appended, nothing above is edited

**The `decision_answered` named on line 18 is no longer on the contract. It was deleted.**
Line 18's list is left verbatim as the Accepted text; this section is the correction, and
it wins over line 18 where the two disagree.

`decision_answered(npc_id, kind, decision)` was declared at `npc_events.gd:34` and was
**never emitted anywhere in `src/` and never subscribed to**. It was the signal half of the
`NpcDecision` seam line 28 refuses below; the refusal was recorded, the signal was not
removed, and it sat on a published seam as a rumour of a decision system that does not
exist. Line 28's trigger — "a second consumer must *ask a question and wait for an answer*
rather than evaluate one" — has no second consumer, and BL-0745, the one feature that
would want it, is **blocked on a product ruling only the repo owner can make**. So the
signal is deleted rather than reserved: reserving it would have been a back door around
that ruling.

The other six are unchanged and each has a producer. The contract is now guarded by
`tests/modules/npc/test_npc_event_contract.gd`, which fails if any signal declared on
`NpcEvents` is neither emitted by production code nor named in an explicit, documented
reservation list. **This correction changes line 18 from seven signals to six, and adds no
new seam.**

### Correction (2026-10-04, audit N2) — appended, nothing above is edited

**What a signal on this contract now OWES, beyond being declared: a real producer, or a
documented reservation.**

The F2 guard above was shown by mutation to be satisfiable by a line nobody runs — a signal
declared with its only `.emit(` inside a function no production path reaches. So the rule
was rewritten to two narrower, true claims (`tests/modules/npc/test_npc_event_contract.gd`):

1. **The producer lives in the module layer.** Every signal must be emitted from a file
   under `src/modules/`. `app/` is where *subscribers* connect (line 21) and `ui/` is where
   panels read; a composition root announcing a module's fact is an inversion, not a
   producer. This is what closes the audited hole by construction, because the dead emit
   lived in `app/`.
2. **Every signal is observed or accounted for.** A production `.connect(` under `src/`, or
   an entry in `RESERVATIONS` carrying a written reason. Only `stage_advanced` has a
   subscriber today (`app/npc_boot.gd:67`), so the other five are now RESERVED with reasons
   — **this changes the F2 note's claim that `RESERVATIONS` is empty**, which was true when
   written and is superseded here.

**What the guard does NOT claim, stated so no reader over-reads it:** that an emit executes.
Static call-graph reachability was built and rejected, because it reports `NpcApi
.advance_stage` — the producer of the ONE signal that does have a subscriber — as dead: it
is reached only through an injected `Callable(NpcApi, "tally")`. A promise is kept by being
**wired and attributable**, not by being proven to fire; that needs a coverage run, not a
source scan. So declaring a signal here now means: you have a producer in the module that
owns the fact, and either a subscriber or a written reason why there is not one yet.

### Correction (N4, 2026-10-04) — appended, nothing above is edited

**One of the six signals has a subscriber. Five do not, and that is a recorded state, not a
defect to be closed by inventing consumers.**

`app/npc_ledger.gd` connects to **`stage_advanced`** only, from
`app/npc_boot.gd:_install_event_seams`. The other five — `npc_tracked`, `npc_transient`,
`presence_changed`, `bond_changed`, `npc_restored` — are all emitted by production code
(`npc/api.gd` and `social/api.gd`) and **no subscriber anywhere in `game/` connects to
any of them.**

**The rule this records:** a published contract may legitimately carry a signal whose
consumer has not been built yet. The obligation on the publisher is that every such signal
has a **named intended consumer or a stated reservation** — *not* that a consumer is
invented so the count looks complete. Inventing one is precisely what deleted
`decision_answered` above: a blessed seam with no implementor is a rumour of a system that
does not exist, and the previous round paid to remove one. The census in
`tests/modules/npc/test_npc_event_contract.gd` enforces the mechanical half as **Rule 2 —
observed, or the gap is written down**: every declared signal must have a production
`.connect(` under `res://src` **or** an entry in its `RESERVATIONS` dictionary carrying a
non-blank reason of at least twenty characters, and a reservation naming a signal the
contract does not declare is itself a failure. **As of 2026-10-04 that list is populated
with exactly these five signals** — an earlier version of this paragraph said the list was
"deliberately empty", which was true when it was written and is now wrong; the populated
list is what the census actually holds, and it is enforced rather than advisory. The
remaining half no test can enforce is the *reason* the ledger is the wrong home, which is
below.

**`NpcLedger` does not grow to absorb them, deliberately.** It is an audit trail of stage
*movement*, bounded at `MAX_ROWS := 64` — the one event whose consequence a later reader
must be able to reconstruct ("why is the elder at `elder_taught`, and what drove them
there?"). The five unsubscribed signals fail that test on their own terms:

- **`npc_tracked`** — a roster *addition*. `NpcApi.state(player).tracked_ids` is the
  authoritative, unbounded-accurate answer to "who do I know", readable at any time; a
  bounded log of who first entered would be a lossy shadow of it.
- **`npc_transient`** — an npc that, by ADR 0092, **leaves no roster entry at all**. There
  is no persistent fact for a log to be the only home of, and the registry that *does* hold
  it for the room visit is cleared on unload anyway.
- **`presence_changed`** — presence is a *state*, fully readable through
  `NpcApi.presence_here(location_id)`. A bounded log of transitions would be a strictly
  worse copy of that read model, not the place a fact lives.
- **`bond_changed`** — `social/` owns the bond ledger and `SocialApi.summary(player)`
  publishes it. `NpcLedger` in `app/` reading a `social/` table it does not own is the
  sideways dependency ADR 0093 exists to prevent.
- **`npc_restored`** — fired by `NpcApi.attach`, i.e. at boot/load. A log row recording that
  a save was loaded answers a question nobody asks, and ADR 0093 already accepts the cost
  that an event firing before a subscriber connects is lost; the roster *is* the restore
  record.

**The trigger that would change any of this**, in the spirit of line 28's refusals: a
feature that must REACT to one of these signals rather than read it — a quest that opens on
`bond_changed`, a party system that follows `npc_tracked`, a save-migration tool that
needs `npc_restored` as a replayable stream — gets its own subscriber in its own boot
function, exactly as ADR 0093 line 21 describes. It does not get added to this ledger, and
it does not get added to `RESERVATIONS`.

### Correction (N2, 2026-10-04) — the emit-scan is INVERTED, not removed

**Nothing above this line is edited.** The "Correction (N4)" section's reservations remain
what it says they are. What changed is the SHAPE of the guard that enforces them, and it
is worth writing down why because the guard had already been caught overclaiming once.

The first version of `tests/modules/npc/test_npc_event_contract.gd` asked a single
question: does `<name>.emit(` appear anywhere under `res://src`? The audit answered that
question with a line in **dead code** — `signal npc_introduced` declared, its only emit
placed inside a function that no production file calls — and `--suite test_npc` returned
`509 passed, 0 failed`. The guard proved a LINE exists, not that the function runs, and it
was reported as if it closed the question.

**The obvious repair was measured and rejected.** A call-graph reachability set from a
production entry point (`app/` boot, `NpcBoot.install`, `item_workbench_app.gd::_ready`,
the pulse loop) is the stronger claim, and it does not survive contact with this tree:

- `NpcApi.advance_stage` — which emits `stage_advanced`, the one signal with a real
  production subscriber — has **no qualified call site anywhere in `src/`**. It is reached
  only by a bare `advance_stage(...)` inside `tally`, and `tally` reaches production
  solely through the **injected** `Callable(NpcApi, "tally")` at `app/npc_boot.gd`. Every
  static shape that resolves that indirection — bare call, `Class.method`, name literal —
  reports the one genuinely reachable producer as dead.
- `NpcLedger.rows` is the mirror image: the bare name `rows` IS called from another file,
  so a name-keyed rule calls the auditor's dead function **reachable** while a
  receiver-aware rule calls the real producer **dead**.

The two approximations each fail on a different true fact, and a guard reporting those
backwards is worse than no guard. So the rule is **inverted** rather than strengthened.

**What the rule now is.** Every signal on the contract must be emitted from a file under
`res://src/modules/` — the layer that OWNS it — and must have either a production
`.connect(` under `res://src` or a written `RESERVATIONS` entry carrying a reason.
`app/` is where subscribers live (line 21), not emitters, so the audit's shape is refused
**by construction** rather than by analysis.

**Mutation proof, measured.** Declaring `npc_introduced` and emitting it only from an
unreachable function gave `Results: 49 passed, 2 failed`, naming the signal twice — once
by the layer rule ("emitted only from `res://src/contracts/npc_events.gd`, which is
outside `src/modules/`") and once by the subscription-or-reservation rule.

**What this guard claims, exactly:** every signal on the contract is published by the
layer that owns it, and every one is either observed by production code or carries a
written reason saying it is not yet. **What it does not claim:** that any particular emit
executes on any particular run. A function under `src/modules/` that nothing calls can
still satisfy the layer rule. That residual hole is narrower than the one it replaced, and
it is stated in the test file rather than papered over.