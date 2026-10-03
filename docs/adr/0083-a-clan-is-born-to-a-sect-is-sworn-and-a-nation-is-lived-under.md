# 0083 A clan is born to, a sect is sworn, and a nation is lived under

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0062 (a race is a body plan), ADR 0063 (a bloodline is a diluted
  inheritance), ADR 0064 (a clan is a standing with obligations), ADR 0076 (a relationship is
  a cause ledger), ADR 0079 (clan is a named module with an empty facade)
- Resolves: the vocabulary half of BL-0169 and BL-0172

## How this decision was reached

Recorded because the ordering is load-bearing and is otherwise invisible in the
tree: an ADR citing a backlog id could just as easily have been written before
the id existed.

**The backlog came first.** `BL-0169..BL-0207` are 39 one-line sub-features,
written and committed before any agent was dispatched. They are contiguous, and
this ADR's `- Resolves:` line names `BL-0169`/`BL-0172` — ids that cannot be
cited until the list exists. ADR 0084 names `BL-0173` and ADR 0085 names
`BL-0187`/`BL-0193`/`BL-0194`/`BL-0196`. A citation is therefore the ordering
proof, and it is in the file rather than in a commit message that could be
rewritten.

**Then five design agents ran in parallel**, each owning one area and each
brainstorming before designing: hierarchy/offices, territory/conflict,
doctrine/teaching, simulation/UI, and one adversarial reviewer whose only job was
to find what the other four got wrong. Its findings changed the design: it
measured `TechniquesApi` sitting at exactly 12 public methods, which is why this
feature gates technique access through a `contracts/` seam rather than a new
verb, and it found that `social` (ADR 0076) already owns institution `regard`,
which is why no tier here keeps a second copy.

**Everything load-bearing was then re-measured against the live repo** rather
than taken from those reports — the 12-method cap, `Actor.to_dict`'s verbatim
`module_data` copy, and the absence of a world-level persistence root — and the
three open questions they raised are recorded as DEF-0118, DEF-0119 and DEF-0143
rather than decided here.

## Context

ADR 0064 built a clan — born to, a lineage across generations, `standing` + `rank` + `duty` +
`patronage` — and explicitly reserved the word "clan" as *the vocabulary social features will
read*. Nothing has read it. The natural next requests are a **sect** (join a school, be taught,
hold a position) and a **nation** (a polity, offices, land, war), and the trap is that all
three get built as three parallel hierarchies with three copies of the same three numbers.

What makes the trap dangerous here is that the duplication is invisible until it is expensive.
There is already precedent for exactly this in the repo: ADR 0066 had to collapse three copies
of `RATE_STEP` into one shared curve, and ADR 0050 left three per-realm magnitude tables
unreconciled and the backlog still carries the debt. A third hierarchy is the same failure
with more surface.

Two facts measured now make the decision harder than it looks:

- **`TechniquesApi` is at exactly 12 public methods** (`modules/techniques/api.gd`: `attach`,
  `codex`, `slots`, `learn`, `equip`, `unequip`, `rebuild`, `settle_upkeep`, `raise_mastery`,
  `summary`, `inspect`, `technique_state`), and `MAX_FACADE_PUBLIC_METHODS` is 12. Nine of the
  repo's facades sit exactly at the cap. So "add a method" is not a free move anywhere in this
  program, and a sect that must gate technique access cannot get a new verb on the technique
  facade to do it.
- **`social` already owns institution regard** (ADR 0076). `SocialState.regard` is a
  `Dictionary` of aggregate regard keyed by institution id, and its own comment says the
  *"clan module owns that number already — this is the read model, not a second writer of it."*
  That claim is currently true of nothing, because `clan` is an empty facade (ADR 0079). Whichever
  module fills it inherits a written expectation.

## Decision

**Three tiers, one vocabulary, and each tier answers a question no other tier answers.**

| Tier | Question | Persists across | Distinct because |
|---|---|---|---|
| clan | "who are my people, what did we earn, what do I owe?" | generations | bloodline + succession |
| sect | "who taught me, and what am I obliged to do?" | the institution's life | doctrine + teaching + duties |
| nation | "whose law am I under, and who holds the seats?" | the polity's life | offices that may be vacant + land |

The three are **not** nested in a containment tree. A clan exists without a sect; a sect exists
without a nation; a nation is made of many sects and clans that were never related. `nation`
depends on `sect` in the module graph because a nation's offices are filled from sects, never
because a nation contains them. Rejected: `clan ⊂ sect ⊂ nation`, which would force every
person to be born into a sect and make "no institution" unrepresentable.

**One claim shape, authored once, in `core/` — not `contracts/`.** The claim is
`(position, standing, obligation)`:

- `position` — discrete and authored, from a `position_id`. Never an index, never a number.
- `standing` — a continuous integer, earned, and **able to fall**. Clamped at zero, never negative.
- `obligation` — an open ledger of terms, stored as ids and counts.

`position` and `standing` are **never derived from each other** (ADR 0064's rule, carried
forward unchanged). A member can hold a high position on thin standing, and can hold thick
standing in no position at all. That gap is the whole politics layer; a design that collapses it
into one number has built a spreadsheet.

**The claim type lives in `core/institution_claim.gd`, not `contracts/`.** It has to be an
`@export` field on `SectDef` and `NationDef`, which are authored `.tres` Resources, and Godot
cannot `@export` a `RefCounted`. A `Resource` in `contracts/` is what that leaves, and
`RESOURCE_HOME_UNITS = ("core", "modules")` plus `AGENTS.md`'s note that *"`core` is a layer, not
a module, so the cross-module facade rule never applied to it"* are the precedent for exactly
this case: foundation data that three units construct and three `.tres` types serialize.
`contracts/` receives **signal contracts only** — `SectEvents`, `NationEvents` — modelled on
`contracts/destiny_events.gd`.

**The three-state vocabulary is declared once here, because every screen will need it:**

- `{}` — **this does not exist**. A spare row in a pool. Hidden, `is_filled() == false`, not
  counted.
- `"vacant": true` — **this exists and its value is absent**. An office with no holder, an
  authored seat nobody fills. Row **visible**, `is_filled() == true`, own tone.
- `{"ok": false, "reason": R}` — **this action exists and is refused**. Button disabled, `R`
  is the facade's authored reason string, never a UI string.

A vacancy is **never** `0`, never `"-"`, never a hidden row. A nation that renders an unfilled
office as zero has destroyed the succession design, which exists to make a vacancy legible.

**Three rules that hold for every tier, so no tier can drift:**

1. **An institution grants recognition and access, never power.** See ADR 0084.
2. **A position is a duty, not a level.** It carries authored `duties` and `authorities`.
   Authority is authored data, so "may this member expel another" is a content question.
3. **Leaving is always permitted and always costs.** Expulsion costs the expeller strictly more
   than it costs the expelled. A player with no exit is in a bad state with no out.

**Reputation stays out of the claim.** `social` (ADR 0076) already owns `regard` — how an
actor is regarded, keyed by institution id — and already owns a `trust` axis whose own
documentation says **trust is what gates teaching**. Sect membership therefore *moves* `regard`
through `SocialApi.apply_cause` and never keeps a second copy. Standing is what an institution
thinks of you; regard is what everyone else does. Folding them is one number, and one number
cannot express the gap that makes the politics interesting (ADR 0064).

## Consequences

- `race → bloodline → clan → sect → nation` is a strict acyclic chain, and each tier reads only
  the ones below it. `nation` reads `sect`; the reverse edge is a cycle and `tools arch` fails
  on it.
- The `nation → sect` edge is the design's most load-bearing constraint and **the checker cannot
  see it**: `BARE_REF_UNITS` (`tools/arch/rules.py`) excludes `modules/*`, so a bare `SectApi`
  or `SectState` reference inside `modules/nation/` reports zero violations, and `_find_cycle`
  is fed by `registry.json` alone, so a cycle written that way is invisible. It is enforced by
  review and by the test named in ADR 0084, not by the gate.
- Both facades start under the cap and are designed to stay there: reads fold into `summary()`
  (the precedent is `DestinyApi`, which documents the fold in its own body), and any read a
  screen needs must be reachable from `summary() -> Dictionary`.
- Sect technique access does **not** add a technique-facade method. It runs through a
  `contracts/` seam shaped like `damage_mechanism.gd` (ADR 0067), reached by component id,
  because `TechniquesApi` is at 12 and `TechniqueGate` is not the only path to a codex entry.
  Recorded in full when that seam is built; the constraint is fixed here.
- `sect` needs no `world` dependency. Territory is a claim over places authored inside `sect`,
  and `WorldApi` is itself at 12, so adding territory verbs there is not available.
- **Disclosed gap, owned elsewhere:** a nation is a polity that outlives the actor who founded
  it, but `actor.module_data` is the only persistence root in the repo and it dies with the
  actor. Where a polity ledger lives is an open decision and needs its own ADR *before* a
  roster ships. The first slice uses `actor.module_data` and the ledger is JSON-safe.
- The three-state vocabulary and the "grants no power" refusal are now the two things every
  later sect/nation ADR must not re-litigate. A later ADR that needs a sixth state, or a stat
  grant, supersedes this one rather than extending it.