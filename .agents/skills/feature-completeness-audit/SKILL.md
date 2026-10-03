---
name: feature-completeness-audit
description: >
  Audit whether a feature is genuinely COMPLETE rather than merely present: build a
  feature map with explicit links between features, trace a full user pipeline from
  intent to observable outcome, and classify every gap. Use when asked to audit,
  review, or map a subsystem's completeness; to answer "is this feature done"; to
  find dead, unwired, unreachable, or never-built features; or to turn an audit into
  a prioritised backlog. The core rule: a feature is complete only when it wires to
  all its related features AND a user can traverse a complete pipeline through it
  using only shipped code.
---

# Feature completeness audit

## The rule this skill exists to enforce

**A feature is complete only if it wires to all its related features AND a user can
traverse a complete pipeline through it using only shipped code.**

Presence is not completeness. A file exists; a function is called; a test passes. None
of that means a player can *use* the feature. Most "done" work in a codebase is a
component with no wire: an input that reaches nothing, a value written and never read,
a mechanic whose failure branch can never fire, content that exists but cannot be
obtained.

## Three failure classes — do not collapse them

The audit must distinguish these, because each needs a different fix and a different
backlog entry:

| Class | Meaning | Backlog action |
|---|---|---|
| **UNDEFINED** | No spec, ADR, or intent anywhere. Nobody decided this. | Add: needs a design decision first. |
| **UNBUILT** | Specified and decided, code absent or stubbed. | Add: build it, the decision already exists. |
| **UNWIRED** | Code exists and works, but nothing connects it to a pipeline. | Add: highest priority — the work is paid for and invisible. |
| **VACUOUS** | Wired, but the condition can never be false (or never true). | Add: the guard/mechanic is theatre. |

UNWIRED is the class that hides best: it passes every test, appears in every grep, and
no player can reach it.

## Completeness criteria

Answer each with **yes / no / partial + evidence**. A feature is COMPLETE only when all
nine are yes. Any `no` is a finding.

1. **REACHABLE** — can a user or an actor actually get here by doing something? A
   function only tests call, or a screen only `tools ui drive` opens, is not reachable.
   *Test:* name the concrete user action that arrives here.
2. **WIRED OUT** — does this feature's output feed a downstream consumer a user can
   observe? Write-only data, an unused return value, or an event with no listener is
   not wired. *Test:* name the downstream consumer.
3. **PIPELINE** — is there a complete path intent → action → cost → effect → observable
   outcome? Name every stage. A break anywhere is a finding.
4. **CONTENT EXISTS** — every piece of data the feature needs is authored and present.
   A reference to an item/realm/stat that resolves to nothing is a finding.
   *Test:* resolve each referenced id.
5. **OBTAINABLE** — is required content reachable through real acquisition, or only by
   a test that grants it directly? A test helper handing the player the item is not
   acquisition.
6. **GATES ARE SOUND** — every precondition is (a) *satisfiable* from a legal prior
   state, and (b) *non-trivial*, i.e. a bare actor does not already pass it.
   (a) failing = circular prerequisite, the progression is untraversable past that point.
   (b) failing = the gate is theatre. Check both; they fail independently.
7. **FAILURE IS REACHABLE** — can the failure/error branch actually occur? If success is
   guaranteed, every failure mechanic and every item serving it is dead content.
   *Test:* name the input state that triggers failure.
8. **PERSISTS** — if it holds state, does it survive save/load, serialized exactly once?
   Duplicated state can silently disagree with itself after a round trip.
9. **PROOF AT THE SEAM** — is there a test that exercises the real pipeline end to end?
   *And is it load-bearing?* A test that passes against a wrong implementation proves
   nothing.

## Method

**1. Map before you judge.** Build the feature map first: every feature in scope, its
entry points, its outputs, and the links between them. Judge each node against the nine
criteria *after* the map exists — otherwise you assess features in isolation and miss
the unwired ones, which are only visible as a broken link.

**2. Trace the pipeline by hand.** Pick the feature. Walk intent → observable outcome
through real code, naming each stage and the file that implements it. Where you cannot
name a stage, that is the finding.

**3. Test the wires, not the nodes.** A feature whose link to its neighbour is missing
is the target finding. Draw the link graph; dangling edges are the work.

**4. Mutation-test the proof.** For each claim of completeness, break the
implementation deliberately and confirm something fails. If nothing fails, the claim is
unproven — say so. A green suite is evidence of nothing until you have seen it go red.

## Evidence discipline

These have each cost real time. Follow them.

- **Green is not evidence.** A test that passes against a wrong implementation proves
  only that the test and the implementation agree, which is what two copies of the same
  mistake always do.
- **A docstring is a claim, not evidence.** Comments, ADR prose, and test names assert
  what the code should do. Read the assertions.
- **Understand what a tool grades before trusting it.** A gate can pass while measuring
  the wrong thing. Ask what population it actually inspects.
- **Verify before reporting.** Re-run the authoritative command. Distrust a first read,
  and distrust a summary table until you know which table you are looking at.
- **A tool's output is a claim about the tool's model.** Confirm the model.

## Deliverable

Keep it lean. Prose that would not surprise a competent agent should be deleted.

**1. Feature map** — features and the links between them. Mark each link wired or
dangling. This is the primary artefact; the rest is commentary on it.

**2. Pipeline trace** — per feature, the stage chain. Name the stage that breaks.

**3. Verdict table** — the nine criteria per feature, yes/no/partial with evidence.

**4. User story mapping** — lean. For each feature: *As a player, I want X, so that Y.*
Then the gap stories the audit implies, in the same voice. No personas, no epics, no
prioritisation frameworks.

**5. Backlog additions** — one entry per finding, classified UNDEFINED / UNBUILT /
UNWIRED / VACUOUS, each with the evidence and the next step. Use the repo's backlog tool;
do not hand-edit the tracker. If nothing is wrong, say so and show the evidence that
established it — an empty result is a result.

## Rules

- Audit before you build. Do not fix what you are auditing unless asked; a finding that
  is silently fixed is a finding that is lost.
- Report what contradicts your own map. A map that never needs revision is a map you
  did not build.
- Rank by *player-visible* impact, not by effort.
- A feature nobody can reach outranks a feature nobody noticed is unreachable.
