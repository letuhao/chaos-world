# 0939 foundation is snapshotted perfection chased under a time limit

- Status: Accepted
- Date: 2026-10-09
- Commissions: BL-0951 (the foundation program; this ADR is its design pass)
- Depends on: BL-0830's prep depth, ADR 0169 (the lifespan ladder), ADR 0258 (the age bands), ADR 0130/0181 (death and rebirth), ADR 0027 (versioned module data), ADR 0067 (the one spine)

## Context

Two characters at the same realm are not the same power — in the novels the difference
is talent × effort × resources × lineage luck, and a wrong early choice is a debt the
future collects. The tree already owns every ingredient except the debt: prep depth
measures how far past a gate an actor trained (BL-0830), each path caps its training
space per realm (channel refinement caps, huyệt quality), the lifespan ladder buys 10x
life per band (ADR 0169), the age bands slow the old and sharpen their insight
(ADR 0258), and death already mints a fresh body while the soul keeps its ledgers
(ADR 0130/0181). What is missing is the carry-forward: today a realm left at 20%
perfection costs nothing later, nothing closes, and training costs no time.

## Decision

- **One shared foundation and principle; each path implements its own rules over them.**
  A new `foundation` module owns the RECORD (per realm: the perfection snapshot and the
  carried aggregate) and the shared vocabulary (the refusal ids, the mending contract).
  The three paths keep their own gate arithmetic and their own principle-based
  measurement — the module never learns a path's formula, and no path keeps a second
  copy of the record (ADR 0066).
- **Perfection is snapshotted at departure.** The score is BL-0830's depth (the
  past-the-gate training fraction), written once at breakthrough. It is never
  rebuildable; the underlying stats stay trainable, so no content dies.
- **The wall is a floor plus scaling.** Each realm authors `min_foundation`. Below it: a
  named refusal (`foundation_insufficient`), visible in the preview before the wall.
  Above it: the tribulation scales with how far above the actor stands.
- **Time is the currency.** Any action costs time (AGENTS.md); a sitting consumes world
  periods, and the age bands make lingering progressively expensive. The final band
  collapses training to near-zero and permits one last, harsher attempt — burning the
  last years.
- **Mending is a web, never one door** (all eight avenues ship, each bounded and priced):
  rebirth (the baseline), the miracle elixir (wealth), the heaven-defying rite (a gamble
  that scars on failure), the secret realm (danger + time), the master sacrifice (a
  relationship, and the mentor's permanent decline), the forbidden lifespan art (years),
  karmic virtue (deeds, unbuyable), and dual-cultivation aid (a transfer — the partner
  loses what the actor gains). The module caps the TOTAL mend per realm below full: a
  poor foundation is a scar, never erased.
- **No combat stats.** Foundation gates and scales breakthroughs; "stronger at the same
  realm" comes from the training itself. The actor-vs-actor census stays flat.
- **Rebirth leaves a trace.** Each death grants a karmic-memory soul fate that slightly
  raises the next body's starting foundation.

## Consequences

- The gate-ladder audit learns the floor (`qi_gate_ladder_findings` must model
  `min_foundation`, or it grades a ladder nobody walks); a traversal walks a sloppy run
  into the wall and a perfected run through; the preview shows the wall before it is hit
  — a consequence the player cannot read is a trap, not a cost.
- The retrofit of time costs onto EXISTING verbs is a separate audit — this ADR binds
  the program's verbs and all new mechanics; a repo-wide sweep is its own item.
- The mending avenues are authored content gated through the module's verbs: no avenue
  grows a second foundation, and each pairs its gift with its price (AGENTS.md's
  yin-yang).
