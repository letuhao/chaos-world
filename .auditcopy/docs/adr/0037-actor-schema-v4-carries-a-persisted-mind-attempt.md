# 0037 Actor schema v4 carries a persisted Mind breakthrough attempt

- Status: Accepted
- Date: 2026-10-02
- Supersedes: the `Actor.SCHEMA_VERSION is 3` line in ADR 0028

## Context

ADR 0028 recorded schema v3, when an acupoint set, body progress and the body attempt all rode
in `module_data`. The Mind path then needed the same thing: a breakthrough that is a transaction
rather than a single roll. `MindAdvancement` was rewritten as an explicit lifecycle
(`preview` → `start` → `resolve_attempt` → `cancel`) whose once-only award guarantee lives on
the attempt record's `outcome_granted` flag — not on the incidental fact that advancing a path
zeroes its progress. That flag only protects the reward if it survives a save/load, so the
attempt has to be part of the actor payload.

`SCHEMA_VERSION` stayed at 3 while a new `mind_attempt` slot appeared, which left ADR 0028's
claim true only by accident and made the payload shape ambiguous for any save written between
the two states.

## Decision

- **`Actor.SCHEMA_VERSION` is 4.** The attempt rides in its own `mind_attempt` payload slot and
  is excluded from the generic `module_data` loop so it is serialized exactly once.
- **`from_dict` dispatches on the version.** A payload without the slot — v3 or older — loads
  with no active attempt, and one without `sea` loads with a default sea. Both defaults are
  tested against hand-built legacy payloads rather than assumed.
- **The slot is a raw dictionary.** Core never imports the module's attempt class; the module
  restores its own typed record on load. This follows the existing acupoint/body-progress
  precedent in the same file.
- **Accepting an older schema never invents state.** A missing attempt is "no attempt in
  progress", not a pending one, so an old save cannot appear mid-transaction.

## Consequences

- ADR 0028's `SCHEMA_VERSION is 3` line is superseded here rather than edited, so the accepted
  record stays immutable.
- An award granted before a save cannot be granted again after loading, because
  `outcome_granted` round-trips with the attempt.
- Core carries one more payload key but still no Mind-typed field; the module owns the meaning.
- `tools arch` cannot catch a `core/` file importing a module class through a global
  `class_name`, so this boundary rests on review rather than the checker.
