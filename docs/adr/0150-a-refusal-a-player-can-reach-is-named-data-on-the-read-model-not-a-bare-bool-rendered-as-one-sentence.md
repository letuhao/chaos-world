# A refusal a player can reach is named data on the read model, not a bare bool

Completes the "observable" clause of the program's acceptance gate. No `core/` change.

## Status

Accepted.

## Context

An audit of the six criterion legs found that the `{ok: false, reason: R}` shape exists on
only **two** of them. Train, break through, fail recoverably and reach-the-terminal-realm
answer a bare `false`.

That is not by itself a defect — a bool is a fine answer. The defect is what the screen does
with it. `body_cultivation_panel.gd:386-388` renders four distinct failures as one sentence:

```
"Repaired" if repaired else "Nothing damaged to repair"
```

The worst instance is on the **fail-recoverably** leg. A hero with damaged channels and no
repair elixir is told *"Nothing damaged to repair"* — while the same screen's `unmet` line,
rendered from the same `panel_state`, says `Damaged channels need repair: lung`. **The screen
contradicts itself on the seventh leg of the acceptance gate**, and the real cause — the
missing elixir — is named nowhere on it.

The same collapse happens on `attempt_breakthrough` (four distinct refusals, one message),
`strengthen_next` (a capped channel reads as "no elixir"), and `withdraw` (three causes, one
bool).

## Decision

**A refusal a player can reach is published as named data on the read model.** The screen
renders the name; it does not infer one from a `false`.

The read model already carries the vocabulary: `BodyCultivationApi.panel_state` publishes
`unmet`, `ready` and `tier_gates`. So the repair costs **no facade method** — which matters,
because `items` and `body_cultivation` are both at `rules.MAX_FACADE_PUBLIC_METHODS` and a
13th public verb fails `tools arch`.

- `preview`'s refusal is published as an `unavailable` list alongside `unmet`, naming which
  clause blocked. It is a list because four causes collapse to one message today, and the
  panel must be able to say which.
- The panel renders `unavailable` when the verb returns `false`, and says nothing it cannot
  back. When the list is empty and the verb still refused, that is a finding, not a message
  to invent.

## Why not the alternatives

**Add a verb that returns a reason.** `BodyCultivationApi` is at the cap. The repo already
answered this at `institution_resolver.gd:100-104`: fold the work into the read model rather
than widen the surface.

**Write four `else` branches in the screen.** The screen cannot know which of four causes
fired — it is handed a `bool`. Guessing from `unmet` re-derives the truth in the UI program,
which is the ADR 0034 rule this file already follows for `ascension_unmet`.

## Consequences

- **The tribulation leg is a different defect and this ADR does not fix it.** It already
  *has* named refusals and discards them: `tribulation_screen.gd:72-73` disables Begin and
  Fight, so four real refusals sit behind a control a player cannot press. Adding prose to
  `_report` would change nothing reachable. That is a *disabled-control* decision — offer the
  control and explain, or publish the fact and stay disabled — and it needs its own ADR
  because the two options are genuinely different products.
- **`begin_breakthrough` / `resolve_breakthrough` have zero production callers.** The
  durable, save-spanning half of the breakthrough lifecycle is unwired, so `panel_state`'s
  `attempt` is permanently `""` and the facade's promise that a panel can offer *resolve*
  rather than a fresh attempt is unimplemented. The machinery is proven to work when driven.
  Recorded separately: building that affordance is a feature, deleting the claim is a
  decision.
- **A guard belongs here.** Nothing asserts that a `false` from a player-facing verb has a
  name the screen can render. That is the check that would have caught the seventh-leg
  contradiction, and it belongs in the next agent that touches this surface.