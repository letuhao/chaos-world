# 0264 A gated NPC behaviour reads regard through an injected seam, and the counterpart withdraws it

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0091 (`regard`/`trust` belong to `social`, the bond is a derived sum),
  ADR 0076 (a gate reads the ledger, never a derived stat), ADR 0092 (an npc is tracked or
  transient), ADR 0253 (the alive layer's four capabilities), ADR 0256 (a first impression is
  seeded once), ADR 0044 (a refused verb writes nothing)
- Resolves: DEF-0123 (the NPC-behaviour half only; the price half is ADR 0250)

## Context

DEF-0123 asks for **NPC behaviour and shop prices** to react to a social gate. The price half
shipped as ADR 0250 and is closed. This ADR is the behaviour half, and it had to be measured
before anything was written, because a peer had just landed a large amount of `npc/`.

**What the measurement found — the behaviour half is MOSTLY built, and genuinely missing one
thing.**

Already shipped and load-bearing:

- `NpcAliveness` gives an NPC a **daily round**, **incident memory** keyed to the real cause
  id, **authored opinions**, and a **reaction tell answered on approach**.
- `NpcAliveness.tell` matches an authored trigger against **real state** — the cause ledger,
  the derived **bond class**, the day's slot, or "no history".
- `NpcMinorComposer` composes minor NPCs from their **place**, and `NpcPersona` persists
  nothing.
- ADR 0256 landed a seeded first impression and the pursuit surface on top.

**The gap, stated precisely.** `NpcAliveness.tell` reacts to `TRIGGER_BOND_CLASS`, and a bond
class is a *pure function of `standing` and `trust`* — so the axis `social` publishes as the
teaching gate is already an input to behaviour, transitively. But `regard` — the
**institutional** axis, the one `SocialGate`'s `regard_at_least` verb exists for and the one
`clan`, `sect` and `nation` all write — is read by **nothing** in `npc/`. No NPC behaviour
consults a gate at all. Grepping `game/src/modules/npc` for `regard` returns the English word
in two docstrings and zero code.

That is the residual: **an NPC's warmth toward the player cannot depend on how the world
regards the player**, and no authored `NpcDef` can say "this one only opens up to somebody the
sects like".

## Decision

**One authored gate on the def, evaluated through ONE injected `Callable`, consulted by
exactly ONE reader — and the counter-force is that warmth both opens and closes the door.**

- **The authority is a seam, not a formula.** `NpcGates.set_social_gate(Callable)` takes a
  `Callable(player: Actor, requirement: Dictionary) -> Dictionary`, the `CustodyApi.set_resolver`
  and `MarketFavour.set_reputation_reader` shape verbatim, and `app/npc_boot.gd` binds
  **`SocialApi.gate`** as a bare static-function reference — which already *is* that
  signature, so there is no adapter and no second copy of the axis. `app/` is the only layer
  allowed to know both modules, the same reason `_install_favour` exists.
  `tools/arch/registry.json` is **unchanged**: a `Callable` carries the edge, so `npc` gains no
  dependency and `tools arch` still prints `ok boundaries ok`.
- **The gate is AUTHORED ON THE DEF, as a plain `Dictionary` and not a `Resource`.** `NpcDef`
  gains `social_gate: Dictionary`, read by the closed vocabulary `SocialGate` already
  publishes (`bond_at_least`, `trust_at_least`, `standing_at_least`, `regard_at_least`,
  `caused_by`, `all_of`, `any_of`, `none_of`). A plain dictionary is ADR 0076's own shape:
  it serializes inside a placement without a value object, and **an unknown verb refuses
  closed and names itself** rather than quietly unlocking content.
- **A gate reads the LEDGER, never a derived stat** (ADR 0076 line 6), so the authored
  requirement never names standing as a number it computes. The module passes the requirement
  through **untouched** and does not interpret a single verb — there is no second evaluator,
  which is the whole of ADR 0076's rule.
- **The default is EXACTLY today's behaviour.** No reader bound, a dead reader, a null player,
  an empty `social_gate`, or a reader answering anything that is not a Dictionary all read
  **`gate_open: true`, `gate_reason: ""`, `warmth: 0`** — byte-identical to the row as it is
  today. That is what makes the existing `test_npc_alive.gd` assertions the regression guard
  for this file rather than something they have to be taught about.
- **## Yin-yang: the counterpart WITHDRAWS, it does not merely withhold.**
  An advantage needs a counterpart (AGENTS.md). A gate that only ever *opens* is a pure
  upside with no cost, which is the strict-best-response defect. So warmth is a **signed**
  reading of the *same* gate result: an authored `regard_at_least` that passes sets warmth to
  `+1`, one that **fails** because the world does not hold the player at that bar sets it to
  `-1`, and anything neutral is `0`. The published `warmth` is therefore `-1, 0 or +1`, and
  **`warmth == 0` is the shipped default**, so the counter-force is not a new mechanic bolted
  on: it is the sign of the number that was already being read. One axis, two signs — the same
  pair ADR 0250 shipped for the price, for the same reason.
- **The tell is where it lands, because a tell is already "what the body does on approach".**
  `NpcGates` is consulted by `NpcReadModel.alive` and its verdict is published **beside**
  `tells` as `gate_open` / `gate_reason` / `warmth`. It does **not** silently replace the
  authored body: a gated-off NPC still gets its authored `tells`, because ADR 0044 says a
  refused verb writes nothing and a gate is a fact a panel must be able to *show*, not a hidden
  mutation of authored content.
- **No orphan verbs.** `NpcGates.evaluate` is reached from exactly one production reader
  (`NpcReadModel.alive`) plus the composition-root install, and the suite asserts both counts
  by source scan, so a read nobody calls cannot accumulate the way this program accumulated
  nine dead-code entries.

### What this deliberately does NOT do

- **It does not gate content**, and it does not add a gate to a quest or an event. DEF-0123's
  own recorded correction is that the gate must be evaluated in `app/` and passed a **verdict**,
  never a live handle; this ADR passes a verdict, and only into a behaviour read.
- **It does not touch pricing.** That is ADR 0250 and it is closed.
- **It does not put a `regard` number on an `NpcDef`.** The authored gate names a *threshold*
  against `social`'s own ledger. A def-owned regard number would be the second writer of the
  axis ADR 0091 forbids, and `clan/api.gd:57` already says this in as many words.

## Consequences

- **New file `game/src/modules/npc/npc_gates.gd`**; `NpcDef` gains one `Dictionary` export;
  `NpcReadModel.alive` gains three published read keys; `app/npc_boot.gd` gains one install
  line. `NpcApi` does **not** grow — it is at `rules.MAX_FACADE_PUBLIC_METHODS` and a
  thirteenth public verb fails `tools arch`, which is the `NpcAliveness` collaborator
  precedent stated in that file's own header.
- **`warmth` is published, not hidden**, so a panel can render the counter-force; the numbers
  ADR 0256 hid behind a debug flag are not repeated here because warmth is a **-1/0/+1
  position**, not a magnitude the player can farm.
- **With no reader bound the behaviour is unchanged**, which is the property that makes this
  safe to land alongside the other `npc/` work in flight.
- **Rejected:** a direct `SocialApi.gate` call inside `npc/` (the edge is declared, but a
  *call* rather than a seam — the reason ADR 0250 bound a `Callable` instead of preloading the
  facade); re-deriving the gate in `npc/` (a second evaluator is exactly what ADR 0076
  forbids); gating on `SocialStats.REPUTATION` (a derived stat is a shop discount waiting to
  happen); a `regard` number on `NpcDef` (the second writer ADR 0091 names); one-way warmth
  with no counterpart (the AGENTS.md violation); silently swapping the authored body for a
  gated one (a hidden mutation of authored content, and it would hide the gate from the
  player entirely).